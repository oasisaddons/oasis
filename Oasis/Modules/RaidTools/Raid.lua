-- Oasis Modul 5: Raids & Beute (Termine mit Anmeldung, Beuteverteilung, Beute-Log)
local ADDON, ns = ...
ns.ModuleFile("Oasis_Raidwerkzeuge", function()   -- Modul Raid-Werkzeuge (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Comm, Store = ns.K, ns.K.C, ns.Comm, ns.Store
-- Sicherheit beim Empfang (Addon-Nachrichten anderer koennen manipuliert sein):
-- Texte entschaerfen, Zahlen begrenzen, Namen pruefen, Flut drosseln
local SEC = {}
do
    local function cut(s, max)
        if not max or #s <= max then return s end
        return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
    end
    -- Escape-Sequenzen (|c |r |n |H |T |K |A ...) und Steuerzeichen unschaedlich; links: gueltige Item-/Zauberlinks bleiben
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

local Raid = {}
ns.Raid = Raid

-- Gilden-Optionen (Gildenleitung legt fest; Standard = bisheriges Verhalten)
ns.GuildOption({ page = "raid", key = "rlead", default = "", kind = "names", label = "Schlachtzugsleiter",
    desc = "Duerfen den Raidplaner bearbeiten, Termine immer anlegen und fremde Termine verwalten - unabhaengig vom Gildenrang" })
ns.GuildOption({ page = "raid", key = "rassi", default = "", kind = "names", label = "Schlachtzugs-Assistenz",
    desc = "Helfen im laufenden Raid: Ready-Check, Fehlende ansagen, Taktik-Karte zeichnen, Gruppen im Raidplaner sortieren. Keine Termine, keine Beute-Einstellungen, keine Taktiken dauerhaft aendern." })
local function rankFmt(v)
    v = tonumber(v) or 0
    if v <= 0 then return ns.L["aus"] end
    local names = ns.Admin and ns.Admin.RankNames and ns.Admin.RankNames() or {}
    return (ns.L["bis Rang %d"]):format(v) .. (names[v - 1] and (": " .. names[v - 1]) or "")
end
ns.GuildOption({ page = "raid", key = "rleadRank", default = 0, min = 0, max = 10, step = 1, label = "Schlachtzugsleiter ab Gildenrang",
    desc = "Automatisch Schlachtzugsleiter: alle Mitglieder bis zu diesem Gildenrang. 0 = aus (nur die Namensliste).", fmt = rankFmt })
ns.GuildOption({ page = "raid", key = "rassiRank", default = 0, min = 0, max = 10, step = 1, label = "Schlachtzugs-Assistenz ab Gildenrang",
    desc = "Automatisch Schlachtzugs-Assistenz: alle Mitglieder bis zu diesem Gildenrang. 0 = aus (nur die Namensliste).", fmt = rankFmt })
ns.GuildOption({ page = "raid", key = "rStaffInfo", kind = "info", label = "Schlachtzugsleitung",
    text = function() return ns.Admin and ns.Admin.RaidStaffText and ns.Admin.RaidStaffText() or "" end })
ns.GuildOption({ page = "raid", key = "rdEvRank", default = 10, min = 1, max = 10, step = 1,
    label = "Termine anlegen", desc = "Bis zu welchem Gildenrang Mitglieder auf der Raid-Seite neue Termine anlegen duerfen. 10 = alle.",
    fmt = function(v) return (ns.L["bis Rang %d"]):format(v) end })
ns.GuildOption({ page = "raid", key = "rdOffEd", default = true,
    label = "Offiziere verwalten fremde Termine", desc = "Offiziere duerfen auch Termine anderer einladen und loeschen. Aus = nur der Ersteller (und die Gildenleitung)." })
ns.GuildOption({ page = "raid", key = "rdRemMin", default = 15, min = 5, max = 60, step = 5,
    label = "Erinnerung vor Termin", desc = "Wie viele Minuten vor Beginn alle Zusagen eine Erinnerung bekommen.",
    fmt = function(v) return v .. " Min" end })
local function rankAllowed(v)
    v = tonumber(v) or 10
    if v >= 10 then return true end
    if ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage() then return true end
    if ns.Admin and ns.Admin.Can and ns.Admin.Can("raid.events") then return true end
    local ri = ns.Admin and ns.Admin.RankOf and ns.Admin.RankOf(ns.me())
    if ri == nil then return true end
    return ri + 1 <= v
end
Raid.RankAllowed = rankAllowed

local ROLES = {
    tank = { "Tank", C.blue },
    heal = { "Heiler", C.mint },
    dps = { "Schaden", C.pink },
}
local CHOICES = {
    need = { "Bedarf", C.mint, 1 },
    greed = { "Zweitspec", C.amber, 2 },
    mog = { "Transmog", C.violet, 3 },
    pass = { "Passen", C.dim, 4 },
}
ns.Relabel(function()
    ROLES.tank[1], ROLES.heal[1], ROLES.dps[1] = L["Tank"], L["Heiler"], L["Schaden"]
    CHOICES.need[1], CHOICES.greed[1], CHOICES.mog[1], CHOICES.pass[1] = L["Bedarf"], L["Zweitspec"], L["Transmog"], L["Passen"]
end)

------------------------------------------------------------------------
-- Termine
------------------------------------------------------------------------
local function parseWhen(d, t)
    -- TT.MM. (deutsch) oder MM/TT (englisch)
    local a, b = (d or ""):match("(%d+)[%./](%d+)")
    local day, mon = a, b
    if (d or ""):find("/", 1, true) then day, mon = b, a end
    local hh, mm = (t or ""):match("(%d+):(%d+)")
    if not day or not hh then return nil end
    local now = date("*t")
    local function mk(y)
        return time({ year = y, month = tonumber(mon), day = tonumber(day), hour = tonumber(hh), min = tonumber(mm), sec = 0 })
    end
    local ts = mk(now.year)
    if ts < time() - 86400 then ts = mk(now.year + 1) end
    return ts
end

------------------------------------------------------------------------
-- WoW-Kalender: Oasis-Termine als Gildentermin eintragen, Kalendertermine anzeigen
------------------------------------------------------------------------
Raid.toCalendar = true
Raid.ParseWhen = parseWhen
-- Arten von Gildenevents (Gildenleitung): Symbol, Farbe, Kalendertyp
Raid.KINDS = {
    { key = "raid", text = "Raid", icon = "raid", color = { 1, 0.3, 0.3 } },
    { key = "dungeon", text = "Dungeon", icon = "dungeons", color = { 0.38, 0.6, 1 } },
    { key = "meet", text = "Treffen", icon = "camp", color = { 0.4, 0.86, 0.62 } },
    { key = "pvp", text = "PvP", icon = "deathroll", color = { 0.98, 0.76, 0.34 } },
    { key = "other", text = "Sonstiges", icon = "chronicle", color = { 0.7, 0.7, 0.75 } },
    -- 0.6.469: Gilden-Events jenseits von Raids
    { key = "fish", text = "Angelwettbewerb", icon = "map", color = { 0.36, 0.68, 0.98 } },
    { key = "race", text = "Rennen", icon = "stats", color = { 0.98, 0.82, 0.3 } },
    { key = "photo", text = "Fotoabend", icon = "camera", color = { 0.85, 0.55, 1 } },
    { key = "dice", text = "Wuerfelturnier", icon = "deathroll", color = { 0.93, 0.3, 0.32 } },
}
Raid.KIND = {}
for _, k in ipairs(Raid.KINDS) do Raid.KIND[k.key] = k end
function Raid.CanCalendar()
    return C_Calendar and C_Calendar.CreateGuildSignUpEvent and CanEditGuildEvent and CanEditGuildEvent() and true or false
end
function Raid.AddToCalendar(ev)
    if not Raid.CanCalendar() then return false end
    local ok, e = pcall(function()
        local d = date("*t", ev.ts)
        if C_Calendar.CloseEvent then C_Calendar.CloseEvent() end
        C_Calendar.CreateGuildSignUpEvent()
        C_Calendar.EventSetTitle(ev.title or "Oasis")
        C_Calendar.EventSetDescription(((ev.inst or "") ~= "" and (ev.inst .. "  ·  ") or "") .. L["Angelegt mit Oasis"])
        if Enum and Enum.CalendarEventType and C_Calendar.EventSetType then
            local T = Enum.CalendarEventType
            local byKind = { raid = T.Raid, dungeon = T.Dungeon, pvp = T.PvP, meet = T.Meeting, other = T.Other }
            local t = (ev.kind and byKind[ev.kind]) or ((ev.max or 5) > 5 and T.Raid or T.Dungeon)
            if t then C_Calendar.EventSetType(t) end
        end
        C_Calendar.EventSetDate(d.month, d.day, d.year)
        C_Calendar.EventSetTime(d.hour, d.min)
        C_Calendar.AddEvent()
    end)
    if not ok then ns.err(L["WoW-Kalender"], e) end
    return ok
end
-- Kalendertermine, die nicht schon als Oasis-Termin existieren
function Raid.CalendarOnly()
    local out = {}
    if not ns.GuildInfo then return out end
    local own = Store.List("events")
    for _, c in ipairs(ns.GuildInfo.CalendarEvents()) do
        local dup = false
        for _, e in ipairs(own) do
            if e.title == c.title and math.abs((e.ts or 0) - c.ts) < 7200 then dup = true break end
        end
        if not dup and c.ts > ns.now() - 6 * 3600 then out[#out + 1] = c end
    end
    return out
end

-- Event anlegen (auch fuer die Gildenleitung): t = { title, inst, ts, max, kind, desc }, weeks = Wiederholungen
function Raid.CreateEvent(t, toCal, weeks)
    local made = {}
    for i = 0, math.max(0, (weeks or 1) - 1) do
        local ev = Store.Put("events", {
            id = ns.newId("ev"), title = t.title, inst = t.inst or "", ts = t.ts + i * 7 * 86400,
            max = t.max or 5, kind = t.kind, desc = t.desc,
        })
        if toCal and Raid.CanCalendar() then Raid.AddToCalendar(ev) end
        made[#made + 1] = ev
    end
    ns.RefreshPage("raid")
    ns.RefreshPage("home")
    return made
end
-- Erinnerung 15 Minuten vorher (fuer alle, die zugesagt haben, und den Ersteller)
ns.Listen("LOGIN", function()
    ns.Every(30, function()
        ns.char.reminded = ns.char.reminded or {}
        local now = ns.now()
        for _, ev in ipairs(Raid.Events()) do
            local left = (ev.ts or 0) - now
            if left > 0 and left <= (tonumber(ns.GuildOpt("rdRemMin")) or 15) * 60 and not ns.char.reminded[ev.id] and ns.db.settings.raidReminder ~= false then
                local mine = Raid.MySignup(ev.id)
                if (mine and mine.status == "yes") or ns.isMe(ev.by) then
                    ns.char.reminded[ev.id] = now
                    K.Toast((L["%s beginnt gleich"]):format(ev.title or "?"), (L["in %d Min"]):format(math.ceil(left / 60)) .. ((ev.inst or "") ~= "" and ("  ·  " .. ev.inst) or ""),
                        C.amber, function() ns.ShowPage("raid") end, "announce")
                end
            end
        end
        -- alte Erinnerungen vergessen
        for id, ts in pairs(ns.char.reminded) do if now - ts > 7 * 86400 then ns.char.reminded[id] = nil end end
    end)
end)

function Raid.Events()
    local now = ns.now()
    local out = Store.List("events", function(e) return (e.ts or 0) > now - 6 * 3600 end)
    table.sort(out, function(a, b) return a.ts < b.ts end)
    return out
end
function Raid.Signups(evId)
    return Store.List("signups", function(s) return s.ev == evId end)
end
function Raid.MySignup(evId)
    return Store.Get("signups", evId .. "@" .. ns.me())
end

function Raid.SignUp(ev, role, status)
    local _, classFile = UnitClass("player")
    local prof = ns.Radar.myProfile()
    local old = Raid.MySignup(ev.id)
    if (status or "yes") == "yes" and not (old and old.status == "yes") then
        if ns.Badges then ns.Badges.Add("signups", 1) end
        if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("signups", ev.id) end
    end
    Store.Put("signups", {
        id = ev.id .. "@" .. ns.me(), ev = ev.id, who = ns.me(),
        role = role or (old and old.role) or "dps", status = status or "yes",
        class = classFile or "", lvl = prof.lvl, ilvl = prof.ilvl, u = old and old.u or nil,
    })
end

function Raid.Invite(ev)
    local n = 0
    local list = Raid.Signups(ev.id)
    local yes = 0
    for _, s in ipairs(list) do if s.status == "yes" then yes = yes + 1 end end
    if yes > 4 and IsInGroup() and not IsInRaid() and C_PartyInfo.ConvertToRaid then
        C_PartyInfo.ConvertToRaid()
    end
    for _, s in ipairs(list) do
        if s.status == "yes" and not ns.isMe(s.who) and not UnitInParty(ns.short(s.who)) and not UnitInRaid(ns.short(s.who)) then
            if C_PartyInfo and C_PartyInfo.InviteUnit then
                C_PartyInfo.InviteUnit(ns.ChatName(s.who))
                n = n + 1
                if not IsInRaid() and n >= 4 then break end
            end
        end
    end
    ns.print((L["%d Einladungen verschickt.%s"]):format(n, (not IsInRaid() and yes > 4) and L[" Sobald die Gruppe steht: nochmal klicken (wird zum Schlachtzug)."] or ""))
end

ns.Listen("STORE", function(coll, rec, old)
    if coll == "events" and not old and not rec.del and rec.by ~= ns.me() and ns.db.settings.raidNewEventToast ~= false then
        ns.Sound.Next("event")
        K.Toast(L["Neuer Termin: "] .. (rec.title or "?"), ns.fmtWhen(rec.ts) .. "  -  " .. (rec.inst or ""), C.blue,
            function() ns.ShowPage("raid") end)
    end
    if coll == "events" or coll == "signups" or coll == "loot" or coll == "sres" then ns.RefreshPage("raid") end
    if coll == "events" or coll == "signups" then ns.RefreshPage("groups") end
end)

------------------------------------------------------------------------
-- Beuteverteilung (ueber Gruppen-/Schlachtzugskanal)
------------------------------------------------------------------------
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_BODY = { 4 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 },
    INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 },
    INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18, 16 },
    INVTYPE_RANGEDRIGHT = { 18, 16 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local function equippedFor(link)
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(link)
    local slots = SLOTS[equipLoc or ""] or {}
    local out = {}
    for _, s in ipairs(slots) do
        local l = GetInventoryItemLink("player", s)
        if l then out[#out + 1] = l end
    end
    return out[1] or "", out[2] or ""
end

Raid.session = nil
Raid.announce = true

function Raid.StartSession(link)
    if not link or not link:find("item:") then ns.print(L["Bitte einen Itemlink einfuegen (Shift-Klick auf das Item)."]) return end
    local ch = ns.groupChannel()
    if not ch then ns.print(L["Du bist in keiner Gruppe."]) return end
    if not ns.isGroupLead() then ns.print(L["Nur Anfuehrer oder Assistenten koennen verteilen."]) return end
    local sid = tostring(math.random(100000, 999999))
    Raid.session = { sid = sid, link = link, leader = ns.me(), responses = {}, t = ns.now() }
    Comm.Group("LOOTSTART", sid, link)
    if Raid.announce then
        local chn = ns.groupChannel()
        if chn then ns.SendChat(L["[Oasis] Verteilung: "] .. link .. " - " .. L["Bedarf / Zweitspec / Passen im Oasis-Fenster"], chn) end
    end
    Raid.ShowPopup(Raid.session)
    ns.ShowPage("raid")
    Raid.SetTab("loot")
end
ns.slash.vergabe = function(rest) Raid.StartSession(rest) end

-- Absender in meiner Gruppe / Anfuehrer oder Assistent? (Pruefung beim Empfang, nicht nur in der Oberflaeche)
local GROUPCH = { RAID = true, PARTY = true, INSTANCE_CHAT = true }
local function groupMember(name)
    if not name or not ns.Group then return nil end
    local m = ns.Group.Member and ns.Group.Member(name)
    if m then return m end
    local s = ns.short(name)
    if (UnitInRaid and UnitInRaid(s)) or (UnitInParty and UnitInParty(s)) then return { name = name } end
    return nil
end
local function groupLead(name)
    if ns.Group and ns.Group.IsAssist and ns.Group.IsAssist(name) then return true end
    local s = ns.short(name or "")
    if UnitIsGroupLeader and ns.safe(UnitIsGroupLeader(s)) then return true end
    if UnitIsGroupAssistant and ns.safe(UnitIsGroupAssistant(s)) then return true end
    return false
end
Raid.GroupMember, Raid.GroupLead = groupMember, groupLead
Comm.On("LOOTSTART", function(sender, channel, sid, link)
    if not GROUPCH[channel or ""] or not groupMember(sender) or not groupLead(sender) then return end
    link = SEC.Link(link)
    sid = tostring(sid or "")
    if not link or not sid:match("^%d+$") or #sid > 12 then return end
    if not SEC.Rate("lootstart", 2) then return end
    Raid.session = { sid = sid, link = link, leader = sender, responses = {}, t = ns.now() }
    Raid.ShowPopup(Raid.session)
    ns.RefreshPage("raid")
end)

local function respond(choice)
    local s = Raid.session
    if not s then return end
    local e1, e2 = equippedFor(s.link)
    local r = { choice = choice, e1 = e1, e2 = e2 }
    -- der Verteiler wuerfelt fuer jede Antwort (gleiche Regeln fuer alle)
    if ns.isMe(s.leader) and choice ~= "pass" then r.roll = math.random(1, 100) end
    s.responses[ns.me()] = r
    if not ns.isMe(s.leader) then
        Comm.Group("LOOTRESP", s.sid, choice, e1, e2)
    end
    ns.RefreshPage("raid")
end
Comm.On("LOOTRESP", function(sender, _, sid, choice, e1, e2)
    local s = Raid.session
    if not s or s.sid ~= sid or s.awarded then return end
    if not CHOICES[choice or ""] or not groupMember(sender) then return end   -- nur Mitspieler, gueltige Wahl
    local function iid(v) v = tostring(v or "") return v:match("^%d+$") and #v <= 9 and v or "" end
    e1, e2 = iid(e1), iid(e2)
    -- schon gewuerfelt? kein Neuwuerfeln durch erneutes Senden
    local old = s.responses[sender]
    if old and old.roll and choice ~= "pass" then old.choice = choice ns.RefreshPage("raid") return end
    s.responses[sender] = { choice = choice, e1 = e1 or "", e2 = e2 or "", roll = (ns.isMe(s.leader) and choice ~= "pass") and math.random(1, 100) or nil }
    ns.RefreshPage("raid")
end)

function Raid.Award(name)
    local s = Raid.session
    if not s or s.awarded then return end
    s.awarded = name
    -- Beute-Punkte buchen (nur wer Punkte vergeben darf)
    if ns.Points and ns.Points.CanManage() then
        local choice = s.responses[name] and s.responses[name].choice or "need"
        local cost = ns.Points.ItemCost(s.link, choice)
        if cost > 0 then ns.Points.Charge(name, cost, s.link, choice) end
    end
    Comm.Group("LOOTAWARD", s.sid, name)
    Store.Put("loot", {
        id = "award-" .. s.sid, item = s.link, who = name, src = "Vergabe",
        zone = ns.safe(GetRealZoneText()) or "", mapID = C_Map.GetBestMapForUnit("player") or 0,
        ts = ns.now(), quality = select(3, C_Item.GetItemInfo(s.link)) or 0,
    })
    if Raid.announce then
        local ch = ns.groupChannel()
        if ch then ns.SendChat(L["[Oasis] "] .. s.link .. " > " .. ns.short(name), ch) end
    end
    ns.RefreshPage("raid")
end
Comm.On("LOOTAWARD", function(sender, _, sid, name)
    local s = Raid.session
    if not s or s.sid ~= sid then return end
    if not (ns.Admin and ns.Admin.SameName and ns.Admin.SameName(sender, s.leader) or sender == s.leader) then return end   -- nur der Verteiler selbst
    name = SEC.Name(name)
    if not name then return end
    s.awarded = name
    if ns.isMe(name) and ns.db.settings.raidWinToast ~= false then
        K.Toast(L["Du bekommst das Item!"], s.link, C.mint)
    end
    if Raid.popup then Raid.popup:Hide() end
    ns.RefreshPage("raid")
end)

-- Popup fuer die Wahl: Item gross mit Qualitaetsrahmen, Verbesserung fuer dich, vier Wahl-Knoepfe, Zeitbalken
local POP_W = 420
function Raid.ShowPopup(s)
    local f = Raid.popup
    local LM = ns.LootMaster
    if not f then
        f = CreateFrame("Frame", "OasisLootPopup", UIParent)
        f:SetSize(POP_W, 168)
        f:SetPoint("CENTER", 0, 180)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        K.Fill(f, C.bg)
        K.Border(f, C.line)
        f.edge = f:CreateTexture(nil, "ARTWORK")
        f.edge:SetPoint("TOPLEFT") f.edge:SetPoint("TOPRIGHT") f.edge:SetHeight(2)
        f.glow = f:CreateTexture(nil, "BORDER")
        f.glow:SetPoint("TOPLEFT") f.glow:SetPoint("TOPRIGHT") f.glow:SetHeight(90)
        f.head = K.Text(f, 10, C.muted)
        f.head:SetPoint("TOPLEFT", 14, -12)
        f.head:SetWidth(POP_W - 90)
        f.head:SetWordWrap(false)
        f.left = K.Title(f, 13, C.text, "RIGHT")
        f.left:SetPoint("TOPRIGHT", -14, -10)
        f.left:SetWidth(60)
        if LM and LM.ItemButton then
            f.iconBtn = LM.ItemButton(f, 52)
        else
            f.iconBtn = CreateFrame("Button", nil, f)
            f.iconBtn:SetSize(52, 52)
            f.iconBtn.icon = f.iconBtn:CreateTexture(nil, "ARTWORK")
            f.iconBtn.icon:SetAllPoints()
            function f.iconBtn:SetItem(l) self.link = l self.icon:SetTexture(C_Item.GetItemIconByID(ns.itemID(l) or 0) or 134400) end
            f.iconBtn:SetScript("OnEnter", function(self) K.ItemTip(self, Raid.session and Raid.session.link) end)
            f.iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        f.iconBtn:SetPoint("TOPLEFT", 14, -32)
        f.icon = f.iconBtn.icon
        f.name = K.Text(f, 15, C.text)
        f.name:SetPoint("TOPLEFT", 78, -32)
        f.name:SetWidth(POP_W - 92)
        f.name:SetWordWrap(false)
        f.up = K.Text(f, 11, C.muted)
        f.up:SetPoint("TOPLEFT", 78, -52)
        f.up:SetWidth(POP_W - 92)
        f.up:SetWordWrap(false)
        f.eq = K.Text(f, 10, C.dim)
        f.eq:SetPoint("TOPLEFT", 78, -68)
        f.eq:SetWidth(POP_W - 92)
        f.eq:SetWordWrap(true)
        f.eq:SetJustifyV("TOP")
        local bw = math.floor((POP_W - 28 - 3 * 6) / 4)
        f.buttons = {}
        for k, key in ipairs({ "need", "greed", "mog", "pass" }) do
            local ch = CHOICES[key]
            local b = K.Button(f, ch[1], bw, 28, key == "need" and "primary" or "ghost", function()
                respond(key)
                f:Hide()
            end)
            b:SetPoint("BOTTOMLEFT", 14 + (k - 1) * (bw + 6), 22)
            b.cl = b:CreateTexture(nil, "OVERLAY")
            b.cl:SetPoint("BOTTOMLEFT", 1, 1) b.cl:SetPoint("BOTTOMRIGHT", -1, 1) b.cl:SetHeight(2)
            b.cl:SetColorTexture(ch[2][1], ch[2][2], ch[2][3], 0.9)
            f.buttons[k] = b
        end
        -- Zeitbalken (Farbe laeuft gruen -> rot)
        f.timer = K.Bar(f, POP_W - 28, 5)
        f.timer:SetPoint("BOTTOMLEFT", 14, 10)
        f:SetScript("OnUpdate", function(self)
            local left = 1 - (GetTime() - self.start) / 60
            self.timer:Set(left)
            if LM and LM.TimeColor then
                local r, g, b = LM.TimeColor(math.max(0, left))
                self.timer.fill:SetColorTexture(r, g, b, 1)
            end
            self.left:SetText(("%d s"):format(math.max(0, math.ceil(left * 60))))
            if left <= 0 then self:Hide() end
        end)
        Raid.popup = f
    end
    f.start = GetTime()
    f.head:SetText(K.Upper((L["Beuteverteilung von %s"]):format(ns.displayName(s.leader))))
    f.name:SetText(s.link)
    f.iconBtn:SetItem(s.link)
    local qc = (LM and LM.QColor and LM.QColor(LM.Quality(s.link))) or C.accent
    f.edge:SetColorTexture(qc[1], qc[2], qc[3], 1)
    if not K.Gradient(f.glow, "VERTICAL", { qc[1], qc[2], qc[3], 0 }, { qc[1], qc[2], qc[3], 0.14 }) then f.glow:SetColorTexture(qc[1], qc[2], qc[3], 0.05) end
    local up
    if ns.Upgrade and ns.Upgrade.Text then local ok, t = pcall(ns.Upgrade.Text, s.link) if ok then up = t end end
    f.up:SetText(up or ("|cff666666" .. L["Kein Vergleich moeglich"] .. "|r"))
    if ns.Upgrade and ns.Upgrade.Glow and ns.Upgrade.Compare then
        local ok, pct = pcall(ns.Upgrade.Compare, s.link)
        pcall(ns.Upgrade.Glow, f.iconBtn, ok and pct or nil, (ns.db and ns.db.settings and ns.db.settings.noAnim) and true or false)
    end
    local e1, e2 = equippedFor(s.link)
    local pts = ""
    if ns.Points then
        local me = ns.Points.Of(ns.me())
        pts = "\n" .. (L["Deine Prioritaet %s (Platz %d)  ·  Bedarf kostet %d, Zweitspec %d"]):format(ns.Points.FmtPR(me.pr), me.rank,
            ns.Points.ItemCost(s.link, "need"), ns.Points.ItemCost(s.link, "greed"))
    end
    f.eq:SetText(L["Angelegt: "] .. (e1 ~= "" and e1 or "-") .. (e2 ~= "" and ("  " .. e2) or "") .. pts)
    ns.withItem(s.link, function(link, _, _, icon)
        f.name:SetText(link)
        f.iconBtn:SetItem(link)
        if icon and f.icon then f.icon:SetTexture(icon) end
    end)
    f:Show()
    K.FadeIn(f, 0, 0)
    ns.Sound.Play("loot")
end

------------------------------------------------------------------------
-- Beute-Log: eigene Beute ab gewaehlter Qualitaet
------------------------------------------------------------------------
local function toPattern(fmt)
    if not fmt then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p
end
local createdPat = toPattern(LOOT_ITEM_CREATED_SELF)

ns.On("CHAT_MSG_LOOT", function(text, playerName)
    text, playerName = ns.safe(text), ns.safe(playerName)
    if not text then return end
    if createdPat and text:match(createdPat) then return end
    local me = ns.short(ns.me())
    if playerName and playerName ~= "" and not ns.isMe(playerName) and not ns.SameName(playerName, me) then return end
    if not playerName or playerName == "" then
        -- Fallback: nur Texte der eigenen Beute
        local selfPat = toPattern(LOOT_ITEM_SELF)
        local pushPat = toPattern(LOOT_ITEM_PUSHED_SELF)
        if not ((selfPat and text:match(selfPat)) or (pushPat and text:match(pushPat))) then return end
    end
    -- Farbcodes sind je nach Client |cffXXXXXX oder |cnIQ4: -> nur den Item-String nehmen
    local itemString = text:match("|H(item:[^|]+)|h")
    if not itemString then return end
    ns.withItem(itemString, function(full, _, quality)
        quality = quality or 0
        local id = ns.itemID(full)
        if Raid.RecentLoot(id) then return end
        if quality >= 4 then if ns.Badges then ns.Badges.Add("epics", 1) end end
        if quality < (ns.db.settings.lootMinQuality or 3) then return end
        Store.Put("loot", {
            id = ("loot-%s-%d-%d"):format(ns.short(ns.me()), id or 0, math.floor(ns.now() / 30)),
            item = full, who = ns.me(), src = "Beute", quality = quality, raid = ((select(2, IsInInstance())) == "raid" or IsInRaid()) or nil,   -- 0.6.460: Raid-Kennung
            zone = ns.safe(GetRealZoneText()) or "", mapID = C_Map.GetBestMapForUnit("player") or 0, ts = ns.now(),
        })
    end)
end)

------------------------------------------------------------------------
-- Blizzards Beute-Verlauf (wer hat was pro Boss bekommen) - zuverlaessiger als der Chat
------------------------------------------------------------------------
local recent = {}
-- dasselbe Item nicht doppelt erfassen (Chat + Beute-Verlauf)
function Raid.RecentLoot(itemID)
    if not itemID then return false end
    local t = recent[itemID]
    recent[itemID] = GetTime()
    return t and (GetTime() - t) < 120
end

local function scanLootHistory()
    local LH = C_LootHistory
    if not (LH and LH.GetAllEncounterInfos and LH.GetSortedDropsForEncounter) then return end
    local ok, encs = pcall(LH.GetAllEncounterInfos)
    if not ok or type(encs) ~= "table" then return end
    for _, enc in ipairs(encs) do
        local ok2, drops = pcall(LH.GetSortedDropsForEncounter, enc.encounterID)
        if ok2 and type(drops) == "table" then
            for _, drop in ipairs(drops) do
                local w = drop.winner
                local link = ns.safe(drop.itemHyperlink)
                if w and ns.safe(w.isSelf) and link then
                    local id = ("lh-%s-%s-%s"):format(tostring(enc.encounterID), tostring(drop.lootListID or ns.itemID(link)), date("%y%m%d"))
                    if not Store.Get("loot", id) then
                        local itemID = ns.itemID(link)
                        local _, full, quality = C_Item.GetItemInfo(link)
                        quality = quality or 0
                        if not Raid.RecentLoot(itemID) then
                            if quality >= 4 and ns.Badges then ns.Badges.Add("epics", 1) end
                            if quality >= (ns.db.settings.lootMinQuality or 3) then
                                Store.Put("loot", {
                                    id = id, item = full or link, who = ns.me(), src = "Beute", quality = quality, raid = ((select(2, IsInInstance())) == "raid" or IsInRaid()) or nil,
                                    zone = ns.safe(enc.encounterName) or ns.safe(GetRealZoneText()) or "",
                                    mapID = C_Map.GetBestMapForUnit("player") or 0, ts = ns.now(),
                                })
                            end
                        end
                    end
                end
            end
        end
    end
end
local lhPending
local function lhSoon()
    if lhPending then return end
    lhPending = true
    ns.After(2, function() lhPending = nil local ok, e = pcall(scanLootHistory) if not ok then ns.err("LootHistory", e) end end)
end
ns.On("LOOT_HISTORY_UPDATE_DROP", lhSoon)
ns.On("LOOT_HISTORY_UPDATE_ENCOUNTER", lhSoon)
Raid.ScanLootHistory = scanLootHistory

------------------------------------------------------------------------
-- Seite
-- Reiter fuer alle: Termine (Karten + Detail), Meine Beute, Beute-Log
-- Reiter "Raidleitung" (nur Berechtigte): Neuer Termin, Verteilung, Aufstellung, Punkte
------------------------------------------------------------------------
local tab, selectedEv, lootSearch = "events", nil, ""
local leadTab, showDetail = "new", false
local pageRef
local leadRef   -- Rahmen der Seite "Raidleitung" (eigener Navigationspunkt)
local LEAD_TABS = { new = true, loot = true, plan = true, points = true }
local itemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local prefillAt

-- Raidleitung sichtbar: Leitung / Schlachtzugsleiter / Assistenten (Admin.CanRaidPlan),
-- dazu wer gerade eine Verteilung leitet (sonst kaeme der Pluendermeister nicht an seine Liste)
local function canLead()
    if ns.Admin and ns.Admin.Can and ns.Admin.Can("raid.events") then return true end
    if Raid.session and ns.isMe(Raid.session.leader) then return true end
    return false
end
Raid.CanLead = canLead

local function applyTabs()
    local p = pageRef
    local lead = canLead()
    if not p then
        if leadRef then
            leadRef.seg:Select(leadTab)
            for k, f in pairs(leadRef.tabs) do f:SetShown(k == leadTab) end
            for _, lk in pairs(leadRef.locks or {}) do lk:Update() end
        end
        return
    end
    -- Raidleitung fuer alle sichtbar, fuer Nicht-Berechtigte gesperrt (abgedunkelt mit Hinweis)
    if p.leadSegBtn then p.leadSegBtn:Show() end
    p.seg:Select(tab)
    for k, f in pairs(p.tabs) do f:SetShown(k == tab) end
    local ld = leadRef
    if ld then
        ld.seg:Select(leadTab)
        for k, f in pairs(ld.tabs) do f:SetShown(k == leadTab) end
        for _, lk in pairs(ld.locks or {}) do lk:Update() end
        if ld.badge then ld.badge:SetText(lead and L["nur fuer die Raidleitung sichtbar"] or L["Du hast diese Rechte nicht - du siehst nur."]) end
    end
end

local lootTab = "mine"
function Raid.SetTab(t)
    if t == "mine" or t == "log" then
        lootTab = t
        ns.ShowPage("loot")
        ns.RefreshPage("loot")
        return
    end
    -- Termin-Vorlage (z.B. aus dem Dungeon-Journal) gehoert ins Formular der Raidleitung
    if t == "events" and (Raid.prefill or (prefillAt and GetTime() - prefillAt < 2)) and canLead() then t = "new" end
    if LEAD_TABS[t] or t == "lead" then
        if LEAD_TABS[t] then leadTab = t end
        applyTabs()
        ns.ShowPage("raidlead")
        ns.RefreshPage("raidlead")
        return
    end
    if t == "events" then showDetail = false end
    tab = t
    if pageRef then
        applyTabs()
        ns.RefreshPage("raid")
    end
end
-- Termin in der Detailansicht oeffnen
function Raid.OpenEvent(id)
    selectedEv, showDetail = id, true
    tab = "events"
    if pageRef then applyTabs() ns.RefreshPage("raid") end
end

-- Art eines Termins (Farbe/Symbol)
local function kindOf(ev)
    return Raid.KIND[ev.kind or ((ev.max or 5) > 5 and "raid" or "dungeon")] or Raid.KIND.other
end
-- empfohlene Aufstellung je Groesse
local function needFor(max)
    max = max or 5
    local need = (max <= 5 and { tank = 1, heal = 1 }) or (max <= 10 and { tank = 2, heal = 3 }) or (max <= 20 and { tank = 2, heal = 5 }) or { tank = 4, heal = 10 }
    need.dps = math.max(0, max - need.tank - need.heal)
    return need
end
-- "heute 20:00", "morgen", "in 3 Tagen"
local function countdown(ts)
    local d = (ts or 0) - ns.now()
    if d <= 0 then return "|cff66db9e" .. L["laeuft gerade"] .. "|r" end
    if d < 3600 then return "|cffe8b44a" .. (L["in %d Min"]):format(math.max(1, math.floor(d / 60))) .. "|r" end
    local today = date("%Y%m%d", ns.now())
    local tomorrow = date("%Y%m%d", ns.now() + 86400)
    local day = date("%Y%m%d", ts)
    if day == today then return "|cffe8b44a" .. L["heute"] .. "  ·  " .. (L["in %d Std"]):format(math.floor(d / 3600)) .. "|r" end
    if day == tomorrow then return "|cffe8b44a" .. L["morgen"] .. "|r" end
    return (L["in %d Tagen"]):format(math.max(2, math.floor(d / 86400 + 0.5)))
end
-- Wunschrolle fuer eine Zusage: bisherige Anmeldung, sonst Profilrolle, sonst Schaden
local function myRole(ev)
    local mine = Raid.MySignup(ev.id)
    if mine and mine.role and ROLES[mine.role] then return mine.role end
    if ns.Profile and ns.Profile.RolesOf then
        local r = ns.Profile.RolesOf(ns.me())
        for _, k in ipairs({ "tank", "heal", "dps" }) do if r[k] then return k end end
    end
    return "dps"
end
local function signUp(ev, role, status)
    if not ev or ev.cal or ev.preview then return end
    Raid.SignUp(ev, role, status)
    ns.RefreshPage("raid")
    ns.RefreshPage("groups")
end

------------------------------------------------------------------------
-- Animationen + Helfer fuer Banner, Wunsch-Beute und Teilnahme
------------------------------------------------------------------------
-- Animationen aus, wenn der Spieler sie reduziert hat
local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
-- kurzer Puls: Leuchten + leicht wachsender Rahmen ueber einem Knopf/Feld
local function pulse(b, c)
    if not b or not animOn() then return end
    c = c or C.accent
    local g = b.pulseTex
    if not g then
        g = b:CreateTexture(nil, "OVERLAY")
        g:SetBlendMode("ADD")
        b.pulseTex = g
    end
    g:SetColorTexture(c[1], c[2], c[3], 1)
    g:SetAlpha(0)
    g:Show()
    K.Tween(g, 0.45, function(p)
        local d = 1 + 4 * p
        g:ClearAllPoints()
        g:SetPoint("TOPLEFT", b, "TOPLEFT", -d, d)
        g:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", d, -d)
        g:SetAlpha(0.42 * (1 - p))
    end, function() g:Hide() end)
end
-- Balken (K.Bar) auf p fuellen, auf Wunsch von 0 aus
local function fillBar(bar, p, animate)
    bar.p = p
    if not animate or not animOn() then bar:Set(p) return end
    bar:Set(0)
    K.Tween(bar, 0.7, function(x) bar:Set(p * x) end, function() bar:Set(bar.p or p) end)
end

------------------------------------------------------------------------
-- Bausteine im Stil von Profil / Handwerks-Boerse (lokal nachgebaut, Kit bleibt unberuehrt)
------------------------------------------------------------------------
local FAM_CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local FAM_EMBER = ns.MEDIA .. "ember"
local function famGrad(tex, dir, c, a1, a2, fb)
    if not K.Gradient(tex, dir, { c[1], c[2], c[3], a1 }, { c[1], c[2], c[3], a2 }) then
        tex:SetColorTexture(c[1], c[2], c[3], fb or (a1 + a2) / 2)
    end
end
-- Leuchtscheibe: Schein + dunkle Scheibe in Farbe + Symbol (wie Leerzustand/Kacheln der Vorbilder)
local function famDisc(parent, size, glyph, color)
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(size, size)
    d.halo = d:CreateTexture(nil, "BACKGROUND")
    d.halo:SetTexture(FAM_EMBER)
    d.halo:SetBlendMode("ADD")
    d.halo:SetSize(size * 2, size * 2)
    d.halo:SetPoint("CENTER")
    d.halo:SetAlpha(0.3)
    d.disc = d:CreateTexture(nil, "BORDER")
    d.disc:SetTexture(FAM_CIRCLE)
    d.disc:SetAllPoints()
    d.icon = K.Glyph(d, math.floor(size * 0.5 + 0.5), glyph, color)
    d.icon:SetPoint("CENTER")
    function d:SetColor(c)
        self.halo:SetVertexColor(c[1], c[2], c[3])
        self.disc:SetVertexColor(c[1] * 0.25, c[2] * 0.25, c[3] * 0.25)
        self.icon:SetVertexColor(c[1], c[2], c[3])
    end
    d:SetColor(color or C.accent)
    return d
end
-- Kennzahl-Kachel: Leuchtscheibe links, grosse Zahl mittig, Beschriftung darunter, Farbkante oben,
-- Verlauf + Schein beim Hover, Fortschrittsbalken unten. Gleiche Schnittstelle wie K.HudTile (:Set, .tip).
local function famTile(parent, icon, label, color, onClick)
    color = color or C.accent
    local c = color
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(66)
    t.color = c
    t.grad = t:CreateTexture(nil, "BORDER", nil, 1)
    t.grad:Hide()
    t.hov = t:CreateTexture(nil, "BORDER", nil, 2)
    t.hov:SetColorTexture(1, 1, 1, 0)
    t.top = t:CreateTexture(nil, "ARTWORK")
    t.top:Hide()
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(t, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.10 }, 12) end
    t.disc = famDisc(t, 34, icon, c)
    t.disc.halo:Hide()
    t.disc:SetPoint("LEFT", 12, 0)
    t.icon = t.disc.icon
    t.value = K.Title(t, 24, C.text, "CENTER")
    t.value:SetPoint("TOP", 0, -9)
    t.value:SetPoint("LEFT", t.disc, "RIGHT", 4, 0)
    t.value:SetPoint("RIGHT", t, "RIGHT", -8, 0)
    t.value:SetWordWrap(false)
    t.label = K.Text(t, 10, C.muted, "CENTER")
    t.label:SetPoint("BOTTOM", 0, 9)
    t.label:SetPoint("LEFT", t.disc, "RIGHT", 4, 0)
    t.label:SetPoint("RIGHT", t, "RIGHT", -8, 0)
    t.label:SetWordWrap(false)
    t.label:SetText(label)
    t.sub = K.Text(t, 10, c, "CENTER")
    t.sub:SetPoint("TOP", t.value, "BOTTOM", 0, -1)
    t.sub:SetPoint("LEFT", t.disc, "RIGHT", 4, 0)
    t.sub:SetPoint("RIGHT", t, "RIGHT", -8, 0)
    t.sub:SetWordWrap(false)
    t.bar = t:CreateTexture(nil, "ARTWORK", nil, 2)
    t.bar:SetPoint("BOTTOMLEFT")
    t.bar:SetHeight(2)
    t.bar:SetColorTexture(c[1], c[2], c[3], 0.9)
    t.bar:Hide()
    local function hover(on)
        local h0, h1 = t.hov:GetAlpha() or 0, on and 1 or 0
        if animOn() then
            K.Tween(t.hov, 0.16, function(q) t.hov:SetAlpha(h0 + (h1 - h0) * q) end)
        else
            t.hov:SetAlpha(h1)
        end
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(t, { 1, 1, 1, on and 0.06 or 0.03 }, { 1, 1, 1, 0.10 }, 12) end
    end
    t:SetScript("OnEnter", function(self)
        hover(true)
        if self.tip then K.ShowTip(self, self.tip) end
    end)
    t:SetScript("OnLeave", function() hover(false) GameTooltip:Hide() end)
    if onClick then t:SetScript("OnClick", onClick) end
    -- Wert setzen; animate = hochzaehlen; progress 0..1 = Balken unten; sub = farbiger Zusatz unter der Zahl
    function t:Set(value, sub, progress, animate)
        local s = sub or ""
        self.sub:SetText(s)
        self.sub:SetShown(s ~= "")
        -- mit Zusatz rutscht die Zahl etwas hoch, damit alles in die Kachel passt
        self.value:ClearAllPoints()
        self.value:SetPoint("TOP", 0, s ~= "" and -6 or -11)
        self.value:SetPoint("LEFT", self.disc, "RIGHT", 4, 0)
        self.value:SetPoint("RIGHT", self, "RIGHT", -8, 0)
        self.label:SetShown(s == "" or (self:GetHeight() or 66) >= 66)
        local n = tonumber(value)
        local vc = (n == nil or n > 0) and C.text or C.dim
        self.value:SetTextColor(vc[1], vc[2], vc[3])
        if animate and n and animOn() then K.CountUp(self.value, n, 0.9) else self.value:SetText(value ~= nil and tostring(value) or "-") end
        if progress then
            self.bar:Show()
            local w = math.max(1, (self:GetWidth() or 100) * math.max(0, math.min(1, progress)))
            if animate and animOn() then
                self.bar:SetWidth(1)
                K.Tween(self.bar, 0.9, function(p) self.bar:SetWidth(math.max(1, w * p)) end)
            else
                self.bar:SetWidth(w)
            end
        else
            self.bar:Hide()
        end
    end
    return t
end

-- eigene Wuensche (Gesucht-Liste) nach Item-ID
local function myWantIDs()
    local out, n = {}, 0
    if not (ns.Wants and ns.Wants.All) then return out, 0 end
    for _, w in ipairs(ns.Wants.All()) do
        if (tonumber(w.itemID) or 0) > 0 and not w.del and ns.isMe(w.who) then out[w.itemID] = w n = n + 1 end
    end
    return out, n
end
-- Eintrag der Dungeon-Datenbank zum Ziel/Titel eines Termins
local function dungeonEntry(ev)
    if not (ev and ns.Dungeons and ns.Dungeons.Match) then return nil end
    local ok, d = pcall(function() return ns.Dungeons.Match(ev.inst) or ns.Dungeons.Match(ev.title) end)
    if not ok or type(d) ~= "table" then return nil end
    if type(d.data) == "table" and d.data.bosses then return d.data, d end
    for _, e in ipairs(ns.DungeonData or {}) do
        if e.name == d.nameEN or e.name == d.name or (e.de and e.de == d.name) or ("db:" .. tostring(e.key)) == d.key then return e, d end
    end
    return nil, d
end
-- Beute der Ziel-Instanz, die auf deiner Wunschliste steht
function Raid.WantedLoot(ev)
    if not ev or ev.cal then return {} end
    local wants, n = myWantIDs()
    if n == 0 then return {} end
    local e = dungeonEntry(ev)
    local out, seen = {}, {}
    for _, b in ipairs(e and e.bosses or {}) do
        for _, it in ipairs(b.loot or {}) do
            local id = it[1]
            if id and wants[id] and not seen[id] then
                seen[id] = true
                out[#out + 1] = { id = id, name = it[2], boss = b.name }
            end
        end
    end
    return out
end
-- naechster kommender Termin, fuer den du zugesagt hast
function Raid.NextMine()
    local now = ns.now()
    for _, ev in ipairs(Raid.Events()) do
        if (ev.ts or 0) > now - 3600 then
            local m = Raid.MySignup(ev.id)
            if m and m.status == "yes" then return ev, m end
        end
    end
end
-- deine Gruppe in der Aufstellung (Raidplaner)
local function myGroup(evId)
    if not (ns.RaidPlanner and ns.RaidPlanner.Get) then return nil end
    local ok, plan = pcall(ns.RaidPlanner.Get, evId)
    if not ok or type(plan) ~= "table" then return nil end
    for name, sl in pairs(plan.slots or {}) do
        if ns.isMe(name) then return sl.group end
    end
end
-- Teilnahme der letzten Tage: zugesagt / in der Aufstellung / Termine gesamt
function Raid.Attendance(days)
    local now = ns.now()
    local from = now - (days or 30) * 86400
    local total, yes, planned = 0, 0, 0
    for _, e in ipairs(Store.List("events", function(e) return (e.ts or 0) < now and (e.ts or 0) >= from and not e.del end)) do
        total = total + 1
        local m = Raid.MySignup(e.id)
        if m and m.status == "yes" then yes = yes + 1 end
        if myGroup(e.id) then planned = planned + 1 end
    end
    return yes, total, planned
end
-- Vorbereitung (nur ausserhalb des Kampfes abfragen, sonst letzter Stand)
local prepCache = {}
local function prepState()
    if not (InCombatLockdown and ns.safe(InCombatLockdown())) then
        local sum, n = 0, 0
        if GetInventoryItemDurability then
            for slot = 1, 18 do
                local ok, cur, mx = pcall(GetInventoryItemDurability, slot)
                if ok then
                    cur, mx = ns.safe(cur), ns.safe(mx)
                    if type(cur) == "number" and type(mx) == "number" and mx > 0 then sum = sum + cur / mx n = n + 1 end
                end
            end
        end
        prepCache.dura = n > 0 and (sum / n) or nil
        prepCache.raid = (IsInRaid and ns.safe(IsInRaid())) and true or false
        prepCache.group = (IsInGroup and ns.safe(IsInGroup())) and true or false
    end
    return prepCache
end
-- grosser Countdown: "2:04:13" (Tage:Std:Min) bzw. "04:13" (Std:Min)
local function bigCountdown(ts)
    local d = (ts or 0) - ns.now()
    if d <= 0 then return L["laeuft gerade"], "" end
    local days = math.floor(d / 86400)
    local h = math.floor((d % 86400) / 3600)
    local m = math.floor((d % 3600) / 60)
    if days > 0 then return ("%d:%02d:%02d"):format(days, h, m), L["Tage : Std : Min"] end
    return ("%02d:%02d"):format(h, m), L["Std : Min"]
end

------------------------------------------------------------------------
-- Termin-Karte (eine Zeile der Kartenliste)
------------------------------------------------------------------------
local STATUS = {
    { key = "yes", text = "Zusage", color = C.mint },
    { key = "maybe", text = "Vielleicht", color = C.amber },
    { key = "no", text = "Absage", color = C.red },
}
local DET_BAN_H, DET_TILE_H = 96, 44   -- Detailansicht: Bannerhoehe, Kachelhoehe
local CARD_H = 198   -- Hoehe der Vorschau-Karte im Formular; in der Liste waechst jede Karte mit ihrem Inhalt
local DATE_W = 54
local CX = DATE_W + 12   -- hier beginnt der Inhalt rechts vom Datumsblock
-- K.Button setzt beim Verlassen den Rahmen zurueck -> gewaehlte Farbe danach wieder setzen
local function keepBorder(b)
    b:HookScript("OnLeave", function(s) if s.onColor then K.SetBorderColor(s, s.onColor) end end)
end

-- Namens-Chip (Teilnehmer, freier Platz oder Gruppen-Kennung), wiederverwendet je Karte
local function chipAt(r, i)
    local c = r.chips[i]
    if c then return c end
    c = CreateFrame("Frame", nil, r.card)
    c:SetHeight(16)
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bar = c:CreateTexture(nil, "ARTWORK")
    c.bar:SetPoint("TOPLEFT")
    c.bar:SetPoint("BOTTOMLEFT")
    c.bar:SetWidth(2)
    c.icon = K.Glyph(c, 10, nil, C.text)
    c.icon:SetPoint("LEFT", 5, 0)
    c.t = K.Text(c, 10, C.text)
    c.t:SetPoint("LEFT", 17, 0)
    c.t:SetPoint("RIGHT", -4, 0)
    c.t:SetWordWrap(false)
    c.dash = {}
    r.chips[i] = c
    return c
end
-- gestrichelter Rahmen fuer freie Plaetze (kurze Striche statt durchgehender Linie)
local function setDashed(c, on, w)
    local n = on and (math.floor((w - 3) / 6) + 1) or 0
    local need = on and (n * 2 + 4) or 0
    for j = 1, math.max(need, #c.dash) do
        local d = c.dash[j]
        if j <= need then
            if not d then d = c:CreateTexture(nil, "BORDER") c.dash[j] = d end
            d:ClearAllPoints()
            d:SetColorTexture(1, 1, 1, 0.24)
            if j <= n then d:SetSize(3, 1) d:SetPoint("TOPLEFT", (j - 1) * 6, 0)
            elseif j <= 2 * n then d:SetSize(3, 1) d:SetPoint("BOTTOMLEFT", (j - n - 1) * 6, 0)
            else
                local k = j - 2 * n
                d:SetSize(1, 4)
                d:SetPoint(k <= 2 and "TOPLEFT" or "TOPRIGHT", 0, (k % 2 == 1) and -2 or -10)
            end
            d:Show()
        elseif d then d:Hide() end
    end
end

-- Gruppen bilden: Raidplan der Leitung, sonst automatisch (Tanks/Heiler auf die Gruppen verteilt)
-- roleOf = { [Name] = "tank"/"heal"/"dps" } (nur Zusagen); liefert groups[1..ng] = { {name, role}, ... }
local function groupsFor(evId, roleOf, ng)
    local groups = {}
    for g = 1, ng do groups[g] = {} end
    local plan = ns.RaidPlanner and ns.RaidPlanner.Get and ns.RaidPlanner.Get(evId)
    local placed = {}
    if plan and plan.slots and next(plan.slots) then
        for name, sl in pairs(plan.slots) do
            local g = groups[sl.group or 1]
            if g and #g < 5 and roleOf[name] then g[#g + 1] = { name = name, role = sl.role or roleOf[name] or "dps" } placed[name] = true end
        end
    end
    local order = {}
    for _, key in ipairs({ "tank", "heal", "dps" }) do
        local tmp = {}
        for name, rl in pairs(roleOf) do if rl == key and not placed[name] then tmp[#tmp + 1] = name end end
        table.sort(tmp)
        for _, name in ipairs(tmp) do order[#order + 1] = { name = name, role = key } end
    end
    local gi = 1
    for _, x in ipairs(order) do
        for _ = 1, ng do
            if #groups[gi] < 5 then break end
            gi = gi % ng + 1
        end
        if #groups[gi] < 5 then groups[gi][#groups[gi] + 1] = x end
        gi = gi % ng + 1
    end
    return groups
end
-- Gruppen-Raster: Spalten G1..Gn, je 5 Plaetze untereinander (Karten und Detailansicht)
-- r.card = Halter, r.chips = Chip-Vorrat; extraOf(m) liefert optional Zusatztext + Tooltipzeile
-- liefert neue Chipzahl und die Oberkante des letzten Platzes
local function drawGroupGrid(r, groups, ng, x0, yTop, avail, nameOf, nChip, extraOf, onClick)
    local cols = ng
    if ng > 4 and (avail - (ng - 1) * 4) / ng < 70 then cols = math.ceil(ng / 2) end
    local cw = math.floor((avail - (cols - 1) * 4) / cols)
    if r.maxColW then cw = math.min(cw, r.maxColW) end
    for g = 1, ng do
        local ci, ri = (g - 1) % cols, math.floor((g - 1) / cols)
        local gx, gy = x0 + ci * (cw + 4), yTop - ri * 112
        nChip = nChip + 1
        local h = chipAt(r, nChip)
        h:EnableMouse(false)
        h.tip = nil
        h.t:SetText("|cff888888" .. (L["G%d"]):format(g) .. "|r  |cff555555" .. #groups[g] .. "/5|r")
        h.icon:Hide()
        h.t:ClearAllPoints()
        h.t:SetPoint("LEFT", 3, 0)
        h.t:SetPoint("RIGHT", -2, 0)
        h.bg:SetColorTexture(1, 1, 1, 0.04)
        h.bar:Hide()
        setDashed(h, false, cw)
        h:SetAlpha(1)
        h:SetSize(cw, 14)
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", r.card, "TOPLEFT", gx, gy)
        h:Show()
        for s = 1, 5 do
            local m = groups[g][s]
            nChip = nChip + 1
            local c = chipAt(r, nChip)
            c:SetSize(cw, 16)
            c.t:ClearAllPoints()
            c.t:SetPoint("LEFT", m and 17 or 5, 0)
            c.t:SetPoint("RIGHT", -3, 0)
            c.who = m and m.name or nil
            if m then
                local rc = ns.Profile and ns.Profile.ROLE_COLORS[m.role] or C.dim
                local ex, exTip
                if extraOf then ex, exTip = extraOf(m) end
                c.t:SetText(nameOf(m.name) .. (m.maybe and " |cffe8b44a?|r" or "") .. ((ex and cw >= 110) and (" |cff777777" .. ex .. "|r") or ""))
                if ns.Profile then c.icon:SetTexture(ns.Profile.RoleTexture(m.role)) c.icon:Show() else c.icon:Hide() end
                c.icon:SetVertexColor(rc[1], rc[2], rc[3])
                c.icon:SetAlpha(1)
                c.bg:SetColorTexture(rc[1], rc[2], rc[3], 0.12)
                c.bar:SetColorTexture(rc[1], rc[2], rc[3], 0.9)
                c.bar:Show()
                setDashed(c, false, cw)
                c:SetAlpha(m.maybe and 0.5 or 1)
                c.tip = { nameOf(m.name), ROLES[m.role] and ROLES[m.role][1] or m.role,
                    m.maybe and ("|cffe8b44a" .. L["Vielleicht"] .. "|r") or ("|cff66db9e" .. L["Zusage"] .. "|r"),
                    "|cff888888" .. (L["G%d"]):format(g) .. "|r" }
                if exTip then c.tip[#c.tip + 1] = exTip end
            else
                c.t:SetText("")
                c.icon:Hide()
                c.bg:SetColorTexture(1, 1, 1, 0.02)
                c.bar:Hide()
                setDashed(c, true, cw)
                c:SetAlpha(1)
                c.tip = { (L["G%d"]):format(g), "|cff888888" .. L["frei"] .. "|r" }
            end
            if not c.tipHooked then
                c.tipHooked = true
                c:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
                c:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            c:SetScript("OnMouseUp", function(self) if onClick then onClick(self) end end)
            c:EnableMouse(true)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", r.card, "TOPLEFT", gx, gy - 16 - (s - 1) * 18)
            c:Show()
        end
    end
    local rows = math.ceil(ng / cols)
    return nChip, yTop - (rows - 1) * 112 - 16 - 4 * 18
end

local function createCard(l)
    local r = K.Row(l)
    r.stripe:SetAlpha(0)
    r.stripe = nil
    r.hl:ClearAllPoints()
    -- Karte selbst (unten 6px Luft zur naechsten)
    local card = CreateFrame("Frame", nil, r)
    card:SetPoint("TOPLEFT", 0, 0)
    card:SetPoint("BOTTOMRIGHT", 0, 6)
    card:EnableMouse(false)
    r.card = card
    card.bg = K.Fill(card, C.panel)
    K.Border(card, C.line)
    r.hl:SetAllPoints(card)
    r.accent = card:CreateTexture(nil, "ARTWORK")
    r.accent:SetPoint("TOPLEFT")
    r.accent:SetPoint("BOTTOMLEFT")
    r.accent:SetWidth(3)
    -- Datumsblock (schmal)
    r.dateBg = card:CreateTexture(nil, "BORDER")
    r.dateBg:SetPoint("TOPLEFT", 3, 0)
    r.dateBg:SetPoint("BOTTOMLEFT", 3, 0)
    r.dateBg:SetWidth(DATE_W)
    -- Familien-Look (Profil/Handwerks-Boerse): Verlauf in Terminfarbe, Glanz oben, Schein hinter dem Datum
    r.glow = card:CreateTexture(nil, "BORDER", nil, 1)
    r.glow:SetAllPoints()
    r.hov = card:CreateTexture(nil, "BORDER", nil, 2)
    r.hov:SetAllPoints()
    r.hov:SetAlpha(0)
    r.gloss = card:CreateTexture(nil, "ARTWORK", nil, 1)
    r.gloss:SetPoint("TOPLEFT", 1, -1) r.gloss:SetPoint("TOPRIGHT", -1, -1)
    r.gloss:SetHeight(16)
    if not K.Gradient(r.gloss, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.04 }) then r.gloss:Hide() end
    r.dHalo = card:CreateTexture(nil, "BORDER", nil, 3)
    r.dHalo:SetTexture(FAM_EMBER)
    r.dHalo:SetBlendMode("ADD")
    r.dHalo:SetSize(70, 70)
    r.dHalo:SetPoint("CENTER", card, "TOPLEFT", 3 + DATE_W / 2, -32)
    r.dHalo:SetAlpha(0.22)
    r.wday = K.Text(card, 9, C.muted, "CENTER")
    r.wday:SetPoint("TOPLEFT", 3, -8)
    r.wday:SetWidth(DATE_W)
    r.wday:SetWordWrap(false)
    r.day = K.Title(card, 22, C.text, "CENTER")
    r.day:SetPoint("TOPLEFT", 3, -20)
    r.day:SetWidth(DATE_W)
    r.mon = K.Text(card, 9, C.muted, "CENTER")
    r.mon:SetPoint("TOPLEFT", 3, -44)
    r.mon:SetWidth(DATE_W)
    r.time = K.Text(card, 11, C.text, "CENTER", K.FONT)
    r.time:SetPoint("TOPLEFT", 3, -57)
    r.time:SetWidth(DATE_W)

    -- Zeile 1 rechts: Zusage / Vielleicht / Absage
    r.status = {}
    local prev
    for i = #STATUS, 1, -1 do
        local s = STATUS[i]
        local b = K.Button(r, L[s.text], 66, 20, "ghost", function(self)
            local ev = self:GetParent().item
            if not ev then return end
            signUp(ev, s.key == "yes" and myRole(ev) or nil, s.key)
            pulse(self, s.color)
        end)
        if prev then b:SetPoint("RIGHT", prev, "LEFT", -3, 0) else b:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -7) end
        b.st = s
        keepBorder(b)
        b:HookScript("OnLeave", function(x) if x.bgCol and x.bg then x.bg:SetColorTexture(unpack(x.bgCol)) end end)
        r.status[s.key] = b
        prev = b
    end
    -- Zeile 2 rechts: Reservierung
    r.srBtn = K.Button(r, L["Reservieren"], 92, 18, "ghost", function(self)
        local ev = self:GetParent().item
        if ev and ns.SoftRes and ns.SoftRes.Open then ns.SoftRes.Open(ev) end
    end)
    r.srBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -30)
    r.srBtn:HookScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
    r.srBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    -- Zeile 3 rechts: Rolle waehlen
    r.roles = {}
    local prevR
    for i, key in ipairs({ "dps", "heal", "tank" }) do
        local b = K.Button(r, "", 26, 20, "ghost", function(self)
            local ev = self:GetParent().item
            if not ev then return end
            local mine = Raid.MySignup(ev.id)
            local st = mine and mine.status ~= "no" and mine.status or "yes"
            signUp(ev, key, st)
            pulse(self, ns.Profile and ns.Profile.ROLE_COLORS[key] or C.accent)
        end)
        b.glyph = K.Glyph(b, 13, ns.Profile and ns.Profile.RoleTexture(key) or nil, ns.Profile and ns.Profile.ROLE_COLORS[key] or C.text)
        b.glyph:SetPoint("CENTER")
        b.role = key
        b:SetScript("OnEnter", function(self) K.ShowTip(self, { ROLES[key][1], L["Klick: als deine Rolle anmelden"] }) end)
        b:SetScript("OnLeave", function(self) GameTooltip:Hide() K.SetBorderColor(self, self.onColor or C.line) end)
        if prevR then b:SetPoint("RIGHT", prevR, "LEFT", -3, 0) else b:SetPoint("TOPRIGHT", card, "TOPRIGHT", -8, -52) end
        r.roles[key] = b
        prevR = b
    end
    r.roleLbl = K.Text(r, 10, C.dim, "RIGHT")
    r.roleLbl:SetPoint("RIGHT", prevR, "LEFT", -6, 0)
    r.roleLbl:SetText(L["Deine Rolle"])

    -- Zeile 1/2 links: Titel, Termin
    r.title = K.Title(card, 14, C.text)
    r.title:SetPoint("TOPLEFT", CX, -9)
    r.title:SetPoint("RIGHT", r.status.yes, "LEFT", -8, 0)
    r.title:SetWordWrap(false)
    r.kind = K.Glyph(card, 12, nil, C.muted)
    r.kind:SetPoint("TOPLEFT", CX, -32)
    r.meta = K.Text(card, 10, C.muted)
    r.meta:SetPoint("TOPLEFT", CX + 17, -33)
    r.meta:SetPoint("RIGHT", r.srBtn, "LEFT", -8, 0)
    r.meta:SetWordWrap(false)
    -- Zeile 3 links: Rollen-Bloecke (Symbol, Balken, Zahl) - Maus drueber zeigt, wer schon dabei ist
    r.roleBlk = {}
    for i, key in ipairs({ "tank", "heal", "dps" }) do
        local rc = ns.Profile and ns.Profile.ROLE_COLORS[key] or C.text
        local blk = CreateFrame("Frame", nil, card)
        blk:SetSize(94, 16)
        blk:EnableMouse(true)
        blk.icon = K.Glyph(blk, 12, ns.Profile and ns.Profile.RoleTexture(key) or nil, rc)
        blk.icon:SetPoint("LEFT", 0, 0)
        blk.track = blk:CreateTexture(nil, "BORDER")
        blk.track:SetPoint("LEFT", 17, 0)
        blk.track:SetSize(40, 5)
        blk.track:SetColorTexture(rc[1], rc[2], rc[3], 0.15)
        blk.fill = blk:CreateTexture(nil, "ARTWORK")
        blk.fill:SetPoint("LEFT", blk.track, "LEFT")
        blk.fill:SetHeight(5)
        blk.fill:SetColorTexture(rc[1], rc[2], rc[3], 0.95)
        blk.num = K.Text(blk, 10, C.text)
        blk.num:SetPoint("LEFT", blk.track, "RIGHT", 5, 0)
        blk.key, blk.color = key, rc
        blk:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
        blk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.roleBlk[key] = blk
    end
    r.counts = K.Text(card, 10, C.muted)
    r.counts:SetPoint("RIGHT", r.roleLbl, "LEFT", -10, 0)
    r.counts:SetWordWrap(false)
    -- darunter: Teilnehmer als Namens-Chips nebeneinander (mit Umbruch)
    r.chips = {}
    r.sr = K.Text(card, 10, C.muted)
    r.sr:SetWordWrap(false)

    r:SetScript("OnClick", function(self)
        if self.item and not self.item.preview then Raid.OpenEvent(self.item.id) end
    end)
    -- Hover: Rahmen in der Terminfarbe, Karte etwas heller
    r:HookScript("OnEnter", function(self)
        if self.kc then K.SetBorderColor(self.card, self.kc) end
        self.card.bg:SetColorTexture(C.panel[1] + 0.03, C.panel[2] + 0.03, C.panel[3] + 0.035, 1)
        self.hov:SetAlpha(1) self.dHalo:SetAlpha(0.45)
    end)
    r:HookScript("OnLeave", function(self)
        K.SetBorderColor(self.card, C.line)
        self.card.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
        self.hov:SetAlpha(0) self.dHalo:SetAlpha(0.22)
    end)
    return r
end

-- Zeile 3 und Chips an die Kartenbreite anpassen; liefert die benoetigte Hoehe
local function layoutRow3(r, W)
    local narrow = W < 600
    local bw = narrow and 66 or 98
    for i, key in ipairs({ "tank", "heal", "dps" }) do
        local blk = r.roleBlk[key]
        blk:ClearAllPoints()
        blk:SetPoint("TOPLEFT", r.card, "TOPLEFT", CX + (i - 1) * bw, -54)
        blk:SetWidth(bw - 4)
        blk.track:SetWidth(narrow and 14 or 40)
    end
    r.counts:ClearAllPoints()
    r.counts:SetPoint("TOPLEFT", r.card, "TOPLEFT", CX + 3 * bw + 4, -56)
    r.counts:SetPoint("RIGHT", r.roleLbl, "LEFT", -10, 0)
    r.narrow = narrow
end

local function updateCard(r, e)
    local k = kindOf(e)
    local kc = k.color
    r.kc = kc
    r.accent:SetColorTexture(kc[1], kc[2], kc[3], 0.95)
    if r.glow then
        famGrad(r.glow, "HORIZONTAL", kc, 0.10, 0, 0.04)
        famGrad(r.hov, "VERTICAL", kc, 0, 0.12, 0.05)
        r.dHalo:SetVertexColor(kc[1], kc[2], kc[3])
    end
    if not K.Gradient(r.dateBg, "HORIZONTAL", { kc[1], kc[2], kc[3], 0.16 }, { kc[1], kc[2], kc[3], 0.03 }) then
        r.dateBg:SetColorTexture(kc[1], kc[2], kc[3], 0.08)
    end
    local W = r.listW or r:GetWidth() or 0
    if W < 200 then W = 700 end
    layoutRow3(r, W)
    r.wday:SetText(K.Upper and K.Upper(ns.weekday(e.ts)) or ns.weekday(e.ts))
    r.wday:SetTextColor(kc[1], kc[2], kc[3])
    r.day:SetText(tonumber(date("%d", e.ts)))
    r.mon:SetText(date(L["%d.%m."], e.ts))
    r.time:SetText(date("%H:%M", e.ts))
    r.title:SetText(e.title or "?")
    r.kind:SetTexture(ns.ICONS and ns.ICONS[k.icon] or nil)
    r.kind:SetVertexColor(kc[1], kc[2], kc[3])
    local isCal = e.cal and true or false
    for _, b in pairs(r.status) do b:SetShown(not isCal) end
    for _, b in pairs(r.roles) do b:SetShown(not isCal) end
    r.roleLbl:SetShown(not isCal and not r.narrow)
    r.srBtn:SetShown(not isCal and ns.SoftRes ~= nil)
    for _, blk in pairs(r.roleBlk) do blk:SetShown(not isCal) end
    local nChip = 0
    local function hideChips()
        for i = nChip + 1, #r.chips do r.chips[i]:Hide() end
    end
    if isCal then
        r.meta:SetText(countdown(e.ts) .. "  ·  |cff777777" .. L["WoW-Kalender"] .. "|r")
        r.counts:ClearAllPoints()
        r.counts:SetPoint("TOPLEFT", r.card, "TOPLEFT", CX, -56)
        r.counts:SetPoint("RIGHT", r.card, "RIGHT", -10, 0)
        r.counts:SetShown(true)
        r.counts:SetText("|cff888888" .. L["Anmeldung ueber den WoW-Kalender"] .. "|r")
        r.sr:SetText("")
        r.sr:Hide()
        hideChips()
        r.wantH = 78
        return
    end
    r.counts:SetShown(not r.narrow)
    local parts = { countdown(e.ts) }
    if (e.inst or "") ~= "" and e.inst ~= e.title then parts[#parts + 1] = e.inst end
    parts[#parts + 1] = L[k.text]
    if e.by then parts[#parts + 1] = "|cff777777" .. ns.displayName(e.by) .. "|r" end
    r.meta:SetText(table.concat(parts, "  ·  "))
    -- Anmeldestand nach Rollen
    local have, yes, maybe = { tank = 0, heal = 0, dps = 0 }, 0, 0
    local names = { tank = {}, heal = {}, dps = {} }
    local roleOf, maybes = {}, {}
    for _, s in ipairs(Raid.Signups(e.id)) do
        if s.status == "yes" then
            yes = yes + 1
            local rk = have[s.role] and s.role or "dps"
            have[rk] = have[rk] + 1
            roleOf[s.who] = rk
            local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[s.who]
            names[rk][#names[rk] + 1] = ns.colorName and ns.colorName(s.who, m and m.class) or ns.short(s.who or "?")
        elseif s.status == "maybe" then
            maybe = maybe + 1
            maybes[#maybes + 1] = { name = s.who, role = (have[s.role] and s.role) or "dps" }
        end
    end
    local need = needFor(e.max)
    for _, key in ipairs({ "tank", "heal", "dps" }) do
        local blk = r.roleBlk[key]
        local n, nd = have[key], math.max(1, need[key] or 1)
        local full = n >= nd
        blk.fill:SetWidth(math.max(0.01, blk.track:GetWidth() * math.min(1, n / nd)))
        blk.fill:SetShown(n > 0)
        blk.num:SetText((full and "|cff66db9e" or "|cffe8b44a") .. n .. "/" .. nd .. "|r")
        local tip = { ROLES[key][1] .. "  " .. n .. "/" .. nd }
        for j, nm in ipairs(names[key]) do if j <= 12 then tip[#tip + 1] = nm end end
        if n == 0 then tip[#tip + 1] = "|cff888888" .. L["noch niemand"] .. "|r" end
        if not full then tip[#tip + 1] = "|cffe8b44a" .. (L["noch %d gesucht"]):format(nd - n) .. "|r" end
        blk.tip = tip
    end
    r.counts:SetText((L["%d/%d Zusagen"]):format(yes, e.max or 5) .. (maybe > 0 and ("  ·  " .. (L["%d vielleicht"]):format(maybe)) or ""))
    -- Gruppen bilden: Raidplan der Leitung, sonst automatisch (Tanks/Heiler auf die Gruppen verteilt)
    local size = e.max or 5
    local ng = math.max(1, math.min(8, math.ceil(size / 5)))
    local groups = groupsFor(e.id, roleOf, ng)
    -- Chips nebeneinander setzen
    local x0, xMax = CX, W - 10
    local x, y = x0, -78
    local function put(w)
        if x > x0 and x + w > xMax then x = x0 y = y - 19 end
        local px, py = x, y
        x = x + w + 4
        return px, py
    end
    local function chip(kindC, text, role, alpha)
        nChip = nChip + 1
        local c = chipAt(r, nChip)
        local rc = role and ns.Profile and ns.Profile.ROLE_COLORS[role] or C.dim
        c.t:SetText(text)
        if role and ns.Profile then c.icon:SetTexture(ns.Profile.RoleTexture(role)) c.icon:Show() else c.icon:Hide() end
        c.icon:SetVertexColor(rc[1], rc[2], rc[3])
        c.t:ClearAllPoints()
        c.t:SetPoint("LEFT", role and 17 or 5, 0)
        c.t:SetPoint("RIGHT", -4, 0)
        local tw = (c.t:GetStringWidth() or 0)
        local w = math.min(130, math.max(kindC == "head" and 18 or 34, math.floor(tw + (role and 23 or 10))))
        c:SetWidth(w)
        if kindC == "free" then
            c.bg:SetColorTexture(1, 1, 1, 0.02)
            c.bar:Hide()
            c.icon:SetAlpha(0.45)
            setDashed(c, true, w)
        elseif kindC == "head" then
            c.bg:SetColorTexture(0, 0, 0, 0)
            c.bar:Hide()
            setDashed(c, false, w)
        else
            c.bg:SetColorTexture(rc[1], rc[2], rc[3], 0.12)
            c.bar:SetColorTexture(rc[1], rc[2], rc[3], 0.9)
            c.bar:Show()
            c.icon:SetAlpha(1)
            setDashed(c, false, w)
        end
        c:SetAlpha(alpha or 1)
        local px, py = put(w)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", r.card, "TOPLEFT", px, py)
        c:Show()
    end
    local function nameOf(n)
        local mm = ns.Radar and ns.Radar.byName and ns.Radar.byName[n]
        return ns.colorName and ns.colorName(n, mm and mm.class) or ns.short(n)
    end
    local grid = ng > 1 and not r.narrow
    if grid then
        -- Raid: Spalten G1..Gn, je 5 Plaetze untereinander
        for _, m in ipairs(maybes) do
            for g = 1, ng do
                if #groups[g] < 5 then groups[g][#groups[g] + 1] = { name = m.name, role = m.role, maybe = true } break end
            end
        end
        nChip, y = drawGroupGrid(r, groups, ng, x0, -76, xMax - x0, nameOf, nChip, nil, function() if r.Click then r:Click() end end)
        hideChips()
    else
    for _, c in ipairs(r.chips) do c:EnableMouse(false) end
    for g = 1, ng do
        if ng > 1 and #groups[g] > 0 then chip("head", "|cff777777" .. (L["G%d"]):format(g) .. "|r") end
        for _, m in ipairs(groups[g]) do chip("name", nameOf(m.name), m.role) end
    end
    for _, m in ipairs(maybes) do chip("name", nameOf(m.name) .. " |cffe8b44a?|r", m.role, 0.5) end
    -- freie Plaetze je Rolle (5er: einzeln, Raids: zusammengefasst)
    for _, key in ipairs({ "tank", "heal", "dps" }) do
        local miss = math.max(0, (need[key] or 0) - have[key])
        if miss > 0 then
            if ng == 1 then
                for _ = 1, miss do chip("free", "|cff666666" .. L["frei"] .. "|r", key) end
            else
                chip("free", "|cff777777" .. (L["%d frei"]):format(miss) .. "|r", key)
            end
        end
    end
    hideChips()
    end
    local bottom = (nChip > 0) and (y - 16) or -72
    -- eigene Anmeldung hervorheben
    local mine = Raid.MySignup(e.id)
    for key, b in pairs(r.status) do
        local on = mine and mine.status == key
        local c = b.st.color
        b.label:SetTextColor(unpack(on and { 1, 1, 1 } or c))
        b.label:SetAlpha(on and 1 or 0.75)
        b.onColor = on and c or nil
        K.SetBorderColor(b, on and c or C.line)
        if b.bg then
            local f = on and 0.55 or 0.12
            b.bgCol = { c[1] * f, c[2] * f, c[3] * f, 1 }
            b.bg:SetColorTexture(unpack(b.bgCol))
        end
    end
    local curRole = mine and mine.status ~= "no" and mine.role or nil
    for key, b in pairs(r.roles) do
        local on = curRole == key
        b.glyph:SetAlpha(on and 1 or 0.35)
        b.onColor = on and ns.Profile and ns.Profile.ROLE_COLORS[key] or nil
        K.SetBorderColor(b, b.onColor or C.line)
    end
    -- Reservierung: Zeile nur, wenn etwas reserviert ist oder Wunschliste-Treffer
    local sr = ns.SoftRes and ns.SoftRes.Mine and ns.SoftRes.Mine(e.id)
    local srText
    if sr then
        local _, link = itemInfo(sr.item)
        srText = (L["Reserviert: %s"]):format(link or ("Item " .. sr.item))
        r.srBtn:SetLabel(L["Aendern"])
        r.srBtn.tip = { L["Reservierung"], srText }
    else
        r.srBtn:SetLabel(L["Reservieren"])
        r.srBtn.tip = { L["Reservierung"], "|cff888888" .. L["Noch nichts reserviert"] .. "|r" }
    end
    local wl = Raid.WantedLoot(e)
    if #wl > 0 then srText = (srText and (srText .. "  ·  ") or "") .. "|cffe8b44a" .. (L["%d Items von deiner Wunschliste"]):format(#wl) .. "|r" end
    if srText then
        r.sr:ClearAllPoints()
        r.sr:SetPoint("TOPLEFT", r.card, "TOPLEFT", CX, bottom - 5)
        r.sr:SetPoint("RIGHT", r.card, "RIGHT", -10, 0)
        r.sr:SetText(srText)
        r.sr:Show()
        bottom = bottom - 17
    else
        r.sr:SetText("")
        r.sr:Hide()
    end
    r.wantH = math.max(78, -bottom + 8)
end

------------------------------------------------------------------------
-- Kartenliste mit variabler Hoehe, sichtbarer Scrollleiste, Verlauf unten
-- und Hinweis "x weitere Termine". Oeffentlich: Raid.BuildEventList(parent)
------------------------------------------------------------------------
local function buildCardList(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.rows, box.data, box.cur, box.target, box.max, box.total = {}, {}, 0, 0, 0, 0
    box.empty = K.Text(box, 13, C.dim, "CENTER")
    box.empty:SetPoint("TOP", 0, -30)
    box.empty:SetPoint("LEFT", 20, 0)
    box.empty:SetPoint("RIGHT", -20, 0)
    box.empty:SetWordWrap(true)
    box.empty:Hide()
    local sc = CreateFrame("ScrollFrame", nil, box)
    sc:SetPoint("TOPLEFT")
    sc:SetPoint("BOTTOMRIGHT", -12, 0)
    sc:EnableMouseWheel(true)
    local body = CreateFrame("Frame", nil, sc)
    body:SetSize(1, 1)
    sc:SetScrollChild(body)
    box.sc, box.body = sc, body
    -- Scrollleiste: Spur + greifbarer Balken
    local bar = CreateFrame("Button", nil, box)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)
    bar:SetWidth(7)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(1, 1, 1, 0.06)
    local thumb = CreateFrame("Button", nil, bar)
    thumb:SetWidth(7)
    thumb:SetFrameLevel(bar:GetFrameLevel() + 2)
    thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
    thumb.tex:SetAllPoints()
    thumb.tex:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.6)
    thumb:SetScript("OnEnter", function(self) self.tex:SetColorTexture(C.text[1], C.text[2], C.text[3], 0.85) end)
    thumb:SetScript("OnLeave", function(self) if not self.drag then self.tex:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.6) end end)
    box.bar, box.thumb = bar, thumb
    -- Verlauf unten + Hinweis (ueber den Karten)
    local ov = CreateFrame("Frame", nil, box)
    ov:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 0, 0)
    ov:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 0, 0)
    ov:SetHeight(44)
    ov:SetFrameLevel(sc:GetFrameLevel() + 40)
    ov:EnableMouse(false)
    ov.fade = ov:CreateTexture(nil, "BACKGROUND")
    ov.fade:SetAllPoints()
    if not K.Gradient(ov.fade, "VERTICAL", { 0.02, 0.02, 0.025, 0.95 }, { 0.02, 0.02, 0.025, 0 }) then
        ov.fade:SetColorTexture(0, 0, 0, 0.35)
    end
    local more = CreateFrame("Button", nil, ov)
    more:SetHeight(18)
    more:SetPoint("BOTTOM", 0, 3)
    more:SetFrameLevel(ov:GetFrameLevel() + 2)
    more.bg = K.Fill(more, C.raised)
    K.Border(more, C.line)
    more.t = K.Text(more, 10, C.text, "CENTER")
    more.t:SetPoint("CENTER", 0, 0)
    more:SetScript("OnClick", function() box:ScrollTo(box.target + math.max(60, (sc:GetHeight() or 300) - 60)) end)
    box.ov, box.more = ov, more

    local function smooth() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
    function box:UpdateBar()
        local view = sc:GetHeight() or 0
        local max = math.max(0, self.total - view)
        self.max = max
        if max <= 1 or view <= 0 then
            bar:Hide() ov:Hide()
            return
        end
        bar:Show()
        local bh = bar:GetHeight() or view
        local th = math.max(24, math.floor(bh * view / self.total))
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", bar, "TOP", 0, -math.floor((bh - th) * (self.cur / max)))
        -- weitere (nicht ganz sichtbare) Karten unterhalb
        local below = 0
        for i = 1, #self.data do
            local r = self.rows[i]
            if r and r.bottom and r.bottom > self.cur + view + 4 then below = below + 1 end
        end
        if self.cur < max - 2 then
            ov:Show()
            if below > 0 then
                more.t:SetText((below == 1 and L["1 weiterer Termin"] or (L["%d weitere Termine"]):format(below)) .. "  |cff888888v|r")
                more:SetWidth(math.max(120, (more.t:GetStringWidth() or 100) + 20))
                more:Show()
            else
                more:Hide()
            end
        else
            ov:Hide()
        end
    end
    function box:Apply(v)
        self.cur = v
        sc:SetVerticalScroll(v)
        self:UpdateBar()
    end
    function box:ScrollTo(v, instant)
        self.target = math.max(0, math.min(self.max or 0, v or 0))
        if instant or not smooth() then self:Apply(self.target) self:SetScript("OnUpdate", nil) return end
        self:SetScript("OnUpdate", function(s, el)
            local d = s.target - s.cur
            if math.abs(d) < 0.5 then s:Apply(s.target) s:SetScript("OnUpdate", nil) return end
            s:Apply(s.cur + d * math.min(1, (el or 0.016) * 14))
        end)
    end
    sc:SetScript("OnMouseWheel", function(_, d) box:ScrollTo(box.target - d * 70) end)
    -- Balken ziehen / auf die Spur klicken
    thumb:SetScript("OnMouseDown", function(self)
        if not GetCursorPosition then return end
        local _, cy = GetCursorPosition()
        self.drag = cy / (self:GetEffectiveScale() or 1)
        self.start = box.cur
    end)
    thumb:SetScript("OnMouseUp", function(self) self.drag = nil self.tex:SetColorTexture(C.muted[1], C.muted[2], C.muted[3], 0.6) end)
    thumb:SetScript("OnUpdate", function(self)
        if not self.drag or not GetCursorPosition then return end
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self.drag = nil return end
        local _, cy = GetCursorPosition()
        cy = cy / (self:GetEffectiveScale() or 1)
        local range = (bar:GetHeight() or 0) - (self:GetHeight() or 0)
        if range > 0 then box:ScrollTo(self.start + (self.drag - cy) * box.max / range, true) end
    end)
    bar:SetScript("OnClick", function(self)
        if not GetCursorPosition then return end
        local _, cy = GetCursorPosition()
        cy = cy / (self:GetEffectiveScale() or 1)
        local ty = thumb:GetTop() or 0
        local page = math.max(60, (sc:GetHeight() or 300) - 60)
        box:ScrollTo(box.target + (cy < ty and page or -page))
    end)

    -- Daten setzen: Karten wiederverwenden, Leseposition halten
    function box:SetData(d)
        self.data = d or {}
        local W = math.floor(sc:GetWidth() or 0)
        if W < 100 then W = math.max(300, math.floor((self:GetWidth() or 0) - 12)) end
        if W < 300 then W = 700 end
        body:SetWidth(W)
        local y = 0
        for i, e in ipairs(self.data) do
            local r = self.rows[i]
            if not r then
                r = createCard(body)
                self.rows[i] = r
            end
            r.listW = W
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            r:SetWidth(W)
            r.item, r.index = e, i
            r:Show()
            local ok, err = pcall(updateCard, r, e)
            if not ok then ns.err(L["Liste"], err) end
            local h = (r.wantH or 120) + 6
            r:SetHeight(h)
            r.top, r.bottom = y, y + h
            y = y + h
        end
        for i = #self.data + 1, #self.rows do self.rows[i].item = nil self.rows[i]:Hide() end
        self.total = y
        body:SetHeight(math.max(1, y))
        self.max = math.max(0, y - (sc:GetHeight() or 0))
        local keep = math.min(self.target, self.max)
        self.target = keep
        self:Apply(math.min(self.cur, self.max))
        self.empty:SetShown(#self.data == 0 and self.emptyOn ~= false)
    end
    sc:SetScript("OnSizeChanged", function()
        if box.relayout then return end
        box.relayout = true
        box:SetData(box.data)
        box.relayout = nil
    end)
    return box
end

-- Termin-Art: Dungeon/5er -> Gruppen-Seite, alles andere -> Raids & Beute
function Raid.IsGroupEvent(e)
    return kindOf(e).key == "dungeon"
end
-- Termin-Liste fuer andere Seiten (z.B. "Geplante Dungeons" auf der Gruppen-Seite)
function Raid.BuildEventList(parent)
    return buildCardList(parent)
end

------------------------------------------------------------------------
-- Reiter "Termine": Kartenliste + Detailansicht
------------------------------------------------------------------------
local RAID_FILTERS = { { key = "all", text = "Alle Raids" }, { key = "mine", text = "Meine Zusagen" } }
local filterEvents   -- weiter unten (braucht upcoming)
local function buildEvents(f)
    -- Kartenliste
    local cards = CreateFrame("Frame", nil, f)
    cards:SetAllPoints()
    f.cards = cards
    f.head = K.GameHead(cards, L["Anstehende Termine"], C.accent)
    f.head:SetPoint("TOPLEFT", 0, -2)
    f.head:SetPoint("RIGHT", cards, "RIGHT", -280, 0)
    f.hint = K.Text(cards, 10, C.dim, "RIGHT")
    f.hint:SetPoint("TOPRIGHT", 0, -6)
    f.hint:SetWidth(160)
    f.hint:SetText(L["Klick auf eine Karte: Details"])
    f.hint:Hide()
    -- Filter: Alle Raids | Meine Zusagen (Auswahl gemerkt)
    f.filt = CreateFrame("Frame", nil, cards)
    f.filt:SetSize(10, 20)
    f.filt:SetPoint("TOPRIGHT", 0, -1)
    f.filt.btns = {}
    for i, it in ipairs(RAID_FILTERS) do
        local b = CreateFrame("Button", nil, f.filt)
        b:SetHeight(20)
        b.bg = K.Fill(b, C.raised)
        K.Border(b, C.line)
        b.t = K.Text(b, 11, C.muted, "CENTER")
        b.t:SetPoint("CENTER", 0, 0)
        b.key = it.key
        b:SetScript("OnClick", function(self)
            if ns.db and ns.db.settings then ns.db.settings.raidEvFilter = self.key end
            ns.RefreshPage("raid")
        end)
        b:SetScript("OnEnter", function(self) if f.filt.cur ~= self.key then self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) end end)
        b:SetScript("OnLeave", function(self) if f.filt.cur ~= self.key then self.t:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end end)
        f.filt.btns[i] = b
    end
    function f.filt:Update(cnt, cur)
        self.cur = cur
        local x = 0
        for i = #self.btns, 1, -1 do
            local b = self.btns[i]
            local on = b.key == cur
            b.t:SetText(L[RAID_FILTERS[i].text] .. "  " .. (on and "|cffffffff" or "|cff888888") .. (cnt[b.key] or 0) .. "|r")
            local c = on and C.text or C.muted
            b.t:SetTextColor(c[1], c[2], c[3])
            b.bg:SetColorTexture(on and C.accent2[1] * 0.45 or C.raised[1], on and C.accent2[2] * 0.45 or C.raised[2], on and C.accent2[3] * 0.45 or C.raised[3], 1)
            K.SetBorderColor(b, on and C.accent2 or C.line)
            local w = math.max(60, math.floor((b.t:GetStringWidth() or 0) + 20))
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", self, "TOPRIGHT", -x, 0)
            x = x + w + 4
        end
        self:SetWidth(math.max(10, x))
    end
    local list = buildCardList(cards)
    list:SetPoint("TOPLEFT", 0, -28)
    list:SetPoint("BOTTOMRIGHT", 0, 0)
    list.empty:SetText(L["Keine anstehenden Raids - die Raidleitung legt Termine an."])
    f.list = list
    f.newBtn = K.Button(cards, L["Termin anlegen"], 140, 26, "primary", function() Raid.SetTab("new") end)
    f.newBtn:SetPoint("TOPRIGHT", cards, "TOPRIGHT", 0, 0)
    f.newBtn:Hide()

    -- Banner "Dein naechster Raid" (nur mit eigener Zusage): Countdown, Ziel, Rolle, Gruppe, Zusagen, Vorbereitung
    local bn = CreateFrame("Button", nil, cards)
    bn:SetPoint("TOPLEFT", 0, 0)
    bn:SetPoint("RIGHT", cards, "RIGHT", 0, 0)
    bn:SetHeight(100)
    bn.bg = K.Fill(bn, C.panel)
    K.Border(bn, C.line)
    bn.glow = bn:CreateTexture(nil, "BORDER")
    bn.glow:SetPoint("TOPLEFT", 3, 0)
    bn.glow:SetPoint("BOTTOMLEFT", 3, 0)
    bn.glow:SetWidth(170)
    bn.accent = bn:CreateTexture(nil, "ARTWORK")
    bn.accent:SetPoint("TOPLEFT")
    bn.accent:SetPoint("BOTTOMLEFT")
    bn.accent:SetWidth(3)
    bn.hl = bn:CreateTexture(nil, "HIGHLIGHT")
    bn.hl:SetAllPoints()
    bn.hl:SetColorTexture(1, 1, 1, 0.04)
    bn.kicker = K.Text(bn, 10, C.amber)
    bn.kicker:SetPoint("TOPLEFT", 14, -10)
    bn.kicker:SetText(K.Upper(L["Dein naechster Raid"]))
    bn.cd = K.Title(bn, 28, C.text)
    bn.cd:SetPoint("TOPLEFT", 14, -26)
    bn.cdSub = K.Text(bn, 10, C.dim)
    bn.cdSub:SetPoint("TOPLEFT", 14, -62)
    bn.when = K.Text(bn, 10, C.muted)
    bn.when:SetPoint("TOPLEFT", 14, -78)
    bn.when:SetWidth(150)
    bn.when:SetWordWrap(false)
    bn.title = K.Title(bn, 15, C.text)
    bn.title:SetPoint("TOPLEFT", 186, -10)
    bn.title:SetPoint("RIGHT", bn, "RIGHT", -14, 0)
    bn.title:SetWordWrap(false)
    bn.meta = K.Text(bn, 11, C.muted)
    bn.meta:SetPoint("TOPLEFT", 186, -32)
    bn.meta:SetPoint("RIGHT", bn, "RIGHT", -14, 0)
    bn.meta:SetWordWrap(false)
    bn.cnt = K.Text(bn, 11, C.text)
    bn.cnt:SetPoint("TOPLEFT", 186, -54)
    bn.classes = CreateFrame("Frame", nil, bn)
    bn.classes:SetHeight(16)
    bn.classes:SetPoint("LEFT", bn.cnt, "RIGHT", 10, 0)
    bn.classes:SetPoint("RIGHT", bn, "RIGHT", -14, 0)
    bn.classes.icons = {}
    bn.prep = K.Text(bn, 11, C.muted)
    bn.prep:SetPoint("TOPLEFT", 186, -76)
    bn.prep:SetPoint("RIGHT", bn, "RIGHT", -14, 0)
    bn.prep:SetWordWrap(false)
    function bn:UpdatePrep()
        local ev = self.ev
        if not ev then return end
        local p = prepState()
        local ok = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13|t "
        local no = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:13:13|t "
        local parts = {}
        if p.dura then
            parts[#parts + 1] = (p.dura > 0.5 and ok or no) .. L["Ausruestung repariert"] .. " |cff888888(" .. math.floor(p.dura * 100 + 0.5) .. "%)|r"
        end
        local inGrp = ((ev.max or 5) > 5) and p.raid or (p.raid or p.group)
        parts[#parts + 1] = (inGrp and ok or no) .. L["Gruppe/Raid beigetreten"]
        self.prep:SetText(table.concat(parts, "     "))
    end
    function bn:UpdateClock()
        if not self.ev then return end
        local a, b = bigCountdown(self.ev.ts)
        self.cd:SetText(a)
        self.cdSub:SetText(K.Upper(b))
    end
    -- Countdown live, gedrosselt auf 1x pro Sekunde (OnUpdate laeuft nur, solange das Banner sichtbar ist)
    bn:SetScript("OnUpdate", function(self, el)
        self.acc = (self.acc or 0) + (el or 0)
        if self.acc < 1 then return end
        self.acc = 0
        self:UpdateClock()
        self.tick = (self.tick or 0) + 1
        if self.tick >= 5 then self.tick = 0 self:UpdatePrep() end
    end)
    bn:SetScript("OnClick", function(self) if self.ev then Raid.OpenEvent(self.ev.id) end end)
    bn:Hide()
    f.banner = bn
    f.animNext = true
    f:HookScript("OnShow", function() f.animNext = true f.bannerEv = nil end)
    cards:HookScript("OnShow", function() f.animNext = true end)

    -- Raid-Interesse (solange kein Termin steht): Kopf-Kacheln, Rollen + Tage melden, Kader-Vorschau mit echten Leuten.
    -- Alles in einer Scrollflaeche, damit auf kleinen Fenstern nichts ueberlappt.
    local DAYS = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }
    local RC = { tank = C.blue, heal = C.mint, dps = C.red }
    local RNAME = { tank = "Tank", heal = "Heiler", dps = "Schaden" }
    local function roleTex(r) return ns.MEDIA .. "icons\\role_" .. r end
    local function canEvents() return ns.Admin and ns.Admin.Can and ns.Admin.Can("raid.events") or false end
    local ipSc = CreateFrame("ScrollFrame", nil, cards)
    ipSc:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -4)
    ipSc:SetPoint("BOTTOMRIGHT", cards, "BOTTOMRIGHT", 0, 0)
    local ip = CreateFrame("Frame", nil, ipSc)
    ip:SetSize(700, 600)
    ipSc:SetScrollChild(ip)
    ipSc:EnableMouseWheel(true)
    ipSc:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, (ip:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - d * 40)))
    end)
    f.interest = ipSc
    ipSc.body = ip
    ip.roleSel, ip.daySel = {}, {}

    -- 1) Kopf-Kacheln: Interessenten, Tanks, Heiler, Schaden
    ip.tiles = {}
    for i, it in ipairs({ { "all", ns.MEDIA .. "icons\\raid", "Interessenten", C.accent },
        { "tank", roleTex("tank"), "Tanks", C.blue }, { "heal", roleTex("heal"), "Heiler", C.mint }, { "dps", roleTex("dps"), "Schaden", C.red } }) do
        local t = famTile(ip, it[2], L[it[3]], it[4])
        t.key = it[1]
        ip.tiles[i] = t
    end

    -- 2) Melde-Feld
    local pn = K.Panel(ip, C.panel)
    ip.pn = pn
    pn.edge = pn:CreateTexture(nil, "ARTWORK")
    pn.edge:SetPoint("TOPLEFT") pn.edge:SetPoint("BOTTOMLEFT") pn.edge:SetWidth(3)
    pn.edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    pn.glow = pn:CreateTexture(nil, "BORDER")
    pn.glow:SetAllPoints()
    if not K.Gradient(pn.glow, "HORIZONTAL", { C.accent[1], C.accent[2], C.accent[3], 0.12 }, { 0, 0, 0, 0 }) then pn.glow:Hide() end
    -- Kopf wie die Profil-Karte: Leuchtscheibe mit Raid-Symbol, Kicker, grosser Titel
    pn.emb = famDisc(pn, 42, ns.MEDIA .. "icons\\raid", C.accent)
    pn.emb:SetPoint("TOPLEFT", 16, -14)
    pn.kick = K.Text(pn, 10, C.amber)
    pn.kick:SetPoint("TOPLEFT", 70, -12)
    pn.kick:SetText(K.Upper(L["Raid-Interesse"]))
    pn.title = K.Title(pn, 18, C.text)
    pn.title:SetPoint("TOPLEFT", 70, -25)
    pn.title:SetText(L["Bei Raids dabei sein?"])
    pn.state = K.Text(pn, 10, C.mint, "RIGHT")
    pn.state:SetPoint("TOPRIGHT", -14, -14)
    pn.state:SetWidth(220)
    pn.state:SetWordWrap(false)
    pn.sub = K.Text(pn, 11, C.muted)
    pn.sub:SetPoint("TOPLEFT", pn.title, "BOTTOMLEFT", 0, -3)
    pn.sub:SetPoint("RIGHT", pn, "RIGHT", -16, 0)
    pn.sub:SetWordWrap(false)
    pn.sub:SetText(L["Noch kein Termin - melde dein Interesse, dann weiss die Raidleitung, wann es passt."])
    pn.rLab = K.Text(pn, 10, C.dim)
    pn.rLab:SetText(K.Upper(L["Deine Rollen"]))
    pn.dLab = K.Text(pn, 10, C.dim)
    pn.dLab:SetText(K.Upper(L["Wann kannst du?"]))
    -- grosse Rollen-Kacheln: Symbol + Name, aktive leuchtet in Rollenfarbe
    ip.roleBtns = {}
    for i, r in ipairs({ "tank", "heal", "dps" }) do
        local rc = RC[r]
        local b = CreateFrame("Button", nil, pn)
        b:SetSize(84, 52)
        b.bg = K.Fill(b, C.raised)
        K.Border(b, C.line)
        b.glow = b:CreateTexture(nil, "BORDER")
        b.glow:SetAllPoints()
        if not K.Gradient(b.glow, "VERTICAL", { rc[1], rc[2], rc[3], 0 }, { rc[1], rc[2], rc[3], 0.28 }) then b.glow:SetColorTexture(rc[1], rc[2], rc[3], 0.14) end
        b.top = b:CreateTexture(nil, "ARTWORK")
        b.top:SetPoint("TOPLEFT") b.top:SetPoint("TOPRIGHT") b.top:SetHeight(2)
        b.top:SetColorTexture(rc[1], rc[2], rc[3], 0.95)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(rc[1], rc[2], rc[3], 0.08)
        -- Rollen-Symbol in Leuchtscheibe (wie die Kennzahl-Kacheln)
        b.disc = famDisc(b, 28, roleTex(r), rc)
        b.disc:SetPoint("TOP", 0, -5)
        b.icon = b.disc.icon
        b.t = K.Text(b, 11, C.text, "CENTER")
        b.t:SetPoint("BOTTOM", 0, 5)
        b.t:SetText(L[RNAME[r]])
        b.check = b:CreateTexture(nil, "OVERLAY")
        b.check:SetSize(12, 12)
        b.check:SetPoint("TOPRIGHT", -4, -4)
        b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        b.role = r
        b:SetScript("OnClick", function(self)
            ip.roleSel[r] = not ip.roleSel[r] or nil
            ip.dirty = true
            f:UpdateInterest()
            if ip.roleSel[r] then pulse(self, rc) end
        end)
        b:SetScript("OnEnter", function(self) K.ShowTip(self, { L[RNAME[r]], L["Klick: Rolle an/aus"] }) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ip.roleBtns[i] = b
    end
    -- Wochentage als Schalter-Chips mit Zaehler (wie viele koennen da), bester Tag hervorgehoben
    ip.dayBtns = {}
    for i, d in ipairs(DAYS) do
        local b = CreateFrame("Button", nil, pn)
        -- Tages-Saeule wie die Wochen-Balken im Profil: Zahl oben, Verlaufs-Balken, Tag darunter
        b:SetSize(38, 52)
        b.bg = K.Fill(b, { 1, 1, 1, 0.035 })
        K.Border(b, C.line)
        b.fill = b:CreateTexture(nil, "BORDER")
        b.fill:SetPoint("BOTTOMLEFT", 5, 18) b.fill:SetPoint("BOTTOMRIGHT", -5, 18)
        b.fill:SetHeight(1)
        b.cap = b:CreateTexture(nil, "ARTWORK")
        b.cap:SetHeight(2)
        b.cap:SetPoint("BOTTOMLEFT", b.fill, "TOPLEFT") b.cap:SetPoint("BOTTOMRIGHT", b.fill, "TOPRIGHT")
        b.cap:SetColorTexture(1, 1, 1, 0.5)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.05)
        b.t = K.Title(b, 12, C.text, "CENTER")
        b.t:SetPoint("BOTTOM", 0, 4)
        b.t:SetText(L[d])
        b.n = K.Text(b, 9, C.dim, "CENTER")
        b.n:SetPoint("TOP", 0, -4)
        b.star = b:CreateTexture(nil, "OVERLAY")
        b.star:SetPoint("BOTTOMLEFT", 6, 1) b.star:SetPoint("BOTTOMRIGHT", -6, 1) b.star:SetHeight(2)
        b.star:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 1)
        b.sel = b:CreateTexture(nil, "BORDER", nil, 1)
        b.sel:SetAllPoints()
        famGrad(b.sel, "VERTICAL", C.accent, 0.22, 0.02, 0.1)
        b.idx = i
        b:SetScript("OnClick", function(self)
            ip.daySel[i] = not ip.daySel[i] or nil
            ip.dirty = true
            f:UpdateInterest()
            if ip.daySel[i] then pulse(self, C.accent) end
        end)
        b:SetScript("OnEnter", function(self)
            local lines = { L[d], (L["%d koennen an diesem Tag"]):format(self.cnt or 0) }
            for _, nm in ipairs(self.names or {}) do lines[#lines + 1] = nm end
            lines[#lines + 1] = "|cff888888" .. L["Klick: Tag an/aus"] .. "|r"
            K.ShowTip(self, lines)
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ip.dayBtns[i] = b
    end
    -- Hauptknopf + Leitungs-Knopf
    ip.go = K.Button(pn, L["Interesse melden"], 190, 30, "primary", function(self)
        local mine = Store.Get("raidint", "ri-" .. ns.me())
        if mine and not mine.del and not ip.dirty then
            Store.Delete("raidint", "ri-" .. ns.me())
            K.Toast(L["Raid-Interesse"], L["Zurueckgezogen."], C.dim)
            ip.flash = { L["Zurueckgezogen."], C.dim }
        else
            local roles, days = "", ""
            for _, r in ipairs({ "tank", "heal", "dps" }) do if ip.roleSel[r] then roles = roles .. r:sub(1, 1) end end
            for i = 1, 7 do if ip.daySel[i] then days = days .. i end end
            if roles == "" then
                ns.print(L["Waehle mindestens eine Rolle."])
                for _, b in ipairs(ip.roleBtns) do pulse(b, C.red) end
                return
            end
            Store.Put("raidint", { id = "ri-" .. ns.me(), roles = roles, days = days })
            K.Toast(L["Raid-Interesse"], L["Gemeldet - die Raidleitung sieht dich jetzt."], C.mint)
            ip.flash = { L["Gemeldet!"], C.mint }
        end
        ip.dirty = false
        pulse(self, ip.flash[2])
        ip.animNext = true
        ns.RefreshPage("raid")
    end)
    ip.lead = K.Button(pn, L["Termin aus Interesse anlegen"], 210, 24, "ghost", function()
        if not canEvents() then return end
        local wd = ip.bestDay
        local n = ip.total or 0
        Raid.prefill = { kind = "raid", max = (n >= 12) and 20 or 10, wd = wd }
        Raid.SetTab("new")
    end)
    ip.lead:HookScript("OnEnter", function(self)
        if self.locked then return end
        local wd = ip.bestDay
        K.ShowTip(self, { L["Termin aus Interesse anlegen"],
            wd and (L["Vorschlag: %s - %d Interessenten koennen da"]):format(L[DAYS[wd]], ip.dayCnt and ip.dayCnt[wd] or 0) or L["Noch keine Wunschtage gemeldet."],
            "|cff888888" .. L["Oeffnet das Termin-Formular vorbelegt."] .. "|r" })
    end)
    ip.lead:HookScript("OnLeave", function() GameTooltip:Hide() end)
    K.LockButton(ip.lead, canEvents, ns.Admin and ns.Admin.Need and ns.Admin.Need("raid.events") or "raidlead")
    ip.best = K.Text(pn, 10, C.muted)
    ip.best:SetWordWrap(false)

    -- 3) Kader-Vorschau: Gruppen als Karten (Chip-Raster wie die Raid-Termin-Karten)
    ip.kHead = K.GameHead(ip, L["So sieht ein Raid-Kader aus"], C.accent)
    ip.comp = K.Text(ip, 11, C.muted, "RIGHT")
    ip.comp:SetWordWrap(false)
    local function ri(r, sz) return "|T" .. roleTex(r) .. ":" .. (sz or 13) .. ":" .. (sz or 13) .. "|t" end
    ip.comp:SetText(ri("tank") .. " 2 " .. L["Tanks"] .. "    " .. ri("heal") .. " 5 " .. L["Heiler"] .. "    " .. ri("dps") .. " 13 " .. L["Schaden"])
    -- feste Beispiel-Aufstellung (20er Raid): je Gruppe 5 Plaetze
    local LAYOUT = { { "tank", "heal", "dps", "dps", "dps" }, { "tank", "heal", "dps", "dps", "dps" },
        { "heal", "dps", "dps", "dps", "dps" }, { "heal", "heal", "dps", "dps", "dps" } }
    ip.gcards = {}
    for g = 1, 4 do
        local gc = K.Panel(ip, C.panel)
        gc.top = gc:CreateTexture(nil, "ARTWORK")
        gc.top:SetPoint("TOPLEFT") gc.top:SetPoint("TOPRIGHT") gc.top:SetHeight(2)
        gc.top:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
        gc.r = { card = gc, chips = {} }
        gc.g = g
        ip.gcards[g] = gc
    end

    -- 4) Leerzustand statt vier Karten voller "frei": Leuchtscheibe, Hinweis, Soll-Aufstellung als Rollen-Scheiben
    --    (die fruehere Hinweisleiste unten entfaellt; ihr Text steht hier bzw. im Tooltip des Kader-Kopfs)
    ip.note = CreateFrame("Frame", nil, ip)
    ip.note:Hide()
    local ke = K.Panel(ip, C.panel)
    ke.glow = ke:CreateTexture(nil, "BORDER")
    ke.glow:SetAllPoints()
    if not K.Gradient(ke.glow, "VERTICAL", { C.accent[1], C.accent[2], C.accent[3], 0 }, { C.accent[1], C.accent[2], C.accent[3], 0.08 }) then ke.glow:Hide() end
    ke.disc = famDisc(ke, 44, ns.MEDIA .. "icons\\raid", C.amber)
    ke.disc:SetPoint("TOP", 0, -18)
    ke.text = K.Text(ke, 12, C.muted, "CENTER")
    ke.text:SetPoint("TOP", ke.disc, "BOTTOM", 0, -12)
    ke.text:SetWordWrap(true)
    ke.text:SetText(L["Wer Interesse meldet, erscheint hier auf einem passenden Platz. Steht ein Termin, meldest du dich direkt auf der Karte an."])
    ke.roles = {}
    for i, r in ipairs({ { "tank", 2 }, { "heal", 5 }, { "dps", 13 } }) do
        local s = CreateFrame("Frame", nil, ke)
        s:SetSize(96, 30)
        s.disc = famDisc(s, 26, roleTex(r[1]), RC[r[1]])
        s.disc:SetPoint("LEFT", 0, 0)
        s.n = K.Title(s, 16, C.text)
        s.n:SetPoint("LEFT", s.disc, "RIGHT", 8, 5)
        s.n:SetText(r[2])
        s.l = K.Text(s, 9, C.muted)
        s.l:SetPoint("LEFT", s.disc, "RIGHT", 8, -8)
        s.l:SetText(K.Upper(L[r[1] == "tank" and "Tanks" or r[1] == "heal" and "Heiler" or "Schaden"]))
        ke.roles[i] = s
    end
    ke:Hide()
    ip.kEmpty = ke
    ip.kHead:EnableMouse(true)
    ip.kHead:SetScript("OnEnter", function(self)
        K.ShowTip(self, { L["So sieht ein Raid-Kader aus"], L["Wer Interesse meldet, erscheint hier auf einem passenden Platz. Steht ein Termin, meldest du dich direkt auf der Karte an."] })
    end)
    ip.kHead:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 0.6.455: Aufbau nach Entwurf - Kopf-Kasten "Raidplanung" mit Termin-Knopf, Melde-Feld, Kasten "Anstehende Termine",
    -- rechts eine Spalte mit Raid-Interesse (Zahlen je Rolle) und "Deine Anmeldung"
    local function box(parent)
        local b = CreateFrame("Frame", nil, parent)
        if ns.Insta and ns.Insta.Glass then pcall(ns.Insta.Glass, b, { 0.055, 0.055, 0.065, 0.85 }, { 1, 1, 1, 0.08 }, 10)
        else K.Fill(b, C.panel) K.Border(b, C.line) end
        return b
    end
    local hb = box(ip)
    hb.ic = famDisc(hb, 34, ns.MEDIA .. "icons\\raid", C.accent)
    hb.ic:SetPoint("LEFT", 14, 0)
    hb.t = K.Title(hb, 16, C.text)
    hb.t:SetPoint("TOPLEFT", 60, -14)
    hb.t:SetText(L["Raidplanung"])
    hb.s = K.Text(hb, 11, C.muted)
    hb.s:SetPoint("TOPLEFT", hb.t, "BOTTOMLEFT", 0, -4)
    hb.s:SetPoint("RIGHT", hb, "RIGHT", -190, 0)
    hb.s:SetWordWrap(false)
    hb.s:SetText(L["Hier findest du anstehende Raid-Termine und kannst dein Interesse anmelden."])
    hb.new = K.Button(hb, L["Termin anlegen"], 160, 32, "primary", function()
        if not canEvents() then return end
        local n = ip.total or 0
        Raid.prefill = { kind = "raid", max = (n >= 12) and 20 or 10, wd = ip.bestDay }
        Raid.SetTab("new")
    end)
    hb.new:SetPoint("RIGHT", -14, 0)
    K.LockButton(hb.new, canEvents, ns.Admin and ns.Admin.Need and ns.Admin.Need("raid.events") or "raidlead")
    ip.hb = hb
    local eb = box(ip)
    -- 0.6.457: dezentes Hintergrundbild (Gildenmodul), unten dunkel auslaufend
    if ns.GuildPack then
        eb.art = eb:CreateTexture(nil, "BACKGROUND", nil, 2)
        eb.art:SetPoint("TOPLEFT", 3, -3) eb.art:SetPoint("BOTTOMRIGHT", -3, 3)
        eb.art:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\raid_events_bg")
        eb.art:SetAlpha(0.45)
        eb.shade = eb:CreateTexture(nil, "BACKGROUND", nil, 3)
        eb.shade:SetAllPoints(eb.art)
        if not K.Gradient(eb.shade, "VERTICAL", { 0, 0, 0, 0.5 }, { 0, 0, 0, 0.1 }) then eb.shade:Hide() end
        if K.RoundMask then pcall(K.RoundMask, eb.art, eb, 10) pcall(K.RoundMask, eb.shade, eb, 10) end
    end
    eb.head = K.GameHead(eb, L["Anstehende Termine"], C.accent)
    eb.head:SetPoint("TOPLEFT", 14, -12)
    eb.head:SetPoint("RIGHT", eb, "RIGHT", -14, 0)
    eb.disc = famDisc(eb, 44, ns.MEDIA .. "icons\\raid", C.amber)
    eb.disc:SetPoint("TOP", 0, -40)
    eb.t = K.Title(eb, 15, C.text, "CENTER")
    eb.t:SetPoint("TOP", eb.disc, "BOTTOM", 0, -14)
    eb.t:SetText(L["Noch keine Termine"])
    eb.s = K.Text(eb, 11, C.muted, "CENTER")
    eb.s:SetPoint("TOP", eb.t, "BOTTOM", 0, -6)
    eb.s:SetWidth(380)
    eb.s:SetWordWrap(true)
    eb.s:SetText(L["Es sind aktuell keine Raid-Termine geplant. Melde dein Interesse an, damit die Raidleitung weiss, wann ein Termin fuer die Gilde passt."])
    ip.eb = eb
    local sb = box(ip)
    sb.ic = famDisc(sb, 30, ns.MEDIA .. "icons\\groups", C.accent)
    sb.ic:SetPoint("TOPLEFT", 12, -12)
    sb.t = K.Title(sb, 14, C.text)
    sb.t:SetPoint("TOPLEFT", 52, -12)
    sb.t:SetText(L["Raid-Interesse"])
    sb.n = K.Text(sb, 11, C.muted)
    sb.n:SetPoint("TOPLEFT", sb.t, "BOTTOMLEFT", 0, -3)
    sb.rows = {}
    for i, r in ipairs({ "tank", "heal", "dps" }) do
        local row = CreateFrame("Frame", nil, sb)
        row:SetHeight(36)
        row:SetPoint("TOPLEFT", 10, -54 - (i - 1) * 38)
        row:SetPoint("RIGHT", sb, "RIGHT", -10, 0)
        row.line = row:CreateTexture(nil, "ARTWORK")
        row.line:SetPoint("TOPLEFT") row.line:SetPoint("TOPRIGHT") row.line:SetHeight(1)
        row.line:SetColorTexture(1, 1, 1, 0.06)
        row.disc = famDisc(row, 24, roleTex(r), RC[r])
        row.disc:SetPoint("LEFT", 2, 0)
        row.l = K.Text(row, 12, C.text)
        row.l:SetPoint("LEFT", 36, 0)
        row.l:SetText(L[RNAME[r]])
        row.v = K.Title(row, 13, C.text, "RIGHT")
        row.v:SetPoint("RIGHT", -4, 0)
        row.role = r
        -- 0.6.459: Drueberfahren zeigt, wer sich fuer diese Rolle gemeldet hat
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local lines = { L[RNAME[r]] .. "  |cff888888" .. #(self.names or {}) .. "|r" }
            for _, nm in ipairs(self.names or {}) do lines[#lines + 1] = nm end
            if #(self.names or {}) == 0 then lines[#lines + 1] = "|cff888888" .. L["Noch niemand gemeldet."] .. "|r" end
            K.ShowTip(self, lines)
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        sb.rows[i] = row
    end
    sb:EnableMouse(true)
    sb:SetScript("OnEnter", function(self)
        local lines = { L["Raid-Interesse"] }
        for _, x in ipairs(self.all or {}) do lines[#lines + 1] = x end
        if #(self.all or {}) == 0 then lines[#lines + 1] = "|cff888888" .. L["Noch niemand gemeldet."] .. "|r" end
        K.ShowTip(self, lines)
    end)
    sb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Namen sichtbar unter den Rollen (bis zu drei, Rest als Zahl)
    sb.who = K.Text(sb, 10, C.muted)
    sb.who:SetPoint("TOPLEFT", 12, -54 - 3 * 38 - 2)
    sb.who:SetPoint("RIGHT", sb, "RIGHT", -12, 0)
    sb.who:SetWordWrap(true)
    ip.sb = sb
    local mb = box(ip)
    mb.ic = famDisc(mb, 30, ns.MEDIA .. "icons\\profile", C.muted)
    mb.ic:SetPoint("TOPLEFT", 12, -12)
    mb.t = K.Title(mb, 14, C.text)
    mb.t:SetPoint("LEFT", mb.ic, "RIGHT", 10, 0)
    mb.t:SetText(L["Deine Anmeldung"])
    mb.state = K.Text(mb, 12, C.text, "CENTER")
    mb.state:SetPoint("TOP", 0, -66)
    mb.s = K.Text(mb, 11, C.muted, "CENTER")
    mb.s:SetPoint("TOP", mb.state, "BOTTOM", 0, -10)
    mb.s:SetPoint("LEFT", 14, 0) mb.s:SetPoint("RIGHT", -14, 0)
    mb.s:SetWordWrap(true)
    ip.mb = mb

    -- Anordnung je nach Breite (Kacheln 4/2 Spalten, Tage neben/unter den Rollen, Gruppen 4/2 Spalten)
    local GC_H = 8 + 16 + 4 * 18 + 16 + 6
    function ip:Layout()
        local W = math.floor(ipSc:GetWidth() or 0)
        if W < 200 then W = 700 end
        self:SetWidth(W)
        -- 0.6.455: rechte Spalte ab 760 px, sonst alles untereinander
        local RW = (W >= 760) and 230 or ((W >= 520) and 190 or 0)   -- 0.6.456: immer zwei Spalten, rechts schmaler wenn eng
        local w = RW > 0 and (W - RW - 12) or W
        local y = 0
        self.hb:ClearAllPoints()
        self.hb:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y)
        self.hb:SetSize(w, 66)
        y = y - 66 - 10
        -- Kacheln
        local tc = (w >= 520) and 4 or 2
        local tw = math.floor((w - (tc - 1) * 8) / tc)
        -- 0.5.847: die vier Zahlen-Kacheln entfallen, die Zahlen stehen in der Kopfzeile des Melde-Felds
        for i, t in ipairs(self.tiles) do
            local ci, rr = (i - 1) % tc, math.floor((i - 1) / tc)
            t:ClearAllPoints()
            t:SetSize(tw, 66)
            t:SetPoint("TOPLEFT", self, "TOPLEFT", ci * (tw + 8), y - rr * 74)
            t:Hide()
        end
        -- 0.6.458: Melde-Feld kompakt - flache Rollen-Knoepfe (Symbol links), niedrige Tages-Chips,
        -- Knopf und Hinweis in einer Zeile; Kopf ohne Zahlen (stehen rechts im Kasten "Raid-Interesse")
        local inner = w - 28
        pn.edge:Hide() pn.glow:Hide()
        pn.kick:Hide()
        pn.emb:ClearAllPoints() pn.emb:SetPoint("TOPLEFT", 14, -12)
        pn.emb:SetScale(0.8)
        pn.title:ClearAllPoints() pn.title:SetPoint("TOPLEFT", 60, -14)
        local RB_H = 34
        local RB_W = math.max(80, math.floor((inner - 2 * 6) / 3))   -- 0.6.460: ueber die ganze Breite
        local rolesW = 3 * RB_W + 2 * 6
        pn.rLab:ClearAllPoints() pn.rLab:SetPoint("TOPLEFT", 14, -62)
        for k, b in ipairs(self.roleBtns) do
            b:ClearAllPoints()
            b:SetSize(RB_W, RB_H)
            b:SetPoint("TOPLEFT", pn, "TOPLEFT", 14 + (k - 1) * (RB_W + 6), -76)
            b.disc:ClearAllPoints() b.disc:SetPoint("LEFT", 6, 0) b.disc:SetScale(0.8)
            b.t:ClearAllPoints() b.t:SetPoint("LEFT", 36, 0)
        end
        local dayGap = 4
        local wide = false   -- 0.6.460: Rollen und Tage immer untereinander, je ueber die ganze Breite
        local dx, dy = wide and (14 + rolesW + 16) or 14, wide and -76 or (-76 - RB_H - 26)
        local dw = math.max(28, math.floor((inner - 6 * dayGap) / 7))
        pn.dLab:ClearAllPoints() pn.dLab:SetPoint("TOPLEFT", dx, dy + 14)
        for k, b in ipairs(self.dayBtns) do
            b:ClearAllPoints()
            b:SetSize(dw, RB_H)
            b:SetPoint("TOPLEFT", pn, "TOPLEFT", dx + (k - 1) * (dw + dayGap), dy)
            b.t:ClearAllPoints() b.t:SetPoint("CENTER", 0, -1)
            b.n:ClearAllPoints() b.n:SetPoint("TOPRIGHT", -3, -2)
            b.fill:SetAlpha(0) b.cap:Hide()
        end
        local rowY = dy - RB_H - 12
        self.go:ClearAllPoints()
        self.go:SetSize(math.min(190, inner), 30)
        self.go:SetPoint("TOPRIGHT", pn, "TOPRIGHT", -14, rowY)
        self.best:ClearAllPoints()
        self.best:SetPoint("LEFT", pn, "TOPLEFT", 14, rowY - 15)
        self.best:SetPoint("RIGHT", self.go, "LEFT", -10, 0)
        local bottom = rowY - 30
        local ph = -bottom + 14
        pn:ClearAllPoints()
        pn:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y)
        pn:SetSize(w, ph)
        y = y - ph - 10
        self.eb:ClearAllPoints()
        self.eb:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y)
        self.eb:SetSize(w, 180)   -- 0.6.458: niedriger (wurde unten abgeschnitten)
        y = y - 180 - 10
        if RW > 0 then
            self.sb:ClearAllPoints()
            self.sb:SetPoint("TOPLEFT", self, "TOPLEFT", w + 12, 0)
            self.sb:SetSize(RW, 196)
            self.mb:ClearAllPoints()
            self.mb:SetPoint("TOPLEFT", self.sb, "BOTTOMLEFT", 0, -10)
            self.mb:SetSize(RW, 190)
        else
            self.sb:ClearAllPoints()
            self.sb:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y)
            self.sb:SetSize(w, 176)
            y = y - 186
            self.mb:ClearAllPoints()
            self.mb:SetPoint("TOPLEFT", self, "TOPLEFT", 0, y)
            self.mb:SetSize(w, 150)
            y = y - 160
        end
        -- Kader-Ansicht entfernt: nur der Leitungs-Knopf bleibt unter dem Interesse-Feld
        self.kHead:Hide()
        self.comp:Hide()
        for _, gc in ipairs(self.gcards) do gc:Hide() end
        if self.kEmpty then self.kEmpty:Hide() end
        self.lead:ClearAllPoints()
        self.lead:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, y)
        self.lead:Hide()   -- 0.6.455: steckt jetzt im Kopf-Kasten ("Termin anlegen" mit Vorschlag aus dem Interesse)
        self:SetHeight(-y + 2)
    end
    ipSc:SetScript("OnSizeChanged", function()
        ip:Layout()
        if ipSc:IsShown() and ip.groups then ip:DrawGroups() end
    end)
    ipSc:Hide()

    -- alle Interessenten (frisch, max. 21 Tage)
    function Raid.Interests()
        local cut = ns.now() - 21 * 86400
        return Store.List("raidint", function(r) return not r.del and (r.u or 0) > cut end)
    end
    local function daysText(r)
        local parts = {}
        for c in (r.days or ""):gmatch("%d") do local d = DAYS[tonumber(c)] if d then parts[#parts + 1] = L[d] end end
        return table.concat(parts, " ")
    end
    -- Gruppen-Karten zeichnen (eigene Chips je Karte, freie Plaetze gestrichelt mit gewuenschter Rolle)
    function ip:DrawGroups()
        local gw = self.gcW or 160
        for g, gc in ipairs(self.gcards) do
            local grp = self.groups[g]
            local members = {}
            for _, m in ipairs(grp) do if m.name then members[#members + 1] = m end end
            local n = drawGroupGrid(gc.r, { members }, 1, 8, -8, gw - 16, function(nm)
                return ns.colorName(nm, ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(nm))
            end, 0, function(m) return m.days ~= "" and m.days or nil, nil end)
            for k = n + 1, #gc.r.chips do gc.r.chips[k]:Hide() end
            local h = gc.r.chips[1]
            h.t:SetText("|cffdddddd" .. K.Upper((L["Gruppe %d"]):format(g)) .. "|r  " .. (#members >= 5 and "|cff66db9e" or (#members > 0 and "|cffe8b44a" or "|cff666666")) .. #members .. "/5|r")
            h.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.10)
            gc.top:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], #members > 0 and 0.9 or 0.35)
            -- freie Plaetze: Symbol der gesuchten Rolle blass, "frei"
            local free = {}
            for _, m in ipairs(grp) do if not m.name then free[#free + 1] = m.role end end
            for s = 1, 5 do
                local c = gc.r.chips[1 + s]
                local m = members[s]
                if m then
                    c.tip = { ns.colorName(m.name, ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(m.name)),
                        ri(m.role, 12) .. " " .. L[RNAME[m.role]],
                        "|cff888888" .. L["Kann:"] .. "|r " .. (m.days ~= "" and m.days or L["Tage offen"]),
                        "|cff888888" .. L["Raid-Interesse"] .. "|r" }
                else
                    local fr = free[s - #members] or "dps"
                    local rc = RC[fr]
                    c.icon:SetTexture(roleTex(fr))
                    c.icon:SetVertexColor(rc[1], rc[2], rc[3])
                    c.icon:SetAlpha(0.55)
                    c.icon:Show()
                    c.bg:SetColorTexture(rc[1], rc[2], rc[3], 0.05)
                    c.t:ClearAllPoints()
                    c.t:SetPoint("LEFT", 17, 0)
                    c.t:SetPoint("RIGHT", -3, 0)
                    c.t:SetText(K.hex({ rc[1] * 0.55 + 0.2, rc[2] * 0.55 + 0.2, rc[3] * 0.55 + 0.2 }) .. L[RNAME[fr]] .. "|r |cff555555" .. L["gesucht"] .. "|r")
                    c.tip = { (L["Gruppe %d"]):format(g), ri(fr, 12) .. " " .. L[RNAME[fr]] .. " " .. L["gesucht"] }
                end
            end
        end
    end

    function f:UpdateInterest()
        local ipSc = self.interest
        local ip = ipSc.body
        local all = Raid.Interests()
        local mine
        for _, r in ipairs(all) do if ns.isMe(r.by) then mine = r end end
        -- Auswahl aus der eigenen Meldung uebernehmen (solange man nichts aendert)
        if mine and not ip.dirty then
            ip.roleSel, ip.daySel = {}, {}
            for c in (mine.roles or ""):gmatch(".") do ip.roleSel[c == "t" and "tank" or c == "h" and "heal" or "dps"] = true end
            for c in (mine.days or ""):gmatch("%d") do ip.daySel[tonumber(c)] = true end
        elseif not mine and not ip.dirty and not next(ip.roleSel) then
            -- Vorschlag: eigene Rollen aus dem Profil
            local r = ns.Profile and ns.Profile.RolesOf and ns.Profile.RolesOf(ns.me())
            if type(r) == "table" then for k, v in pairs(r) do if v then ip.roleSel[k] = true end end end
        end
        local anim = ip.animNext and animOn()
        ip.animNext = false
        ip.isEmpty = #all == 0
        ip:Layout()
        -- Zaehler je Rolle und Tag
        local rc, dc, dn = { tank = 0, heal = 0, dps = 0 }, {}, {}
        for _, r in ipairs(all) do
            for _, k in ipairs({ "tank", "heal", "dps" }) do if (r.roles or ""):find(k:sub(1, 1), 1, true) then rc[k] = rc[k] + 1 end end
            for c in (r.days or ""):gmatch("%d") do
                local d = tonumber(c)
                dc[d] = (dc[d] or 0) + 1
                dn[d] = dn[d] or {}
                if #dn[d] < 12 then dn[d][#dn[d] + 1] = ns.colorName(r.by, ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(r.by)) end
            end
        end
        local best, bestN = nil, 0
        for d = 1, 7 do if (dc[d] or 0) > bestN then best, bestN = d, dc[d] end end
        ip.bestDay, ip.dayCnt, ip.total = best, dc, #all
        -- Kacheln (nur bei geaenderten Zahlen bzw. beim Oeffnen hochzaehlen -> kein Flackern beim Nachladen)
        local vals = { all = #all, tank = rc.tank, heal = rc.heal, dps = rc.dps }
        -- Zahlen in die Kopfzeile: "RAID-INTERESSE  ·  3 Interessenten  ·  1 Tank  1 Heiler  1 Schaden"
        pn.kick:SetText(K.Upper(L["Raid-Interesse"]) .. "   |cff888888" .. (L["%d Interessenten"]):format(#all) .. "|r"
            .. (#all > 0 and ("   " .. K.hex(C.blue) .. (rc.tank or 0) .. " " .. L["Tank"] .. "|r   " .. K.hex(C.mint) .. (rc.heal or 0) .. " " .. L["Heiler"]
                .. "|r   " .. K.hex(C.red) .. (rc.dps or 0) .. " " .. L["Schaden"] .. "|r") or "")
            .. (mine and ("   |cff66db9e" .. L["du bist dabei"] .. "|r") or ""))
        ip.sb.n:SetText((L["%d Interessenten"]):format(#all))
        local byRole, allNames = { tank = {}, heal = {}, dps = {} }, {}
        for _, r in ipairs(all) do
            local nm = ns.colorName(r.by, ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(r.by))
            local rs = {}
            for _, k in ipairs({ "tank", "heal", "dps" }) do
                if (r.roles or ""):find(k:sub(1, 1), 1, true) then table.insert(byRole[k], nm) rs[#rs + 1] = L[RNAME[k]] end
            end
            allNames[#allNames + 1] = nm .. "  |cff888888" .. table.concat(rs, ", ") .. ((r.days or "") ~= "" and ("  ·  " .. daysText(r)) or "") .. "|r"
        end
        for _, row in ipairs(ip.sb.rows) do row.v:SetText(rc[row.role] or 0) row.names = byRole[row.role] end
        ip.sb.all = allNames
        local shortN = {}
        for k2, r in ipairs(all) do if k2 <= 3 then shortN[#shortN + 1] = ns.colorName(r.by, ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(r.by)) end end
        ip.sb.who:SetText(#all > 0 and (table.concat(shortN, ", ") .. (#all > 3 and ("  |cff888888+" .. (#all - 3) .. "|r") or "")) or "")
        if mine then
            local parts = {}
            for _, r in ipairs({ "tank", "heal", "dps" }) do if (mine.roles or ""):find(r:sub(1, 1), 1, true) then parts[#parts + 1] = L[RNAME[r]] end end
            ip.mb.state:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14|t " .. L["Du bist gemeldet"])
            ip.mb.s:SetText(table.concat(parts, ", ") .. ((mine.days or "") ~= "" and ("\n" .. daysText(mine)) or ""))
        else
            ip.mb.state:SetText(L["Noch nicht angemeldet."])
            ip.mb.s:SetText(L["Waehle deine Rolle(n) und Wunschtage aus und melde dein Interesse, damit die Raidleitung planen kann."])
        end
        K.UpdateLockButton(ip.hb.new)
        for _, t in ipairs(ip.tiles) do
            local v = vals[t.key]
            local sub = (t.key == "all") and (mine and L["du bist dabei"] or "") or ""
            local p = (t.key ~= "all" and #all > 0) and (v / #all) or nil
            t:Set(v, sub, p, anim or (t.last ~= nil and t.last ~= v and animOn()))
            t.last = v
            t.tip = { L[t.key == "all" and "Interessenten" or RNAME[t.key]], (L["%d Interessenten"]):format(v) }
        end
        -- Rollen-Kacheln
        for _, b in ipairs(ip.roleBtns) do
            local on = ip.roleSel[b.role] and true or false
            local c = RC[b.role]
            K.SetBorderColor(b, on and c or C.line)
            b.glow:SetShown(on)
            b.top:SetShown(on)
            b.check:SetShown(on)
            b.disc:SetAlpha(on and 1 or 0.45)
            b.disc.halo:SetAlpha(on and 0.55 or 0.15)
            b.bg:SetColorTexture(C.raised[1], C.raised[2], C.raised[3], on and 1 or 0.55)
            b.t:SetTextColor((on and C.text or C.dim)[1], (on and C.text or C.dim)[2], (on and C.text or C.dim)[3])
        end
        -- Tage
        for i, b in ipairs(ip.dayBtns) do
            local on = ip.daySel[i] and true or false
            local isBest = best ~= nil and i == best
            local n = dc[i] or 0
            b.cnt, b.names = n, dn[i]
            K.SetBorderColor(b, on and C.accent or C.line, on and 1 or 0.6)
            b.sel:SetShown(on)
            b.t:SetTextColor((on and C.text or C.muted)[1], (on and C.text or C.muted)[2], (on and C.text or C.muted)[3])
            b.n:SetText(n > 0 and tostring(n) or "")
            b.n:SetTextColor((isBest and C.amber or C.muted)[1], (isBest and C.amber or C.muted)[2], (isBest and C.amber or C.muted)[3])
            local fc = isBest and C.amber or C.accent
            if not K.Gradient(b.fill, "VERTICAL", { fc[1] * 0.45, fc[2] * 0.45, fc[3] * 0.45, 0.9 }, { fc[1], fc[2], fc[3], 1 }) then
                b.fill:SetColorTexture(fc[1], fc[2], fc[3], 0.8)
            end
            b.fill:SetAlpha((on or isBest) and 1 or 0.6)
            b.fill:SetHeight(math.max(1, math.floor(18 * (bestN > 0 and n / bestN or 0))))
            b.fill:SetShown(n > 0)
            b.cap:SetShown(n > 0)
            b.star:SetShown(isBest)
        end
        -- Knopf + Status
        if mine and not ip.dirty then ip.go:SetLabel("|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14|t  " .. L["Zurueckziehen"])
        elseif mine then ip.go:SetLabel(L["Interesse aendern"])
        else ip.go:SetLabel(L["Interesse melden"]) end
        if mine then
            pn.state:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t " .. (ip.dirty and L["Aenderung noch nicht gespeichert"] or L["Du bist gemeldet"]))
            pn.state:SetTextColor((ip.dirty and C.amber or C.mint)[1], (ip.dirty and C.amber or C.mint)[2], (ip.dirty and C.amber or C.mint)[3])
        else pn.state:SetText("") end
        if ip.flash then
            local fl = ip.flash
            ip.flash = nil
            pn.state:SetText(fl[1])
            pn.state:SetTextColor(fl[2][1], fl[2][2], fl[2][3])
            if animOn() then
                pn.state:SetAlpha(0)
                K.Tween(pn.state, 0.4, function(p) pn.state:SetAlpha(p) end, function() pn.state:SetAlpha(1) end)
                ns.After(2.5, function() if ipSc:IsShown() then f:UpdateInterest() end end)
            end
        end
        ip.best:SetText(best and ((L["Bester Tag:"] .. "  |cffe8b44a" .. L[DAYS[best]] .. "|r  |cff888888(" .. (L["%d koennen"]):format(bestN) .. ")|r"))
            or (#all > 0 and L["Noch keine Wunschtage - tippe an, wann du kannst."] or L["Noch niemand gemeldet - sei der Erste!"]))
        K.UpdateLockButton(ip.lead)
        -- Kader fuellen: knappe Rollen zuerst, jede Person einmal (auf die festen Rollen-Plaetze)
        local used = {}
        local function take(roleCh)
            for _, r in ipairs(all) do
                if not used[r.by] and (r.roles or ""):find(roleCh, 1, true) then used[r.by] = true return r end
            end
        end
        local groups = {}
        local need = { tank = {}, heal = {}, dps = {} }
        for g, roles in ipairs(LAYOUT) do
            groups[g] = {}
            for s, role in ipairs(roles) do
                local slot = { role = role }
                groups[g][s] = slot
                table.insert(need[role], slot)
            end
        end
        for _, role in ipairs({ "tank", "heal", "dps" }) do
            for _, slot in ipairs(need[role]) do
                local r = take(role:sub(1, 1))
                if r then slot.name, slot.days = r.by, daysText(r) end
            end
        end
        ip.groups = groups
        ip:DrawGroups()
        if anim then
            K.FadeIn(ip.pn, 0.05)
            if ip.isEmpty then K.FadeIn(ip.kEmpty, 0.12)
            else for g, gc in ipairs(ip.gcards) do K.FadeIn(gc, 0.12 + (g - 1) * 0.05) end end
        end
    end
    ipSc:HookScript("OnShow", function() ip.animNext = true end)

    -- Detail: Banner, Rollen-Kacheln, Rollen-Balken, Gruppen-Raster, Vielleicht/Absage-Chips, Fusszeile
    f.back = K.Button(f, "< " .. L["Alle Termine"], 130, 22, "ghost", function()
        showDetail = false
        ns.RefreshPage("raid")
    end)
    f.back:SetPoint("TOPLEFT", 0, 0)
    local det = K.Panel(f, C.panel)
    det:SetPoint("TOPLEFT", 0, -30)
    det:SetPoint("BOTTOMRIGHT", 0, 0)
    det.accent = det:CreateTexture(nil, "ARTWORK")
    det.accent:SetPoint("TOPLEFT")
    det.accent:SetPoint("BOTTOMLEFT")
    det.accent:SetWidth(3)

    -- Banner: Ladebild dezent, Verlauf in der Terminfarbe, Datum gross
    local ban = CreateFrame("Frame", nil, det)
    ban:SetPoint("TOPLEFT", 3, 0)
    ban:SetPoint("TOPRIGHT", 0, 0)
    ban:SetHeight(DET_BAN_H)
    if ban.SetClipsChildren then ban:SetClipsChildren(true) end
    ban.art = ban:CreateTexture(nil, "BACKGROUND", nil, 1)
    ban.art:SetAllPoints()
    ban.art:SetTexCoord(0, 1, 0.3, 0.62)
    ban.art:SetAlpha(0.22)
    ban.tint = ban:CreateTexture(nil, "BACKGROUND", nil, 2)
    ban.tint:SetAllPoints()
    ban.shade = ban:CreateTexture(nil, "BORDER")
    ban.shade:SetPoint("BOTTOMLEFT")
    ban.shade:SetPoint("BOTTOMRIGHT")
    ban.shade:SetHeight(1)
    ban.shade:SetColorTexture(1, 1, 1, 0.06)
    ban.wday = K.Text(ban, 10, C.muted, "CENTER")
    ban.wday:SetPoint("TOPLEFT", 8, -12)
    ban.wday:SetWidth(60)
    ban.wday:SetWordWrap(false)
    ban.dHalo = ban:CreateTexture(nil, "BORDER", nil, 1)
    ban.dHalo:SetTexture(FAM_EMBER)
    ban.dHalo:SetBlendMode("ADD")
    ban.dHalo:SetSize(110, 110)
    ban.dHalo:SetPoint("CENTER", ban, "TOPLEFT", 38, -46)
    ban.dHalo:SetAlpha(0.35)
    ban.gloss = ban:CreateTexture(nil, "BORDER", nil, 2)
    ban.gloss:SetPoint("TOPLEFT") ban.gloss:SetPoint("TOPRIGHT") ban.gloss:SetHeight(20)
    if not K.Gradient(ban.gloss, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.05 }) then ban.gloss:Hide() end
    ban.day = K.Title(ban, 30, C.text, "CENTER")
    ban.day:SetPoint("TOPLEFT", 8, -26)
    ban.day:SetWidth(60)
    ban.mon = K.Text(ban, 10, C.muted, "CENTER")
    ban.mon:SetPoint("TOPLEFT", 8, -60)
    ban.mon:SetWidth(60)
    ban.time = K.Text(ban, 12, C.text, "CENTER", K.FONT)
    ban.time:SetPoint("TOPLEFT", 8, -74)
    ban.time:SetWidth(60)
    f.ban = ban
    f.dTitle = K.Title(ban, 18, C.text)
    f.dTitle:SetPoint("TOPLEFT", 80, -14)
    f.dTitle:SetWordWrap(false)
    f.dCount = K.Text(ban, 13, C.amber)
    f.dCount:SetPoint("TOPLEFT", f.dTitle, "BOTTOMLEFT", 0, -6)
    f.dCount:SetWordWrap(false)
    f.dMeta = K.Text(ban, 11, C.muted)
    f.dMeta:SetPoint("TOPLEFT", f.dCount, "BOTTOMLEFT", 0, -5)
    f.dMeta:SetWordWrap(false)
    f.dMine = K.Text(ban, 11, C.muted)
    f.dMine:SetPoint("TOPLEFT", f.dMeta, "BOTTOMLEFT", 0, -5)
    f.dMine:SetWordWrap(false)
    -- Notiz als Hinweis-Kaertchen rechts im Banner
    local note = CreateFrame("Frame", nil, ban)
    note.bg = K.Fill(note, { 0, 0, 0, 0.45 })
    K.Border(note, C.line)
    note.bar = note:CreateTexture(nil, "ARTWORK")
    note.bar:SetPoint("TOPLEFT")
    note.bar:SetPoint("BOTTOMLEFT")
    note.bar:SetWidth(2)
    note.bar:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 0.9)
    note.lbl = K.Text(note, 9, C.amber)
    note.lbl:SetPoint("TOPLEFT", 9, -6)
    note.lbl:SetText(K.Upper(L["Hinweis"]))
    note.t = K.Text(note, 11, C.text)
    note.t:SetPoint("TOPLEFT", 9, -19)
    note.t:SetPoint("BOTTOMRIGHT", -8, 5)
    note.t:SetWordWrap(true)
    note.t:SetJustifyV("TOP")
    note:Hide()
    f.note = note
    -- Status der Reservierung (alter Name dSr bleibt fuer die Logik)
    f.dSr = K.Text(det, 11, C.muted)
    f.dSr:SetWordWrap(false)

    -- Anmelde-Kacheln: Rolle (leuchtet in Rollenfarbe), Vielleicht/Absage dezent daneben
    f.roleBtns, f.roleList = {}, {}
    for _, key in ipairs({ "tank", "heal", "dps" }) do
        local rc = ROLES[key][2]
        local b = CreateFrame("Button", nil, det)
        b:SetHeight(DET_TILE_H)
        b.bg = K.Fill(b, C.raised)
        K.Border(b, C.line)
        b.grad = b:CreateTexture(nil, "BORDER", nil, 1)
        b.grad:SetAllPoints()
        famGrad(b.grad, "HORIZONTAL", rc, 0.12, 0.01)
        b.glow = b:CreateTexture(nil, "BORDER", nil, 2)
        b.glow:SetAllPoints()
        famGrad(b.glow, "VERTICAL", rc, 0.04, 0.30, 0.22)
        b.glow:Hide()
        b.top = b:CreateTexture(nil, "ARTWORK")
        b.top:SetPoint("TOPLEFT") b.top:SetPoint("TOPRIGHT") b.top:SetHeight(2)
        b.top:SetColorTexture(rc[1], rc[2], rc[3], 0.85)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetPoint("BOTTOMLEFT", 1, 1)
        b.line:SetPoint("BOTTOMRIGHT", -1, 1)
        b.line:SetHeight(2)
        b.line:SetColorTexture(rc[1], rc[2], rc[3], 1)
        b.line:Hide()
        b.rdisc = famDisc(b, 28, ns.Profile and ns.Profile.RoleTexture(key) or nil, rc)
        b.rdisc:SetPoint("LEFT", 8, 0)
        b.ricon = b.rdisc.icon
        b.label = K.Text(b, 13, C.text)
        b.label:SetPoint("TOPLEFT", 42, -7)
        b.label:SetText(ROLES[key][1])
        b.sub = K.Text(b, 10, C.dim)
        b.sub:SetPoint("TOPLEFT", 42, -23)
        b.sub:SetWordWrap(false)
        b.sub:SetPoint("RIGHT", -6, 0)
        b:SetScript("OnClick", function(self)
            local ev = Store.Get("events", selectedEv)
            if ev then signUp(ev, key, "yes") pulse(self, rc) end
        end)
        b:SetScript("OnEnter", function(self)
            K.SetBorderColor(self, rc)
            self.rdisc.halo:SetAlpha(0.7)
            K.ShowTip(self, { ROLES[key][1], L["Klick: als deine Rolle anmelden"] })
        end)
        b:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            self.rdisc.halo:SetAlpha(0.3)
            K.SetBorderColor(self, self.onColor or C.line)
        end)
        b.role = key
        f.roleBtns[key] = b
        f.roleList[#f.roleList + 1] = b
    end
    local maybe = K.Button(det, L["Vielleicht"], 84, 20, "ghost", function()
        local ev = Store.Get("events", selectedEv)
        if ev then signUp(ev, nil, "maybe") end
    end)
    local no = K.Button(det, L["Absage"], 84, 20, "ghost", function()
        local ev = Store.Get("events", selectedEv)
        if ev then signUp(ev, nil, "no") end
    end)
    f.signBtns = { maybe, no }
    keepBorder(maybe) keepBorder(no)

    -- Mitte scrollbar: Rollen-Balken, Gruppen-Raster, Vielleicht/Absage, Hinweise, Wunsch-Beute
    local sc = CreateFrame("ScrollFrame", nil, det)
    sc:EnableMouseWheel(true)
    local body = CreateFrame("Frame", nil, sc)
    body:SetSize(1, 1)
    sc:SetScrollChild(body)
    sc:SetScript("OnMouseWheel", function(self, d)
        local maxS = math.max(0, (body:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.max(0, math.min(maxS, (self:GetVerticalScroll() or 0) - d * 40)))
    end)
    f.dSc, f.dBody = sc, body
    f.cols, f.colList = {}, {}
    for i, key in ipairs({ "tank", "heal", "dps" }) do
        local rc = ROLES[key][2]
        local col = CreateFrame("Frame", nil, body)
        col:SetHeight(20)
        col:EnableMouse(true)
        f.colList[i] = col
        col.icon = K.Glyph(col, 13, ns.Profile and ns.Profile.RoleTexture(key) or nil, rc)
        col.icon:SetPoint("TOPLEFT", 0, 0)
        col.h = K.Text(col, 11, rc)
        col.h:SetPoint("TOPLEFT", 18, 0)
        col.num = K.Text(col, 11, C.text, "RIGHT")
        col.num:SetPoint("TOPRIGHT", 0, 0)
        col.bar = K.Bar(col, 118, 5)
        col.bar.fill:SetColorTexture(rc[1], rc[2], rc[3], 0.95)
        col.bar:SetPoint("TOPLEFT", 0, -15)
        col:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
        col:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.cols[key] = col
    end
    f.gridR = { chips = {}, card = body, maxColW = 170 }
    f.flowR = { chips = {}, card = body }
    f.mLbl = K.Text(body, 10, C.amber)
    f.nLbl = K.Text(body, 10, C.red)
    f.other = K.Text(body, 11, C.muted)
    f.other:SetWordWrap(true)
    f.dEmpty = K.Text(body, 11, C.dim)

    -- Fusszeile
    f.invite = K.Button(det, L["Alle einladen"], 120, 26, "primary", function()
        local ev = Store.Get("events", selectedEv)
        if ev then Raid.Invite(ev) end
    end)
    f.del = K.Button(det, L["Termin loeschen"], 120, 26, "danger", function()
        if selectedEv then Store.Delete("events", selectedEv) selectedEv = nil showDetail = false end
    end)
    f.calOpen = K.Button(det, L["Kalender oeffnen"], 140, 26, "ghost", function()
        if ToggleCalendar then pcall(ToggleCalendar) elseif Calendar_Toggle then pcall(Calendar_Toggle) end
    end)
    f.journal = K.Button(det, L["Dungeon-Journal"], 130, 26, "ghost")
    -- Reservieren: Pillen-Hauptknopf mit rundem Beutel-Symbol, Akzentfarbe, Glow beim Ueberfahren
    local sr = CreateFrame("Button", nil, det)
    sr:SetSize(150, 32)
    local function pill(layer, sub, grow)
        local t = {}
        local h = 32 + grow * 2
        t.l = sr:CreateTexture(nil, layer, nil, sub)
        t.r = sr:CreateTexture(nil, layer, nil, sub)
        t.m = sr:CreateTexture(nil, layer, nil, sub)
        t.l:SetSize(h, h)
        t.l:SetPoint("LEFT", -grow, 0)
        t.r:SetSize(h, h)
        t.r:SetPoint("RIGHT", grow, 0)
        t.m:SetPoint("TOPLEFT", t.l, "TOP", 0, 0)
        t.m:SetPoint("BOTTOMRIGHT", t.r, "BOTTOM", 0, 0)
        for _, x in ipairs({ t.l, t.r }) do
            x:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        end
        t.m:SetTexture("Interface\\Buttons\\WHITE8X8")
        function t:Color(c, a) for _, x in ipairs({ self.l, self.r, self.m }) do x:SetVertexColor(c[1], c[2], c[3], a or 1) end end
        function t:Shown(on) for _, x in ipairs({ self.l, self.r, self.m }) do x:SetShown(on) end end
        return t
    end
    sr.glow = pill("BACKGROUND", 1, 4)
    sr.glow:Color(C.accent, 0.28)
    sr.glow:Shown(false)
    sr.body = pill("BACKGROUND", 2, 0)
    sr.body:Color(C.accent2, 1)
    sr.ring = sr:CreateTexture(nil, "BORDER")
    sr.ring:SetSize(28, 28)
    sr.ring:SetPoint("LEFT", 2, 0)
    sr.ring:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    sr.ring:SetVertexColor(0, 0, 0, 0.45)
    sr.icon = sr:CreateTexture(nil, "ARTWORK")
    sr.icon:SetSize(24, 24)
    sr.icon:SetPoint("CENTER", sr.ring, "CENTER")
    sr.icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    if sr.CreateMaskTexture then
        pcall(function()
            local m = sr:CreateMaskTexture()
            m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            m:SetAllPoints(sr.icon)
            sr.icon:AddMaskTexture(m)
        end)
    end
    sr.label = K.Text(sr, 13, { 1, 1, 1, 1 }, "CENTER")
    sr.label:SetPoint("LEFT", sr.ring, "RIGHT", 4, 0)
    sr.label:SetPoint("RIGHT", -12, 0)
    sr.label:SetText(L["Reservieren"])
    function sr:SetLabel(t) self.label:SetText(t) end
    sr:SetScript("OnEnter", function(self)
        self.glow:Shown(true)
        self.body:Color(C.accent, 1)
        K.ShowTip(self, { L["Reservierung"], L["Klick: Item aus der Beute reservieren"] })
    end)
    sr:SetScript("OnLeave", function(self)
        self.glow:Shown(false)
        self.body:Color(C.accent2, 1)
        GameTooltip:Hide()
    end)
    sr:SetScript("OnMouseDown", function(self) self.label:SetPoint("LEFT", self.ring, "RIGHT", 4, -1) end)
    sr:SetScript("OnMouseUp", function(self) self.label:SetPoint("LEFT", self.ring, "RIGHT", 4, 0) end)
    sr:SetScript("OnClick", function()
        local ev = Store.Get("events", selectedEv)
        if ev and ns.SoftRes and ns.SoftRes.Open then ns.SoftRes.Open(ev) end
    end)
    f.srOpen = sr
    -- reserviertes Item als Symbol neben dem Knopf
    local si = CreateFrame("Button", nil, det)
    si:SetSize(26, 26)
    si.tex = si:CreateTexture(nil, "ARTWORK")
    si.tex:SetAllPoints()
    si.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    K.Border(si, C.amber)
    si:SetScript("OnEnter", function(self) if self.id then K.ItemTip(self, "item:" .. self.id) end end)
    si:SetScript("OnLeave", function() GameTooltip:Hide() end)
    si:Hide()
    f.srItem = si
    f.det = det
    -- "Fuer dich interessant": Beute der Ziel-Instanz, die auf deiner Wunschliste steht
    local wr = CreateFrame("Frame", nil, body)
    wr:SetHeight(24)
    wr.lbl = K.Text(wr, 10, C.amber)
    wr.lbl:SetPoint("LEFT", 0, 0)
    wr.lbl:SetText(K.Upper(L["Fuer dich interessant"]))
    wr.icons = {}
    wr:Hide()
    f.wantRow = wr
    det:SetScript("OnSizeChanged", function() Raid.LayoutDetail(f) end)
end

-- Detailansicht an die Breite anpassen; Mitte (Balken, Raster, Chips) wird hier gesetzt
function Raid.LayoutDetail(f)
    local w = math.floor((f.det:GetWidth() or 0) - 28)
    if w < 150 then return end
    local wide = w >= 520
    -- Banner: Notiz rechts (breit) bzw. ausgeblendet ins Meta (schmal)
    local noteW = 0
    if f.note.has and w >= 460 then
        noteW = math.min(240, math.floor(w * 0.34))
        f.note:ClearAllPoints()
        f.note:SetPoint("TOPRIGHT", f.ban, "TOPRIGHT", -12, -12)
        f.note:SetSize(noteW, DET_BAN_H - 24)
        f.note:Show()
    else
        f.note:Hide()
    end
    local tw = w + 14 - 80 - (noteW > 0 and (noteW + 16) or 0)
    for _, t in ipairs({ f.dTitle, f.dCount, f.dMeta, f.dMine }) do t:SetWidth(math.max(60, tw)) end
    -- Kacheln
    local maybe, no = f.signBtns[1], f.signBtns[2]
    local sideW = wide and 92 or 0
    local tileW = math.floor((w - sideW - 8 - (wide and 8 or 0)) / 3)
    local tileY = -(DET_BAN_H + 10)
    for i, b in ipairs(f.roleList) do
        b:SetWidth(tileW)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", f.det, "TOPLEFT", 14 + (i - 1) * (tileW + 4), tileY)
        b.sub:SetShown(tileW >= 110)
    end
    maybe:ClearAllPoints()
    no:ClearAllPoints()
    local midTop
    if wide then
        maybe:SetWidth(sideW)
        no:SetWidth(sideW)
        maybe:SetPoint("TOPRIGHT", f.det, "TOPRIGHT", -14, tileY)
        no:SetPoint("TOPRIGHT", f.det, "TOPRIGHT", -14, tileY - DET_TILE_H + 20)
        midTop = tileY - DET_TILE_H - 10
    else
        local hw = math.floor((w - 4) / 2)
        maybe:SetWidth(hw)
        no:SetWidth(hw)
        maybe:SetPoint("TOPLEFT", f.det, "TOPLEFT", 14, tileY - DET_TILE_H - 6)
        no:SetPoint("LEFT", maybe, "RIGHT", 4, 0)
        midTop = tileY - DET_TILE_H - 6 - (maybe:IsShown() and 26 or 0) - 4
    end
    -- Fusszeile: links Einladen/Loeschen, rechts Journal + Reservieren-Pille (+ Item / Stand)
    local foot = 12
    f.invite:ClearAllPoints()
    f.invite:SetPoint("BOTTOMLEFT", 14, foot + 3)
    f.del:ClearAllPoints()
    f.del:SetPoint("LEFT", f.invite, "RIGHT", 8, 0)
    f.calOpen:ClearAllPoints()
    f.calOpen:SetPoint("BOTTOMLEFT", 14, foot + 3)
    local leftW = (f.invite:IsShown() and 248) or (f.calOpen:IsShown() and 140) or 0
    local srShown = f.srOpen:IsShown()
    local srTextW = srShown and math.min(200, math.max(0, w - leftW - 150 - (f.journal:IsShown() and 138 or 0) - 50)) or 0
    local rightW = (f.journal:IsShown() and 138 or 0) + (srShown and (158 + (f.srItem:IsShown() and 32 or 0) + srTextW) or 0)
    local stacked = leftW > 0 and rightW > 0 and (leftW + rightW + 10 > w)
    local y = stacked and (foot + 36) or foot
    f.journal:ClearAllPoints()
    f.srOpen:ClearAllPoints()
    f.srItem:ClearAllPoints()
    f.dSr:ClearAllPoints()
    if f.journal:IsShown() then
        f.journal:SetPoint("BOTTOMRIGHT", -14, y + 3)
        f.srOpen:SetPoint("RIGHT", f.journal, "LEFT", -10, 0)
    else
        f.srOpen:SetPoint("BOTTOMRIGHT", -14, y)
    end
    local anchor = f.srOpen
    if f.srItem:IsShown() then
        f.srItem:SetPoint("RIGHT", f.srOpen, "LEFT", -8, 0)
        anchor = f.srItem
    end
    f.dSr:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    f.dSr:SetWidth(math.max(1, srTextW))
    f.dSr:SetJustifyH("RIGHT")
    f.dSr:SetShown(srShown and srTextW >= 60)
    local midBottom = (stacked and (foot + 36 + 34) or (foot + 34)) + 6
    -- Mitte
    f.dSc:ClearAllPoints()
    f.dSc:SetPoint("TOPLEFT", f.det, "TOPLEFT", 14, midTop)
    f.dSc:SetPoint("BOTTOMRIGHT", f.det, "BOTTOMRIGHT", -14, midBottom)
    f.dBody:SetWidth(w)
    Raid.LayoutDetailBody(f, w)
end

-- Inhalt der scrollbaren Mitte setzen (aus f.dState, von refreshDetail gefuellt)
function Raid.LayoutDetailBody(f, w)
    local st = f.dState
    local body = f.dBody
    local y = 0
    if not st or st.cal then
        for _, c in ipairs(f.gridR.chips) do c:Hide() end
        for _, c in ipairs(f.flowR.chips) do c:Hide() end
        for _, col in ipairs(f.colList) do col:Hide() end
        f.mLbl:Hide() f.nLbl:Hide() f.dEmpty:Hide()
        f.other:ClearAllPoints()
        f.other:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
        f.other:SetWidth(w)
        body:SetHeight(40)
        return
    end
    -- Rollen-Balken nebeneinander
    local cw = math.floor((w - 24) / 3)
    for i, col in ipairs(f.colList) do
        col:Show()
        col:ClearAllPoints()
        col:SetPoint("TOPLEFT", body, "TOPLEFT", (i - 1) * (cw + 12), y)
        col:SetWidth(cw)
        col.bar:SetWidth(cw)
        if col.bar.p then col.bar:Set(col.bar.p) end
    end
    y = y - 30
    -- Gruppen-Raster (Raids und 5er gleich: je 5 untereinander)
    local n = 0
    n, y = drawGroupGrid(f.gridR, st.groups, st.ng, 0, y, w, st.nameOf, 0, st.extraOf)
    for i = n + 1, #f.gridR.chips do f.gridR.chips[i]:Hide() end
    y = y - 16 - 12
    -- Vielleicht / Absage als Chip-Reihen
    local fn = 0
    local function flow(label, lbl, list, alpha)
        if #list == 0 then lbl:Hide() return end
        lbl:ClearAllPoints()
        lbl:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y - 2)
        lbl:SetText(K.Upper(label) .. " (" .. #list .. ")")
        lbl:Show()
        local x0 = 92
        local x = x0
        for _, m in ipairs(list) do
            fn = fn + 1
            local c = chipAt(f.flowR, fn)
            c:EnableMouse(true)
            c.t:SetText(m.text)
            local rc = m.role and ns.Profile and ns.Profile.ROLE_COLORS[m.role] or C.dim
            if m.role and ns.Profile then c.icon:SetTexture(ns.Profile.RoleTexture(m.role)) c.icon:Show() else c.icon:Hide() end
            c.icon:SetVertexColor(rc[1], rc[2], rc[3])
            c.t:ClearAllPoints()
            c.t:SetPoint("LEFT", m.role and 17 or 6, 0)
            c.t:SetPoint("RIGHT", -4, 0)
            local cw2 = math.min(150, math.max(40, math.floor((c.t:GetStringWidth() or 0) + (m.role and 24 or 12))))
            c:SetSize(cw2, 16)
            c.bg:SetColorTexture(rc[1], rc[2], rc[3], 0.1)
            c.bar:SetColorTexture(m.col[1], m.col[2], m.col[3], 0.9)
            c.bar:Show()
            setDashed(c, false, cw2)
            c:SetAlpha(alpha)
            c.tip = m.tip
            if not c.tipHooked then
                c.tipHooked = true
                c:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
                c:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
            if x > x0 and x + cw2 > w then x = x0 y = y - 19 end
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", body, "TOPLEFT", x, y)
            c:Show()
            x = x + cw2 + 4
        end
        y = y - 24
    end
    flow(L["Vielleicht"], f.mLbl, st.maybes, 0.8)
    flow(L["Absage"], f.nLbl, st.nos, 0.6)
    for i = fn + 1, #f.flowR.chips do f.flowR.chips[i]:Hide() end
    -- Hinweise (Sperre) und Wunsch-Beute
    f.other:ClearAllPoints()
    f.other:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
    f.other:SetWidth(w)
    local ot = f.other:GetText()
    if ot and ot ~= "" then y = y - math.max(14, math.floor(f.other:GetStringHeight() or 14)) - 8 end
    if f.wantRow:IsShown() then
        f.wantRow:ClearAllPoints()
        f.wantRow:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y)
        f.wantRow:SetWidth(w)
        y = y - 30
    end
    f.dEmpty:Hide()
    body:SetHeight(math.max(1, -y))
end

-- Ladebild zum Ziel (nur wenn die Datei im Client existiert, sonst bleibt der Farbverlauf)
local DET_ART = {
    { "onyx", "LoadScreenOnyxiasLair" }, { "hyjal", "LoadScreenHyjal" }, { "molten", "LoadScreenMoltenCore" },
    { "geschmolz", "LoadScreenMoltenCore" }, { "blackwing", "LoadScreenBlackWingLair" }, { "pechschwing", "LoadScreenBlackWingLair" },
    { "deadmine", "LoadScreenDeadmines" }, { "todesmine", "LoadScreenDeadmines" }, { "schattenfang", "LoadScreenShadowFangKeep" },
    { "shadowfang", "LoadScreenShadowFangKeep" }, { "scharlach", "LoadScreenScarletMonastery2" }, { "scarlet", "LoadScreenScarletMonastery2" },
    { "wailing", "LoadScreenWailingCaverns" }, { "klagende", "LoadScreenWailingCaverns" }, { "ragefire", "LoadScreenRagefireChasm" },
    { "flammenschlund", "LoadScreenRagefireChasm" }, { "gnomeregan", "LoadScreenGnomeregan" }, { "uldaman", "LoadScreenUldaman" },
    { "stratholme", "LoadScreenStrathome" }, { "scholomance", "LoadScreenScholomance" }, { "orgrimmar", "LoadScreenOrgrimmar" },
}
local function detArt(ev)
    local s = ((ev.inst or "") .. " " .. (ev.title or "")):lower()
    for _, a in ipairs(DET_ART) do
        if s:find(a[1], 1, true) then
            local path = "Interface\\Glues\\LoadingScreens\\" .. a[2]
            if GetFileIDFromPath then
                local ok, id = pcall(GetFileIDFromPath, path)
                if ok and (id == nil or id == 0) then return nil end
            end
            return path
        end
    end
end

local function refreshDetail(f, ev)
    -- nur beim Oeffnen eines (anderen) Termins animieren, nicht bei jedem Refresh
    local fresh = f.detEv ~= ev.id
    f.detEv = ev.id
    if fresh then
        K.FadeIn(f.det, 0)
        if f.dSc.SetVerticalScroll then f.dSc:SetVerticalScroll(0) end
    end
    local kc = kindOf(ev).color
    f.det.accent:SetColorTexture(kc[1], kc[2], kc[3], 0.95)
    local ban = f.ban
    if ban.dHalo then ban.dHalo:SetVertexColor(kc[1], kc[2], kc[3]) end
    if not K.Gradient(ban.tint, "HORIZONTAL", { kc[1], kc[2], kc[3], 0.30 }, { kc[1], kc[2], kc[3], 0.02 }) then
        ban.tint:SetColorTexture(kc[1], kc[2], kc[3], 0.10)
    end
    local art = detArt(ev)
    if art and ban.artPath ~= art then ban.art:SetTexture(art) end
    ban.artPath = art
    ban.art:SetShown(art ~= nil)
    ban.wday:SetText(K.Upper(ns.weekday(ev.ts)))
    ban.wday:SetTextColor(kc[1], kc[2], kc[3])
    ban.day:SetText(tonumber(date("%d", ev.ts)))
    ban.mon:SetText(date(L["%d.%m."], ev.ts))
    ban.time:SetText(date("%H:%M", ev.ts))
    f.dTitle:SetText(ev.title or "?")
    -- reiner Kalendertermin: nur anzeigen, Anmeldung laeuft ueber den WoW-Kalender
    local isCal = ev.cal and true or false
    for _, b in pairs(f.roleBtns) do b:SetShown(not isCal) end
    for _, b in ipairs(f.signBtns) do b:SetShown(not isCal) end
    f.calOpen:SetShown(isCal)
    f.srOpen:SetShown(not isCal and ns.SoftRes ~= nil)
    f.dSr:SetShown(not isCal)
    f.note.has = (ev.desc or "") ~= ""
    f.note.t:SetText(ev.desc or "")
    if isCal then
        f.dCount:SetText(countdown(ev.ts))
        f.dMeta:SetText(ns.fmtWhen(ev.ts) .. "  ·  " .. L["WoW-Kalender"])
        f.dMine:SetText("")
        f.other:SetText(L["Dieser Termin steht im WoW-Kalender. Anmelden kannst du dich dort."])
        f.invite:Hide()
        f.del:Hide()
        f.journal:Hide()
        f.wantRow:Hide()
        f.srItem:Hide()
        f.dState = { cal = true }
        Raid.LayoutDetail(f)
        return
    end
    f.dCount:SetText(countdown(ev.ts))
    local meta = ns.fmtWhen(ev.ts) .. ((ev.inst or "") ~= "" and ev.inst ~= ev.title and ("  ·  " .. ev.inst) or "")
        .. L["  -  von "] .. ns.Radar.Colored(ev.by)
    -- Dungeon aus dem Journal erkannt? Dann Stufenbereich + Journal-Knopf
    local dg = ns.Dungeons and (ns.Dungeons.Match(ev.inst) or ns.Dungeons.Match(ev.title))
    f.journal:SetShown(dg ~= nil)
    if dg then
        f.journal:SetLabel(L["Dungeon ansehen"])
        f.journal:SetScript("OnClick", function() if ns.Dungeons then ns.Dungeons.ShowDungeon(dg.key) end end)
        meta = meta .. "  ·  " .. (L["Stufe %s"]):format(dg.level)
    end
    f.dMeta:SetText(meta)
    -- Reservierung: Pille + Item-Symbol bzw. Stand
    local sr = ns.SoftRes and ns.SoftRes.Mine and ns.SoftRes.Mine(ev.id)
    if sr then
        local _, link = itemInfo(sr.item)
        f.dSr:SetText((L["Reserviert: %s"]):format(link or ("Item " .. sr.item)))
        f.srOpen:SetLabel(L["Aendern"])
        f.srItem.id = sr.item
        f.srItem.tex:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(sr.item)) or 134400)
        f.srItem:SetShown(f.srOpen:IsShown())
    else
        f.dSr:SetText("|cff666666" .. L["Noch nichts reserviert"] .. "|r")
        f.srOpen:SetLabel(L["Reservieren"])
        f.srItem:Hide()
    end
    local mine = Raid.MySignup(ev.id)
    for key, b in pairs(f.roleBtns) do
        local on = mine and mine.status == "yes" and mine.role == key
        local rc = ROLES[key][2]
        b.glow:SetShown(on and true or false)
        b.line:SetShown(on and true or false)
        b.ricon:SetAlpha(on and 1 or 0.7)
        if b.rdisc then b.rdisc.halo:SetAlpha(on and 0.6 or 0.3) end
        b.label:SetTextColor(unpack(on and rc or C.text))
        b.onColor = on and rc or nil
        K.SetBorderColor(b, b.onColor or C.line)
    end
    f.signBtns[1].onColor = (mine and mine.status == "maybe") and C.amber or nil
    f.signBtns[2].onColor = (mine and mine.status == "no") and C.red or nil
    f.signBtns[1].label:SetTextColor(unpack(f.signBtns[1].onColor or C.muted))
    f.signBtns[2].label:SetTextColor(unpack(f.signBtns[2].onColor or C.muted))
    K.SetBorderColor(f.signBtns[1], f.signBtns[1].onColor or C.line)
    K.SetBorderColor(f.signBtns[2], f.signBtns[2].onColor or C.line)
    if mine then
        f.dMine:SetText(mine.status == "yes" and ("|cff66db9e" .. L["Du bist dabei als "] .. (ROLES[mine.role] and ROLES[mine.role][1] or "?") .. "|r")
            or mine.status == "maybe" and ("|cffe8b44a" .. L["Du hast 'Vielleicht' gesagt"] .. "|r") or ("|cffff5a4a" .. L["Du hast abgesagt"] .. "|r"))
    else
        f.dMine:SetText("|cff888888" .. L["Noch nicht angemeldet - waehle unten deine Rolle"] .. "|r")
    end
    -- Anmeldungen sammeln
    local byRole = { tank = {}, heal = {}, dps = {} }
    local roleOf, info, maybes, nos = {}, {}, {}, {}
    local function lvlLine(s)
        local lv, il = s.lvl, (s.ilvl or 0) > 0 and s.ilvl or nil
        if not lv and not il then return nil, nil end
        local short = (lv or "?") .. (il and ("/" .. il) or "")
        local tip = "|cff888888" .. (L["Stufe %s"]):format(lv or "?") .. (il and ("  ·  " .. (L["Gegenstandsstufe %d"]):format(il)) or "") .. "|r"
        return short, tip
    end
    for _, s in ipairs(Raid.Signups(ev.id)) do
        local rk = byRole[s.role] and s.role or "dps"
        local short, tip = lvlLine(s)
        info[s.who] = { short = short, tip = tip, class = s.class }
        if s.status == "yes" then
            byRole[rk][#byRole[rk] + 1] = s.who
            roleOf[s.who] = rk
        elseif s.status == "maybe" then
            maybes[#maybes + 1] = { text = ns.colorName(s.who, s.class), role = rk, col = C.amber,
                tip = { ns.colorName(s.who, s.class), ROLES[rk][1], "|cffe8b44a" .. L["Vielleicht"] .. "|r", tip } }
        else
            nos[#nos + 1] = { text = "|cff999999" .. ns.displayName(s.who) .. "|r", col = C.red,
                tip = { ns.colorName(s.who, s.class), "|cffff5a4a" .. L["Absage"] .. "|r", tip } }
        end
    end
    local need = needFor(ev.max)
    for key, col in pairs(f.cols) do
        local have, want = #byRole[key], need[key]
        local full = have >= want
        col.h:SetText(ROLES[key][1])
        col.num:SetText((full and "|cff66db9e" or "|cffe8b44a") .. have .. "/" .. want .. "|r")
        fillBar(col.bar, want > 0 and have / want or 1, fresh)
        local tip = { ROLES[key][1] .. "  " .. have .. "/" .. want }
        for j, nm in ipairs(byRole[key]) do if j <= 15 then tip[#tip + 1] = ns.colorName(nm, info[nm] and info[nm].class) end end
        if not full then tip[#tip + 1] = "|cffe8b44a" .. (L["noch %d gesucht"]):format(want - have) .. "|r" end
        col.tip = tip
        f.roleBtns[key].sub:SetText((full and "|cff66db9e" or "|cff999999") .. have .. "/" .. want .. "|r  " .. (full and L["voll"] or (L["noch %d gesucht"]):format(want - have)))
    end
    local ng = math.max(1, math.min(8, math.ceil((ev.max or 5) / 5)))
    local groups = groupsFor(ev.id, roleOf, ng)
    f.dState = {
        groups = groups, ng = ng, maybes = maybes, nos = nos,
        nameOf = function(n) return ns.colorName(n, info[n] and info[n].class) end,
        extraOf = function(m)
            local x = info[m.name]
            if not x then return nil end
            return x.short, x.tip and (x.tip .. "\n|cff666666" .. L["Stufe / Gegenstandsstufe beim Anmelden"] .. "|r")
        end,
    }
    local lines = {}
    if ns.Lockouts and ns.Lockouts.BoundHint then local okB, hB = pcall(ns.Lockouts.BoundHint, ev) if okB and hB then lines[#lines + 1] = hB end end
    f.other:SetText(table.concat(lines, "\n"))
    local canEdit = ns.isMe(ev.by) or (ns.Admin and ns.Admin.RaidRole and ns.Admin.RaidRole(ns.me()) == "lead") or false
    if not canEdit then
        if ns.GuildOpt("rdOffEd") ~= false then canEdit = ns.isOfficer()
        else canEdit = (ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage()) or false end
    end
    f.invite:SetShown(canEdit)
    f.del:SetShown(canEdit)
    -- Wunsch-Beute der Ziel-Instanz
    local wl = Raid.WantedLoot(ev)
    local wr = f.wantRow
    local shown = math.min(#wl, 12)
    for i = 1, shown do
        local it = wl[i]
        local b = wr.icons[i]
        if not b then
            b = CreateFrame("Button", nil, wr)
            b:SetSize(22, 22)
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetAllPoints()
            b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            K.Border(b, C.amber)
            b:SetScript("OnEnter", function(self) if self.id then K.ItemTip(self, "item:" .. self.id) end end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                if self.id and IsModifiedClick and IsModifiedClick("CHATLINK") then
                    local _, l = itemInfo(self.id)
                    if l then ChatEdit_InsertLink(l) end
                end
            end)
            wr.icons[i] = b
        end
        b.id = it.id
        b.tex:SetTexture((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id)) or 134400)
        b:ClearAllPoints()
        b:SetPoint("LEFT", wr.lbl, "RIGHT", 10 + (i - 1) * 26, 0)
        b:Show()
        if fresh then K.FadeIn(b, 0.2 + i * 0.05) end
    end
    for i = shown + 1, #wr.icons do wr.icons[i]:Hide() end
    wr:SetShown(shown > 0)
    Raid.LayoutDetail(f)
end

local function upcoming()
    local evs = Raid.Events()
    for _, c in ipairs(Raid.CalendarOnly()) do evs[#evs + 1] = c end
    table.sort(evs, function(a, b) return a.ts < b.ts end)
    return evs
end
Raid.Upcoming = upcoming
-- Raids & Beute zeigt alles ausser Dungeon-/Gruppen-Terminen (die stehen auf der Gruppen-Seite)
local function raidUpcoming()
    local out = {}
    for _, e in ipairs(upcoming()) do if not Raid.IsGroupEvent(e) then out[#out + 1] = e end end
    return out
end
local function isMineEv(e)
    local s = not e.cal and Raid.MySignup(e.id)
    return s and (s.status == "yes" or s.status == "maybe") or false
end
Raid.IsMineEvent = isMineEv
-- Filter anwenden; liefert Schluessel, gefilterte Liste und Zaehler
function filterEvents(evs)
    local fk = ns.db and ns.db.settings and ns.db.settings.raidEvFilter or "all"
    if fk ~= "mine" then fk = "all" end
    local cnt, out = { all = #evs, mine = 0 }, {}
    for _, e in ipairs(evs) do
        local m = isMineEv(e)
        if m then cnt.mine = cnt.mine + 1 end
        if fk == "all" or m then out[#out + 1] = e end
    end
    return fk, out, cnt
end

-- Banner "Dein naechster Raid" fuellen; liefert die Hoehe, um die die Kartenliste nach unten rutscht
local function refreshBanner(f)
    local bn = f.banner
    local ev, mine = Raid.NextMine()
    if not ev then
        bn.ev = nil
        bn:Hide()
        f.bannerEv = nil
        return 0
    end
    local fresh = f.bannerEv ~= ev.id
    f.bannerEv = ev.id
    bn.ev = ev
    local kc = kindOf(ev).color
    bn.accent:SetColorTexture(kc[1], kc[2], kc[3], 0.95)
    if not K.Gradient(bn.glow, "HORIZONTAL", { kc[1], kc[2], kc[3], 0.18 }, { kc[1], kc[2], kc[3], 0 }) then
        bn.glow:SetColorTexture(kc[1], kc[2], kc[3], 0.08)
    end
    bn:UpdateClock()
    bn.when:SetText(ns.fmtWhen(ev.ts))
    bn.title:SetText(ev.title or "?")
    local parts = {}
    if (ev.inst or "") ~= "" then parts[#parts + 1] = ev.inst end
    local role = mine and ROLES[mine.role] and mine.role or "dps"
    parts[#parts + 1] = (ns.Profile and (ns.Profile.RoleIcon(role, 13) .. " ") or "") .. L["Deine Rolle"] .. ": " .. K.hex(ROLES[role][2]) .. ROLES[role][1] .. "|r"
    local grp = myGroup(ev.id)
    parts[#parts + 1] = grp and ((L["Gruppe %d"]):format(grp)) or ("|cff777777" .. L["noch keine Gruppe"] .. "|r")
    bn.meta:SetText(table.concat(parts, "  ·  "))
    -- Zusagen + Klassen-Symbole
    local yes, classes = 0, {}
    for _, s in ipairs(Raid.Signups(ev.id)) do
        if s.status == "yes" then
            yes = yes + 1
            local cls = (s.class ~= "" and s.class) or (ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(s.who)) or nil
            classes[#classes + 1] = { cls = cls, who = s.who }
        end
    end
    local fmt = function(v) return (L["%d Zusagen"]):format(math.floor(v + 0.5)) end
    if fresh and animOn() then K.CountUp(bn.cnt, yes, 0.8, fmt) else bn.cnt:SetText(fmt(yes)) end
    local icons = bn.classes.icons
    local maxN = math.max(0, math.floor(((bn:GetWidth() or 600) - 186 - 14 - (bn.cnt:GetStringWidth() or 70) - 10) / 16))
    local n = 0
    local coords = CLASS_ICON_TCOORDS
    for _, c in ipairs(classes) do
        if n >= math.min(maxN, 30) then break end
        if c.cls and coords and coords[c.cls] then
            n = n + 1
            local t = icons[n]
            if not t then
                t = CreateFrame("Frame", nil, bn.classes)
                t:SetSize(14, 14)
                t.tex = t:CreateTexture(nil, "ARTWORK")
                t.tex:SetAllPoints()
                t.tex:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
                t:EnableMouse(true)
                t:SetScript("OnEnter", function(self) if self.who then K.ShowTip(self, { ns.colorName(self.who, self.cls) }) end end)
                t:SetScript("OnLeave", function() GameTooltip:Hide() end)
                icons[n] = t
            end
            local tc = coords[c.cls]
            t.tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            t.who, t.cls = c.who, c.cls
            t:ClearAllPoints()
            t:SetPoint("LEFT", bn.classes, "LEFT", (n - 1) * 16, 0)
            t:Show()
            if fresh then K.FadeIn(t, 0.15 + n * 0.03) end
        end
    end
    for i = n + 1, #icons do icons[i]:Hide() end
    bn:UpdatePrep()
    bn:Show()
    if fresh then K.FadeIn(bn, 0) end
    return 110
end

local function refreshEvents(f)
    local evs = raidUpcoming()
    local ev
    if showDetail and selectedEv then
        ev = Store.Get("events", selectedEv)
        if not ev then for _, e in ipairs(evs) do if e.id == selectedEv then ev = e end end end
        if ev and ev.del then ev = nil end
    end
    if not ev then showDetail = false end
    f.cards:SetShown(not showDetail)
    f.back:SetShown(showDetail)
    f.det:SetShown(showDetail)
    if not showDetail then
        f.detEv = nil
        local top = -refreshBanner(f)
        f.head:SetPoint("TOPLEFT", 0, top - 2)
        f.hint:SetPoint("TOPRIGHT", 0, top - 6)
        f.filt:SetPoint("TOPRIGHT", 0, top - 1)
        f.list:SetPoint("TOPLEFT", 0, top - 28)
        f.head:SetCount(#evs > 0 and #evs or nil)
        local fk, shown, cnt = filterEvents(evs)
        f.filt:Update(cnt, fk)
        f.filt:SetShown(#evs > 0)
        f.list:SetData(shown)
        f.list.empty:SetText(fk == "mine" and L["Du hast noch keinem Termin zugesagt."] or L["Keine anstehenden Raids - die Raidleitung legt Termine an."])
        f.newBtn:SetShown(#evs == 0)
    K.LockButton(f.newBtn, canLead, "raidlead")
        if f.demo then f.demo:SetShown(#evs == 0) end
        if f.interest then
            -- 0.6.455: ohne Termine fuellt die Interesse-Ansicht die Seite (eigener Kopf-Kasten mit Knopf)
            f.interest:ClearAllPoints()
            f.interest:SetPoint("TOPLEFT", f.cards, "TOPLEFT", 0, top)
            f.interest:SetPoint("BOTTOMRIGHT", f.cards, "BOTTOMRIGHT", 0, 0)
            f.head:SetShown(#evs > 0)
            if #evs == 0 then f.newBtn:Hide() end
            f.interest:SetShown(#evs == 0)
            if #evs == 0 then f:UpdateInterest() end
        end
        f.list.empty:SetShown(#evs > 0 and #shown == 0)
        -- Karten beim Oeffnen gestaffelt einblenden (nicht bei jedem Refresh)
        if f.animNext then
            f.animNext = false
            for i, row in ipairs(f.list.rows) do
                if row:IsShown() then K.FadeIn(row, (i - 1) * 0.07) end
            end
        end
        return
    end
    refreshDetail(f, ev)
end

------------------------------------------------------------------------
-- Raidleitung > Neuer Termin: Art, Titel/Ziel, Monatskalender, Uhrzeit, Groesse, Wiederholung,
-- Live-Vorschau der Karte und darunter die Terminliste zum Verwalten (alles scrollbar)
------------------------------------------------------------------------
local DAY = 86400
local TIMES = { "18:00", "18:30", "19:00", "19:30", "20:00", "20:30", "21:00" }
local SIZES = { 5, 10, 20, 40 }
local REPEATS = { 1, 2, 4, 8 }
local MONTHS = { "Januar", "Februar", "Maerz", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" }
local WDAYS = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }
local FORM_LH, FORM_RH, FORM_LISTH = 286, 290, 250

local function trim(s) return ((s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function parseHM(s)
    local h, m = trim(s):match("^(%d%d?)[:%.](%d%d)$")
    h, m = tonumber(h), tonumber(m)
    if h and m and h < 24 and m < 60 then return h, m end
end

-- auswaehlbarer Chip (optional mit Symbol); SetOn faerbt Rahmen/Flaeche in der Akzentfarbe
local function choiceChip(parent, text, w, h, onClick, icon)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 60, h or 24)
    b.bg = K.Fill(b, C.raised)
    K.Border(b, C.line)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(b, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.10 }, 8) end
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.06)
    if icon then
        b.icon = K.Glyph(b, 14, icon, C.muted)
        b.icon:SetPoint("LEFT", 7, 0)
    end
    b.label = K.Text(b, 12, C.muted, icon and "LEFT" or "CENTER")
    if icon then
        b.label:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
        b.label:SetPoint("RIGHT", -3, 0)
    else
        b.label:SetPoint("LEFT", 2, 0)
        b.label:SetPoint("RIGHT", -2, 0)
    end
    b.label:SetWordWrap(false)
    b.label:SetText(text)
    function b:SetOn(on, c)
        c = c or C.accent
        self.on = on
        if self.glassFill then
            ns.Insta.Glass(self, on and { c[1], c[2], c[3], 0.14 } or { 1, 1, 1, 0.03 }, on and { c[1], c[2], c[3], 0.75 } or { 1, 1, 1, 0.10 }, 8)
        else
            if on then self.bg:SetColorTexture(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 1)
            else self.bg:SetColorTexture(C.raised[1], C.raised[2], C.raised[3], C.raised[4] or 1) end
            K.SetBorderColor(self, on and c or C.line)
        end
        local t = on and C.text or C.muted
        self.label:SetTextColor(t[1], t[2], t[3])
        if self.icon then
            self.icon:SetVertexColor(c[1], c[2], c[3])
            self.icon:SetAlpha(on and 1 or 0.55)
        end
    end
    b:SetScript("OnClick", function(self) onClick(self) end)
    return b
end

local function buildForm(f)
    local st = {}
    f.st = st
    local function resetState()
        local now = date("*t", ns.now())
        st.kind, st.max, st.weeks, st.time = "raid", 20, 1, "20:00"
        st.y, st.m, st.sel = now.year, now.month, nil
        st.title, st.inst = "", ""
    end
    resetState()
    f.resetState = resetState

    -- alles in einer Scrollflaeche, damit auf kleinen Fenstern nichts ueberlappt
    local sc = CreateFrame("ScrollFrame", nil, f)
    sc:SetAllPoints()
    local body = CreateFrame("Frame", nil, sc)
    body:SetSize(600, 900)
    sc:SetScrollChild(body)
    sc:EnableMouseWheel(true)
    sc:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, (body:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - d * 40)))
    end)
    f.scroll, f.body = sc, body

    -- Live-Vorschau: dieselbe Karte, die die Mitglieder unter "Termine" sehen
    f.pvHead = K.GameHead(body, L["Vorschau - so sehen es die Mitglieder"], C.violet)
    if f.pvHead.mark then f.pvHead.mark:Hide() end
    f.pvHead.text:SetText(L["Vorschau - so sehen es die Mitglieder"])
    f.pvHead:SetPoint("TOPLEFT", 0, -2)
    f.pvHead:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    local pvHost = CreateFrame("Frame", nil, body)
    pvHost:SetPoint("TOPLEFT", 0, -26)
    pvHost:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    pvHost:SetHeight(CARD_H)
    local pv = createCard(pvHost)
    pv:SetAllPoints(pvHost)
    pv:EnableMouse(false)
    for _, b in pairs(pv.status) do b:EnableMouse(false) end
    for _, b in pairs(pv.roles) do b:EnableMouse(false) end
    pv.srBtn:EnableMouse(false)
    f.preview, f.pvHost = pv, pvHost

    local lc = CreateFrame("Frame", nil, body)
    local rc = CreateFrame("Frame", nil, body)
    f.lc, f.rc = lc, rc
    -- Schnellstart: die letzten Termine der Gilde als Vorlage ("wie letzte Woche") - ein Klick fuellt alles aus
    f.qs = CreateFrame("Frame", nil, body)
    f.qs:SetHeight(30)
    f.qs.lbl = K.Text(f.qs, 11, C.muted)
    f.qs.lbl:SetPoint("LEFT", 0, 0)
    f.qs.lbl:SetText(L["Wie zuletzt:"])
    f.qs.chips = {}
    function f.fillQuick()
        local seen, list = {}, {}
        local evs = Raid.Events()
        table.sort(evs, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
        for _, e in ipairs(evs) do
            local key = (e.title or "") .. "|" .. (e.inst or "")
            if not e.cal and not e.demo and e.ts and not seen[key] and #list < 4 then
                seen[key] = true
                list[#list + 1] = e
            end
        end
        if #list == 0 and ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() then
            list = { { title = "Onyxia", inst = "Onyxias Hort", kind = "raid", max = 40, ts = ns.now() - 6 * DAY } }
        end
        local x = (f.qs.lbl:GetStringWidth() or 60) + 10
        for i = 1, math.max(#list, #f.qs.chips) do
            local e = list[i]
            local b = f.qs.chips[i]
            if e and not b then
                b = choiceChip(f.qs, "", 120, 24, function(self) f.applyQuick(self.ev) end)
                b:HookScript("OnEnter", function(self) K.ShowTip(self, { self.ev.title or "?", (self.ev.inst or "") .. "  ·  " .. ns.weekday(self.ev.ts, true) .. " " .. date("%H:%M", self.ev.ts),
                    "|cff888888" .. L["Klick: Art, Ziel, Uhrzeit, Groesse und Wochentag uebernehmen"] .. "|r" }) end)
                b:HookScript("OnLeave", function() GameTooltip:Hide() end)
                f.qs.chips[i] = b
            end
            if b then
                b:SetShown(e ~= nil)
                if e then
                    b.ev = e
                    b.label:SetText((e.title or "?") .. "  |cff888888" .. ns.weekday(e.ts, true) .. " " .. date("%H:%M", e.ts) .. "|r")
                    local bw = math.min(220, math.floor((b.label:GetStringWidth() or 80) + 22))
                    b:SetWidth(bw)
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", x, 0)
                    x = x + bw + 6
                    b:SetOn(false)
                end
            end
        end
        f.qs.n = #list
        f.qs:SetShown(#list > 0)
    end
    function f.applyQuick(e)
        if not e then return end
        st.kind = (e.kind and Raid.KIND[e.kind]) and e.kind or st.kind
        st.max = e.max or st.max
        st.title, st.inst = e.title or "", e.inst or ""
        f.titleBox:SetText(st.title)
        f.instBox:SetText(st.inst)
        st.time = date("%H:%M", e.ts)
        f.timeBox:SetText(TIMES and (function() for _, t in ipairs(TIMES) do if t == st.time then return "" end end return st.time end)() or st.time)
        -- naechster gleicher Wochentag ab morgen
        local wd = tonumber(date("%w", e.ts))
        local base = date("*t", ns.now())
        for k = 1, 7 do
            local ts = time({ year = base.year, month = base.month, day = base.day + k, hour = 12 })
            if tonumber(date("%w", ts)) == wd then
                local t = date("*t", ts)
                st.sel, st.y, st.m = ts, t.year, t.month
                break
            end
        end
        f.update()
        if K.FadeIn and f.preview then f.preview.oasisFadedAt = nil K.FadeIn(f.preview, 0) end
    end
    local function label(parent, text)
        local s = K.Text(parent, 11, C.muted)
        s:SetText(text)
        return s
    end

    -- Art
    f.kindLbl = label(lc, L["Art"])
    f.kindChips = {}
    for i, k in ipairs(Raid.KINDS) do
        local b = choiceChip(lc, L[k.text], 70, 26, function(self)
            st.kind = k.key
            if k.key == "dungeon" and st.max > 5 then st.max = 5
            elseif k.key == "raid" and st.max <= 5 then st.max = 20 end
            pulse(self, k.color)
            f.update()
        end, ns.ICONS and ns.ICONS[k.icon] or nil)
        b.kind = k
        f.kindChips[i] = b
    end

    -- Titel + Ziel (Freitext oder Auswahl aus der Dungeon-Datenbank)
    f.titleLbl = label(lc, L["Titel"])
    f.titleBox = K.Input(lc, 180, L["Titel, z.B. Todesminen"], function(t) st.title = t f.update() end)
    f.instLbl = label(lc, L["Instanz / Ziel"])
    f.instBox = K.Input(lc, 150, L["Instanz / Ziel"], function(t) st.inst = t f.update() end)
    local function openPicker(anchor)
        if not (ns.Dungeons and ns.Dungeons.List) then ns.print(L["Keine Dungeon-Daten gefunden."]) return end
        local ok, list = pcall(ns.Dungeons.List)
        if not ok or type(list) ~= "table" then ns.print(L["Keine Dungeon-Daten gefunden."]) return end
        local items = {}
        for _, d in ipairs(list) do
            if not d.closed and d.name and #items < 35 then
                local k = Raid.KIND[d.raid and "raid" or "dungeon"]
                local icon = type(d.icon) == "string" and d.icon or nil
                items[#items + 1] = {
                    key = d.name, d = d,
                    text = d.name .. (((d.level or "") ~= "") and ("\n|cff888888" .. d.level .. "|r") or ""),
                    icon = icon or (ns.ICONS and ns.ICONS[k.icon]) or nil,
                    color = (not icon) and k.color or nil,
                    checked = trim(st.inst):find(d.name, 1, true) == 1,
                }
            end
        end
        if #items == 0 then ns.print(L["Keine Dungeon-Daten gefunden."]) return end
        K.TilePicker(anchor, L["Ziel waehlen"], items, function(key)
            for _, it in ipairs(items) do
                if it.key == key then
                    local d = it.d
                    st.inst = d.name .. (((d.level or "") ~= "") and (" (" .. d.level .. ")") or "")
                    f.instBox:SetText(st.inst)
                    if trim(st.title) == "" then st.title = d.name f.titleBox:SetText(d.name) end
                    if d.raid then
                        st.kind = "raid"
                        if st.max <= 5 then st.max = 20 end
                    elseif st.kind ~= "raid" then
                        st.kind, st.max = "dungeon", 5
                    end
                end
            end
            f.update()
        end)
    end
    f.pick = K.Button(lc, "...", 28, 24, "ghost", function(self) openPicker(self) end)
    if ns.ICONS and ns.ICONS.dungeons then
        f.pick.label:SetText("")
        f.pick.glyph = K.Glyph(f.pick, 15, ns.ICONS.dungeons, C.text)
        f.pick.glyph:SetPoint("CENTER")
    end
    f.pick:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Ziel waehlen"], L["Raids und Dungeons aus dem Dungeon-Journal"] }) end)
    f.pick:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- Uhrzeit: Schnellwahl + eigene Zeit
    f.timeLbl = label(lc, L["Uhrzeit"])
    f.timeChips = {}
    for i, t in ipairs(TIMES) do
        local b = choiceChip(lc, t, 44, 24, function(self)
            st.time = t
            f.timeBox:SetText("")
            pulse(self)
            f.update()
        end)
        b.t = t
        f.timeChips[i] = b
    end
    f.timeBox = K.Input(lc, 58, L["HH:MM"], function(t)
        if parseHM(t) then st.time = trim(t) end
        f.update()
    end)

    -- Gruppengroesse + Wiederholung
    f.sizeLbl = label(lc, L["Gruppengroesse"])
    f.sizeChips = {}
    for i, n in ipairs(SIZES) do
        local b = choiceChip(lc, (L["%d Spieler"]):format(n), 60, 24, function(self)
            st.max = n
            pulse(self)
            f.update()
        end)
        b.n = n
        f.sizeChips[i] = b
    end
    f.repLbl = label(lc, L["Wiederholen"])
    f.repChips = {}
    for i, n in ipairs(REPEATS) do
        local b = choiceChip(lc, n == 1 and L["Einmalig"] or (L["Alle %d Wochen"]):format(n), 60, 24, function(self)
            st.weeks = n
            pulse(self)
            f.update()
        end)
        b.n = n
        f.repChips[i] = b
    end
    f.calToggle = K.Toggle(lc, L["Auch im WoW-Kalender eintragen"], function() return Raid.toCalendar end, function(v) Raid.toCalendar = v end)

    -- Monatskalender
    f.prevM = K.Button(rc, "<", 26, 22, "ghost", function()
        local now = date("*t", ns.now())
        if st.y * 12 + st.m <= now.year * 12 + now.month then return end
        st.m = st.m - 1
        if st.m < 1 then st.m, st.y = 12, st.y - 1 end
        f.update()
    end)
    f.nextM = K.Button(rc, ">", 26, 22, "ghost", function()
        st.m = st.m + 1
        if st.m > 12 then st.m, st.y = 1, st.y + 1 end
        f.update()
    end)
    f.monTitle = K.Title(rc, 14, C.text, "CENTER")
    f.wdLbls = {}
    for i, w in ipairs(WDAYS) do
        local s = K.Text(rc, 10, i >= 6 and C.amber or C.dim, "CENTER")
        s:SetText(L[w])
        f.wdLbls[i] = s
    end
    f.cells = {}
    for i = 1, 42 do
        local c = CreateFrame("Button", nil, rc)
        c.bg = K.Fill(c, { 1, 1, 1, 0.025 })
        K.Border(c, C.line)
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(c, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 6) end
        -- wie viele aus dem Raid-Interesse koennen an diesem Wochentag
        c.int = K.Text(c, 8, C.mint, "RIGHT")
        c.int:SetPoint("TOPRIGHT", -2, -1)
        c.hl = c:CreateTexture(nil, "HIGHLIGHT")
        c.hl:SetAllPoints()
        c.hl:SetColorTexture(1, 1, 1, 0.07)
        c.num = K.Text(c, 12, C.text, "CENTER")
        c.num:SetPoint("CENTER", 0, 1)
        c.dot = c:CreateTexture(nil, "OVERLAY")
        c.dot:SetSize(4, 4)
        c.dot:SetPoint("BOTTOM", 0, 3)
        c:SetScript("OnClick", function(self)
            if self.past or not self.ts then return end
            local t = date("*t", self.ts)
            st.sel = self.ts
            st.y, st.m = t.year, t.month
            f.update()
            pulse(f.cells[self.idx])
        end)
        c.idx = i
        f.cells[i] = c
    end
    f.summary = K.Text(rc, 11, C.muted)
    f.summary:SetWordWrap(true)
    f.create = K.Button(rc, L["Termin anlegen"], 200, 34, "primary", function(self)
        if not rankAllowed(ns.GuildOpt("rdEvRank")) then ns.print(L["Termine anlegen darf bei euch nur die Gildenleitung bzw. hoehere Raenge."]) return end
        local ev, ts = f.buildEv()
        if not ts then ns.print(L["Bitte einen Tag im Kalender waehlen."]) return end
        if ts <= ns.now() then ns.print(L["Der Termin liegt in der Vergangenheit."]) return end
        pulse(self, C.mint)
        local made = Raid.CreateEvent({ title = ev.title, inst = ev.inst, ts = ts, max = st.max, kind = st.kind }, Raid.toCalendar, st.weeks)
        if made[1] then selectedEv = made[1].id end
        K.Toast(L["Termin angelegt"], (ev.title or "?") .. "  ·  " .. ns.fmtWhen(ts)
            .. (#made > 1 and ("  ·  " .. (L["%d Termine"]):format(#made)) or ""), C.mint)
        f.titleBox:SetText("")
        f.instBox:SetText("")
        f.timeBox:SetText("")
        resetState()
        f.update()
        ns.RefreshPage("raid")
    end)
    local fp = f.create.label:GetFont()
    if fp then K.SetFontSafe(f.create.label, fp, 14, "") end

    -- Terminliste zum Verwalten (feste Hoehe, scrollt selbst)
    local lh = K.GameHead(body, L["Anstehende Termine"], C.blue)
    f.listHead = lh
    local list = K.List(body, 50, function(l)
        local r = K.Row(l)
        r.day = K.Text(r, 20, C.text, "CENTER", K.FONT)
        r.day:SetPoint("LEFT", 6, 5)
        r.day:SetWidth(44)
        r.mon = K.Text(r, 9, C.muted, "CENTER")
        r.mon:SetPoint("TOP", r.day, "BOTTOM", 0, -1)
        r.mon:SetWidth(44)
        r.kind = K.Glyph(r, 14, nil, C.muted)
        r.kind:SetPoint("LEFT", 58, 0)
        r.cols.cnt = K.Text(r, 16, C.violet, "RIGHT", K.FONT)
        r.cols.cnt:SetPoint("RIGHT", -10, 0)
        r.cols.cnt:SetWidth(70)
        r.cols.title = K.Text(r, 13, C.text)
        r.cols.title:SetPoint("TOPLEFT", 80, -8)
        r.cols.title:SetPoint("RIGHT", r.cols.cnt, "LEFT", -10, 0)
        r.cols.title:SetWordWrap(false)
        r.cols.meta = K.Text(r, 11, C.muted)
        r.cols.meta:SetPoint("BOTTOMLEFT", 80, 8)
        r.cols.meta:SetPoint("RIGHT", r.cols.cnt, "LEFT", -10, 0)
        r.cols.meta:SetWordWrap(false)
        r:SetScript("OnClick", function(self)
            if self.item then Raid.OpenEvent(self.item.id) end
        end)
        return r
    end, function(r, e)
        local k = kindOf(e)
        r.kind:SetTexture(ns.ICONS and ns.ICONS[k.icon] or nil)
        r.kind:SetVertexColor(k.color[1], k.color[2], k.color[3])
        r.day:SetText(date("%d", e.ts))
        r.mon:SetText(ns.weekday(e.ts, true) .. "  " .. date("%H:%M", e.ts))
        r.cols.title:SetText(e.title or "?")
        r.sel:SetShown(selectedEv == e.id)
        if e.cal then
            r.cols.meta:SetText("|cff777777" .. L["WoW-Kalender"] .. "|r")
            r.cols.cnt:SetText("")
            return
        end
        r.cols.meta:SetText((e.inst or "") .. L["  |cff777777von "] .. ns.displayName(e.by) .. "|r")
        local yes = 0
        for _, s in ipairs(Raid.Signups(e.id)) do if s.status == "yes" then yes = yes + 1 end end
        r.cols.cnt:SetText(yes .. "/" .. (e.max or 5))
    end)
    list.empty:SetText(L["Keine anstehenden Termine."])
    f.list = list
    lh.text:SetText(L["Anstehende Termine"])
    if lh.mark then lh.mark:Hide() end

    -- Schritt-Koepfe: kleine Nummer + ruhiger Titel
    local function stepHead(n, text)
        local h = CreateFrame("Frame", nil, lc)
        h:SetHeight(20)
        h.disc = h:CreateTexture(nil, "ARTWORK")
        h.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        h.disc:SetSize(18, 18)
        h.disc:SetPoint("LEFT", 0, 0)
        h.disc:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.35)   -- 0.6.462: Nummer im Akzent-Kreis
        h.n = K.Title(h, 11, C.text, "CENTER")
        h.n:SetPoint("CENTER", h.disc, "CENTER", 0, 0)
        h.n:SetText(n)
        h.t = K.Title(h, 13, C.text)
        h.t:SetPoint("LEFT", h.disc, "RIGHT", 8, 0)
        h.t:SetText(text)
        h.hint = K.Text(h, 10, C.dim)
        h.hint:SetPoint("LEFT", h.t, "RIGHT", 10, -1)
        return h
    end
    f.step1 = stepHead(1, L["Aktivitaet"])
    f.step2 = stepHead(2, L["Zeitpunkt"])
    f.step3 = stepHead(3, L["Gruppe"])
    f.step1.hint:SetText(L["Was fuer ein Termin soll es sein?"])
    f.step2.hint:SetText(L["Wann findet der Termin statt?"])
    f.step3.hint:SetText(L["Wie viele Spieler und wie oft?"])

    -- rechts: so wird der Termin (ruhige Zusammenfassung) + Anlegen
    local sum = CreateFrame("Frame", nil, body)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(sum, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.10 }, 14) end
    f.sumCard = sum
    -- 0.6.462: dezentes Hintergrundbild (Gildenmodul) oben in der Vorschau, nach unten auslaufend
    if ns.GuildPack then
        sum.art = sum:CreateTexture(nil, "BACKGROUND", nil, 2)
        sum.art:SetPoint("TOPLEFT", 3, -3) sum.art:SetPoint("TOPRIGHT", -3, -3)
        sum.art:SetHeight(104)
        sum.art:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\raid_preview_bg")
        sum.art:SetTexCoord(0, 1, 0.12, 0.6)
        sum.art:SetAlpha(0.4)
        -- 0.6.464: niedriger, unten weich ins Transparente auslaufend (Verlauf auf dem Bild selbst)
        if sum.art.SetGradient and CreateColor then pcall(sum.art.SetGradient, sum.art, "VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 1)) end
        if K.RoundMask then pcall(K.RoundMask, sum.art, sum, 14, { "tl", "tr" }) end
    end
    sum.cap = K.Text(sum, 12, C.text)
    sum.cap:SetPoint("TOPLEFT", 16, -14)
    sum.cap:SetText(L["Termin-Vorschau"])
    sum.disc = CreateFrame("Frame", nil, sum)
    sum.disc:SetSize(76, 76)   -- 0.6.463: grosse Scheibe wie im Entwurf
    sum.disc:SetPoint("TOPLEFT", 18, -66)
    sum.disc.bg = sum.disc:CreateTexture(nil, "BACKGROUND")
    sum.disc.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    sum.disc.bg:SetAllPoints()
    sum.disc.g = K.Glyph(sum.disc, 40, nil, C.text)
    sum.disc.g:SetPoint("CENTER")
    sum.title = K.Title(sum, 22, C.text)
    sum.title:SetPoint("TOPLEFT", sum.disc, "TOPRIGHT", 14, -18)
    sum.title:SetPoint("RIGHT", sum, "RIGHT", -14, 0)
    sum.title:SetWordWrap(false)
    sum.inst = K.Text(sum, 11, C.muted)
    sum.inst:SetPoint("TOPLEFT", sum.title, "BOTTOMLEFT", 0, -4)
    sum.inst:SetPoint("RIGHT", sum, "RIGHT", -14, 0)
    sum.inst:SetWordWrap(false)
    -- 0.6.463: Trennlinie, darunter vier Zeilen mit Symbol (Datum, Uhrzeit, Spieler, Wiederholung)
    sum.div = sum:CreateTexture(nil, "ARTWORK")
    sum.div:SetHeight(1)
    sum.div:SetPoint("TOPLEFT", 18, -156) sum.div:SetPoint("TOPRIGHT", -18, -156)
    sum.div:SetColorTexture(1, 1, 1, 0.1)
    sum.rows = {}
    for k, ic in ipairs({ "chronicle", "camp", "groups", "sync" }) do
        local g = K.Glyph(sum, 16, ns.MEDIA .. "icons\\" .. ic, C.muted)
        g:SetPoint("TOPLEFT", 22, -170 - (k - 1) * 28)
        local t = K.Text(sum, 13, C.text)
        t:SetPoint("LEFT", g, "RIGHT", 14, 0)
        sum.rows[k] = t
    end
    -- Datum gross, darunter Countdown (alt, ausgeblendet - steht in den Zeilen)
    sum.date = K.Title(sum, 20, C.text)
    sum.date:SetPoint("TOPLEFT", 16, -92)
    sum.date:SetAlpha(0)
    sum.time = K.Text(sum, 12, C.muted)
    sum.time:SetPoint("TOPLEFT", sum.date, "BOTTOMLEFT", 0, -4)
    sum.time:SetAlpha(0)
    sum.facts = K.Text(sum, 11, C.text)
    sum.facts:SetPoint("TOPLEFT", sum.time, "BOTTOMLEFT", 0, -10)
    sum.facts:SetPoint("RIGHT", sum, "RIGHT", -14, 0)
    sum.facts:SetWordWrap(true)
    sum.facts:SetJustifyH("LEFT")
    sum.facts:SetAlpha(0)
    f.summary:SetParent(sum)
    f.create:SetParent(sum)
    f.calToggle:SetParent(sum)
    sum.pv = CreateFrame("Button", nil, sum)
    sum.pv:SetHeight(38)   -- 0.6.463: als umrandeter Knopf mit Symbol
    if ns.Insta and ns.Insta.Glass then pcall(ns.Insta.Glass, sum.pv, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.14 }, 6) end
    sum.pv.ic = K.Glyph(sum.pv, 16, ns.MEDIA .. "icons\\groups", C.muted)
    sum.pv.ic:SetPoint("LEFT", 16, 0)
    sum.pv.t = K.Text(sum.pv, 12, C.text)
    sum.pv.t:SetPoint("LEFT", 44, 0)
    sum.pv:SetScript("OnClick", function()
        f.showPv = not f.showPv
        f.layout()
        f.update()
        if f.showPv and K.FadeIn then f.pvHost.oasisFadedAt = nil K.FadeIn(f.pvHost, 0) end
    end)
    sum.pv:SetScript("OnEnter", function(self) self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    sum.pv:SetScript("OnLeave", function(self) self.t:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)

    -- Vorschau-Termin aus dem Formular; ts = nil, solange kein Tag gewaehlt ist
    function f.buildEv()
        local h, m = parseHM(st.time)
        if not h then h, m = 20, 0 end
        local ts
        if st.sel then
            local t = date("*t", st.sel)
            ts = time({ year = t.year, month = t.month, day = t.day, hour = h, min = m, sec = 0 })
        end
        local title = trim(st.title)
        if title == "" then title = trim(st.inst):gsub("%s*%(.-%)$", "") end
        if title == "" then title = L[Raid.KIND[st.kind].text] end
        return { id = "preview", preview = true, title = title, inst = trim(st.inst), ts = ts, max = st.max, kind = st.kind, by = ns.me() }, ts
    end

    -- Breite verteilen: breit = Formular links, Kalender rechts; schmal = untereinander
    local function layout()
        local w = math.floor(sc:GetWidth() or 0)
        if w < 100 then return end
        body:SetWidth(w)
        local y0 = 0
        -- Vorschau nur auf Wunsch (oben, volle Breite)
        f.pvHead:SetShown(f.showPv == true)
        pvHost:SetShown(f.showPv == true)
        if f.showPv then y0 = -26 - CARD_H - 14 end
        if f.qs:IsShown() then
            f.qs:ClearAllPoints()
            f.qs:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y0)
            f.qs:SetPoint("RIGHT", body, "RIGHT", 0, 0)
            y0 = y0 - 38
        end
        local two = w >= 640
        local RW = two and math.max(240, math.floor(w * 0.34)) or w
        local LW = two and (w - RW - 18) or w
        lc:ClearAllPoints()
        lc:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y0)
        -- Kopfzeilen der alten Felder werden nicht mehr gebraucht (Platzhalter sagen alles)
        for _, x in ipairs({ f.kindLbl, f.titleLbl, f.instLbl, f.timeLbl, f.sizeLbl, f.repLbl }) do x:Hide() end
        -- 0.6.463: genau nach Entwurf - Ueberschrift "Neuen Termin planen" + Schloss-Hinweis, Schritt-Leiste (1-2-3),
        -- darunter drei Kaesten; Felder mit Beschriftung, Uhrzeit-Spalte mit Trennlinie, Gruppe zweispaltig
        local PX = 18
        local CWD = LW - 2 * PX
        f.secBox = f.secBox or {}
        local function sec(k, top, bottom)
            local b = f.secBox[k]
            if not b then
                b = CreateFrame("Frame", nil, lc)
                if ns.Insta and ns.Insta.Glass then pcall(ns.Insta.Glass, b, { 0.055, 0.055, 0.065, 0.7 }, { 1, 1, 1, 0.08 }, 10) end
                f.secBox[k] = b
            end
            b:SetFrameLevel(math.max(0, lc:GetFrameLevel()))
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", lc, "TOPLEFT", 0, -top)
            b:SetSize(LW, bottom - top)
        end
        local function vline(key, x, top, h)
            f.vl = f.vl or {}
            local t = f.vl[key]
            if not t then t = lc:CreateTexture(nil, "ARTWORK") t:SetColorTexture(1, 1, 1, 0.08) f.vl[key] = t end
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", lc, "TOPLEFT", x, -top)
            t:SetSize(1, h)
            t:Show()
        end
        -- Kopf
        if not f.planHead then
            local ph = {}
            ph.t = K.Title(lc, 24, C.text)
            ph.t:SetText(L["Neuen Termin planen"])
            ph.lock = CreateFrame("Frame", nil, lc)
            ph.lock:SetHeight(24)
            if ns.Insta and ns.Insta.Glass then pcall(ns.Insta.Glass, ph.lock, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.1 }, 6) end
            ph.lock.t = K.Text(ph.lock, 10, C.muted)
            ph.lock.t:SetPoint("LEFT", 10, 0)
            ph.lock.t:SetText("|TInterface\\PetBattles\\PetBattle-LockIcon:12:12|t  " .. L["Nur fuer die Raidleitung"])
            ph.lock:SetWidth((ph.lock.t:GetStringWidth() or 120) + 22)
            ph.steps = {}
            local TXT = { { "Aktivitaet", "Art und Ziel des Termins" }, { "Zeitpunkt", "Datum und Uhrzeit" }, { "Gruppe", "Gruppengroesse und Wiederholung" } }
            for k = 1, 3 do
                local st2 = {}
                st2.ring = lc:CreateTexture(nil, "ARTWORK")
                st2.ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                st2.ring:SetSize(34, 34)
                st2.inner = lc:CreateTexture(nil, "ARTWORK", nil, 1)
                st2.inner:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                st2.inner:SetSize(30, 30)
                st2.inner:SetPoint("CENTER", st2.ring)
                st2.inner:SetVertexColor(0.05, 0.05, 0.06, 1)
                st2.n = K.Title(lc, 13, C.text, "CENTER")
                st2.n:SetPoint("CENTER", st2.ring, "CENTER", 0, 0)
                st2.n:SetText(k)
                st2.a = K.Title(lc, 12, C.text)
                st2.a:SetPoint("TOPLEFT", st2.ring, "TOPRIGHT", 10, -3)
                st2.a:SetText(L[TXT[k][1]])
                st2.b = K.Text(lc, 9, C.dim)
                st2.b:SetPoint("TOPLEFT", st2.a, "BOTTOMLEFT", 0, -3)
                st2.b:SetText(L[TXT[k][2]])
                st2.line = lc:CreateTexture(nil, "ARTWORK")
                st2.line:SetHeight(1)
                st2.line:SetColorTexture(1, 1, 1, 0.12)
                ph.steps[k] = st2
            end
            f.planHead = ph
        end
        local ph = f.planHead
        ph.t:ClearAllPoints() ph.t:SetPoint("TOPLEFT", lc, "TOPLEFT", 0, -4)
        ph.lock:ClearAllPoints() ph.lock:SetPoint("LEFT", ph.t, "RIGHT", 14, 0)
        local segW = math.floor(LW / 3)
        for k, st2 in ipairs(ph.steps) do
            st2.ring:ClearAllPoints()
            st2.ring:SetPoint("TOPLEFT", lc, "TOPLEFT", (k - 1) * segW, -44)
            local on = k == 1
            st2.ring:SetVertexColor(on and C.accent[1] or 0.45, on and C.accent[2] or 0.45, on and C.accent[3] or 0.48, 1)
            st2.line:ClearAllPoints()
            st2.line:SetPoint("LEFT", st2.a, "RIGHT", 10, 0)
            st2.line:SetPoint("RIGHT", lc, "TOPLEFT", k * segW - 12, 0)
            st2.line:SetShown(k < 3)
        end
        -- 1 Aktivitaet
        local y = 92
        local s1 = y
        y = y + 14
        f.step1:ClearAllPoints() f.step1:SetPoint("TOPLEFT", PX, -y) f.step1:SetWidth(CWD)
        y = y + 32
        local cw = math.floor((CWD - 4 * 8) / 5)
        for i, b in ipairs(f.kindChips) do
            b:SetSize(cw, 40)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", PX + ((i - 1) % 5) * (cw + 8), -y - math.floor((i - 1) / 5) * 46)
        end
        y = y + 52 + math.floor((#f.kindChips - 1) / 5) * 46
        local tw = math.floor((CWD - 16 - 34) / 2)
        f.instLbl:SetText(L["Instanz / Ziel"]) f.instLbl:Show()
        f.instLbl:ClearAllPoints() f.instLbl:SetPoint("TOPLEFT", lc, "TOPLEFT", PX, -y)
        f.titleLbl:SetText(L["Titel"] .. " |cff888888(" .. L["optional"] .. ")|r") f.titleLbl:Show()
        f.titleLbl:ClearAllPoints() f.titleLbl:SetPoint("TOPLEFT", lc, "TOPLEFT", PX + tw + 50, -y)
        y = y + 16
        f.instBox:ClearAllPoints() f.instBox:SetPoint("TOPLEFT", PX, -y) f.instBox:SetSize(tw, 30)
        f.pick:ClearAllPoints() f.pick:SetPoint("LEFT", f.instBox, "RIGHT", 4, 0)
        f.titleBox:ClearAllPoints() f.titleBox:SetPoint("TOPLEFT", PX + tw + 50, -y) f.titleBox:SetSize(CWD - tw - 50, 30)
        y = y + 30 + 18
        sec(1, s1, y)
        y = y + 12
        -- 2 Zeitpunkt: Kalender links, Trennlinie, Uhrzeiten rechts
        local s2 = y
        y = y + 14
        f.step2:ClearAllPoints() f.step2:SetPoint("TOPLEFT", PX, -y) f.step2:SetWidth(CWD)
        y = y + 32
        local timeW = math.max(110, math.floor(CWD * 0.24))
        local calW = math.max(210, CWD - timeW - 34)
        local cellW = math.floor((calW - 6 * 4) / 7)
        local cellH = 28
        rc:ClearAllPoints()
        rc:SetParent(lc)
        rc:SetPoint("TOPLEFT", lc, "TOPLEFT", PX, -y)
        rc:SetSize(calW, 230)
        f.prevM:ClearAllPoints() f.prevM:SetPoint("TOPLEFT", 0, 0)
        f.nextM:ClearAllPoints() f.nextM:SetPoint("TOPLEFT", calW - 26, 0)
        f.monTitle:ClearAllPoints()
        f.monTitle:SetPoint("LEFT", f.prevM, "RIGHT", 4, 0)
        f.monTitle:SetPoint("RIGHT", f.nextM, "LEFT", -4, 0)
        for i, sl in ipairs(f.wdLbls) do
            sl:ClearAllPoints()
            sl:SetPoint("TOPLEFT", (i - 1) * (cellW + 4), -30)
            sl:SetWidth(cellW)
        end
        for i, c in ipairs(f.cells) do
            local col, row = (i - 1) % 7, math.floor((i - 1) / 7)
            c:SetSize(cellW, cellH)
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", col * (cellW + 4), -46 - row * (cellH + 4))
        end
        local calH = 46 + 6 * (cellH + 4)
        vline("cal", PX + calW + 16, y, calH)
        local tx = PX + calW + 34
        f.timeLbl:SetText(L["Uhrzeit"]) f.timeLbl:Show()
        f.timeLbl:ClearAllPoints() f.timeLbl:SetPoint("TOPLEFT", lc, "TOPLEFT", tx, -y)
        local tStep = math.floor((calH - 18 - 46) / 7)
        for i, b in ipairs(f.timeChips) do
            b:SetSize(timeW, tStep - 4)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", lc, "TOPLEFT", tx, -y - 18 - (i - 1) * tStep)
        end
        if not f.ownTimeLbl then f.ownTimeLbl = K.Text(lc, 10, C.dim) f.ownTimeLbl:SetText(L["Eigene Uhrzeit"]) end
        f.ownTimeLbl:ClearAllPoints()
        f.ownTimeLbl:SetPoint("TOPLEFT", lc, "TOPLEFT", tx, -y - 18 - 7 * tStep)
        f.timeBox:ClearAllPoints()
        f.timeBox:SetPoint("TOPLEFT", lc, "TOPLEFT", tx, -y - 18 - 7 * tStep - 14)
        f.timeBox:SetSize(timeW, 28)
        y = y + calH + 16
        sec(2, s2, y)
        y = y + 12
        -- 3 Gruppe: Groesse links, Wiederholung rechts
        local s3 = y
        y = y + 14
        f.step3:ClearAllPoints() f.step3:SetPoint("TOPLEFT", PX, -y) f.step3:SetWidth(CWD)
        y = y + 32
        local half = math.floor((CWD - 33) / 2)
        f.sizeLbl:SetText(L["Gruppengroesse"]) f.sizeLbl:Show()
        f.sizeLbl:ClearAllPoints() f.sizeLbl:SetPoint("TOPLEFT", lc, "TOPLEFT", PX, -y)
        f.repLbl:SetText(L["Wiederholung"]) f.repLbl:Show()
        f.repLbl:ClearAllPoints() f.repLbl:SetPoint("TOPLEFT", lc, "TOPLEFT", PX + half + 33, -y)
        vline("grp", PX + half + 16, y, 50)
        y = y + 18
        local scw = math.floor((half - 3 * 6) / 4)
        for i, b in ipairs(f.sizeChips) do b:SetSize(scw, 30) b:ClearAllPoints() b:SetPoint("TOPLEFT", PX + (i - 1) * (scw + 6), -y) end
        for i, b in ipairs(f.repChips) do b:SetSize(scw, 30) b:ClearAllPoints() b:SetPoint("TOPLEFT", PX + half + 33 + (i - 1) * (scw + 6), -y) end
        y = y + 30 + 18
        sec(3, s3, y)
        local LH = y
        lc:SetSize(LW, LH)
        -- rechts: Zusammenfassung + anstehende Termine
        local sumCard = f.sumCard
        sumCard:ClearAllPoints()
        local sumH = 436   -- 0.6.464
        if two then sumCard:SetPoint("TOPLEFT", body, "TOPLEFT", LW + 18, y0)
        else sumCard:SetPoint("TOPLEFT", body, "TOPLEFT", 0, y0 - LH - 12) end
        sumCard:SetSize(RW, sumH)
        f.summary:ClearAllPoints()
        f.summary:SetPoint("TOPLEFT", sumCard.facts, "BOTTOMLEFT", 0, -8)
        f.summary:SetPoint("RIGHT", sumCard, "RIGHT", -14, 0)
        f.calToggle:ClearAllPoints()
        f.calToggle:SetPoint("BOTTOMLEFT", 16, 120)
        f.calToggle:SetWidth(RW - 28)
        sumCard.pv:ClearAllPoints()
        sumCard.pv:SetPoint("BOTTOMLEFT", 16, 72)
        sumCard.pv:SetWidth(RW - 32)
        f.create:ClearAllPoints()
        f.create:SetPoint("BOTTOMLEFT", 16, 16)
        f.create:SetSize(RW - 32, 44)
        local listTop, listX, listW
        if two then listTop, listX, listW = y0 - sumH - 18, LW + 18, RW
        else listTop, listX, listW = y0 - LH - 12 - sumH - 18, 0, w end
        local listH = two and math.max(140, LH - sumH - 18 - 24) or FORM_LISTH
        -- 0.6.463: "Anstehende Termine" als eigener Kasten, leer mit Symbol und Hinweis
        if not f.upBox then
            f.upBox = CreateFrame("Frame", nil, body)
            if ns.Insta and ns.Insta.Glass then pcall(ns.Insta.Glass, f.upBox, { 0.055, 0.055, 0.065, 0.7 }, { 1, 1, 1, 0.08 }, 12) end
            f.upBox:SetFrameLevel(math.max(0, body:GetFrameLevel()))
            f.upEmpty = K.Glyph(f.upBox, 40, ns.MEDIA .. "icons\\chronicle", C.dim)
        end
        f.upBox:ClearAllPoints()
        f.upBox:SetPoint("TOPLEFT", body, "TOPLEFT", listX, listTop)
        f.upBox:SetSize(listW, listH + 40)
        f.upEmpty:ClearAllPoints()
        f.upEmpty:SetPoint("TOP", f.upBox, "TOP", 0, -64)
        f.upEmpty:SetShown(#(list.data or {}) == 0)
        list.empty:SetText(L["Noch keine Termine."] .. "\n|cff999999" .. L["Sobald du einen Termin anlegst, wird er hier angezeigt."] .. "|r")
        lh:ClearAllPoints()
        lh:SetPoint("TOPLEFT", body, "TOPLEFT", listX + 16, listTop - 12)
        lh:SetWidth(listW - 32)
        list:ClearAllPoints()
        list:SetPoint("TOPLEFT", body, "TOPLEFT", listX + 10, listTop - 36)
        list:SetSize(listW - 20, listH)
        local bottom = math.max(-y0 + LH, -listTop + 24 + listH) + 10
        body:SetHeight(bottom)
    end
    f.layout = layout
    sc:SetScript("OnSizeChanged", layout)
    f:HookScript("OnShow", function() f.animNext = true end)
    f.animNext = true

    -- alles neu zeichnen (bei jeder Eingabe)
    function f.update()
        local ev, ts = f.buildEv()
        for _, b in ipairs(f.kindChips) do b:SetOn(st.kind == b.kind.key, b.kind.color) end
        local custom = parseHM(f.timeBox:GetText())
        for _, b in ipairs(f.timeChips) do b:SetOn(not custom and st.time == b.t) end
        for _, b in ipairs(f.sizeChips) do b:SetOn(st.max == b.n) end
        for _, b in ipairs(f.repChips) do b:SetOn(st.weeks == b.n) end
        -- Kalender
        local now = date("*t", ns.now())
        f.monTitle:SetText(L[MONTHS[st.m]] .. " " .. st.y)
        f.prevM:SetEnabledState(st.y * 12 + st.m > now.year * 12 + now.month)
        local todayKey = date("%Y%m%d", ns.now())
        local selKey = st.sel and date("%Y%m%d", st.sel)
        local evDays = {}
        for _, e in ipairs(upcoming()) do evDays[date("%Y%m%d", e.ts)] = true end
        local first = time({ year = st.y, month = st.m, day = 1, hour = 12 })
        local lead = (tonumber(date("%w", first)) + 6) % 7
        -- Raid-Interesse: wer kann an welchem Wochentag (1 = Mo)
        local intDays, bestN = {}, 0
        if Raid.Interests then
            for _, r in ipairs(Raid.Interests()) do
                for ch in tostring(r.days or ""):gmatch("%d") do
                    local d = tonumber(ch)
                    if d then intDays[d] = (intDays[d] or 0) + 1 if intDays[d] > bestN then bestN = intDays[d] end end
                end
            end
        end
        local kc = Raid.KIND[st.kind].color
        for i, c in ipairs(f.cells) do
            local ts2 = first + (i - 1 - lead) * DAY
            local t = date("*t", ts2)
            local key = date("%Y%m%d", ts2)
            local inMonth = t.month == st.m
            c.ts = time({ year = t.year, month = t.month, day = t.day, hour = 12 })
            c.past = key < todayKey
            c.num:SetText(t.day)
            local sel = key == selKey
            local wdI = (tonumber(date("%w", ts2)) + 6) % 7 + 1
            local ni = intDays[wdI] or 0
            c.int:SetText((ni > 0 and not c.past) and ni or "")
            local best = ni > 0 and ni == bestN and not c.past and inMonth
            if c.glassFill then
                local fill = sel and { C.accent[1], C.accent[2], C.accent[3], 0.55 } or { 1, 1, 1, inMonth and 0.035 or 0.01 }
                local line = (sel or key == todayKey) and { C.accent[1], C.accent[2], C.accent[3], 0.9 } or (best and { C.mint[1], C.mint[2], C.mint[3], 0.6 }) or { 1, 1, 1, 0.08 }
                ns.Insta.Glass(c, fill, line, 6)
                local tc = sel and C.text or ((c.past or not inMonth) and C.dim or C.text)
                c.num:SetTextColor(tc[1], tc[2], tc[3])
            elseif sel then
                c.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
                c.num:SetTextColor(1, 1, 1)
            else
                c.bg:SetColorTexture(1, 1, 1, inMonth and 0.035 or 0.01)
                local tc = (c.past or not inMonth) and C.dim or C.text
                c.num:SetTextColor(tc[1], tc[2], tc[3])
            end
            c:SetAlpha(c.past and 0.35 or (inMonth and 1 or 0.6))
            c.dot:SetColorTexture(sel and 1 or kc[1], sel and 1 or kc[2], sel and 1 or kc[3], 1)
            c.dot:SetShown(evDays[key] and true or false)
        end
        -- Zusammenfassung + Knopf
        if not rankAllowed(ns.GuildOpt("rdEvRank")) then
            f.summary:SetText("|cffff5a4a" .. L["Termine anlegen darf bei euch nur die Gildenleitung bzw. hoehere Raenge."] .. "|r")
        elseif not ts then
            f.summary:SetText("")
        elseif ts <= ns.now() then
            f.summary:SetText("|cffff5a4a" .. L["Der Termin liegt in der Vergangenheit."] .. "|r")
        else
            local same = {}
            for _, e in ipairs(upcoming()) do
                if date("%Y%m%d", e.ts) == date("%Y%m%d", ts) then same[#same + 1] = (e.title or "?") .. " " .. date("%H:%M", e.ts) end
            end
            f.summary:SetText((st.weeks > 1 and ("|cff888888" .. (L["%d Termine, jede Woche zur gleichen Zeit"]):format(st.weeks) .. "|r") or "")
                .. (#same > 0 and ("\n|cffe8b44a" .. L["Am selben Tag schon: "] .. table.concat(same, ", ") .. "|r") or ""))
        end
        f.create:SetAlpha((ts and ts > ns.now()) and 1 or 0.45)
        -- Zusammenfassung rechts
        local sc2 = f.sumCard
        if sc2 then
            local kk = Raid.KIND[st.kind] or Raid.KIND.raid
            local kc2 = kk.color
            sc2.disc.bg:SetVertexColor(kc2[1] * 0.25, kc2[2] * 0.25, kc2[3] * 0.25, 1)
            sc2.disc.g:SetTexture(ns.ICONS and ns.ICONS[kk.icon] or nil)
            sc2.disc.g:SetVertexColor(kc2[1], kc2[2], kc2[3])
            sc2.title:SetText(ev.title or "?")
            sc2.inst:SetText(trim(st.inst) ~= "" and trim(st.inst) or ("|cff666666" .. L["kein Ziel gewaehlt"] .. "|r"))
            if ts then
                sc2.date:SetText(ns.weekday(ts) .. ", " .. date("%d.%m.", ts))
                sc2.time:SetText(date("%H:%M", ts) .. " " .. L["Uhr"] .. "  ·  " .. countdown(ts))
            else
                sc2.date:SetText("|cff666666" .. L["Tag waehlen"] .. "|r")
                sc2.time:SetText((st.time or "") .. " " .. L["Uhr"])
            end
            sc2.facts:SetText((L["%d Spieler"]):format(st.max) .. "  ·  " .. (st.weeks > 1 and (L["%d Wochen"]):format(st.weeks) or L["einmalig"]))
            if sc2.rows then
                sc2.rows[1]:SetText(ts and (ns.weekday(ts) .. ", " .. date("%d.", ts) .. " " .. L[MONTHS[tonumber(date("%m", ts))]] .. " " .. date("%Y", ts)) or ("|cff888888" .. L["Tag waehlen"] .. "|r"))
                sc2.rows[2]:SetText((ts and date("%H:%M", ts) or (st.time or "")) .. " " .. L["Uhr"])
                sc2.rows[3]:SetText((L["%d Spieler"]):format(st.max))
                sc2.rows[4]:SetText(st.weeks > 1 and (L["Alle %d Wochen"]):format(st.weeks) or L["Einmalig"])
            end
            sc2.pv.t:SetText((f.showPv and L["Vorschau ausblenden"] or L["Vorschau fuer die Mitglieder ansehen"]) .. "  >")
            sc2.facts:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
            if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(sc2, { 1, 1, 1, 0.035 }, (ts and ts > ns.now()) and { kc2[1], kc2[2], kc2[3], 0.45 } or { 1, 1, 1, 0.10 }, 14) end
        end
        -- Vorschau
        if not ev.ts then ev.ts = ns.now() + DAY end
        updateCard(f.preview, ev)
        f.preview.item = ev
    end
    f.fillQuick()
    layout()
    f.update()
end

local function refreshForm(f)
    if Raid.prefill then
        local pf = Raid.prefill
        f.st.title, f.st.inst = pf.title or "", pf.inst or ""
        f.titleBox:SetText(f.st.title)
        f.instBox:SetText(f.st.inst)
        if pf.kind and Raid.KIND[pf.kind] then f.st.kind = pf.kind
        elseif f.st.inst ~= "" and f.st.kind ~= "raid" then f.st.kind = "dungeon" end
        if pf.max then f.st.max = pf.max elseif f.st.kind == "dungeon" then f.st.max = 5 end
        -- Wochentag-Vorschlag (Raid-Interesse): naechster passender Tag ab morgen
        if pf.wd then
            local base = date("*t", ns.now())
            for k = 1, 7 do
                local ts = time({ year = base.year, month = base.month, day = base.day + k, hour = 12 })
                if (tonumber(date("%w", ts)) + 6) % 7 + 1 == pf.wd then
                    local t = date("*t", ts)
                    f.st.sel, f.st.y, f.st.m = ts, t.year, t.month
                    break
                end
            end
        end
        Raid.prefill = nil
        prefillAt = GetTime()
    end
    f.calToggle:SetShown(Raid.CanCalendar())
    local had = f.qs:IsShown()
    f.fillQuick()
    if had ~= f.qs:IsShown() and f.layout then f.layout() end
    local evs = upcoming()
    f.listHead:SetCount(#evs > 0 and #evs or nil)
    f.list:SetData(evs)
    if f.layout then f.layout() end
    f.update()
    if f.animNext then
        f.animNext = false
        K.FadeIn(f.pvHost, 0)
        K.FadeIn(f.lc, 0.06)
        K.FadeIn(f.rc, 0.12)
        for i, row in ipairs(f.list.rows) do
            if row:IsShown() then K.FadeIn(row, 0.18 + (i - 1) * 0.05) end
        end
    end
end

------------------------------------------------------------------------
-- Beute-Ansichten (Meine Beute, Beute-Log, Verteilung, Punkte): gemeinsame Helfer
-- Aufbau je Ansicht in f:Layout(W) mit fester Rechnung; Rechtecke landen in f.rects (Ueberlappungs-Test)
------------------------------------------------------------------------
local LOOT_CH = { ms = "need", os = "greed", tm = "mog" }   -- Beute-Verlauf des LootMasters -> CHOICES hier
local function lootChoice(x)
    local c = x and x.choice
    if not c then return nil end
    if CHOICES[c] then return c end
    return LOOT_CH[c]
end
local function itemButton(parent, size)
    if ns.LootMaster and ns.LootMaster.ItemButton then return ns.LootMaster.ItemButton(parent, size) end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    function b:SetItem(link) self.link = link self.icon:SetTexture(C_Item.GetItemIconByID(ns.itemID(link) or 0) or 134400) end
    b:SetScript("OnEnter", function(self) K.ItemTip(self, self.link) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end
local function qualityColor(link, q)
    local LM = ns.LootMaster
    if LM and LM.QColor and LM.Quality then return LM.QColor(LM.Quality(link, q)) end
    return C.text
end
local function put(rects, grp, key, o, x, y, w, h)
    o:ClearAllPoints()
    o:SetPoint("TOPLEFT", x, -y)
    if w then o:SetWidth(w) end
    if h then o:SetHeight(h) end
    if rects then rects[#rects + 1] = { grp = grp, key = key, x = x, y = y, w = w or 0, h = h or 0 } end
end
Raid.Put = put
local function newPill(parent, size)
    if ns.LootMaster and ns.LootMaster.Pill then return ns.LootMaster.Pill(parent, size) end
    return K.Badge(parent, 18)   -- gleiche Schnittstelle :Set(text, farbe)
end
-- Scrollflaeche: Mausrad, schmale Leiste rechts; sc:Sync(h) setzt die Inhaltshoehe
local function scrollArea(parent)
    local sc = CreateFrame("ScrollFrame", nil, parent)
    local body = CreateFrame("Frame", nil, sc)
    body:SetSize(600, 400)
    sc:SetScrollChild(body)
    sc.body = body
    local thumb = parent:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    thumb:SetWidth(3)
    thumb:Hide()
    sc.thumb = thumb
    function sc:UpdateThumb()
        local vh, ch = self:GetHeight() or 0, body:GetHeight() or 0
        if ch <= vh + 1 or vh <= 0 then thumb:Hide() return end
        local max = ch - vh
        local th = math.max(20, vh * vh / ch)
        thumb:SetHeight(th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -((vh - th) * math.min(1, (self:GetVerticalScroll() or 0) / max)))
        thumb:Show()
    end
    function sc:Sync(h)
        body:SetHeight(math.max(1, h))
        local max = math.max(0, h - (self:GetHeight() or 0))
        if (self:GetVerticalScroll() or 0) > max then self:SetVerticalScroll(max) end
        self:UpdateThumb()
    end
    -- nutzbare Breite (Platz fuer die Leiste)
    function sc:InnerWidth() return math.max(200, (self:GetWidth() or 0) - 10) end
    sc:EnableMouseWheel(true)
    sc:SetScript("OnMouseWheel", function(self, d)
        local max = math.max(0, (body:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - d * 40)))
        self:UpdateThumb()
    end)
    return sc, body
end
-- Item-Zeile (Meine Beute / Beute-Log): Symbol mit Qualitaetsrahmen, Name, Unterzeile, rechts Wahl/Wert/Zeit
local ROW_H = 46
local function lootRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0)
    r.card = CreateFrame("Frame", nil, r)
    r.card:SetAllPoints()
    r.card:SetFrameLevel(r:GetFrameLevel())
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(r.card, { 1, 1, 1, 0.02 }, { 1, 1, 1, 0.06 }, 10) end
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.04)
    r.edge = r:CreateTexture(nil, "ARTWORK")
    r.edge:SetPoint("TOPLEFT") r.edge:SetPoint("BOTTOMLEFT") r.edge:SetWidth(2)
    r.edge:Hide()
    r.icon = itemButton(r, 36)
    r.name = K.Text(r, 13, C.text)
    r.name:SetWordWrap(false)
    r.sub = K.Text(r, 10, C.muted)
    r.sub:SetWordWrap(false)
    r.pill = newPill(r, 10)
    r.val = K.Text(r, 11, C.muted, "RIGHT")
    r.val:SetWordWrap(false)
    r.when = K.Text(r, 10, C.dim, "RIGHT")
    r.when:SetWordWrap(false)
    r:SetScript("OnEnter", function(self) if self.link then K.ItemTip(self, self.link) end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link) end
    end)
    -- Spalten nach Breite: schmal -> Wahl/Wert wandern in die Unterzeile
    function r:Layout(W, rects)
        self.wide = W >= 480
        put(rects, "row", "icon", self.icon, 8, 5, 36, 36)
        local rw = 74
        put(rects, "row", "when", self.when, W - rw - 8, 9, rw, 12)
        local x2 = W - rw - 14
        if self.wide then
            put(rects, "row", "val", self.val, x2 - 90, 25, 90, 14)
            put(rects, "row", "pill", self.pill, x2 - 82, 6, 82, 16)
            x2 = x2 - 98
        end
        local tw = math.max(40, x2 - 54)
        put(rects, "row", "name", self.name, 54, 7, tw, 16)
        put(rects, "row", "sub", self.sub, 54, 26, tw, 13)
        self.pill:SetShown(self.wide and self.hasPill or false)
        self.val:SetShown(self.wide)
    end
    -- x = Beute-Eintrag; who = Namen zeigen; cost = Punktekosten
    function r:Set(x, who, cost)
        self.link = x.item
        self.icon:SetItem(x.item, x.quality)
        local qc = qualityColor(x.item, x.quality)
        self.edge:SetColorTexture(qc[1], qc[2], qc[3], 0.9)
        do
            local raw = tostring(x.item or "")
            local id = ns.itemID(x.item)
            if raw:find("|H", 1, true) and raw:find("|h", 1, true) then
                self.name:SetText(ns.fixColors(raw))
            else
                -- kaputter Link: nur den Namen in Klammern zeigen (oder die Nummer), bis das Spiel den echten Link liefert
                local nm = raw:match("%[(.-)%]")
                self.name:SetText((nm and nm ~= "" and not nm:match("^#%d+$")) and nm or (id and ("#" .. id)) or "?")
            end
            if id then
                ns.withItem(id, function(full)
                    if full and self.link == x.item then self.name:SetText(ns.fixColors(full)) end
                end)
            end
        end
        local ch = lootChoice(x)
        local c = ch and CHOICES[ch]
        local val
        if x.gold then val = "|cffe8b44a" .. x.gold .. " g|r"
        elseif cost and cost > 0 then val = "|cffe06060-" .. math.floor(cost + 0.5) .. " " .. L["Beute"] .. "|r"
        elseif x.roll then val = "|cff888888" .. L["Wurf"] .. "|r " .. x.roll end
        local sub = {}
        if who then sub[#sub + 1] = ns.Radar.Colored(x.who) end
        local zone = ns.zoneName(x.mapID, x.zone)
        if zone and zone ~= "" then sub[#sub + 1] = zone end
        if x.src == "Vergabe" then sub[#sub + 1] = "|cffff6040" .. L["Vergabe"] .. "|r" end
        self.hasPill = c ~= nil
        if c then self.pill:Set(c[1], c[2]) end
        if not self.wide then
            if c then sub[#sub + 1] = K.hex(c[2]) .. c[1] .. "|r" end
            if val then sub[#sub + 1] = val end
        end
        self.sub:SetText(table.concat(sub, "  ·  "))
        self.val:SetText(val or "")
        self.when:SetText(ns.ago(x.ts or x.u))
        self.pill:SetShown(self.wide and c ~= nil)
    end
    return r
end
-- Leerer Zustand: Karte mit Symbol, Titel, Text
local function emptyCard(parent, icon, color)
    -- Leerzustand wie in der Handwerks-Boerse: Leuchtscheibe mit Symbol, ruhiger Verlauf, Text daneben
    local e = CreateFrame("Frame", nil, parent)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(e, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.10 }, 12) end
    e.glow = e:CreateTexture(nil, "BORDER")
    e.glow:Hide()
    e.edge = e:CreateTexture(nil, "ARTWORK")
    e.edge:Hide()
    e.disc = famDisc(e, 44, icon, color)
    e.disc.halo:Hide()
    e.disc:SetPoint("LEFT", 20, 0)
    e.icon = e.disc.icon
    e.title = K.Title(e, 14, C.text)
    e.title:SetPoint("TOPLEFT", 82, -16)
    e.title:SetPoint("RIGHT", -14, 0)
    e.title:SetWordWrap(false)
    e.text = K.Text(e, 11, C.muted)
    e.text:SetPoint("TOPLEFT", 82, -36)
    e.text:SetPoint("RIGHT", -14, 0)
    e.text:SetWordWrap(true)
    e.text:SetJustifyV("TOP")
    return e
end
-- Datumskopf im Verlauf
local function dayLabel(ts)
    ts = ts or 0
    local d = date("%Y%m%d", ts)
    if d == date("%Y%m%d", ns.now()) then return L["Heute"] end
    if d == date("%Y%m%d", ns.now() - 86400) then return L["Gestern"] end
    local wd = ({ "So", "Mo", "Di", "Mi", "Do", "Fr", "Sa" })[tonumber(date("%w", ts)) + 1]
    return L[wd] .. " " .. date("%d.%m.", ts)
end
local MAX_ROWS = 120

------------------------------------------------------------------------
-- Raidleitung > Verteilung (einzelnes Item, alter Weg ohne Beutefenster)
------------------------------------------------------------------------
local function buildLoot(f)
    local sc, body = scrollArea(f)
    sc:SetPoint("TOPLEFT") sc:SetPoint("BOTTOMRIGHT")
    f.sc, f.body = sc, body
    -- Start-Karte
    local st = CreateFrame("Frame", nil, body)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(st, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.10 }, 14) end
    f.startCard = st
    st.title = K.Title(st, 16, C.text)
    st.title:SetText(L["Item waehlen"])
    st.title:SetWordWrap(false)
    st.sub = K.Text(st, 10, C.muted)
    st.sub:SetText(L["Frisch gelootet anklicken oder ein Item per Shift-Klick einfuegen."])
    st.sub:SetWordWrap(false)
    local input = K.Input(st, 390, L["Item mit Shift-Klick hier einfuegen ..."])
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(input, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.10 }, 8) end
    f.input = input
    -- Schnellwahl: was in der letzten Stunde in der Gruppe gelootet wurde (ab Selten) - ein Klick startet
    f.fresh = CreateFrame("Frame", nil, st)
    f.fresh:SetHeight(28)
    f.fresh.lbl = K.Text(f.fresh, 11, C.muted)
    f.fresh.lbl:SetPoint("LEFT", 0, 0)
    f.fresh.lbl:SetText(L["Frisch gelootet:"])
    f.fresh.icons = {}
    function f.FillFresh()
        local cut = ns.now() - 3600
        local list = Store.List("loot", function(x) return (x.ts or x.u or 0) > cut and x.item end)
        table.sort(list, function(a, b) return (a.ts or a.u or 0) > (b.ts or b.u or 0) end)
        local seen, n = {}, 0
        local x0 = (f.fresh.lbl:GetStringWidth() or 80) + 10
        for _, b in ipairs(f.fresh.icons) do b:Hide() end
        for _, it in ipairs(list) do
            local id = ns.itemID(it.item)
            local q = it.quality or (ns.LootMaster and ns.LootMaster.Quality and ns.LootMaster.Quality(it.item)) or 3
            if id and not seen[id] and (tonumber(q) or 3) >= 3 and n < 10 then
                seen[id] = true
                n = n + 1
                local b = f.fresh.icons[n]
                if not b then
                    b = itemButton(f.fresh, 24)
                    b:HookScript("OnEnter", function(self) if self.link then K.ItemTip(self, self.link) GameTooltip:AddLine("|cff888888" .. L["Klick: Verteilung dafuer starten"] .. "|r") GameTooltip:Show() end end)
                    b:HookScript("OnLeave", function() GameTooltip:Hide() end)
                    b:SetScript("OnClick", function(self) if self.link then Raid.StartSession(self.link) end end)
                    f.fresh.icons[n] = b
                end
                b:ClearAllPoints()
                b:SetPoint("LEFT", x0 + (n - 1) * 28, 0)
                b:SetItem(it.item, it.quality)
                b.link = it.item
                b:Show()
            end
        end
        f.fresh.n = n
        f.fresh:SetShown(n > 0)
    end
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if input:HasFocus() and link then input:SetText(link) end
    end)
    f.start = K.Button(st, L["Starten"], 120, 26, "primary", function()
        Raid.StartSession(input:GetText())
        input:SetText("")
        input:ClearFocus()
    end)
    input.onEnter = function(t) if t ~= "" then f.start:Click() end end
    f.ann = K.Toggle(st, L["Ergebnis im Gruppenchat ansagen"], function() return Raid.announce end, function(v) Raid.announce = v end)
    f.lmBtn = K.Button(st, L["Beute-Fenster (ganze Leiche)"] .. "  >", 210, 24, "ghost", function()
        if ns.LootMaster and ns.LootMaster.ShowMaster then ns.LootMaster.ShowMaster() end
    end)
    f.lmBtn:HookScript("OnEnter", function(self)
        K.ShowTip(self, { L["Beute-Fenster (ganze Leiche)"], L["Alle Items einer Leiche auf einmal verteilen - mit Wuerfeln, Punkten, Beuterat oder GDKP."] })
    end)
    f.lmBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- laufende Verteilung: Item gross, Kennzahlen je Wahl
    local card = CreateFrame("Frame", nil, body)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(card, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.10 }, 14) end
    card.edge = card:CreateTexture(nil, "ARTWORK")
    card.edge:Hide()
    card.glow = card:CreateTexture(nil, "BORDER")
    card.glow:Hide()
    f.card = card
    f.sIcon = itemButton(card, 52)
    f.sName = K.Text(card, 15, C.text)
    f.sName:SetWordWrap(false)
    f.sMeta = K.Text(card, 11, C.muted)
    f.sMeta:SetWordWrap(false)
    f.sUp = K.Text(card, 11, C.muted)
    f.sUp:SetWordWrap(false)
    f.counts = {}
    for i, key in ipairs({ "need", "greed", "mog", "pass" }) do
        local ch = CHOICES[key]
        local c = CreateFrame("Frame", nil, card)
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(c, { ch[2][1], ch[2][2], ch[2][3], 0.08 }, { ch[2][1], ch[2][2], ch[2][3], 0.35 }, 8) end
        c.n = K.Title(c, 17, ch[2])
        c.n:SetPoint("LEFT", 8, 0)
        c.t = K.Text(c, 10, C.muted)
        c.t:SetPoint("LEFT", c.n, "RIGHT", 6, 0)
        c.t:SetText(ch[1])
        c.key = key
        f.counts[i] = c
    end
    f.head = K.GameHead(body, L["Antworten"], C.accent)
    -- Antwort-Zeilen (Rangfolge)
    f.rows = {}
    f.empty = emptyCard(body, ns.MEDIA .. "icons\\raid", C.accent)
    f.empty.title:SetText(L["Keine laufende Verteilung"])
    f.empty.text:SetText(L["1. Item links waehlen (frisch gelootet oder Shift-Klick)\n2. Starten - alle mit Oasis bekommen ein Wahlfenster\n3. Antworten erscheinen hier, Vergeben mit einem Klick"])
    -- Kompatibilitaet: f.list.empty wie frueher
    f.list = { empty = f.empty.text, SetData = function() end }
    sc:SetScript("OnSizeChanged", function() if f.Layout then f:Layout() end end)
end

local function lootCandRow(f, i)
    local r = CreateFrame("Frame", nil, f.body)
    r:SetHeight(40)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(r, { 1, 1, 1, 0.02 }, { 1, 1, 1, 0.06 }, 10) end
    r.sel = r:CreateTexture(nil, "ARTWORK")
    r.sel:SetPoint("TOPLEFT", 6, -8) r.sel:SetPoint("BOTTOMLEFT", 6, 8) r.sel:SetWidth(2)
    r.sel:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.9)
    r.glow = r:CreateTexture(nil, "BORDER")
    r.glow:SetAllPoints()
    r.glow:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.05)
    r.pos = K.Title(r, 16, C.text, "CENTER")
    r.name = K.Text(r, 13, C.text)
    r.name:SetWordWrap(false)
    r.nsub = K.Text(r, 10, C.dim)
    r.nsub:SetWordWrap(false)
    r.badge = newPill(r, 11)
    r.eq = {}
    for k = 1, 2 do
        local ic = itemButton(r, 24)
        r.eq[k] = ic
    end
    r.pr = K.Text(r, 12, C.text)
    r.pr:SetWordWrap(false)
    r.award = K.Button(r, L["Vergeben"], 88, 24, "ghost")
    r.cols = { name = r.name, ilvl = r.nsub, pr = r.pr }
    f.rows[i] = r
    return r
end

local function layoutLoot(f)
    local W = f.sc:InnerWidth()
    local R = {}
    f.rects = R
    -- breit: links 1 Item waehlen + Antworten, rechts die laufende Verteilung (bzw. So geht's)
    local two = W >= 640
    local RW = two and math.max(250, math.floor(W * 0.36)) or W
    local LW = two and (W - RW - 16) or W
    local st = f.startCard
    local y = 0
    -- Start-Karte (links)
    put(R, "st", "title", st.title, 16, 14, LW - 32, 18)
    put(R, "st", "sub", st.sub, 16, 36, LW - 32, 14)
    put(R, "st", "input", f.input, 16, 60, LW - 32 - 128, 26)
    put(R, "st", "start", f.start, LW - 16 - 120, 60, 120, 26)
    local sy = 96
    if f.fresh and f.fresh:IsShown() then put(R, "st", "fresh", f.fresh, 16, sy, LW - 32, 28) sy = sy + 34 end
    put(R, "st", "lm", f.lmBtn, 16, sy, math.min(230, LW - 32), 22)
    sy = sy + 30
    put(R, "st", "ann", f.ann, 16, sy, LW - 32, 24)
    sy = sy + 34
    put(R, "body", "start", st, 0, y, LW, sy)
    y = y + sy + 14
    local s = Raid.session
    f.card:SetShown(s ~= nil)
    f.head:SetShown(s ~= nil)
    f.empty:SetShown(s == nil)
    local rx, ry = two and (LW + 16) or 0, two and 0 or y
    if not s then
        put(R, "body", "empty", f.empty, rx, ry, RW, two and 170 or 130)
        if not two then y = y + 106 end
        for _, r in ipairs(f.rows) do r:Hide() end
        f.sc:Sync(math.max(y, two and 150 or 0) + 8)
        return
    end
    -- laufende Verteilung (rechts)
    put(R, "card", "icon", f.sIcon, 16, 16, 52, 52)
    put(R, "card", "name", f.sName, 80, 18, RW - 96, 18)
    put(R, "card", "meta", f.sMeta, 80, 40, RW - 96, 14)
    put(R, "card", "up", f.sUp, 16, 80, RW - 32, 14)
    local cw = math.floor((RW - 32 - 6) / 2)
    for i, c in ipairs(f.counts) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        put(R, "card", "cnt" .. i, c, 16 + col * (cw + 6), 104 + row * 34, cw, 28)
    end
    put(R, "body", "card", f.card, rx, ry, RW, 182)
    if not two then y = y + 192 end
    -- Antworten (links unter der Start-Karte)
    put(R, "body", "head", f.head, 0, y, LW, 18)
    y = y + 26
    local showGear = LW >= 560
    local showInfo = LW >= 420
    for i, r in ipairs(f.rows) do
        if r:IsShown() then
            local RR = (i == 1) and R or nil
            put(RR, "row", "pos", r.pos, 4, 10, 28, 20)
            local nw = showInfo and 140 or math.max(40, LW - 230)
            put(RR, "row", "name", r.name, 38, 5, nw, 16)
            put(RR, "row", "nsub", r.nsub, 38, 22, nw, 13)
            local x = 38 + nw + 8
            put(RR, "row", "badge", r.badge, x, 11, 76, 18)
            x = x + 84
            for k, ic in ipairs(r.eq) do
                ic:SetShown(showGear and ic.link ~= nil)
                if showGear then put(RR, "row", "eq" .. k, ic, x + (k - 1) * 28, 8, 24, 24) end
            end
            if showGear then x = x + 60 end
            r.pr:SetShown(showInfo)
            if showInfo then put(RR, "row", "pr", r.pr, x, 13, math.max(20, LW - x - 104), 14) end
            put(RR, "row", "award", r.award, LW - 96, 8, 88, 24)
            put(R, "body", "r" .. i, r, 0, y, LW, 40)
            y = y + 44
        end
    end
    f.sc:Sync(math.max(y, two and 192 or 0) + 8)
end

local function refreshLoot(f)
    local s = Raid.session
    f.Layout = layoutLoot
    if f.FillFresh then pcall(f.FillFresh) end
    for _, r in ipairs(f.rows) do r:Hide() end
    if not s then
        layoutLoot(f)
        return
    end
    f.sName:SetText(s.link)
    f.sIcon:SetItem(s.link)
    local qc = qualityColor(s.link)
    f.card.edge:SetColorTexture(qc[1], qc[2], qc[3], 1)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(f.card, { 1, 1, 1, 0.03 }, { qc[1], qc[2], qc[3], 0.45 }, 14) end
    local n = 0
    local rows = {}
    -- Soft-Reserve fuer dieses Item (anstehende Termine)
    local srSet = {}
    if ns.SoftRes and ns.SoftRes.ForItem then
        for _, w in ipairs(ns.SoftRes and ns.SoftRes.ForItem(ns.itemID(s.link) or 0) or {}) do srSet[w] = true end
    end
    local function hasSR(name)
        local m = ns.Alts and ns.Alts.Main(name) or name
        return srSet[m] or srSet[name] or false
    end
    for name, r in pairs(s.responses) do
        n = n + 1
        rows[#rows + 1] = { name = name, choice = r.choice, e1 = r.e1, e2 = r.e2, pr = ns.Points and ns.Points.Of(name).pr or 0,
            roll = r.roll, sr = r.choice ~= "pass" and hasSR(name) }
    end
    -- Reihenfolge: Wahl (Bedarf vor Zweitspec ...), dann Soft-Reserve, dann Prioritaet, dann Wurf
    table.sort(rows, function(a, b)
        local ca, cb = (CHOICES[a.choice] or CHOICES.pass)[3], (CHOICES[b.choice] or CHOICES.pass)[3]
        if ca ~= cb then return ca < cb end
        if a.sr ~= b.sr then return a.sr end
        if a.pr ~= b.pr then return a.pr > b.pr end
        if (a.roll or 0) ~= (b.roll or 0) then return (a.roll or 0) > (b.roll or 0) end
        return a.name < b.name
    end)
    -- Vorschlag: hoechste Prioritaet in der besten gewaehlten Stufe (nicht Passen)
    if rows[1] and rows[1].choice ~= "pass" and not s.awarded then rows[1].suggest = true end
    local status = s.awarded and (L["|cff4df2b8Vergeben an "] .. ns.displayName(s.awarded) .. "|r") or L["laeuft"]
    local worth = ns.Market and ns.Market.Text(ns.itemID(s.link) or 0)
    f.sMeta:SetText((L["Leitung: %s  -  %d Antworten  -  %s"]):format(ns.displayName(s.leader), n, status)
        .. (worth and ("  -  |cffe8b44a" .. L["Marktwert "] .. worth .. "|r") or ""))
    local up
    if ns.Upgrade and ns.Upgrade.Text then local ok, t = pcall(ns.Upgrade.Text, s.link) if ok then up = t end end
    f.sUp:SetText(up and (L["Fuer dich"] .. ": " .. up) or ("|cff666666" .. L["Fuer dich: kein Vergleich"] .. "|r"))
    local cnt = { need = 0, greed = 0, mog = 0, pass = 0 }
    for _, x in ipairs(rows) do cnt[x.choice] = (cnt[x.choice] or 0) + 1 end
    for _, c in ipairs(f.counts) do c.n:SetText(cnt[c.key] or 0) end
    f.head:SetCount(n > 0 and n or nil)
    local PC = { { 1, 0.82, 0.3 }, { 0.8, 0.82, 0.86 }, { 0.85, 0.55, 0.3 } }
    local mine = s and ns.isMe(s.leader) and not s.awarded
    for i, x in ipairs(rows) do
        local r = f.rows[i] or lootCandRow(f, i)
        r.item = x
        local pos = x.choice ~= "pass" and i or nil
        r.pos:SetText(pos and tostring(pos) or "-")
        local pc = pos and PC[pos] or C.dim
        r.pos:SetTextColor(pc[1], pc[2], pc[3])
        r.name:SetText(ns.Radar.Colored(x.name) .. (x.suggest and ("  |cff66db9e" .. L["Vorschlag"] .. "|r") or ""))
        local p = ns.db.members[x.name]
        r.nsub:SetText(p and (p.ilvl or 0) > 0 and (L["iLvl "] .. p.ilvl) or "")
        local ch = CHOICES[x.choice] or CHOICES.pass
        r.badge:Set(ch[1], ch[2])
        for k, key in ipairs({ "e1", "e2" }) do
            local l = x[key]
            local ic = r.eq[k]
            if l and l ~= "" then ic:SetItem(l) else ic.link = nil end
        end
        if x.choice ~= "pass" then
            local parts = {}
            if x.sr then parts[#parts + 1] = "|cffe8b44a" .. L["SR"] .. "|r" end
            if ns.Points then
                local cost = ns.Points.ItemCost(s and s.link, x.choice)
                parts[#parts + 1] = L["Prio "] .. ns.Points.FmtPR(x.pr) .. (cost > 0 and ("  |cff888888-" .. cost .. "|r") or "")
            end
            if x.roll then parts[#parts + 1] = "|cff888888" .. L["Wurf"] .. "|r " .. x.roll end
            r.pr:SetText(table.concat(parts, "  ·  "))
        else
            r.pr:SetText("")
        end
        r.sel:SetShown(x.suggest and true or false)
        r.glow:SetShown(x.suggest and true or false)
        r.award:SetShown(mine and true or false)
        r.award:SetScript("OnClick", function() Raid.Award(x.name) end)
        r:Show()
    end
    layoutLoot(f)
end

------------------------------------------------------------------------
-- Reiter "Beute-Log": Verlauf (nach Tagen) / nur Vergaben / Statistik
------------------------------------------------------------------------
local logView = "all"
local function buildLog(f)
    f.seg = K.Segments(f, { { key = "all", text = L["Verlauf"] }, { key = "award", text = L["Vergaben"] }, { key = "stats", text = L["Statistik"] } }, function(k)
        logView = k
        f.animNext = true
        ns.RefreshPage("raid") ns.RefreshPage("loot")
    end, 90, { size = 12, pad = 18 })
    f.search = K.Input(f, 260, L["Suchen: Item, Name, Gebiet ..."], function(t) lootSearch = t ns.RefreshPage("raid") ns.RefreshPage("loot") end)
    f.count = K.Text(f, 10, C.dim, "RIGHT")
    f.count:SetWordWrap(false)
    local sc, body = scrollArea(f)
    f.sc, f.body = sc, body
    f.rows, f.days = {}, {}
    f.more = K.Text(body, 11, C.dim, "CENTER")
    f.empty = emptyCard(body, ns.MEDIA .. "icons\\wants", C.amber)
    f.empty.title:SetText(L["Noch keine Beute erfasst"])
    -- Statistik
    f.tiles = {}
    for i, d in ipairs({ { "n", "Items", C.accent, "wants" }, { "d30", "Letzte 30 Tage", C.mint, "raid" },
        { "who", "Empfaenger", C.blue, "social" }, { "epic", "Episch", C.amber, "badges" } }) do
        local t = famTile(body, ns.MEDIA .. "icons\\" .. d[4], L[d[2]], d[3])
        t.key = d[1]
        f.tiles[i] = t
        f.tiles[d[1]] = t
    end
    f.sHead = K.GameHead(body, L["Wer hat was bekommen"], C.amber)
    f.legend = K.Text(body, 10, C.muted, "RIGHT")
    f.legend:SetWordWrap(false)
    f.legend:SetText(K.hex(CHOICES.need[2]) .. L["Bedarf"] .. "|r   " .. K.hex(CHOICES.greed[2]) .. L["Zweitspec"] .. "|r   "
        .. K.hex(CHOICES.mog[2]) .. L["Transmog"] .. "|r   |cff8888aa" .. L["Eigene Beute"] .. "|r")
    f.sRows = {}
    f.animNext = true
    f:HookScript("OnShow", function() f.animNext = true end)
    -- Kompatibilitaet
    f.list = { empty = f.empty.text, SetData = function() end }
    sc:SetScript("OnSizeChanged", function() if f.Layout then f:Layout() end end)
end

local STAT_COL = { ms = CHOICES.need[2], os = CHOICES.greed[2], tm = CHOICES.mog[2], own = { 0.53, 0.53, 0.67 } }
local function statRow(f, i)
    local r = CreateFrame("Button", nil, f.body)
    r:SetHeight(34)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, 0.025)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)
    r.pos = K.Title(r, 13, C.muted, "CENTER")
    r.name = K.Text(r, 12, C.text)
    r.name:SetWordWrap(false)
    r.track = r:CreateTexture(nil, "BORDER")
    r.track:SetColorTexture(1, 1, 1, 0.06)
    r.segs = {}
    for k, key in ipairs({ "ms", "os", "tm", "own" }) do
        local t = r:CreateTexture(nil, "ARTWORK")
        local c = STAT_COL[key]
        t:SetColorTexture(c[1], c[2], c[3], 0.9)
        t.key = key
        r.segs[k] = t
    end
    r.num = K.Text(r, 11, C.muted, "RIGHT")
    r.num:SetWordWrap(false)
    r.last = itemButton(r, 24)
    r:SetScript("OnEnter", function(self)
        if not self.e then return end
        local lines = { ns.Radar.Colored(self.e.name) }
        if ns.LootMaster and ns.LootMaster.StatsTip then ns.LootMaster.StatsTip(lines, self.e.name)
        else lines[#lines + 1] = (L["%d Items"]):format(self.e.total) end
        K.ShowTip(self, lines)
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.sRows[i] = r
    return r
end

local function layoutLog(f)
    local W0 = f:GetWidth() or 600
    local R = {}
    f.rects = R
    -- Kopf: Reiter + Suche (+ Zaehler); schmal: Suche in eigener Zeile
    local segW = f.seg:GetWidth() or 280
    local top
    put(R, "top", "seg", f.seg, 0, 0, segW, 24)
    if W0 >= segW + 12 + 200 then
        local sw = math.min(260, W0 - segW - 12)
        put(R, "top", "search", f.search, W0 - sw, 0, sw, 24)
        f.count:Hide()
        top = 34
    else
        put(R, "top", "search", f.search, 0, 30, W0, 24)
        f.count:Hide()
        top = 62
    end
    f.sc:ClearAllPoints()
    f.sc:SetPoint("TOPLEFT", 0, -top)
    f.sc:SetPoint("BOTTOMRIGHT")
    local W = f.sc:InnerWidth()
    local y = 0
    local stats = logView == "stats"
    for _, t in ipairs(f.tiles) do t:SetShown(stats) end
    f.sHead:SetShown(stats) f.legend:SetShown(stats)
    if stats then
        for _, r in ipairs(f.rows) do r:Hide() end
        for _, d in ipairs(f.days) do d:Hide() end
        f.more:Hide()
        local cols = W >= 560 and 4 or 2
        local tw = math.floor((W - (cols - 1) * 8) / cols)
        for i, t in ipairs(f.tiles) do
            local c, rr = (i - 1) % cols, math.floor((i - 1) / cols)
            put(R, "body", "tile" .. i, t, c * (tw + 8), y + rr * 74, tw, 66)
        end
        y = y + math.ceil(#f.tiles / cols) * 74 + 6
        local lw = W >= 520 and 300 or 0
        f.legend:SetShown(lw > 0)
        put(R, "body", "shead", f.sHead, 0, y, W - lw - 8, 18)
        if lw > 0 then put(R, "body", "legend", f.legend, W - lw, y + 2, lw, 14) end
        y = y + 26
        local nameW = W >= 520 and 150 or 110
        local numW, lastW = 70, 30
        local barX = 36 + nameW + 8
        local barW = math.max(30, W - barX - numW - lastW - 20)
        for i, r in ipairs(f.sRows) do
            if r:IsShown() and r.e then
                local RR = (i == 1) and R or nil
                put(RR, "srow", "pos", r.pos, 2, 9, 30, 16)
                put(RR, "srow", "name", r.name, 36, 10, nameW, 14)
                put(RR, "srow", "track", r.track, barX, 13, barW, 8)
                local x = barX
                local tot = math.max(1, f.statMax or 1)
                for _, sg in ipairs(r.segs) do
                    local n = r.e[sg.key] or 0
                    local w = math.floor(barW * n / tot + 0.5)
                    if n > 0 and w >= 1 then
                        local ww = w
                        if r.animate then ww = 1 end
                        put(nil, "srow", sg.key, sg, x, 13, ww, 8)
                        sg.tw, sg.tx = w, x
                        sg:Show()
                        x = x + w
                    else
                        sg:Hide()
                    end
                end
                put(RR, "srow", "num", r.num, barX + barW + 6, 10, numW, 14)
                put(RR, "srow", "last", r.last, W - lastW, 5, 24, 24)
                put(R, "body", "s" .. i, r, 0, y, W, 34)
                y = y + 36
            end
        end
        if f.empty:IsShown() then put(R, "body", "empty", f.empty, 0, y, W, 84) y = y + 92 end
        f.sc:Sync(y + 8)
        return
    end
    -- Verlauf: Tageskoepfe + Zeilen
    local di, ri = 0, 0
    for _, it in ipairs(f.order or {}) do
        if it.day then
            di = di + 1
            local d = f.days[di]
            put(R, "body", "d" .. di, d, 0, y + (di > 1 and 6 or 0), W, 18)
            y = y + 26 + (di > 1 and 6 or 0)
        else
            ri = ri + 1
            local r = f.rows[ri]
            r:Layout(W, ri == 1 and R or nil)
            put(R, "body", "r" .. ri, r, 0, y, W, ROW_H)
            y = y + ROW_H + 2
        end
    end
    if f.more:IsShown() then put(R, "body", "more", f.more, 0, y + 6, W, 16) y = y + 28 end
    if f.empty:IsShown() then put(R, "body", "empty", f.empty, 0, y, W, 84) y = y + 92 end
    f.sc:Sync(y + 8)
end

local function refreshLog(f)
    f.Layout = layoutLog
    f.seg:Select(logView)
    local anim = f.animNext and animOn()
    f.animNext = false
    local q = lootSearch:lower()
    local rows = Store.List("loot", function(x)
        if logView == "award" and x.src ~= "Vergabe" then return false end
        if q == "" then return true end
        local plain = (x.item or ""):match("%[(.-)%]") or ""
        return (plain .. " " .. (x.who or "") .. " " .. (x.zone or "")):lower():find(q, 1, true) ~= nil
    end)
    table.sort(rows, function(a, b) return (a.ts or a.u or 0) > (b.ts or b.u or 0) end)
    f.data = rows
    for _, r in ipairs(f.rows) do r:Hide() end
    for _, d in ipairs(f.days) do d:Hide() end
    for _, r in ipairs(f.sRows) do r:Hide() r.e = nil end
    f.empty:SetShown(#rows == 0)
    f.empty.text:SetText(q ~= "" and L["Nichts gefunden - andere Suche probieren."]
        or (logView == "award" and L["Noch keine Vergaben - sie erscheinen hier, sobald die Raidleitung Beute verteilt."])
        or L["Noch keine Beute erfasst (ab Qualitaet 'Selten', einstellbar)."])
    if logView == "stats" then
        -- je Spieler (Main + Twinks): Bedarf / Zweitspec / Transmog / eigene Beute
        local by, order = {}, {}
        local cut = ns.now() - 30 * 86400
        local nEpic, n30 = 0, 0
        for _, x in ipairs(rows) do
            local main = (ns.Alts and ns.Alts.Main and x.who and ns.Alts.Main(x.who)) or x.who or "?"
            local e = by[main]
            if not e then e = { name = main, total = 0, ms = 0, os = 0, tm = 0, own = 0, last = nil, lastTs = 0 } by[main] = e order[#order + 1] = e end
            local c = x.choice and (({ need = "ms", greed = "os", mog = "tm" })[x.choice] or x.choice)
            if not (c == "ms" or c == "os" or c == "tm") then c = (x.src == "Vergabe") and "ms" or "own" end
            e[c] = e[c] + 1
            e.total = e.total + 1
            local ts = x.ts or x.u or 0
            if ts > e.lastTs then e.lastTs, e.last, e.lastQ = ts, x.item, x.quality end
            if ts > cut then n30 = n30 + 1 end
            if (x.quality or (ns.LootMaster and ns.LootMaster.Quality and ns.LootMaster.Quality(x.item)) or 0) >= 4 then nEpic = nEpic + 1 end
        end
        table.sort(order, function(a, b) if a.total ~= b.total then return a.total > b.total end return a.name < b.name end)
        f.statMax = order[1] and order[1].total or 1
        f.tiles.n:Set(#rows, nil, nil, anim)
        f.tiles.d30:Set(n30, (L["von %d"]):format(#rows), #rows > 0 and n30 / #rows or nil, anim)
        f.tiles.who:Set(#order, nil, nil, anim)
        f.tiles.epic:Set(nEpic, nil, #rows > 0 and nEpic / #rows or nil, anim)
        f.sHead:SetCount(#order > 0 and #order or nil)
        for i, e in ipairs(order) do
            if i > 60 then break end
            local r = f.sRows[i] or statRow(f, i)
            r.e = e
            r.pos:SetText(i)
            local pc = ({ { 1, 0.82, 0.3 }, { 0.8, 0.82, 0.86 }, { 0.85, 0.55, 0.3 } })[i] or C.muted
            r.pos:SetTextColor(pc[1], pc[2], pc[3])
            r.name:SetText(ns.Radar.Colored(e.name))
            r.num:SetText(e.total .. "  |cff888888" .. L["Items"] .. "|r")
            if e.last then r.last:SetItem(e.last, e.lastQ) r.last:Show() else r.last:Hide() end
            r.bg:SetShown(i % 2 == 0)
            if ns.isMe(e.name) or (ns.Alts and ns.Alts.MyMain and ns.Alts.MyMain() == e.name) then r.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.08) r.bg:Show()
            else r.bg:SetColorTexture(1, 1, 1, 0.025) end
            r.animate = anim
            r:Show()
        end
        layoutLog(f)
        -- Balken wachsen lassen
        if anim then
            for i, r in ipairs(f.sRows) do
                if r:IsShown() and r.e then
                    r.animate = false
                    for _, sg in ipairs(r.segs) do
                        if sg:IsShown() and sg.tw then
                            local w = sg.tw
                            sg:SetWidth(1)
                            K.Tween(sg, 0.6, function(p) sg:SetWidth(math.max(1, w * p)) end, function() sg:SetWidth(w) end, math.min(i, 12) * 0.03)
                        end
                    end
                end
            end
        end
        return
    end
    -- Verlauf: Tageskoepfe + Zeilen (begrenzt; Suche grenzt ein)
    local order, lastDay = {}, nil
    local ri, di = 0, 0
    for k, x in ipairs(rows) do
        if k > MAX_ROWS then break end
        local d = date("%Y%m%d", x.ts or x.u or 0)
        if d ~= lastDay then
            lastDay = d
            di = di + 1
            local h = f.days[di]
            if not h then h = K.GameHead(f.body, "", C.amber) f.days[di] = h end
            h.text:SetText(K.Upper(dayLabel(x.ts or x.u)))
            local cnt = 0
            for j = k, #rows do if date("%Y%m%d", rows[j].ts or rows[j].u or 0) == d then cnt = cnt + 1 else break end end
            h:SetCount(cnt)
            h:Show()
            order[#order + 1] = { day = true }
        end
        ri = ri + 1
        local r = f.rows[ri]
        if not r then r = lootRow(f.body) f.rows[ri] = r end
        r.wide = (f.sc:InnerWidth()) >= 480
        r:Set(x, true)
        r.bg:SetShown(ri % 2 == 0)
        r:Show()
        if anim and ri <= 14 then K.FadeIn(r, ri * 0.025) end
        order[#order + 1] = { row = ri }
    end
    f.order = order
    f.more:SetShown(#rows > MAX_ROWS)
    f.more:SetText((L["%d weitere - Suche grenzt ein"]):format(#rows - MAX_ROWS))
    layoutLog(f)
end

------------------------------------------------------------------------
-- Reiter "Punkte": Rangliste, Erklaerung, Raid-Steuerung (Offiziere)
------------------------------------------------------------------------
local ptsView, ptsFilter = "info", "all"
local SIDE_W, SIDE_H = 300, 430

local function buildPoints(f)
    local P = ns.Points
    local sc, body = scrollArea(f)
    sc:SetPoint("TOPLEFT") sc:SetPoint("BOTTOMRIGHT")
    f.sc, f.body = sc, body
    f.filter = K.Segments(body, { { key = "all", text = L["Alle"] }, { key = "raid", text = L["In meiner Gruppe"] } }, function(k)
        ptsFilter = k
        ns.RefreshPage("raid") ns.RefreshPage("loot")
    end, 110)
    f.hdr = CreateFrame("Frame", nil, body)
    f.hdr:SetHeight(16)
    f.hcols = {}
    for _, d in ipairs({ { "rank", "#", "CENTER" }, { "name", "Name" }, { "ep", "Einsatz", "RIGHT" }, { "gp", "Beute", "RIGHT" }, { "pr", "Prioritaet" }, { "items", "Items", "RIGHT" } }) do
        local t = K.Text(f.hdr, 10, C.dim, d[3])
        t:SetText(L[d[2]])
        t:SetWordWrap(false)
        f.hcols[d[1]] = t
    end
    f.prow = {}
    -- Podest: die drei mit der hoechsten Prioritaet (sind bei "Bedarf" zuerst dran)
    f.pod = {}
    local MED = { { 1, 0.82, 0.3 }, { 0.8, 0.82, 0.86 }, { 0.85, 0.55, 0.3 } }
    for i = 1, 3 do
        local c = CreateFrame("Button", nil, body)
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(c, { 1, 1, 1, 0.03 }, { MED[i][1], MED[i][2], MED[i][3], 0.35 }, 12) end
        c.n = K.Title(c, 22, MED[i])
        c.n:SetPoint("LEFT", 14, 0)
        c.n:SetText(i)
        c.name = K.Text(c, 13, C.text)
        c.name:SetPoint("TOPLEFT", 44, -12)
        c.name:SetPoint("RIGHT", -10, 0)
        c.name:SetWordWrap(false)
        c.pr = K.Text(c, 11, C.muted)
        c.pr:SetPoint("BOTTOMLEFT", 44, 12)
        c.pr:SetPoint("RIGHT", -10, 0)
        c.pr:SetWordWrap(false)
        c:SetScript("OnEnter", function(self) if self.row then self.row:GetScript("OnEnter")(self.row) end end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.pod[i] = c
    end
    f.empty = emptyCard(body, ns.MEDIA .. "icons\\stats", C.amber)
    f.empty.title:SetText(L["Noch keine Punkte"])
    f.emptyBtn = K.Button(f.empty, L["Punkte-Raid starten"] .. "  >", 170, 24, "ghost", function()
        ptsView = "lead"
        ns.RefreshPage("raidlead")
    end)
    f.emptyBtn:SetPoint("BOTTOMRIGHT", -12, 12)
    f.empty.text:SetText(L["Sobald ein Offizier einen Punkte-Raid startet, bekommen alle, die dabei sind, Einsatz-Punkte. Rechts siehst du, wie es funktioniert."])
    f.list = { empty = f.empty.text, SetData = function() end }

    -- Seitenleiste: Info / Leitung / Regeln
    local side = CreateFrame("Frame", nil, body)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(side, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.10 }, 14) end
    f.side = side
    f.sideSeg = K.Segments(side, { { key = "info", text = L["So geht's"] }, { key = "lead", text = L["Leitung"] }, { key = "rules", text = L["Regeln"] } }, function(k)
        ptsView = k
        ns.RefreshPage("raid") ns.RefreshPage("loot")
    end, 76)
    f.sideSeg:SetPoint("TOPLEFT", 8, -8)

    -- Info
    f.info = CreateFrame("Frame", nil, side)
    f.info:SetPoint("TOPLEFT", 12, -44)
    f.info:SetPoint("BOTTOMRIGHT", -12, 12)
    f.me = K.Title(f.info, 12, C.text)
    f.me:SetPoint("TOPLEFT", 0, 0)
    f.me:SetPoint("RIGHT", f.info, "RIGHT", 0, 0)
    f.infoText = K.Text(f.info, 11, C.muted)
    f.infoText:SetPoint("TOPLEFT", 0, -44)
    f.infoText:SetPoint("RIGHT", f.info, "RIGHT", 0, 0)
    f.infoText:SetWordWrap(true)
    f.infoText:SetJustifyV("TOP")
    f.infoText:Hide()
    f.rules3 = {}
    local RDEF = { { "Einsatz", C.mint, "camp" }, { "Beute kostet", C.red, "wants" }, { "Prioritaet", C.amber, "stats" } }
    for i, d in ipairs(RDEF) do
        local c = CreateFrame("Frame", nil, f.info)
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(c, { d[2][1], d[2][2], d[2][3], 0.05 }, { d[2][1], d[2][2], d[2][3], 0.25 }, 10) end
        c:SetHeight(64)
        c:SetPoint("TOPLEFT", 0, -46 - (i - 1) * 70)
        c:SetPoint("RIGHT", f.info, "RIGHT", 0, 0)
        c.g = K.Glyph(c, 16, ns.MEDIA .. "icons\\" .. d[3], d[2])
        c.g:SetPoint("TOPLEFT", 10, -10)
        c.t = K.Title(c, 12, C.text)
        c.t:SetPoint("LEFT", c.g, "RIGHT", 8, 0)
        c.t:SetText(L[d[1]])
        c.b = K.Text(c, 10, C.muted)
        c.b:SetPoint("TOPLEFT", 10, -30)
        c.b:SetPoint("RIGHT", c, "RIGHT", -10, 0)
        c.b:SetWordWrap(true)
        c.b:SetJustifyV("TOP")
        f.rules3[i] = c
    end
    -- Rechner: "Was waere wenn" - Einsatz und Beute verstellen, Prioritaet und Platz sehen
    local calc = CreateFrame("Frame", nil, f.info)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(calc, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.10 }, 10) end
    calc:SetHeight(92)
    calc:SetPoint("TOPLEFT", 0, -46 - 3 * 70 - 4)
    calc:SetPoint("RIGHT", f.info, "RIGHT", 0, 0)
    f.calc = calc
    calc.ep, calc.gp = 100, 0
    calc.t = K.Title(calc, 12, C.text)
    calc.t:SetPoint("TOPLEFT", 10, -10)
    calc.t:SetText(L["Rechner"])
    calc.h = K.Text(calc, 10, C.dim)
    calc.h:SetPoint("LEFT", calc.t, "RIGHT", 8, 0)
    calc.h:SetText(L["Mausrad oder +/-"])
    local function stepper(label, key, x)
        local w = CreateFrame("Frame", nil, calc)
        w:SetSize(118, 24)
        w:SetPoint("TOPLEFT", x, -32)
        w.l = K.Text(w, 10, C.muted)
        w.l:SetPoint("LEFT", 0, 0)
        w.l:SetText(label)
        w.v = K.Title(w, 13, C.text, "CENTER")
        w.v:SetPoint("RIGHT", -24, 0)
        w.v:SetWidth(34)
        local function set(d)
            calc[key] = math.max(0, math.min(2000, calc[key] + d * ((IsShiftKeyDown and IsShiftKeyDown()) and 100 or 10)))
            calc:Update()
        end
        w.minus = K.Button(w, "-", 20, 20, "ghost", function() set(-1) end)
        w.minus:SetPoint("RIGHT", w.v, "LEFT", -2, 0)
        w.plus = K.Button(w, "+", 20, 20, "ghost", function() set(1) end)
        w.plus:SetPoint("RIGHT", 0, 0)
        w:EnableMouseWheel(true)
        w:SetScript("OnMouseWheel", function(_, d) set(d) end)
        calc[key .. "W"] = w
    end
    stepper(L["Einsatz"], "ep", 10)
    stepper(L["Beute"], "gp", 140)
    calc.res = K.Text(calc, 12, C.text)
    calc.res:SetPoint("BOTTOMLEFT", 10, 12)
    calc.res:SetPoint("RIGHT", calc, "RIGHT", -10, 0)
    calc.res:SetWordWrap(false)
    function calc:Update()
        local P = ns.Points
        if not P then return end
        local base = (P.Cfg().base or 100)
        local pr = self.ep / (self.gp + base)
        self.epW.v:SetText(self.ep)
        self.gpW.v:SetText(self.gp)
        local st = P.Standings()
        local rank = 1
        for _, e in ipairs(st.list) do if e.pr > pr then rank = rank + 1 end end
        self.res:SetText((L["Prioritaet %s"]):format(P.FmtPR(pr)) .. "  |cff888888·  " .. (L["waere Platz %d von %d"]):format(rank, math.max(#st.list, rank)) .. "|r")
    end

    -- Leitung (Offiziere)
    f.lead = CreateFrame("Frame", nil, side)
    f.lead:SetPoint("TOPLEFT", 12, -44)
    f.lead:SetPoint("BOTTOMRIGHT", -12, 12)
    f.leadState = K.Text(f.lead, 12, C.text)
    f.leadState:SetPoint("TOPLEFT", 0, 0)
    f.leadState:SetPoint("RIGHT", f.lead, "RIGHT", 0, 0)
    f.leadState:SetWordWrap(true)
    f.startBtn = K.Button(f.lead, "", 240, 28, "primary", function()
        if P.Active() then P.EndRaid() else P.StartRaid() end
    end)
    f.startBtn:SetPoint("TOPLEFT", 0, -40)
    f.startBtn:SetPoint("RIGHT", f.lead, "RIGHT", 0, 0)
    f.bossBtn = K.Button(f.lead, "", 240, 24, "ghost", function()
        local cfg = P.Cfg()
        P.Award(P.GroupNames(), cfg.boss, L["Boss (von Hand)"])
    end)
    f.bossBtn:SetPoint("TOPLEFT", 0, -74)
    f.bossBtn:SetPoint("RIGHT", f.lead, "RIGHT", 0, 0)
    local bl = K.Label(f.lead, L["Ersatzbank (bekommt auch Einsatz)"])
    bl:SetPoint("TOPLEFT", 0, -110)
    f.benchBox = K.Input(f.lead, 170, L["Name ..."])
    f.benchBox:SetPoint("TOPLEFT", 0, -126)
    f.benchBox.onEnter = function(t)
        if t ~= "" then P.bench[ns.fullName(t)] = true end
        f.benchBox:SetText("")
        ns.RefreshPage("raid") ns.RefreshPage("loot")
    end
    f.benchList = K.Text(f.lead, 11, C.text)
    f.benchList:SetPoint("TOPLEFT", 0, -154)
    f.benchList:SetPoint("RIGHT", f.lead, "RIGHT", 0, 0)
    f.benchList:SetWordWrap(true)
    local al = K.Label(f.lead, L["Korrektur (z.B. +20 fuer Vorbereitung)"])
    al:SetPoint("TOPLEFT", 0, -196)
    f.adjName = K.Input(f.lead, 110, L["Name"])
    f.adjName:SetPoint("TOPLEFT", 0, -212)
    f.adjEP = K.Input(f.lead, 50, L["Einsatz"])
    f.adjEP:SetPoint("LEFT", f.adjName, "RIGHT", 4, 0)
    f.adjGP = K.Input(f.lead, 50, L["Beute"])
    f.adjGP:SetPoint("LEFT", f.adjEP, "RIGHT", 4, 0)
    f.adjReason = K.Input(f.lead, 170, L["Grund ..."])
    f.adjReason:SetPoint("TOPLEFT", 0, -240)
    f.adjBtn = K.Button(f.lead, L["Buchen"], 60, 24, "ghost", function()
        local n = f.adjName:GetText()
        local ep, gp = tonumber(f.adjEP:GetText()) or 0, tonumber(f.adjGP:GetText()) or 0
        if n == "" or (ep == 0 and gp == 0) then return end
        P.Adjust(ns.fullName(n), ep, gp, f.adjReason:GetText())
        f.adjName:SetText("") f.adjEP:SetText("") f.adjGP:SetText("") f.adjReason:SetText("")
    end)
    f.adjBtn:SetPoint("LEFT", f.adjReason, "RIGHT", 4, 0)
    f.leadNo = K.Text(side, 12, C.muted)
    f.leadNo:SetPoint("TOPLEFT", 12, -50)
    f.leadNo:SetPoint("RIGHT", side, "RIGHT", -12, 0)
    f.leadNo:SetWordWrap(true)

    -- Regeln
    f.rules = CreateFrame("Frame", nil, side)
    f.rules:SetPoint("TOPLEFT", 12, -44)
    f.rules:SetPoint("BOTTOMRIGHT", -12, 12)
    f.ruleBoxes = {}
    local defs = {
        { "onTime", L["Puenktlich da"] }, { "boss", L["Je Boss"] }, { "finish", L["Bis zum Ende"] },
        { "epic", L["Episches Item"] }, { "rare", L["Seltenes Item"] }, { "decay", L["Verfall pro Woche (%)"] },
        { "rank", L["Punkte vergeben bis Rang (0 = Gildenmeister)"] },
    }
    for i, d in ipairs(defs) do
        local t = K.Text(f.rules, 11, C.text)
        t:SetPoint("TOPLEFT", 0, -4 - (i - 1) * 28)
        t:SetPoint("RIGHT", f.rules, "RIGHT", -62, 0)
        t:SetWordWrap(false)
        t:SetText(d[2])
        local b = K.Input(f.rules, 56, "")
        b:SetPoint("TOPRIGHT", f.rules, "TOPRIGHT", 0, -(i - 1) * 28)
        b:SetNumeric(true)
        b.key = d[1]
        f.ruleBoxes[i] = b
    end
    f.saveRules = K.Button(f.rules, L["Regeln speichern"], 240, 26, "primary", function()
        local ch = {}
        for _, b in ipairs(f.ruleBoxes) do
            local v = tonumber(b:GetText())
            if v then ch[b.key] = v end
        end
        P.SetCfg(ch)
        K.Toast(L["Regeln gespeichert"], L["Gilt ab sofort fuer die ganze Gilde."], C.mint)
    end)
    f.saveRules:SetPoint("TOPLEFT", 0, -208)
    f.saveRules:SetPoint("RIGHT", f.rules, "RIGHT", 0, 0)
    f.rulesNote = K.Text(f.rules, 10, C.dim)
    f.rulesNote:SetPoint("TOPLEFT", 0, -242)
    f.rulesNote:SetPoint("RIGHT", f.rules, "RIGHT", 0, 0)
    f.rulesNote:SetWordWrap(true)
    f.rulesNote:SetText(L["Waffen kosten das 1,5-fache, Zweitspec ein Viertel, Transmog nichts."])
    f.animNext = true
    f:HookScript("OnShow", function() f.animNext = true end)
    sc:SetScript("OnSizeChanged", function() if f.Layout then f:Layout() end end)
end

local function pointsRow(f, i)
    local r = CreateFrame("Button", nil, f.body)
    r:SetHeight(28)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.04)
    r.sel = r:CreateTexture(nil, "ARTWORK")
    r.sel:SetPoint("TOPLEFT", 0, -6) r.sel:SetPoint("BOTTOMLEFT", 0, 6) r.sel:SetWidth(2)
    r.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    r.cols = {}
    r.cols.rank = K.Title(r, 12, C.muted, "CENTER")
    r.cols.name = K.Text(r, 12, C.text)
    r.cols.ep = K.Text(r, 12, C.text, "RIGHT")
    r.cols.gp = K.Text(r, 12, C.muted, "RIGHT")
    r.cols.pr = K.Text(r, 12, C.text)
    r.cols.items = K.Text(r, 11, C.muted, "RIGHT")
    for _, t in pairs(r.cols) do t:SetWordWrap(false) end
    r.track = r:CreateTexture(nil, "BORDER")
    r.track:SetColorTexture(1, 1, 1, 0.06)
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 0.9)
    r:SetScript("OnEnter", function(self)
        local e = self.item
        local P = ns.Points
        if not e or not P then return end
        local lines = { ns.Radar.Colored(e.name), (L["Einsatz %d  ·  Beute %d  ·  Prioritaet %s"]):format(e.ep, e.gp, P.FmtPR(e.pr)), " " }
        for k = #e.log, math.max(1, #e.log - 9), -1 do
            local x = e.log[k]
            if x.kind == "gp" then
                lines[#lines + 1] = "|cffff7a5c-" .. (x.amount or 0) .. "|r  " .. (x.item or "?") .. "  |cff666666" .. ns.ago(x.ts) .. "|r"
            elseif x.kind == "adj" then
                lines[#lines + 1] = "|cffe8b44a" .. L["Korrektur"] .. "|r  " .. (x.reason or "") .. "  |cff666666" .. ns.ago(x.ts) .. "|r"
            else
                lines[#lines + 1] = "|cff66db9e+" .. (x.amount or 0) .. "|r  " .. (x.reason or "") .. "  |cff666666" .. ns.ago(x.ts) .. "|r"
            end
        end
        K.ShowTip(self, lines)
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.prow[i] = r
    return r
end

-- Spalten der Rangliste fuer eine Breite: rank, name, ep, gp, pr(+Balken), items
local function pointCols(lw)
    local c = { rank = { 0, 30 } }
    local right = {}
    local x = lw - 8
    if lw >= 420 then c.items = { x - 40, 40 } x = x - 46 end
    c.pr = { x - 96, 96 } x = x - 102
    c.gp = { x - 56, 56 } x = x - 62
    c.ep = { x - 56, 56 } x = x - 62
    c.name = { 36, math.max(40, x - 36) }
    return c, right
end

local function layoutPoints(f)
    local W = f.sc:InnerWidth()
    local R = {}
    f.rects = R
    local wide = W >= 680
    local lw, lx, ly, sideX, sideY, sideW
    if wide then
        sideW = SIDE_W
        lw = W - sideW - 14
        lx, ly = 0, 0
        sideX, sideY = lw + 14, 0
    else
        sideW = W
        lw = W
        sideX, sideY = 0, 0
        lx, ly = 0, SIDE_H + 14
    end
    put(R, "body", "side", f.side, sideX, sideY, sideW, SIDE_H)
    -- Podest oben ueber der Liste
    local podOn = f.pod and f.pod[1] and f.pod[1]:IsShown()
    if podOn then
        local pw = math.floor((lw - 16) / 3)
        for i, c in ipairs(f.pod) do put(R, "list", "pod" .. i, c, lx + (i - 1) * (pw + 8), ly, pw, 58) end
        ly = ly + 70
    end
    put(R, "list", "filter", f.filter, lx, ly, f.filter:GetWidth() or 230, 24)
    put(R, "list", "hdr", f.hdr, lx, ly + 32, lw, 16)
    local cols = pointCols(lw)
    for key, t in pairs(f.hcols) do
        local c = cols[key]
        t:SetShown(c ~= nil)
        if c then put(R, "hdr", key, t, c[1], 2, c[2], 12) end
    end
    local y = ly + 52
    for i, r in ipairs(f.prow) do
        if r:IsShown() then
            for key, t in pairs(r.cols) do
                local c = cols[key]
                t:SetShown(c ~= nil)
                if c then
                    if key == "pr" then
                        put(i == 1 and R or nil, "prow", key, t, c[1], 3, c[2], 13)
                    else
                        put(i == 1 and R or nil, "prow", key, t, c[1], 7, c[2], 14)
                    end
                end
            end
            local pc = cols.pr
            put(nil, "prow", "track", r.track, pc[1], 19, pc[2] - 8, 4)
            local w = math.max(1, (pc[2] - 8) * (r.prog or 0))
            r.bar:ClearAllPoints()
            r.bar:SetPoint("TOPLEFT", pc[1], -19)
            r.bar:SetHeight(4)
            if not r.growing then r.bar:SetWidth(w) end
            r.barW = w
            r.bar:SetShown((r.prog or 0) > 0)
            put(R, "list", "p" .. i, r, lx, y, lw, 28)
            y = y + 29
        end
    end
    if f.empty:IsShown() then put(R, "list", "empty", f.empty, lx, y + 4, lw, 150) y = y + 162 end
    local h = math.max(y, sideY + SIDE_H)
    f.sc:Sync(h + 8)
end

local function refreshPoints(f)
    local P = ns.Points
    f.Layout = layoutPoints
    local cfg = P.Cfg()
    local st = P.Standings()
    local list = st.list
    if ptsFilter == "raid" then
        local inGroup = {}
        for _, n in ipairs(P.GroupNames()) do inGroup[ns.Alts and ns.Alts.Main(n) or n] = true end
        local out = {}
        for _, e in ipairs(list) do if inGroup[e.name] then out[#out + 1] = e end end
        list = out
    end
    f.maxPR = 0
    for _, e in ipairs(list) do if e.pr > f.maxPR then f.maxPR = e.pr end end
    local anim = f.animNext and animOn()
    f.animNext = false
    for _, r in ipairs(f.prow) do r:Hide() end
    local PC = { { 1, 0.82, 0.3 }, { 0.8, 0.82, 0.86 }, { 0.85, 0.55, 0.3 } }
    for i, e in ipairs(list) do
        if i > 150 then break end
        local r = f.prow[i] or pointsRow(f, i)
        r.item = e
        r.cols.rank:SetText(e.rank)
        local pc = PC[e.rank] or C.muted
        r.cols.rank:SetTextColor(pc[1], pc[2], pc[3])
        r.cols.name:SetText(ns.Radar.Colored(e.name))
        r.cols.ep:SetText(math.floor(e.ep + 0.5))
        r.cols.gp:SetText(math.floor(e.gp + 0.5))
        r.cols.pr:SetText(P.FmtPR(e.pr))
        r.cols.items:SetText(e.items > 0 and e.items or "")
        r.prog = (f.maxPR or 1) > 0 and e.pr / f.maxPR or 0
        local me = ns.isMe(e.name) or (ns.Alts and ns.Alts.MyMain and ns.Alts.MyMain() == e.name)
        r.sel:SetShown(me and true or false)
        if me then r.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.06) else r.bg:SetColorTexture(1, 1, 1, 0) end
        r.growing = anim
        r:Show()
    end
    f.empty:SetShown(#list == 0)
    for i, c in ipairs(f.pod or {}) do
        local e = list[i]
        c:SetShown(#list >= 3)
        if e then
            c.name:SetText(ns.Radar.Colored(e.name))
            c.pr:SetText((L["Prioritaet %s"]):format(P.FmtPR(e.pr)) .. "  ·  " .. (L["%d Items"]):format(e.items or 0))
            c.row = f.prow[i]
        end
    end
    layoutPoints(f)
    if anim then
        for i, r in ipairs(f.prow) do
            if r:IsShown() and r.barW then
                local w = r.barW
                r.bar:SetWidth(1)
                K.Tween(r.bar, 0.7, function(p) r.bar:SetWidth(math.max(1, w * p)) end, function() r.bar:SetWidth(w) r.growing = false end, math.min(i, 15) * 0.025)
            end
        end
    else
        for _, r in ipairs(f.prow) do r.growing = false end
    end

    f.sideSeg:Select(ptsView)
    f.info:SetShown(ptsView == "info")
    f.lead:SetShown(ptsView == "lead")
    f.leadNo:SetShown(false)
    if not f.leadLock then f.leadLock = K.Lock(f.lead, { who = "officer", text = L["Punkte vergeben duerfen nur Offiziere."], check = function() return P.CanManage() end }) end
    f.leadLock:Update()
    f.rules:SetShown(ptsView == "rules")

    local me = P.Of(ns.me())
    f.me:SetText((L["Deine Prioritaet: %s"]):format(P.FmtPR(me.pr)) .. "  |cff888888" .. (L["Platz %d von %d"]):format(me.rank, math.max(#st.list, me.rank)) .. "|r\n|cffa3a3a8"
        .. (L["Einsatz %d  ·  Beute %d  ·  %d Raids  ·  %d Items"]):format(me.ep, me.gp, me.raids, me.items) .. "|r")
    if f.rules3 then
        f.rules3[1].b:SetText((L["+%d beim Start da  ·  +%d je Boss  ·  +%d bis zum Ende. Ersatzbank bekommt das auch."]):format(cfg.onTime, cfg.boss, cfg.finish))
        f.rules3[2].b:SetText((L["Episch %d, Selten %d, Waffen x1,5. Zweitspec ein Viertel, Transmog gratis."]):format(cfg.epic, cfg.rare))
        f.rules3[3].b:SetText((L["Einsatz / (Beute + %d). Hoechste bekommt bei Bedarf das Item. Jede Woche -%d %%."]):format(cfg.base, cfg.decay))
        if f.calc then f.calc:Update() end
    end
    f.infoText:SetText(table.concat({
        "|cffe6e6e6" .. L["So wird fair verteilt:"] .. "|r",
        (L["+%d Einsatz, wenn du beim Start da bist"]):format(cfg.onTime),
        (L["+%d Einsatz je Boss, den der Raid legt"]):format(cfg.boss),
        (L["+%d Einsatz, wenn du bis zum Ende bleibst"]):format(cfg.finish),
        L["Ersatzbank bekommt dieselben Punkte."],
        " ",
        (L["Beute kostet: Episch %d, Selten %d, Waffen x1,5."]):format(cfg.epic, cfg.rare),
        L["Zweitspec kostet ein Viertel, Transmog ist gratis."],
        " ",
        "|cffe6e6e6" .. L["Prioritaet = Einsatz / (Beute + %d)"]:format(cfg.base) .. "|r",
        L["Bei 'Bedarf' bekommt das Item, wer die hoechste Prioritaet hat. Gleichstand: Wuerfeln."],
        (L["Jede Woche verfallen %d %% - so koennen Neue aufholen."]):format(cfg.decay),
    }, "\n"))

    local r = P.Active()
    if r then
        f.leadState:SetText((L["Raid laeuft: %s"]):format(r.title ~= "" and r.title or "?") .. "\n|cff888888" .. (L["seit %s  ·  %d Bosse"]):format(ns.ago(r.t), r.bosses or 0) .. "|r")
        f.startBtn:SetLabel((L["Raid beenden (+%d fuer alle)"]):format(cfg.finish))
    else
        f.leadState:SetText("|cff888888" .. L["Kein Raid aktiv. Starte ihn, wenn alle da sind - Bosse werden dann automatisch gezaehlt."] .. "|r")
        f.startBtn:SetLabel((L["Raid starten (+%d Puenktlich)"]):format(cfg.onTime))
    end
    f.bossBtn:SetLabel((L["Boss-Punkte von Hand (+%d)"]):format(cfg.boss))
    f.bossBtn:SetShown(r ~= nil)
    local b = {}
    for n in pairs(P.bench) do b[#b + 1] = ns.Radar.Colored(n) end
    f.benchList:SetText(#b > 0 and table.concat(b, ", ") or "|cff666666" .. L["niemand"] .. "|r")
    f.leadNo:SetText(L["Punkte vergeben duerfen nur Offiziere."] .. "\n\n" .. L["Frag einen Offizier, wenn Punkte fehlen - jede Buchung ist nachvollziehbar (Maus ueber einen Namen)."])
    for _, bx in ipairs(f.ruleBoxes) do
        if not bx:HasFocus() then bx:SetText(cfg[bx.key]) end
        bx:EnableMouse(P.CanManage())
    end
    f.saveRules:Show()
    K.LockButton(f.saveRules, function() return P.CanManage() end, "officer")
end

------------------------------------------------------------------------
-- Reiter "Meine Beute": Kacheln, eigene Reservierungen, eigene Beute (nur lesen)
------------------------------------------------------------------------
local function isMine(name)
    if not name then return false end
    if ns.isMe(name) then return true end
    if ns.Alts and ns.Alts.Main and ns.Alts.MyMain then
        local m = ns.Alts.MyMain()
        return m ~= nil and ns.Alts.Main(name) == m
    end
    return false
end
local MINE_MAX = 60

local function buildMine(f)
    local sc, body = scrollArea(f)
    sc:SetPoint("TOPLEFT") sc:SetPoint("BOTTOMRIGHT")
    f.sc, f.body = sc, body
    f.tiles = {}
    local defs = {
        { "pr", "Prioritaet", C.accent, "raid" },
        { "rank", "Platz", C.amber, "stats" },
        { "ep", "Einsatz", C.mint, "badges" },
        { "gp", "Beute", C.red, "wants" },
        { "att", "Teilnahme", C.blue, "camp" },
    }
    for i, d in ipairs(defs) do
        local t = famTile(body, ns.MEDIA .. "icons\\" .. d[4], L[d[2]], d[3])
        t:SetHeight(66)
        f.tiles[i] = t
        f.tiles[d[1]] = t
    end
    f.animNext = true
    f:HookScript("OnShow", function() f.animNext = true end)
    f.note = K.Text(body, 11, C.muted)
    f.note:SetWordWrap(true)
    f.note:SetJustifyV("TOP")
    -- Reservierungen
    f.srHead = K.GameHead(body, L["Meine Reservierungen"], C.amber)
    f.srAll = K.Button(body, L["Reservierungen"] .. "  >", 140, 20, "ghost", function() ns.ShowPage("softres") end)
    f.srCards = {}
    f.srEmpty = K.Text(body, 11, C.dim)
    f.srEmpty:SetWordWrap(true)
    f.srEmpty:SetText(L["Keine Reservierung fuer kommende Termine - im Termin auf 'Reservieren' klicken."])
    -- eigene Beute
    f.head = K.GameHead(body, L["Deine Beute"], C.amber)
    f.rows = {}
    f.more = K.Button(body, "", 220, 22, "ghost", function() Raid.SetTab("log") end)
    f.empty = emptyCard(body, ns.MEDIA .. "icons\\wants", C.amber)
    f.empty.title:SetText(L["Noch keine eigene Beute"])
    f.empty.text:SetText(L["Noch keine eigene Beute erfasst (ab Qualitaet 'Selten', einstellbar)."])
    -- Kompatibilitaet
    f.list = { empty = f.empty.text, SetData = function() end }
    function f.layout() if f.Layout then f:Layout() end end
    sc:SetScript("OnSizeChanged", function() f.layout() end)
end

local function srCard(f, i)
    local c = K.Panel(f.body, C.panel)
    c.edge = c:CreateTexture(nil, "ARTWORK")
    c.edge:SetPoint("TOPLEFT") c.edge:SetPoint("BOTTOMLEFT") c.edge:SetWidth(3)
    c.edge:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 1)
    c.day = K.Title(c, 16, C.text, "CENTER")
    c.mon = K.Text(c, 9, C.muted, "CENTER")
    c.title = K.Text(c, 11, C.muted)
    c.title:SetWordWrap(false)
    c.icon = itemButton(c, 26)
    c.name = K.Text(c, 12, C.text)
    c.name:SetWordWrap(false)
    c.hit = CreateFrame("Button", nil, c)
    c.hit:SetAllPoints()
    c.hit:SetFrameLevel((c:GetFrameLevel() or 1) + 1)
    c.icon:SetFrameLevel((c:GetFrameLevel() or 1) + 3)
    c.hit:SetScript("OnClick", function() if c.ev and ns.SoftRes and ns.SoftRes.Open then ns.SoftRes.Open(c.ev) end end)
    c.hit:SetScript("OnEnter", function(self) K.ShowTip(self, { c.ev and c.ev.title or "", "|cff888888" .. L["Klick: Reservierung aendern"] .. "|r" }) end)
    c.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.srCards[i] = c
    return c
end

-- 0.6.460: eigene Beute aus allen Gebieten fuer das Profil (Abenteuer > Beute)
function Raid.ShowMyLoot(host)
    if not host.lootList then
        host.head = K.GameHead(host, L["Deine Beute"], C.amber)
        host.head:SetPoint("TOPLEFT", 0, -2)
        host.head:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        host.lootList = K.List(host, 44, function(l)
            local r = K.Row(l)
            if r.stripe then r.stripe:SetAlpha(0) end
            r.card = r:CreateTexture(nil, "BACKGROUND", nil, -1)
            r.card:SetPoint("TOPLEFT", 0, -3) r.card:SetPoint("BOTTOMRIGHT", 0, 3)
            r.card:SetColorTexture(1, 1, 1, 0.035)
            if K.RoundMask then pcall(K.RoundMask, r.card, r, 8) end
            r.ib = itemButton(r, 30)
            r.ib:SetPoint("LEFT", 8, 0)
            r.n = K.Text(r, 12, C.text)
            r.n:SetPoint("TOPLEFT", 48, -8)
            r.n:SetPoint("RIGHT", r, "RIGHT", -120, 0)
            r.n:SetWordWrap(false)
            r.z = K.Text(r, 10, C.muted)
            r.z:SetPoint("BOTTOMLEFT", 48, 8)
            r.t = K.Text(r, 10, C.dim, "RIGHT")
            r.t:SetPoint("RIGHT", -12, 0)
            return r
        end, function(r, x)
            r.ib:SetItem(x.item)
            r.n:SetText(x.item or "?")
            r.z:SetText((x.zone or "") .. ((x.raid or x.src == "Vergabe") and ("  |cffe8b44a" .. L["Raid"] .. "|r") or ""))
            r.t:SetText(ns.ago(x.ts or x.u))
        end)
        host.lootList:SetPoint("TOPLEFT", 0, -30)
        host.lootList:SetPoint("BOTTOMRIGHT", 0, 0)
        host.lootEmpty = K.Text(host, 12, C.dim, "CENTER")
        host.lootEmpty:SetPoint("TOP", 0, -80)
        host.lootEmpty:SetText(L["Noch keine eigene Beute erfasst (ab Qualitaet 'Selten', einstellbar)."])
    end
    local rows = Store.List("loot", function(x) return isMine(x.who) and x.item end)
    table.sort(rows, function(a, b) return (a.ts or a.u or 0) > (b.ts or b.u or 0) end)
    host.head:SetCount(#rows > 0 and #rows or nil)
    host.lootEmpty:SetShown(#rows == 0)
    host.lootList:SetData(rows)
end

local function layoutMine(f)
    local W = f.sc:InnerWidth()
    local R = {}
    f.rects = R
    local y = 0
    -- Kacheln: 5 / 3 / 2 je Zeile
    local vis = {}
    for _, t in ipairs(f.tiles) do if t:IsShown() then vis[#vis + 1] = t end end
    local cols = math.min(#vis, W >= 660 and 5 or (W >= 420 and 3 or 2))
    cols = math.max(1, cols)
    local tw = math.floor((W - (cols - 1) * 8) / cols)
    for i, t in ipairs(vis) do
        local c, rr = (i - 1) % cols, math.floor((i - 1) / cols)
        put(R, "body", "tile" .. i, t, c * (tw + 8), y + rr * 74, tw, 66)
    end
    y = y + math.ceil(#vis / cols) * 74
    put(R, "body", "note", f.note, 0, y, W, 28)
    y = y + 36
    -- Reservierungen
    local bw = 140
    put(R, "body", "srHead", f.srHead, 0, y, W - bw - 8, 18)
    put(R, "body", "srAll", f.srAll, W - bw, y - 1, bw, 20)
    y = y + 26
    local n = 0
    for _, c in ipairs(f.srCards) do if c:IsShown() then n = n + 1 end end
    if n == 0 then
        put(R, "body", "srEmpty", f.srEmpty, 0, y, W, 28)
        y = y + 34
    else
        local cc = W >= 640 and 3 or (W >= 420 and 2 or 1)
        local cw = math.floor((W - (cc - 1) * 8) / cc)
        local k = 0
        for _, c in ipairs(f.srCards) do
            if c:IsShown() then
                k = k + 1
                local col, row = (k - 1) % cc, math.floor((k - 1) / cc)
                local RR = (k == 1) and R or nil
                put(RR, "src", "day", c.day, 6, 8, 40, 20)
                put(RR, "src", "mon", c.mon, 6, 30, 40, 12)
                put(RR, "src", "title", c.title, 54, 7, cw - 62, 13)
                put(RR, "src", "icon", c.icon, 54, 24, 26, 26)
                put(RR, "src", "name", c.name, 86, 30, cw - 94, 14)
                put(R, "body", "sr" .. k, c, col * (cw + 8), y + row * 64, cw, 56)
            end
        end
        y = y + math.ceil(n / cc) * 64 + 2
    end
    -- eigene Beute
    put(R, "body", "head", f.head, 0, y, W, 18)
    y = y + 26
    local ri = 0
    for _, r in ipairs(f.rows) do
        if r:IsShown() then
            ri = ri + 1
            r:Layout(W, ri == 1 and R or nil)
            put(R, "body", "r" .. ri, r, 0, y, W, ROW_H)
            y = y + ROW_H + 2
        end
    end
    if f.more:IsShown() then put(R, "body", "more", f.more, math.floor((W - 220) / 2), y + 6, 220, 22) y = y + 36 end
    if f.empty:IsShown() then put(R, "body", "empty", f.empty, 0, y, W, 84) y = y + 92 end
    f.sc:Sync(y + 8)
end

local function refreshMine(f)
    local P = ns.Points
    f.Layout = layoutMine
    local active = false
    -- Kacheln nur beim ersten Anzeigen hochzaehlen
    local anim = f.animNext and animOn()
    f.animNext = false
    for _, t in ipairs(f.tiles) do t:SetShown(P ~= nil or t == f.tiles.att) end
    local yes, total, planned = Raid.Attendance(30)
    f.tiles.att:Set(yes, (L["von %d"]):format(total), total > 0 and (yes / total) or nil, anim)
    f.tiles.att.tip = { L["Teilnahme (30 Tage)"], (L["Zugesagt: %d von %d Terminen"]):format(yes, total),
        (L["In der Aufstellung: %d"]):format(planned) }
    if P then
        local st = P.Standings()
        local me = P.Of(ns.me())
        active = #st.list > 0
        local total = math.max(#st.list, me.rank or 0)
        local maxPR = 0
        for _, e in ipairs(st.list) do if e.pr > maxPR then maxPR = e.pr end end
        f.tiles.pr:Set(P.FmtPR(me.pr), nil, maxPR > 0 and (me.pr / maxPR) or nil, anim)
        f.tiles.rank:Set(active and me.rank or "-", active and ((L["von %d"]):format(total)) or "", active and total > 0 and (1 - (me.rank - 1) / total) or nil, anim)
        f.tiles.ep:Set(math.floor(me.ep + 0.5), (L["%d Raids"]):format(me.raids or 0), nil, anim)
        f.tiles.gp:Set(math.floor(me.gp + 0.5), (L["%d Items"]):format(me.items or 0), nil, anim)
        f.tiles.pr.tip = { L["Prioritaet"], L["Prioritaet = Einsatz / (Beute + %d)"]:format(P.Cfg().base) }
        f.tiles.rank.tip = { L["Platz in der Prio-Liste"], L["Bei 'Bedarf' bekommt das Item, wer die hoechste Prioritaet hat. Gleichstand: Wuerfeln."] }
    end
    for _, t in ipairs(f.tiles) do t:SetShown(active) end
    if not P then
        f.note:SetText(L["Beute-Punkte sind nicht aktiv."])
    elseif not active then
        f.note:SetText("|cff888888" .. L["Die Gilde vergibt noch keine Beute-Punkte - deine Werte erscheinen, sobald die Raidleitung einen Raid startet."] .. "|r")
    else
        f.note:SetText("|cff888888" .. L["Wer oft dabei ist und wenig bekommen hat, ist bei 'Bedarf' zuerst dran. Jede Woche verfaellt ein Teil der Punkte."] .. "|r")
    end
    -- eigene Reservierungen fuer kommende Termine
    for _, c in ipairs(f.srCards) do c:Hide() end
    local k = 0
    if ns.SoftRes and ns.SoftRes.Mine then
        local now = ns.now()
        local evs = Raid.Events()
        table.sort(evs, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
        for _, ev in ipairs(evs) do
            if (ev.ts or 0) > now - 6 * 3600 then
                local sr = ns.SoftRes and ns.SoftRes.Mine(ev.id)
                if sr and sr.item then
                    k = k + 1
                    local c = f.srCards[k] or srCard(f, k)
                    c.ev = ev
                    c.day:SetText(date("%d", ev.ts))
                    c.mon:SetText(K.Upper(L[WDAYS[(tonumber(date("%w", ev.ts)) + 6) % 7 + 1]]) .. " " .. date("%m.", ev.ts))
                    c.title:SetText((ev.title or "?") .. "  |cff888888" .. countdown(ev.ts) .. "|r")
                    local ok, _, link = pcall(itemInfo, sr.item)
                    if not ok or type(link) ~= "string" then link = "item:" .. sr.item end
                    c.icon:SetItem(link)
                    c.name:SetText(link:find("|H") and ns.fixColors(link) or ("#" .. sr.item))
                    ns.withItem(sr.item, function(full) if full and c.ev == ev then c.icon:SetItem(full) c.name:SetText(ns.fixColors(full)) end end)
                    c:Show()
                end
            end
        end
    end
    f.srHead:SetCount(k > 0 and k or nil)
    f.srEmpty:SetShown(k == 0)
    f.srAll:SetShown(ns.SoftRes ~= nil)
    -- eigene Beute + Punktekosten der Vergaben
    local cost = {}
    if P then
        for _, r in ipairs(P.Of(ns.me()).log or {}) do
            if r.kind == "gp" and r.item then
                local id = ns.itemID(r.item)
                if id then cost[id] = (cost[id] or 0) + (r.amount or 0) end
            end
        end
    end
    -- 0.6.460: hier nur Raid-Beute (im Raid erhalten oder vergeben); alles andere steht im Profil > Abenteuer > Beute
    local rows = Store.List("loot", function(x) return isMine(x.who) and (x.raid or x.src == "Vergabe") end)
    table.sort(rows, function(a, b) return (a.ts or a.u or 0) > (b.ts or b.u or 0) end)
    for _, r in ipairs(f.rows) do r:Hide() end
    local W = f.sc:InnerWidth()
    for i, x in ipairs(rows) do
        if i > MINE_MAX then break end
        local id = ns.itemID(x.item)
        local c = id and cost[id]
        if c then cost[id] = nil end
        local r = f.rows[i]
        if not r then r = lootRow(f.body) f.rows[i] = r end
        r.wide = W >= 480
        r:Set(x, false, c)
        r.bg:SetShown(i % 2 == 0)
        r:Show()
        if anim and i <= 12 then K.FadeIn(r, 0.15 + i * 0.03) end
    end
    f.head:SetCount(#rows > 0 and #rows or nil)
    f.more:SetShown(#rows > MINE_MAX)
    f.more:SetLabel((L["%d weitere im Beute-Log"]):format(#rows - MINE_MAX) .. "  >")
    f.empty:SetShown(#rows == 0)
    layoutMine(f)
end

------------------------------------------------------------------------
-- Reiter "Raidleitung": Unter-Reiter fuer Leitung / Schlachtzugsleiter / Assistenten
------------------------------------------------------------------------
local function buildLead(f)
    f.seg = K.Segments(f, { { key = "new", text = L["Neuer Termin"] }, { key = "loot", text = L["Verteilung"] },
        { key = "plan", text = L["Aufstellung"] }, { key = "points", text = L["Punkte"] } },
        function(k) leadTab = k applyTabs() ns.RefreshPage("raidlead") end, 90, { size = 12, pad = 18 })
    f.seg:SetPoint("TOPLEFT", 0, 0)
    f.line = f:CreateTexture(nil, "ARTWORK")
    f.line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    f.line:SetHeight(1)
    f.line:SetPoint("TOPLEFT", 0, -26)
    f.line:SetPoint("TOPRIGHT", 0, -26)
    f.badge = K.Text(f, 10, C.amber, "RIGHT")
    f.badge:SetPoint("TOPRIGHT", 0, -6)
    f.badge:SetWordWrap(false)
    f.badge:SetText(L["nur fuer die Raidleitung sichtbar"])
    f.tabs = {}
    for key, builder in pairs({ new = buildForm, loot = buildLoot, points = buildPoints, plan = ns.RaidPlanner.Build }) do
        local sf = CreateFrame("Frame", nil, f)
        sf:SetPoint("TOPLEFT", 0, -34)
        sf:SetPoint("BOTTOMRIGHT")
        builder(sf)
        f.tabs[key] = sf
    end
    -- Sperren fuer Nicht-Berechtigte (Punkte: nur die Offiziers-Spalte, Rangliste bleibt lesbar)
    f.locks = {
        new = K.Lock(f.tabs.new, { who = "raidlead", check = canLead }),
        loot = K.Lock(f.tabs.loot, { who = "raidlead", check = canLead }),
        plan = K.Lock(f.tabs.plan, { who = "raidassist", check = ns.RaidPlanner.CanEdit }),
    }
end

------------------------------------------------------------------------
-- Demo: eigene Beute + eine Reservierung, damit "Meine Beute" gefuellt aussieht (nur lokal, IDs demo-*)
------------------------------------------------------------------------
function Raid.SeedLootDemo()
    if not (ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive()) then return end
    local now = ns.now()
    local function put2(coll, rec)
        rec.demo = true
        rec.u = rec.u or now
        rec.by = rec.by or ns.me()
        Store.merge(coll, rec)
    end
    local MY = {
        { "|cffa335ee|Hitem:9372::::::::|h[Sul'thraze the Lasher]|h|r", "ms", 4, 6, 12 },
        { "|cff0070dd|Hitem:7719::::::::|h[Raging Berserker's Helm]|h|r", "os", 3, 13, 9 },
        { "|cff0070dd|Hitem:10775::::::::|h[Carapace of Tuten'kash]|h|r", "tm", 3, 13, nil },
        { "|cff0070dd|Hitem:6340::::::::|h[Fenrus' Hide]|h|r", nil, 3, 20, nil },
    }
    for k, d in ipairs(MY) do
        put2("loot", { id = "demo-myloot" .. k, item = d[1], who = ns.me(), src = d[2] and "Vergabe" or "Beute", choice = d[2], roll = d[2] and (40 + k * 13) or nil,
            zone = d[2] and "Barrow Deeps" or "Burg Schattenfang", mapID = 0, ts = now - d[4] * 86400 + k * 900, quality = d[3] })
    end
    -- Reservierung fuer den naechsten Demo-Raid
    if ns.SoftRes then
        for _, ev in ipairs(Raid.Events()) do
            if tostring(ev.id):find("^demo%-") and (ev.ts or 0) > now and (ev.max or 0) >= 10 then
                local main = ns.Alts and ns.Alts.Main and ns.Alts.Main(ns.me()) or ns.me()
                put2("sres", { id = ev.id .. "@" .. main, ev = ev.id, item = 9372, who = main, char = ns.me(), ts = now - 3600 })
                break
            end
        end
    end
    ns.RefreshPage("raid")
end
ns.Listen("LOGIN", function()
    local D = ns.Demo
    if D and not D.raidLootHooked and D.Load then
        D.raidLootHooked = true
        local load = D.Load
        D.Load = function(...) load(...) Raid.SeedLootDemo() end
        if D.IsActive and D.IsActive() then ns.After(4, Raid.SeedLootDemo) end
    end
end)

ns.RegisterPage({
    key = "raid", title = "Raids", order = 5,
    sub = "Termine, Anmeldung und Raidleitung",
    build = function(p)
        pageRef = p
        p.seg = K.Segments(p, { { key = "events", text = L["Termine"] } }, function(k) Raid.SetTab(k) end, 100)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.seg:Hide()
        for _, b in ipairs(p.seg.buttons) do if b.key == "lead" then p.leadSegBtn = b end end
        if p.leadSegBtn then
            p.leadSegBtn.label:SetText("|cffe8b44a" .. L["Raidleitung"] .. "|r")
        end
        p.srBtn = K.Button(p, L["Reservierungen"] .. "  >", 150, 22, "ghost", function() ns.ShowPage("softres") end)
        p.srBtn:SetPoint("TOPRIGHT", 0, 0)
        p.srBtn:Hide()
        p.buffBtn = K.Button(p, L["Buff-Monitor"] .. "  >", 140, 22, "ghost", function() ns.ShowPage("buffs") end)
        p.buffBtn:SetPoint("RIGHT", p.srBtn, "LEFT", -6, 0)
        p.buffBtn:Hide()
        p.tabs = {}
        for key, builder in pairs({ events = buildEvents }) do
            local f = CreateFrame("Frame", nil, p)
            f:SetPoint("TOPLEFT", 0, 0)
            f:SetPoint("BOTTOMRIGHT")
            builder(f)
            p.tabs[key] = f
        end
        tab = "events"
        Raid.SetTab("events")
    end,
    refresh = function(p)
        applyTabs()
        -- schmale Seite: Buff-Monitor-Knopf weg, bevor er die Reiter ueberdeckt
        local w = p:GetWidth() or 0
        p.buffBtn:Hide()
        -- Raidleitung: Hinweis rechts nur, wenn er neben die Unter-Reiter passt
        refreshEvents(p.tabs.events)
    end,
})

------------------------------------------------------------------------
-- Raidleitung: eigene Seite (Neuer Termin | Verteilung | Aufstellung | Punkte)
------------------------------------------------------------------------
if ns.ICONS then ns.ICONS.raidlead = ns.MEDIA .. "icons\\admin" end
ns.RegisterPage({
    key = "raidlead", title = "Raidleitung", order = 5.01,
    sub = "Termine anlegen, Beute verteilen, Aufstellung und Punkte",
    build = function(p)
        leadRef = CreateFrame("Frame", nil, p)
        leadRef:SetAllPoints()
        buildLead(leadRef)
        p.lead = leadRef
        -- ganze Seite nur fuer die Raidleitung (ab Assistenz); alle anderen sehen sie gesperrt mit Schloss
        if K.Lock then
            p.rightsLock = K.Lock(p, { who = "raidassist",
                check = function() return ns.Admin and ns.Admin.CanRaidPlan and ns.Admin.CanRaidPlan() or false end })
        end
        applyTabs()
    end,
    refresh = function(p)
        if p.rightsLock then p.rightsLock:Update() end
        applyTabs()
        local ld = p.lead
        local w = p:GetWidth() or 0
        if ld.badge then
            local bw = (ld.badge.GetStringWidth and ld.badge:GetStringWidth()) or 200
            ld.badge:SetShown(w <= 0 or ((ld.seg:GetWidth() or 0) + bw + 16) <= w)
        end
        local lf = ld.tabs
        if leadTab == "new" then refreshForm(lf.new)
        elseif leadTab == "loot" then refreshLoot(lf.loot)
        elseif leadTab == "points" then refreshPoints(lf.points)
        elseif leadTab == "plan" then ns.RaidPlanner.Refresh(lf.plan) end
    end,
})
-- Raid und Raidleitung teilen Daten: eine Seite auffrischen = beide
do
    local orig = ns.RefreshPage
    ns.RefreshPage = function(k, ...)
        orig(k, ...)
        if k == "raid" then orig("raidlead") elseif k == "raidlead" then orig("raid") end
    end
end


------------------------------------------------------------------------
-- Beute: eigene Seite (Meine Beute | Beute-Log)
------------------------------------------------------------------------
if ns.ICONS then ns.ICONS.loot = ns.MEDIA .. "icons\\wants" end
ns.RegisterPage({
    key = "loot", title = "Beute", order = 5.02,
    sub = "Faire Beute: wer oft dabei ist und wenig bekommen hat, ist zuerst dran",
    build = function(p)
        p.seg = K.Segments(p, { { key = "mine", text = L["Meine Beute"] }, { key = "log", text = L["Beute-Log"] } },
            function(k) lootTab = k ns.RefreshPage("loot") end, 100)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.tabs = {}
        for key, builder in pairs({ mine = buildMine, log = buildLog }) do
            local f = CreateFrame("Frame", nil, p)
            f:SetPoint("TOPLEFT", 0, -36)
            f:SetPoint("BOTTOMRIGHT")
            builder(f)
            p.tabs[key] = f
        end
    end,
    refresh = function(p)
        p.seg:Select(lootTab)
        for k, f in pairs(p.tabs) do f:SetShown(k == lootTab) end
        if lootTab == "mine" then refreshMine(p.tabs.mine) else refreshLog(p.tabs.log) end
    end,
})
-- Beute-Daten aendern sich mit der Raid-Seite: mit auffrischen
ns.Listen("STORE", function() if ns.CurrentPage and ns.CurrentPage() == "loot" then ns.RefreshPage("loot") end end)

------------------------------------------------------------------------
-- Loot-Master-Hilfe: am Beutefenster je Item ein "Verteilen"-Knopf (fuer Anfuehrer/Assistenten)
------------------------------------------------------------------------
do
    local helper
    local function build()
        helper = CreateFrame("Frame", "OasisLootHelper", UIParent)
        helper:SetSize(230, 40)
        helper:SetFrameStrata("DIALOG")
        K.Fill(helper, { 0.04, 0.04, 0.05, 0.96 })
        K.Border(helper, C.line)
        helper.head = K.Text(helper, 10, C.amber)
        helper.head:SetPoint("TOPLEFT", 10, -8)
        helper.head:SetText(K.Upper(L["Oasis-Verteilung"]))
        helper.rows = {}
    end
    local function show()
        if ns.LootMaster then return end   -- neues Beute-Fenster (LootMaster.lua) uebernimmt
        if not (IsInGroup() and ns.isGroupLead and ns.isGroupLead()) then return end
        if ns.db and ns.db.settings.lootHelper == false then return end
        local items = {}
        local minQ = (GetLootThreshold and GetLootThreshold()) or 2
        for i = 1, (GetNumLootItems() or 0) do
            local link = GetLootSlotLink(i)
            local _, _, _, _, q = GetLootSlotInfo(i)
            if link and (tonumber(q) or 0) >= math.max(2, minQ) then items[#items + 1] = link end
        end
        if #items == 0 then return end
        if not helper then build() end
        for _, r in ipairs(helper.rows) do r:Hide() end
        for i, link in ipairs(items) do
            local r = helper.rows[i]
            if not r then
                r = CreateFrame("Frame", nil, helper)
                r:SetSize(210, 24)
                r.t = K.Text(r, 11, C.text)
                r.t:SetPoint("LEFT", 0, 0)
                r.t:SetPoint("RIGHT", -84, 0)
                r.t:SetWordWrap(false)
                r.b = K.Button(r, L["Verteilen"], 78, 20, "primary")
                r.b:SetPoint("RIGHT", 0, 0)
                helper.rows[i] = r
            end
            r:SetPoint("TOPLEFT", 10, -26 - (i - 1) * 26)
            r.t:SetText(link)
            r.b:SetScript("OnClick", function() Raid.StartSession(link) end)
            r:Show()
        end
        helper:SetHeight(34 + #items * 26)
        helper:ClearAllPoints()
        if LootFrame and LootFrame:IsShown() then helper:SetPoint("TOPLEFT", LootFrame, "TOPRIGHT", 4, 0) else helper:SetPoint("CENTER", 220, 120) end
        helper:Show()
    end
    ns.On("LOOT_OPENED", function() ns.After(0.1, function() pcall(show) end) end)
    ns.On("LOOT_CLOSED", function() if helper then helper:Hide() end end)
end
end)

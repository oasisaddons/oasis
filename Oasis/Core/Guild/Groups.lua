-- Oasis: Gruppenfinder der Gilde ("Suche Gruppe: Todesminen, brauche Heiler")
local ADDON, ns = ...
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

local Groups = {}
ns.Groups = Groups
Groups.requests = {}   -- Anfragen an meine Suche: [name] = { role, class, lvl, t, state }

local ROLES = {
    tank = { "Tank", { 0.38, 0.62, 1.00 } },
    heal = { "Heiler", { 0.40, 0.86, 0.62 } },
    dps = { "Schaden", { 1.00, 0.35, 0.30 } },
}
ns.Relabel(function()
    ROLES.tank[1], ROLES.heal[1], ROLES.dps[1] = L["Tank"], L["Heiler"], L["Schaden"]
end)
local CAN = {
    WARRIOR = { tank = true, dps = true }, PALADIN = { tank = true, heal = true, dps = true },
    DRUID = { tank = true, heal = true, dps = true }, PRIEST = { heal = true, dps = true },
    SHAMAN = { heal = true, dps = true }, HUNTER = { dps = true }, ROGUE = { dps = true },
    MAGE = { dps = true }, WARLOCK = { dps = true },
}

------------------------------------------------------------------------
-- Meine Rollen (pro Charakter, Standard nach Klasse)
------------------------------------------------------------------------
function Groups.MyRoles()
    if not ns.char.roles then
        local _, classFile = UnitClass("player")
        local can = CAN[classFile or ""] or { dps = true }
        ns.char.roles = { tank = can.tank and classFile == "WARRIOR" or false, heal = (can.heal and classFile == "PRIEST") or false, dps = not (classFile == "PRIEST") }
        if classFile == "PRIEST" then ns.char.roles.heal = true end
    end
    return ns.char.roles
end
local function roleText(r)
    local t = {}
    for _, k in ipairs({ "tank", "heal", "dps" }) do
        if r[k] then t[#t + 1] = (ns.Profile and ns.Profile.RoleIcon(k, 13) .. " " or "") .. K.hex(ROLES[k][2]) .. ROLES[k][1] .. "|r" end
    end
    return table.concat(t, "  ")
end
------------------------------------------------------------------------
-- Plaetze: feste Aufstellung 1 Tank, 1 Heiler, 3 Schaden
-- Datensatz: layout = "thddd", m = "Name:t,Name:d,..." (wer sitzt auf welchem Platz)
------------------------------------------------------------------------
local LAYOUT = "thddd"
local ROLE_OF = { t = "tank", h = "heal", d = "dps" }
local KEY_OF = { tank = "t", heal = "h", dps = "d" }

local function members(g)
    local out = {}
    for name, r in (g.m or ""):gmatch("([^:,]+):(%a)") do out[#out + 1] = { name = name, role = ROLE_OF[r] or "dps" } end
    return out
end
-- 5 Plaetze { role, who } in fester Reihenfolge
function Groups.Slots(g)
    local slots = {}
    local layout = g.layout or LAYOUT
    for i = 1, #layout do slots[i] = { role = ROLE_OF[layout:sub(i, i)] or "dps" } end
    for _, mb in ipairs(members(g)) do
        for _, s in ipairs(slots) do
            if s.role == mb.role and not s.who then s.who = mb.name break end
        end
    end
    -- Leute in der Gruppe ohne Oasis-Platz (per Hand eingeladen): freie Schadensplaetze belegen
    local extra = (g.count or 0) - #members(g)
    for _, s in ipairs(slots) do
        if extra <= 0 then break end
        if not s.who and s.role == "dps" then s.who = "?" extra = extra - 1 end
    end
    return slots
end
function Groups.FreeRoles(g)
    local free = {}
    for _, s in ipairs(Groups.Slots(g)) do if not s.who then free[s.role] = true end end
    return free
end
local function matches(g)
    local my, free = Groups.MyRoles(), Groups.FreeRoles(g)
    for k in pairs(free) do if my[k] then return true end end
    return false
end
Groups.Matches = matches

-- Datensatz neu schreiben (Belegung, freie Rollen, Zaehler)
local function rewrite(g, fn)
    local r = {}
    for k, v in pairs(g) do r[k] = v end
    fn(r)
    local mb = members(r)
    r.count = math.max(#mb, r.count or 0)
    local free = Groups.FreeRoles(r)
    r.tank, r.heal, r.dps = free.tank or false, free.heal or false, free.dps or false
    r.size = #(r.layout or LAYOUT)
    Store.Put("lfg", r)
    return r
end
local function assign(g, name, role)
    return rewrite(g, function(r)
        local list = {}
        for _, mb in ipairs(members(r)) do if mb.name ~= name then list[#list + 1] = mb.name .. ":" .. KEY_OF[mb.role] end end
        list[#list + 1] = name .. ":" .. KEY_OF[role]
        r.m = table.concat(list, ",")
    end)
end

------------------------------------------------------------------------
-- Suchen verwalten
------------------------------------------------------------------------
-- Navigation + Oasis-Leiste: Beitrittsanfragen haben Vorrang vor der Zahl offener Gruppen
function Groups.UpdateBadge()
    local reqs = 0
    if Groups.Mine() then for _, q in pairs(Groups.requests) do if q.state ~= "invited" then reqs = reqs + 1 end end end
    local n = #Groups.Active()
    ns.SetNavBadge("groups", reqs > 0 and ("!" .. reqs) or (n > 0 and tostring(n) or ""))
    if ns.UpdateMiniBar then ns.UpdateMiniBar() end
end
function Groups.Active()
    local now = ns.now()
    local out = Store.List("lfg", function(g) return g.open and (g.exp or 0) > now end)
    table.sort(out, function(a, b) return (a.u or 0) > (b.u or 0) end)
    return out
end
-- Laufende Gruppen (ohne Suchanzeige): aus den Gruppenmeldungen der Oasis-Mitglieder (Profil: gs, gnames, zone, gl).
-- Zeigt, wer gerade zusammen unterwegs ist und wo - mit dem Leiter zum Anfluestern. Eigene Gruppe und Gruppen,
-- fuer die schon eine Suchanzeige laeuft, bleiben draussen.
function Groups.Live()
    local R = ns.Radar
    if not (R and R.roster and ns.Members) then return {} end
    local now, byKey, order = ns.now(), {}, {}
    local searching = {}
    for _, g in ipairs(Groups.Active()) do searching[ns.NameKey(g.who or "")] = true end
    for _, m in ipairs(R.roster) do
        local pr = ns.db.members[m.name]
        if m.online and not ns.isMe(m.name) and pr and type(pr.gnames) == "string" and pr.gnames ~= ""
            and #pr.gnames <= 1500 and type(pr.groupSeen) == "number" and now - pr.groupSeen <= 600 then
            local keys, mine = {}, false
            for key in pr.gnames:gmatch("[^,]+") do
                if #keys < 40 and #key <= 120 and not key:find("[%c|]") then
                    key = ns.NameKey(key)
                    if ns.isMe(key) then mine = true end
                    keys[#keys + 1] = key
                end
            end
            if #keys >= 2 and not mine then
                table.sort(keys)
                local id = table.concat(keys, ",")
                local g = byKey[id]
                if not g then
                    g = { live = true, id = "live:" .. id, keys = keys, reporters = {}, u = pr.groupSeen }
                    byKey[id] = g
                    order[#order + 1] = g
                end
                g.reporters[#g.reporters + 1] = m.name
                if pr.groupSeen > g.u then g.u = pr.groupSeen end
                local kind, n = tostring(pr.gs or ""):match("^(%a)(%d+)$")
                if kind == "i" then g.inst = true g.zone = g.zone or (m.zone ~= "" and m.zone) or pr.zone end
                g.n = math.max(g.n or 0, tonumber(n) or 0, #keys)
                if pr.gl == 1 or pr.gl == "1" then g.who = m.name end
                if searching[ns.NameKey(m.name)] then g.hasAd = true end
            end
        end
    end
    -- dieselbe Gruppe kommt teils doppelt an (ein Mitglied meldet einen Namen mit anderem Realm-Anhang oder die Liste
    -- ist gerade einen Spieler kuerzer): Meldungen mit mindestens zwei gleichen Namen (ohne Realm) zusammenlegen
    local function base(k) return k:match("^(.*)%-[^%-]+$") or k end
    local merged = {}
    for _, g in ipairs(order) do
        local into
        for _, m in ipairs(merged) do
            local same = 0
            for _, k in ipairs(g.keys) do if m.bases[base(k)] then same = same + 1 end end
            if same >= 2 then into = m break end
        end
        if not into then
            g.bases = {}
            for _, k in ipairs(g.keys) do g.bases[base(k)] = true end
            merged[#merged + 1] = g
        else
            for _, k in ipairs(g.keys) do
                if not into.bases[base(k)] then into.bases[base(k)] = true into.keys[#into.keys + 1] = k end
            end
            for _, r in ipairs(g.reporters) do into.reporters[#into.reporters + 1] = r end
            if g.u > into.u then into.u = g.u end
            into.inst = into.inst or g.inst
            into.zone = into.zone or g.zone
            into.n = math.max(into.n or 0, g.n or 0, #into.keys)
            into.who = into.who or g.who
            into.hasAd = into.hasAd or g.hasAd
        end
    end
    order = merged
    local out = {}
    for _, g in ipairs(order) do
        if not g.hasAd then
            table.sort(g.keys)
            table.sort(g.reporters)
            g.leaderKnown = g.who ~= nil
            g.who = g.who or g.reporters[1]
            g.zone = g.zone or ""
            g.title = g.zone ~= "" and g.zone or L["Gruppe unterwegs"]
            out[#out + 1] = g
        end
    end
    table.sort(out, function(a, b)
        if (a.inst and 1 or 0) ~= (b.inst and 1 or 0) then return a.inst and true or false end
        return a.id < b.id
    end)
    return out
end
-- neue Gruppenmeldung eines Mitglieds: Gruppen-Seite nachziehen (gebuendelt)
ns.Listen("PROFILE", function() if ns.Debounce then ns.Debounce("groupsLive", 2, function() ns.RefreshPage("groups") end) end end)
function Groups.Mine()
    local g = Store.Get("lfg", "lfg-" .. ns.short(ns.me()))
    if g and g.open and not g.del and (g.exp or 0) > ns.now() then return g end
end

local function groupSize()
    local n = GetNumGroupMembers()
    return (n and n > 0) and n or 1
end

-- Gilden-Optionen (Gildenleitung): wer darf Suchen starten, wie lange laufen sie
ns.GuildOption({ page = "groups", key = "grRank", default = 10, min = 1, max = 10, step = 1,
    label = "Suche starten ab Rang", desc = "Nur Mitglieder bis zu diesem Rang duerfen eine Gruppensuche starten (10 = alle).",
    fmt = function(v) return (L["bis Rang %d"]):format(v) end })
ns.GuildOption({ page = "groups", key = "grDur", default = 45, min = 15, max = 120, step = 5,
    label = "Laufzeit einer Suche", desc = "Nach dieser Zeit verschwindet eine offene Gruppensuche automatisch.",
    fmt = function(v) return v .. " Min" end })
local function rankAllowed(limit)
    if not limit or limit >= 10 then return true end
    if ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage() then return true end
    local ri = ns.Admin and ns.Admin.RankOf and ns.Admin.RankOf(ns.me())
    return ri == nil or ri < limit
end

-- in einer Gruppe darf nur der Leiter eine Suche starten
function Groups.CanStart()
    if IsInGroup and IsInGroup() and UnitIsGroupLeader and not UnitIsGroupLeader("player") then return false end
    return true
end
function Groups.Start(title, myRole, auto, note, voice)
    if not Groups.CanStart() then ns.print(L["Nur der Gruppenleiter kann eine Suche starten."]) return end
    if not rankAllowed(tonumber(ns.GuildOpt("grRank"))) then ns.print(L["Die Gildenleitung erlaubt Gruppensuchen erst ab einem hoeheren Rang."]) return end
    if not title or title == "" then ns.print(L["Bitte eine Aktivitaet angeben (z.B. Todesminen)."]) return end
    if ns.Badges then ns.Badges.Add("lfgStarted", 1) end
    Groups.weekStart = GetTime()   -- Woche zaehlt erst, wenn ein Gildenmitglied wirklich beitritt
    local _, classFile = UnitClass("player")
    local rec = {
        id = "lfg-" .. ns.short(ns.me()), who = ns.me(), title = title, note = note or "", started = ns.now(),
        layout = LAYOUT, m = ns.me() .. ":" .. KEY_OF[myRole or "dps"],
        count = groupSize(), auto = auto and true or false, open = true, voice = voice and true or false,
        lvl = ns.safe(UnitLevel("player")) or 0, class = classFile or "", exp = ns.now() + (tonumber(ns.GuildOpt("grDur")) or 45) * 60,
    }
    wipe(Groups.requests)
    rewrite(rec, function() end)
    K.Toast(L["Suche gestartet"], title .. L[" - die Gilde wird benachrichtigt."], C.accent)
end
function Groups.Stop()
    if Groups.joined then wipe(Groups.joined) end
    local g = Groups.Mine()
    if not g then return end
    rewrite(g, function(r) r.open = false end)
    wipe(Groups.requests)
end
-- Gruppe aendert sich: Weggegangene frei machen, volle Gruppe beenden
local function inMyGroup(name)
    if ns.isMe(name) then return true end
    local short = ns.short(name)
    return (UnitInParty and UnitInParty(short)) or (UnitInRaid and UnitInRaid(short)) or false
end
local function updateCount()
    local g = Groups.Mine()
    if not g then return end
    local n = groupSize()
    local keep, changed = {}, false
    for _, mb in ipairs(members(g)) do
        -- Eingeladene zaehlen noch 2 Minuten, auch wenn sie noch nicht angenommen haben
        local q = Groups.requests[mb.name]
        local pending = q and q.state == "invited" and ns.now() - (q.t or 0) < 120
        if inMyGroup(mb.name) or pending then keep[#keep + 1] = mb.name .. ":" .. KEY_OF[mb.role] else changed = true end
    end
    if n >= 5 then
        Groups.Stop()
        K.Toast(L["Gruppe voll"], g.title .. L[" - Suche beendet."], C.mint)
    elseif changed or n ~= g.count then
        rewrite(g, function(r) r.m = table.concat(keep, ",") r.count = n end)
    end
end
ns.On("GROUP_ROSTER_UPDATE", function() ns.After(1, updateCount) end)

------------------------------------------------------------------------
-- Platz anklicken: Anfrage an den Suchenden, der laedt (automatisch) ein
------------------------------------------------------------------------
local function gkey(g) return (g.id or "?") .. "@" .. tostring(g.started or 0) end
Groups.Key = gkey
function Groups.Join(g, role)
    if ns.isMe(g.who) then return end
    role = role or "dps"
    if ns.Badges then ns.Badges.Add("joined", 1) end
    Groups.weekJoin = { who = g.who, t = GetTime() }   -- Woche zaehlt erst, wenn man wirklich in der Gruppe ist
    local _, classFile = UnitClass("player")
    local lvl = ns.safe(UnitLevel("player")) or 0
    local mp = ns.Radar and ns.Radar.myProfile and ns.Radar.myProfile()
    local ilvl = mp and tonumber(mp.ilvl) or 0
    Comm.Whisper(g.who, "JOIN", g.id, role, classFile or "", lvl, ilvl)
    -- zusaetzlich ueber die Gilden-Ablage: kommt auch an, wenn das Fluestern verloren geht
    if ns.Store then
        ns.Store.Put("lfgreq", { id = g.id .. ":" .. ns.short(ns.me()), gid = g.id, gst = g.started or 0, role = role, class = classFile or "",
            lvl = lvl, ilvl = ilvl, t = ns.now() })
    end
    Groups.joined = Groups.joined or {}
    Groups.joined[gkey(g)] = { t = GetTime(), role = role }
    K.Toast(L["Anfrage geschickt"], ns.displayName(g.who) .. " - " .. g.title .. L[" als "] .. ROLES[role][1], C.accent)
    Groups.UpdateBadge()
    ns.RefreshPage("groups")
end
function Groups.MyRequest(g)
    local j = Groups.joined and Groups.joined[gkey(g)]
    if j and GetTime() - j.t < 120 then return j.role end
end

local function invite(name)
    if not C_PartyInfo or not C_PartyInfo.InviteUnit then return false end
    if groupSize() >= 5 and not IsInRaid() and C_PartyInfo.ConvertToRaid then C_PartyInfo.ConvertToRaid() end
    local ok = pcall(C_PartyInfo.InviteUnit, ns.ChatName(name))
    return ok
end
function Groups.Invite(name)
    local r = Groups.requests[name]
    local g = Groups.Mine()
    if not r or not g then return end
    if not Groups.FreeRoles(g)[r.role] then
        ns.print((L["Kein freier Platz mehr fuer %s."]):format(ROLES[r.role] and ROLES[r.role][1] or r.role))
        return
    end
    if invite(name) then
        r.state, r.t = "invited", ns.now()
        assign(g, name, r.role)
    end
    ns.RefreshPage("groups")
end
function Groups.Decline(name)
    local g = Groups.Mine()
    Groups.requests[name] = nil
    if g then Comm.Whisper(name, "JOINNO", g.id) end
    ns.RefreshPage("groups")
end

local function onJoin(sender, id, role, classFile, lvl, ilvl)
    local g = Groups.Mine()
    if not g or g.id ~= id then return end
    -- Anfrage-Flut je Absender drosseln, Felder begrenzen
    if not SEC.Rate("join:" .. tostring(sender), 4) then return end
    classFile = tostring(classFile or ""):match("^%u+$") and #classFile <= 16 and classFile or nil
    lvl = SEC.Num(lvl, 0, 200, true) or 0
    ilvl = SEC.Num(ilvl, 0, 2000, true) or 0
    -- eine Person = ein Eintrag, egal in welcher Namensform sie ankommt ("Anna" / "Anna Berg")
    sender = (ns.Alts and ns.Alts.Canon) and ns.Alts.Canon(sender) or sender
    for n in pairs(Groups.requests) do
        if n ~= sender and Comm.whoKey(n) == Comm.whoKey(sender) then
            Groups.requests[sender] = Groups.requests[n]
            Groups.requests[n] = nil
        end
    end
    -- schon bekannt (kam doppelt: Fluestern + Ablage)
    local old = Groups.requests[sender]
    if old and old.role == role and ns.now() - (old.t or 0) < 120 then return end
    role = ROLES[role] and role or "dps"
    if not Groups.FreeRoles(g)[role] then
        Comm.Whisper(sender, "JOINNO", g.id)
        return
    end
    Groups.requests[sender] = { role = role, class = classFile, lvl = tonumber(lvl) or 0, ilvl = tonumber(ilvl) or 0, t = ns.now(), state = "new" }
    if g.auto then
        Groups.Invite(sender)
        ns.Sound.Next("request")
        K.Toast(ns.displayName(sender) .. L[" kommt mit"], ROLES[role][1] .. L[" - eingeladen"], C.mint)
    else
        ns.Sound.Next("request")
        K.Toast(ns.displayName(sender) .. L[" moechte mit"], ROLES[role][1] .. L[" - Level "] .. (lvl or "?")
            .. ((tonumber(ilvl) or 0) > 0 and ("  ·  " .. L["Gear"] .. " " .. ilvl) or "") .. "  -  " .. L["Klick: einladen"], C.amber,
            function() Groups.Invite(sender) ns.ShowPage("groups") end)
    end
    Groups.UpdateBadge()
    ns.RefreshPage("groups")
end
Comm.On("JOIN", function(sender, _, id, role, classFile, lvl, ilvl) onJoin(sender, id, role, classFile, lvl, ilvl) end)

------------------------------------------------------------------------
-- Zusammenfuehren: zwei Suchen fuer dasselbe Ziel, deren Rollen zusammenpassen
------------------------------------------------------------------------
local function sameTarget(a, b)
    if not (a and b and a.title and b.title) then return false end
    local na, nb = a.title:lower():gsub("%s+", ""), b.title:lower():gsub("%s+", "")
    if na == nb then return true end
    local da = ns.Dungeons and ns.Dungeons.Match(a.title)
    local db = ns.Dungeons and ns.Dungeons.Match(b.title)
    return da and db and da.key == db.key or false
end
-- passen alle Leute aus "from" in die freien Plaetze von "into"?
function Groups.CanMerge(from, into)
    if not (from and into) or from.id == into.id or not sameTarget(from, into) then return false end
    local need, open = { tank = 0, heal = 0, dps = 0 }, { tank = 0, heal = 0, dps = 0 }
    for _, sl in ipairs(Groups.Slots(from)) do if sl.who then need[sl.role] = need[sl.role] + 1 end end
    for _, sl in ipairs(Groups.Slots(into)) do if not sl.who then open[sl.role] = open[sl.role] + 1 end end
    for k, n in pairs(need) do
        if n > open[k] then
            -- ueberzaehlige Schadens-/Rollenplaetze duerfen nicht auf Tank/Heiler ausweichen
            return false
        end
    end
    return true
end
function Groups.RequestMerge(into)
    local mine = Groups.Mine()
    if not Groups.CanMerge(mine, into) then return end
    Comm.Whisper(into.who, "MERGE", into.id, mine.m or "", mine.title or "")
    if ns.Store then
        ns.Store.Put("lfgreq", { id = into.id .. ":merge:" .. ns.short(ns.me()), gid = into.id, gst = into.started or 0,
            merge = mine.m or "", t = ns.now() })
    end
    Groups.mergeAsked = into.id
    K.Toast(L["Zusammenfuehren angefragt"], (L["%s bekommt deine Anfrage"]):format(ns.displayName(into.who)), C.accent)
    ns.RefreshPage("groups")
end
-- Zusammenfuehren-Liste pruefen: nur Leute, die wirklich in der (geteilten) Suche des Absenders sitzen,
-- hoechstens 4 - sonst koennte jeder mein Spiel beliebige Spieler einladen lassen
local function mergeList(sender, m)
    local theirs = Store.Get("lfg", "lfg-" .. ns.short(sender or ""))
    if not theirs or theirs.del or not theirs.open or not theirs.who or Comm.whoKey(theirs.who) ~= Comm.whoKey(sender) then return nil end
    local known = {}
    for _, mb in ipairs(members(theirs)) do known[Comm.whoKey(mb.name)] = true end
    local list = {}
    for name, r in tostring(m or ""):sub(1, 400):gmatch("([^:,]+):(%a)") do
        if #list >= 4 then break end
        if SEC.Name(name) and known[Comm.whoKey(name)] then list[#list + 1] = { name = name, role = ROLE_OF[r] or "dps" } end
    end
    return list
end
local function doMerge(sender, m)
    local g = Groups.Mine()
    if not g then return end
    local list = mergeList(sender, m)
    if not list then return end
    for _, x in ipairs(list) do
        if not ns.isMe(x.name) then
            g = assign(Groups.Mine() or g, x.name, x.role)
            local n = x.name
            invite(n)
            -- nur EIN zweiter Versuch, mit Zeit zum Annehmen: nach 30 s, falls noch nicht in der Gruppe
            -- (z.B. musste er erst seine alte Gruppe verlassen)
            ns.After(30, function()
                local cn = ns.ChatName(n)
                if not (UnitInParty and (UnitInParty(cn) or UnitInRaid(cn))) then invite(n) end
            end)
        end
    end
    Comm.Whisper(sender, "MERGEOK", g.id)
    K.Toast(L["Gruppen zusammengefuehrt"], (L["%d Spieler werden eingeladen"]):format(#list), C.mint)
    ns.RefreshPage("groups")
end
local function onMerge(sender, id, m, title)
    local g = Groups.Mine()
    if not g or g.id ~= id then return end
    if Groups.mergeFrom == sender and ns.now() - (Groups.mergeT or 0) < 60 then return end
    local list = mergeList(sender, m)
    if not list or #list == 0 then return end
    Groups.mergeFrom, Groups.mergeT = sender, ns.now()
    local n = #list
    ns.Sound.Next("request")
    if g.auto then
        doMerge(sender, m)
    else
        K.Toast((L["%s will zusammenfuehren"]):format(ns.displayName(sender)), (L["%d Spieler - Klick: alle einladen"]):format(n), C.amber,
            function() doMerge(sender, m) end)
    end
end
Comm.On("MERGE", function(sender, _, id, m, title) onMerge(sender, id, m, title) end)
Comm.On("MERGEOK", function(sender)
    -- meine Suche ist in der anderen aufgegangen - nur, wenn ich genau dort angefragt habe
    local asked = Groups.mergeAsked and Store.Get("lfg", Groups.mergeAsked)
    if not asked or not asked.who or Comm.whoKey(asked.who) ~= Comm.whoKey(sender) then return end
    if Groups.Mine() then Groups.Stop() end
    Groups.mergeAsked = nil
    K.Toast(L["Zusammenfuehren bestaetigt"], (L["%s laedt euch ein - ggf. vorher eure Gruppe verlassen"]):format(ns.displayName(sender)), C.mint)
end)
ns.Listen("STORE", function(coll, rec)
    if coll ~= "lfgreq" or not rec or rec.del or not rec.by or ns.isMe(rec.by) then return end
    if ns.now() - (rec.t or 0) > 300 then return end
    -- Anfrage im Namen eines anderen? (Ersteller muss der letzte Bearbeiter sein)
    if not rec.mb or Comm.whoKey(rec.mb) ~= Comm.whoKey(rec.by) then return end
    local g = Groups.Mine()
    if not g or (rec.gst or 0) ~= (g.started or 0) then return end
    if rec.merge then onMerge(rec.by, rec.gid, rec.merge) return end
    onJoin(rec.by, rec.gid, rec.role, rec.class, rec.lvl, rec.ilvl)
end)
Comm.On("JOINNO", function(sender)
    -- nur, wenn ich bei diesem Absender wirklich angefragt habe
    local asked = false
    if Groups.joined then for id in pairs(Groups.joined) do if id:find(ns.short(sender), 1, true) then asked = true end end end
    if not asked or not SEC.Rate("joinno:" .. sender, 10) then return end
    K.Toast(ns.displayName(sender) .. L[" hat gerade keinen Platz"], L["Probier eine andere Gruppe."], C.dim)
    if Groups.joined then for id in pairs(Groups.joined) do if id:find(ns.short(sender), 1, true) then Groups.joined[id] = nil end end end
    ns.RefreshPage("groups")
end)

-- neue Suche mit freiem Platz fuer meine Rolle -> Hinweis, Klick = Seite oeffnen
ns.Listen("STORE", function(coll, rec, old)
    if coll ~= "lfg" then return end
    if rec.open and not rec.del and not ns.isMe(rec.who) and (not old or not old.open)
        and (matches(rec) or ns.db.settings.lfgAllRoles) and (ns.db.settings.lfgInInstance or not ns.inInstance())
        and SEC.Name(rec.who) and SEC.Rate("lfgtoast:" .. rec.who, 60) then
        local free = {}
        for _, k in ipairs({ "tank", "heal", "dps" }) do if rec[k] then free[#free + 1] = ns.Profile and ns.Profile.RoleIcon(k, 13) or ROLES[k][1] end end
        ns.Sound.Next("group")
        K.Toast(ns.displayName(rec.who) .. L[" sucht: "] .. SEC.Text(rec.title or "?", 60), L["Frei: "] .. table.concat(free, " ") .. L["  -  Klick: Platz aussuchen"], C.accent,
            function() ns.ShowPage("groups") end)
    end
    Groups.UpdateBadge()
    ns.RefreshPage("groups")
end)

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local myRole
local autoInvite = true
local pickTitle

local function roleColor(k) return ns.Profile and ns.Profile.ROLE_COLORS[k] or C.muted end
local function roleTex(k) return ns.Profile and ns.Profile.RoleTexture(k) or nil end
local function defaultRole()
    local my = Groups.MyRoles()
    for _, k in ipairs({ "tank", "heal", "dps" }) do if my[k] then return k end end
    return "dps"
end

-- Platz-Knopf: frei = farbiges Rollensymbol (klickbar), besetzt = grau mit Name im Tooltip
local function makeSlots(parent, size, onClick)
    local slots = {}
    for i = 1, 5 do
        local s = CreateFrame("Button", nil, parent)
        s:SetSize(size, size)
        s.bg = K.Fill(s, C.field)
        K.Border(s, C.line)
        s.icon = s:CreateTexture(nil, "ARTWORK")
        s.icon:SetPoint("CENTER")
        s.icon:SetSize(size - 10, size - 10)
        s.hl = s:CreateTexture(nil, "HIGHLIGHT")
        s.hl:SetAllPoints()
        s.hl:SetColorTexture(1, 1, 1, 0.08)
        s.plus = K.Title(s, 12, C.text, "CENTER")
        s.plus:SetPoint("TOPRIGHT", -1, 1)
        s:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
        s:SetScript("OnLeave", function() GameTooltip:Hide() end)
        s:SetScript("OnClick", function(self) if self.free and onClick then onClick(self) end end)
        slots[i] = s
    end
    return slots
end
local function drawSlots(slots, g, clickable)
    local pending = Groups.MyRequest(g)
    local my = Groups.MyRoles()
    for i, s in ipairs(slots) do
        local slot = Groups.Slots(g)[i]
        if not slot then s:Hide() else
            s:Show()
            s.role, s.group = slot.role, g
            local c = roleColor(slot.role)
            s.icon:SetTexture(roleTex(slot.role))
            s.plus:SetText("")
            if slot.who then
                s.free = false
                s.icon:SetVertexColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
                s.bg:SetColorTexture(0.10, 0.10, 0.11, 1)
                K.SetBorderColor(s, C.line)
                s.tip = { ROLES[slot.role][1], slot.who == "?" and L["besetzt"] or ns.Radar.Colored(slot.who) }
            else
                s.free = clickable and not pending
                s.plus:SetText(pending == slot.role and "|cffff1200...|r" or "+")
                s.icon:SetVertexColor(c[1], c[2], c[3])
                s.bg:SetColorTexture(c[1] * 0.14, c[2] * 0.14, c[3] * 0.14, 1)
                K.SetBorderColor(s, (pending == slot.role) and C.accent or c)
                if pending == slot.role then
                    s.tip = { ROLES[slot.role][1], "|cffff1200" .. L["Angefragt - warte auf Einladung"] .. "|r" }
                elseif clickable then
                    s.tip = { (L["Klick: als %s mitkommen"]):format(ROLES[slot.role][1]),
                        my[slot.role] and L["Passt zu deinen Rollen."] or ("|cffe8b44a" .. L["Spielst du sonst nicht - geht trotzdem."] .. "|r") }
                else
                    s.tip = { ROLES[slot.role][1], L["frei"] }
                end
            end
            s:SetAlpha((pending and pending ~= slot.role and not slot.who) and 0.5 or 1)
        end
    end
end

-- grosser Rollen-Schalter (Symbol + Name)
local function roleToggle(parent, k, w, h, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = K.Fill(b, C.raised)
    K.Border(b, C.line)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(roleTex(k))
    -- Symbol oben, Beschriftung darunter - ohne Ueberlappung
    local is = math.max(16, h - 26)
    b.icon:SetSize(is, is)
    b.icon:SetPoint("TOP", 0, -6)
    b.text = K.Text(b, 11, C.muted, "CENTER")
    b.text:SetPoint("BOTTOM", 0, 5)
    b.text:SetText(ROLES[k][1])
    function b:Refresh()
        local on = get()
        local c = roleColor(k)
        self.icon:SetVertexColor(on and c[1] or 0.35, on and c[2] or 0.35, on and c[3] or 0.37)
        K.SetBorderColor(self, on and c or C.line)
        self.bg:SetColorTexture(on and c[1] * 0.18 or C.raised[1], on and c[2] * 0.18 or C.raised[2], on and c[3] * 0.18 or C.raised[3], 1)
        self.text:SetTextColor(unpack(on and C.text or C.muted))
    end
    b:SetScript("OnClick", function(self) set(not get()) self:Refresh() end)
    b:Refresh()
    return b
end

-- passende Ziele fuer mein Level
-- kleines Bild je Dungeon (Blizzards Gruppensuche-Symbole), sonst Karte; Questen = Buch
local DIMG = { { "ragefire", "RagefireChasm" }, { "wailing", "WailingCaverns" }, { "deadmines", "Deadmines" },
    { "shadowfang", "ShadowfangKeep" }, { "blackfathom", "BlackfathomDeeps" }, { "stockade", "StormwindStockades" },
    { "gnomeregan", "Gnomeregan" }, { "kraul", "RazorfenKraul" }, { "downs", "RazorfenDowns" }, { "scarlet", "ScarletMonastery" },
    { "uldaman", "Uldaman" }, { "zul'farrak", "ZulFarak" }, { "zulfarrak", "ZulFarak" }, { "maraudon", "Maraudon" },
    { "sunken", "SunkenTemple" }, { "blackrock depths", "BlackrockDepths" }, { "dire maul", "DireMaul" },
    { "scholomance", "Scholomance" }, { "stratholme", "Stratholme" },
    -- Forever-Instanzen ohne eigenes Symbol: passendes Bild leihen (Zwergenhallen / zerstoertes Lordaeron)
    { "thanes", "Uldaman" }, { "lordaeron", "Stratholme" } }
local function dungeonImage(d)
    local n = ((d and (d.nameEN or d.name)) or ""):lower()
    for _, x in ipairs(DIMG) do
        if n:find(x[1], 1, true) then return "Interface\\LFGFrame\\LFGIcon-" .. x[2] end
    end
    return "Interface\\Icons\\INV_Misc_Map_01"
end
-- Ziel-Liste fuer die Karten: "fit" = nur dein Levelbereich, "all" = alle offenen Instanzen; dazu Questen in der Zone
-- fit: good = Level passt, edge = knapp darunter/darueber, off = zu niedrig/hoch
local function fitOf(d, lvl)
    if not d or not d.lo then return "good" end
    local hi = d.hi or d.lo
    if lvl >= d.lo and lvl <= hi then return "good" end
    if lvl >= d.lo - 3 and lvl <= hi + 2 then return "edge" end
    return "off"
end
local function targetList(mode)
    local out = {}
    local lvl = ns.safe(UnitLevel("player")) or 0
    if ns.Dungeons and ns.Dungeons.List then
        local list = {}
        for _, d in ipairs(ns.Dungeons and ns.Dungeons.List() or {}) do
            if not d.closed and d.name then
                local f = fitOf(d, lvl)
                if mode == "all" or f ~= "off" then list[#list + 1] = { d = d, fit = f } end
            end
        end
        table.sort(list, function(a, b) return (a.d.lo or 0) < (b.d.lo or 0) end)
        local bestI, bestD
        for i, x in ipairs(list) do
            if x.fit == "good" and x.d.lo then
                local mid = (x.d.lo + (x.d.hi or x.d.lo)) / 2
                local dd = math.abs(mid - lvl)
                if not bestD or dd < bestD then bestD, bestI = dd, i end
            end
        end
        for i, x in ipairs(list) do
            out[#out + 1] = { text = x.d.name, sub = x.d.level, img = dungeonImage(x.d), fit = x.fit, best = (i == bestI) or nil }
        end
    end
    local zone = ns.safe(GetRealZoneText()) or ""
    if zone ~= "" then out[#out + 1] = { text = (L["Questen in %s"]):format(zone), img = "Interface\\Icons\\INV_Misc_Book_08", fit = "good", quest = true } end
    return out
end

-- Optik wie Dashboard/Legacy: Verlauf, Glow, gestaffeltes Einblenden
local EMBER = ns.MEDIA .. "ember"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local FITC = { good = C.mint, edge = C.amber, off = C.dim }
local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
local function grad(tex, dir, c, a1, a2)
    if not K.Gradient(tex, dir, { c[1], c[2], c[3], a1 }, { c[1], c[2], c[3], a2 }) then
        tex:SetColorTexture(c[1], c[2], c[3], (a1 + a2) / 2)
    end
end
local function rise(f, delay)
    if not f then return end
    if not animOn() then f:SetAlpha(1) return end
    f:SetAlpha(0)
    K.Tween(f, 0.3, function(q) f:SetAlpha(q) end, function() f:SetAlpha(1) end, delay)
    ns.After((delay or 0) + 1, function() if (f:GetAlpha() or 1) < 1 then f:SetAlpha(1) end end)
end
-- Hover: Verlauf von unten weich ein-/ausblenden
local function hoverGlow(f, c)
    f.hov = f:CreateTexture(nil, "BORDER", nil, 3)
    f.hov:SetPoint("TOPLEFT", 1, -1)
    f.hov:SetPoint("BOTTOMRIGHT", -1, 1)
    grad(f.hov, "VERTICAL", c or C.accent, 0.20, 0)
    f.hov:SetAlpha(0)
    local function go(on)
        local a0, a1 = f.hov:GetAlpha() or 0, on and 1 or 0
        if animOn() then K.Tween(f.hov, 0.16, function(q) f.hov:SetAlpha(a0 + (a1 - a0) * q) end)
        else f.hov:SetAlpha(a1) end
    end
    f:HookScript("OnEnter", function() go(true) end)
    f:HookScript("OnLeave", function() go(false) end)
end
-- Glanz einmal ueber einen Knopf ziehen
local function sweep(f, delay)
    if not animOn() or not f.sweep then return end
    local w = f:GetWidth() or 200
    if w < 40 then w = 200 end
    K.Tween(f.sweep, 0.7, function(q)
        f.sweep:ClearAllPoints()
        f.sweep:SetPoint("CENTER", f, "LEFT", 20 + (w - 40) * q, 0)
        f.sweep:SetAlpha(0.6 * math.sin(q * math.pi))
    end, function() f.sweep:SetAlpha(0) end, delay)
end
-- Instanz-Bild: rechts als blasser Ausschnitt, links ins Panel ausgeblendet
local function artStrip(f, w, layerColor)
    f.art = f:CreateTexture(nil, "BORDER", nil, 1)
    f.art:SetPoint("TOPRIGHT", -1, -1)
    f.art:SetPoint("BOTTOMRIGHT", -1, 1)
    f.art:SetWidth(w)
    f.art:SetTexCoord(0.12, 0.88, 0.36, 0.64)
    f.art:SetAlpha(0.28)
    f.artFade = f:CreateTexture(nil, "BORDER", nil, 2)
    f.artFade:SetAllPoints(f.art)
    local c = layerColor or C.raised
    if not K.Gradient(f.artFade, "HORIZONTAL", { c[1], c[2], c[3], 1 }, { c[1], c[2], c[3], 0 }) then f.artFade:Hide() end
end

-- Ziel-Karte: Symbol, Name, Stufenband (Farbe nach eigenem Level), Auswahl-Markierung
local function makeCard(parent, onPick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(32)
    b.bg = K.Fill(b, C.raised)
    K.Border(b, C.line)
    artStrip(b, 120)
    b.art:SetAlpha(0.10)
    b.artFade:Hide()
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(b, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 9) end
    b.band = b:CreateTexture(nil, "ARTWORK")
    b.band:SetPoint("TOPLEFT", 1, -1)
    b.band:SetPoint("BOTTOMLEFT", 1, 1)
    b.band:SetWidth(3)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(24, 24)
    b.icon:SetPoint("LEFT", 9, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.pill = CreateFrame("Frame", nil, b)
    b.pill:SetSize(48, 16)
    b.pill:SetPoint("RIGHT", -8, 0)
    b.pill.bg = K.Fill(b.pill, C.field)
    b.pill.bg:Hide()
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(b.pill, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.08 }, 8) end
    -- "Empfohlen": bester Dungeon fuer dein Level
    b.rec = K.Text(b, 9, C.amber, "RIGHT")
    b.rec:SetPoint("RIGHT", b.pill, "LEFT", -6, 0)
    b.rec:SetText(L["empfohlen"])
    b.rec:Hide()
    b.pill.t = K.Text(b.pill, 10, C.muted, "CENTER")
    K.CenterNum(b.pill.t, b.pill, "CENTER", 0, 0)
    b.check = b:CreateTexture(nil, "OVERLAY")
    b.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.check:SetSize(18, 18)
    b.check:SetPoint("RIGHT", b.pill, "LEFT", -2, 0)
    b.check:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    b.name = K.Text(b, 12, C.text)
    b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.name:SetPoint("RIGHT", b.check, "LEFT", -2, 0)
    b:SetScript("OnEnter", function(self)
        if self.tip then K.ShowTip(self, self.tip) end
        if not self.on then if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(self, { 1, 1, 1, 0.06 }, { 1, 1, 1, 0.14 }, 9) end end
    end)
    b:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if not self.on then if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(self, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 9) end end
    end)
    b:SetScript("OnClick", function(self) if onPick and self.value then onPick(self.value) end end)
    function b:Fill(s, on)
        self.value = s.text
        self.on = on and true or false
        self.icon:SetTexture(s.img or "Interface\\Icons\\INV_Misc_Map_01")
        self.art:SetTexture(s.img or "Interface\\Icons\\INV_Misc_Map_01")
        local fc = FITC[s.fit or "good"] or C.muted
        self.band:SetColorTexture(fc[1], fc[2], fc[3], 0)
        self.name:SetText(s.text or "?")
        self.name:SetTextColor(unpack((on or s.fit ~= "off") and C.text or C.muted))
        self.pill:SetShown(s.sub ~= nil and s.sub ~= "")
        self.pill.t:SetText(s.sub or "")
        self.pill.t:SetTextColor(fc[1], fc[2], fc[3])
        self.check:SetShown(self.on)
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(self, on and { C.accent[1], C.accent[2], C.accent[3], 0.12 } or { 1, 1, 1, 0.03 }, on and { C.accent[1], C.accent[2], C.accent[3], 0.75 } or { 1, 1, 1, 0.08 }, 9) end
        self.rec:SetShown(s.best and not on and true or false)
        if self.icon.SetDesaturated then self.icon:SetDesaturated(s.fit == "off" and not on) end
        self.tip = { s.text or "?" }
        if s.sub and s.sub ~= "" then self.tip[#self.tip + 1] = (L["Stufe %s"]):format(s.sub) end
        if not s.quest then
            self.tip[#self.tip + 1] = K.hex(fc) .. (s.fit == "good" and L["Passt zu deinem Level"]
                or s.fit == "edge" and L["Grenzwertig fuer dein Level"] or L["Nicht dein Levelbereich"]) .. "|r"
        end
        self.tip[#self.tip + 1] = "|cff777777" .. L["Klick: als Ziel waehlen"] .. "|r"
    end
    return b
end

-- Rollen-Kachel: grosses Symbol, aktive Rolle leuchtet in Rollenfarbe
local function roleTile(parent, k, onPick)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(48)
    local c = roleColor(k)
    b.bg = K.Fill(b, C.raised)
    K.Border(b, C.line)
    if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(b, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 10) end
    b.grad = b:CreateTexture(nil, "BORDER", nil, 1)
    b.grad:Hide()
    b.glow = b:CreateTexture(nil, "BORDER", nil, 2)
    b.glow:SetTexture(EMBER)
    b.glow:SetBlendMode("ADD")
    b.glow:SetSize(64, 64)
    b.glow:SetVertexColor(c[1], c[2], c[3])
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetTexture(roleTex(k))
    b.icon:SetSize(24, 24)
    b.icon:SetPoint("TOP", 0, -5)
    b.glow:SetPoint("CENTER", b.icon)
    b.text = K.Text(b, 11, C.muted, "CENTER")
    b.text:SetPoint("BOTTOM", 0, 5)
    b.text:SetText(ROLES[k][1])
    b:SetScript("OnEnter", function(self)
        K.ShowTip(self, { ROLES[k][1], L["Klick: mit dieser Rolle starten (stellt auch deine Gruppenrolle um)"] })
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function() onPick(k) end)
    function b:Refresh()
        local on = Groups.MyRoles()[k] and true or false
        local was = self.on
        self.on = on
        self.icon:SetVertexColor(on and c[1] or 0.42, on and c[2] or 0.42, on and c[3] or 0.44)
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(self, on and { c[1], c[2], c[3], 0.12 } or { 1, 1, 1, 0.03 }, on and { c[1], c[2], c[3], 0.75 } or { 1, 1, 1, 0.08 }, 10) end
        self.grad:Hide()
        self.glow:Hide()
        self.text:SetTextColor(unpack(on and c or C.muted))
        if on and was == false and animOn() then
            K.Tween(self.glow, 0.45, function(q) self.glow:SetAlpha(0.9 - 0.4 * q) self.glow:SetSize(40 + 24 * q, 40 + 24 * q) end,
                function() self.glow:SetAlpha(0.5) self.glow:SetSize(64, 64) end)
        elseif not animOn() or was == nil then
            self.glow:SetAlpha(0.5)
        end
    end
    return b
end

-- Schritt-Kreis (1 Ziel, 2 Rolle, 3 Los)
local function stepDot(parent, n, label)
    local s = CreateFrame("Frame", nil, parent)
    s:SetSize(22, 22)
    s.glow = s:CreateTexture(nil, "BACKGROUND")
    s.glow:SetTexture(EMBER)
    s.glow:SetBlendMode("ADD")
    s.glow:SetSize(46, 46)
    s.glow:SetPoint("CENTER")
    s.glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    s.glow:SetAlpha(0)
    s.ring = s:CreateTexture(nil, "BORDER")
    s.ring:SetTexture(CIRCLE)
    s.ring:SetAllPoints()
    s.core = s:CreateTexture(nil, "ARTWORK")
    s.core:SetTexture(CIRCLE)
    s.core:SetSize(18, 18)
    s.core:SetPoint("CENTER")
    s.num = K.Title(s, 11, C.text)
    s.num:SetText(tostring(n))
    K.CenterNum(s.num, s, "CENTER", 0, 0)
    s.lbl = K.Text(parent, 11, C.muted)
    s.lbl:SetPoint("LEFT", s, "RIGHT", 6, 0)
    s.lbl:SetText(label)
    -- state: "done" | "now" | "todo"
    function s:Set(state)
        local was = self.state
        self.state = state
        local a, d, f = C.accent, C.dim, C.field
        if state == "done" then
            self.ring:SetVertexColor(a[1], a[2], a[3])
            self.core:SetVertexColor(a[1], a[2], a[3])
            self.num:SetTextColor(1, 1, 1)
            self.lbl:SetTextColor(C.text[1], C.text[2], C.text[3])
            self.glow:Hide()
        elseif state == "now" then
            self.ring:SetVertexColor(a[1], a[2], a[3])
            self.core:SetVertexColor(f[1], f[2], f[3])
            self.num:SetTextColor(a[1], a[2], a[3])
            self.lbl:SetTextColor(C.text[1], C.text[2], C.text[3])
            self.glow:Hide()
        else
            self.ring:SetVertexColor(C.line[1], C.line[2], C.line[3])
            self.core:SetVertexColor(f[1], f[2], f[3])
            self.num:SetTextColor(d[1], d[2], d[3])
            self.lbl:SetTextColor(d[1], d[2], d[3])
            self.glow:Hide()
        end
        if state == "done" and was and was ~= "done" and animOn() then
            K.Tween(self.core, 0.35, function(q) local z = 18 + 4 * math.sin(math.pi * q) self.core:SetSize(z, z) end, function() self.core:SetSize(18, 18) end)
        end
    end
    s:Set("todo")
    return s
end

-- Options-Zeile: Schalter ueber die volle Breite, Erklaerung im Tooltip
local function optionRow(t, title, desc)
    t:HookScript("OnEnter", function(self) K.ShowTip(self, { title, desc }) end)
    t:HookScript("OnLeave", function() GameTooltip:Hide() end)
    if t.lbl then t.lbl:SetTextColor(C.text[1], C.text[2], C.text[3]) end
    return t
end

ns.RegisterPage({
    key = "groups", title = "Gruppen", order = 2.7,
    sub = "Freien Platz anklicken und du bist dabei - 1 Tank, 1 Heiler, 3 Schaden",
    build = function(p)
        -- oben rechts: welche Rollen spiele ich? (fuer Hinweise)
        local mh = K.Text(p, 11, C.muted, "RIGHT")
        mh:SetPoint("TOPRIGHT", -3 * 44 - 8, -12)
        mh:SetText(L["Ich spiele:"])
        p.myRoles = {}
        for i, k in ipairs({ "tank", "heal", "dps" }) do
            local b = roleToggle(p, k, 40, 36, function() return Groups.MyRoles()[k] end, function(v)
                Groups.MyRoles()[k] = v
                if ns.Radar then ns.Radar.SendHello() end
                ns.RefreshPage("groups")
            end)
            b.text:Hide()
            b.icon:SetPoint("TOP", 0, -4)
            b.icon:SetSize(26, 26)
            b:SetPoint("TOPRIGHT", -(3 - i) * 44, 0)
            b:SetScript("OnEnter", function(self) K.ShowTip(self, { ROLES[k][1], L["Klick: an/aus - passende Gruppen melden sich bei dir"] }) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.myRoles[k] = b
            b:Hide()   -- Rolle wird im Profil gewaehlt (eine Gruppenrolle)
        end
        mh:Hide()
        -- Werkzeug-Knoepfe: auffaellig (primary) und genau so breit wie die Spalte "Eigene Gruppe" darunter
        p.toolBar = CreateFrame("Frame", nil, p)
        p.toolBar:SetPoint("TOPLEFT", 486, -10)
        p.toolBar:SetPoint("TOPRIGHT", 0, -10)
        p.toolBar:SetHeight(30)
        p.markBtn = K.Button(p.toolBar, L["Auto-Marker"], 110, 26, "ghost", function() if ns.Marker then ns.Marker.Toggle() end end)
        p.markBtn:SetPoint("TOPLEFT", 0, 0)
        p.buffBtn = K.Button(p.toolBar, L["Buff-Monitor"], 120, 26, "ghost", function() if ns.BuffMonitor then ns.BuffMonitor.Toggle() end end)
        p.buffBtn:SetPoint("TOPRIGHT", 0, 0)
        p.toolBar:SetScript("OnSizeChanged", function(self, w)
            local half = math.floor(((w or 260) - 6) / 2)
            p.markBtn:SetWidth(half) p.buffBtn:SetWidth(half)
        end)
        local oh = K.Header(p, L["Offene Gruppen"])
        oh:SetPoint("TOPLEFT", 0, -8)
        oh:SetWidth(300)
        p.ohInfo = K.Text(p, 11, C.muted)
        p.ohInfo:SetPoint("TOPLEFT", 0, -28)
        p.ohInfo:SetWidth(470)
        -- Einladungen von Gruppen, bei denen ich angefragt habe, automatisch annehmen
        p.autoAccept = K.Toggle(p, L["Automatisch annehmen"], function() return ns.db.settings.lfgAccept ~= false end,
            function(v) ns.db.settings.lfgAccept = v end)
        p.autoAccept:SetPoint("TOPLEFT", 300, -4)

        -- links: offene Gruppen, je Karte 5 Plaetze zum Anklicken
        local list = K.List(p, 84, function(l)
            local r = K.Row(l)
            r.cols.title = K.Title(r, 14, C.text)
            r.cols.title:SetPoint("TOPLEFT", 12, -8)
            r.cols.title:SetWidth(330)
            r.cols.who = K.Text(r, 11, C.muted)
            r.cols.who:SetPoint("TOPLEFT", 12, -27)
            r.cols.who:SetWidth(330)
            r.slots = makeSlots(r, 34, function(s) Groups.SlotClick(s.group, s.role) end)
            for i, s in ipairs(r.slots) do s:SetPoint("BOTTOMLEFT", 12 + (i - 1) * 40, 8) end
            r.cols.note = K.Text(r, 11, C.text)
            r.cols.note:SetPoint("BOTTOMLEFT", 222, 18)
            r.cols.note:SetWidth(236)
            r.cols.note:SetWordWrap(false)
            r:SetScript("OnEnter", function(self) if self.noteText and self.noteText ~= "" then K.ShowTip(self, { L["Notiz"], self.noteText }) end end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r.cnt = K.Title(r, 14, C.muted, "RIGHT")
            r.cnt:SetPoint("TOPRIGHT", -12, -10)
            r.hint = K.Text(r, 10, C.dim, "RIGHT")
            -- rechts oben unter dem Zaehler (unten ist "Noch offen")
            r.hint:SetPoint("TOPRIGHT", -12, -30)
            r.merge = K.Button(r, L["Zusammenfuehren"], 112, 20, "ghost")
            r.merge:SetPoint("TOPRIGHT", -52, -8)
            r.merge:SetScript("OnEnter", function(self)
                K.ShowTip(self, { L["Zusammenfuehren"], L["Gleiches Ziel und die Rollen passen: der Ersteller laedt deine ganze Gruppe ein, deine Suche endet."] })
            end)
            r.merge:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r.merge:Hide()
            -- ganze Zeile anklickbar: mit meiner Rolle anfragen (bzw. in der Gruppe: Rolle wechseln)
            r:RegisterForClicks("LeftButtonUp")
            r:SetScript("OnClick", function(self)
                local g = self.item
                if not g or ns.isMe(g.who) then return end
                if g.live then
                    -- laufende Gruppe: den Leiter (bzw. ein Mitglied mit Oasis) anschreiben - Text steht fertig im Chat, du schickst ab
                    ns.Whisper(g.who, g.inst and (L["Hi! Habt ihr in %s noch einen Platz frei oder braucht ihr spaeter Ersatz?"]):format(g.title)
                        or L["Hi! Habt ihr in eurer Gruppe noch einen Platz frei?"])
                    return
                end
                local role = defaultRole()
                if not Groups.FreeRoles(g)[role] then
                    K.Toast(L["Kein Platz fuer deine Rolle"], ROLES[role][1] .. "  -  " .. L["Klick direkt auf einen freien Platz"], C.dim)
                    return
                end
                if not self.canClick then return end
                Groups.SlotClick(g, role)
            end)
            -- Mitglied: Gruppe verlassen
            r.leave = CreateFrame("Button", nil, r)
            r.leave:SetSize(92, 20)
            r.leave:SetPoint("TOPRIGHT", -52, -8)
            r.leave.bg = K.Fill(r.leave, { C.red[1] * 0.16, C.red[2] * 0.16, C.red[3] * 0.16, 1 })
            K.Border(r.leave, { C.red[1] * 0.6, C.red[2] * 0.6, C.red[3] * 0.6, 1 })
            r.leave.t = K.Text(r.leave, 11, { 1, 0.55, 0.5 }, "CENTER")
            r.leave.t:SetPoint("CENTER", 0, 0)
            r.leave.t:SetText(L["Verlassen"])
            r.leave:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(C.red[1] * 0.35, C.red[2] * 0.35, C.red[3] * 0.35, 1)
                K.ShowTip(self, { L["Gruppe verlassen"], L["Du verlaesst die WoW-Gruppe sofort."] })
            end)
            r.leave:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(C.red[1] * 0.16, C.red[2] * 0.16, C.red[3] * 0.16, 1)
                GameTooltip:Hide()
            end)
            r.leave:SetScript("OnClick", function() Groups.LeaveGroup() end)
            r.leave:Hide()
            -- laufende Gruppe: fuenf Plaetze als Klassenkreise (Leiter mit hellem Ring), daneben freie Plaetze und Anfluestern
            r.live = CreateFrame("Frame", nil, r)
            r.live:SetPoint("BOTTOMLEFT", 12, 8)
            r.live:SetPoint("BOTTOMRIGHT", -12, 8)
            r.live:SetHeight(34)
            r.live:Hide()
            r.live.seat = {}
            for i = 1, 5 do
                local b = CreateFrame("Button", nil, r.live)
                b:SetSize(30, 30)
                b:SetPoint("LEFT", (i - 1) * 36, 0)
                b.ring = b:CreateTexture(nil, "BORDER")
                b.ring:SetTexture(CIRCLE)
                b.ring:SetAllPoints()
                b.disc = b:CreateTexture(nil, "ARTWORK")
                b.disc:SetTexture(CIRCLE)
                b.disc:SetPoint("TOPLEFT", 2, -2)
                b.disc:SetPoint("BOTTOMRIGHT", -2, 2)
                b.icon = b:CreateTexture(nil, "OVERLAY")
                b.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
                b.icon:SetPoint("TOPLEFT", 3, -3)
                b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
                b.q = K.Text(b, 12, C.dim, "CENTER")
                b.q:SetPoint("CENTER", 0, 0)
                b:SetScript("OnEnter", function(self)
                    if self.tip then K.ShowTip(self, self.tip) end
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                b:SetScript("OnClick", function(self) if self.who then ns.Whisper(self.who) end end)
                r.live.seat[i] = b
            end
            r.live.free = K.Text(r.live, 12, C.mint)
            r.live.free:SetPoint("LEFT", 5 * 36 + 8, 0)
            r.live.ask = K.Button(r.live, L["Anfluestern"], 104, 24, "primary", function() r:Click() end)
            r.live.ask:SetPoint("RIGHT", 0, 0)
            -- eigene Anfrage zurueckziehen
            r.cancel = K.Button(r, L["Zurueckziehen"], 92, 20, "ghost")
            r.cancel:SetPoint("TOPRIGHT", -52, -8)
            r.cancel:Hide()
            return r
        end, function(r, g)
            for _, sl in ipairs(r.slots) do sl:SetShown(not g.live) end
            r.live:SetShown(g.live and true or false)
            if g.live then
                local names = {}
                for i, key in ipairs(g.keys) do
                    if i > 5 then names[#names + 1] = "|cff888888+" .. (#g.keys - 5) .. "|r" break end
                    local mm = ns.Radar.byNameLower and ns.Radar.byNameLower[key]
                    names[#names + 1] = mm and ns.Radar.Colored(mm.name) or ("|cff999999" .. SEC.Text((key:match("^(.*)%-[^%-]+$") or key), 30) .. "|r")
                end
                local n = math.min(g.n or #g.keys, 40)
                local free = math.max(0, 5 - n)
                r.cols.title:SetText((g.inst and "|cffff7838" or "|cffe8b44a") .. SEC.Text(g.title, 50) .. "|r  |cff66db9e" .. L["laeuft gerade"] .. "|r")
                r.cols.who:SetText(table.concat(names, "|cff555555, |r"))
                r.cols.note:SetText("")
                r.noteText = nil
                r.cnt:SetText(n .. (n <= 5 and "/5" or ""))
                r.hint:SetText("")
                -- Plaetze: bekannte Gildenmitglieder mit Klassensymbol, Fremde als "?", frei = leerer Kreis
                local lead = ns.NameKey and ns.NameKey(g.who) or tostring(g.who):lower()
                for i, b in ipairs(r.live.seat) do
                    local key = g.keys[i]
                    local mm = key and ns.Radar.byNameLower and ns.Radar.byNameLower[key]
                    local tc = mm and mm.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[mm.class]
                    b.who = mm and not ns.isMe(mm.name) and mm.name or nil
                    b:EnableMouse(key ~= nil)
                    if key then
                        local cr, cg, cb = ns.classColor(mm and mm.class)
                        cr, cg, cb = cr or 0.5, cg or 0.5, cb or 0.5
                        local isLead = g.leaderKnown and key == lead
                        if isLead then b.ring:SetVertexColor(1, 0.82, 0.3, 1) else b.ring:SetVertexColor(cr, cg, cb, 0.9) end
                        b.disc:SetVertexColor(cr * 0.25, cg * 0.25, cb * 0.25, 1)
                        if tc then b.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
                        b.icon:SetShown(tc ~= nil)
                        b.q:SetText(tc and "" or "?")
                        local nm = mm and ns.Radar.Colored(mm.name) or SEC.Text((key:match("^(.*)%-[^%-]+$") or key), 30)
                        b.tip = { nm }
                        if isLead then b.tip[#b.tip + 1] = L["Leiter"] elseif not mm then b.tip[#b.tip + 1] = L["nicht in der Gilde"] end
                        if b.who then b.tip[#b.tip + 1] = "|cff888888" .. L["Klick: anfluestern"] .. "|r" end
                    else
                        b.ring:SetVertexColor(1, 1, 1, i <= 5 - free and 0.25 or 0.10)
                        b.disc:SetVertexColor(0.05, 0.05, 0.06, 1)
                        b.icon:Hide()
                        b.q:SetText("")
                        b.tip = nil
                    end
                end
                r.live.free:SetText(free > 0 and (free == 1 and L["1 Platz frei"] or (L["%d Plaetze frei"]):format(free)) or ("|cff777777" .. L["voll"] .. "|r"))
                r.live.ask:SetLabel((g.leaderKnown and L["Leiter anfluestern"] or L["Anfluestern"]))
                r.live.ask:SetWidth(g.leaderKnown and 140 or 104)
                r.leave:Hide() r.cancel:Hide() r.merge:Hide()
                r.canClick = true
                r.sel:Hide()
                return
            end
            local dg = ns.Dungeons and ns.Dungeons.Match(g.title)
            r.cols.title:SetText(SEC.Text(g.title or "?", 60) .. (dg and ("  |cff777777" .. (L["Stufe %s"]):format(dg.level) .. "|r") or ""))
            r.cols.who:SetText(ns.Radar.Label(g.who) .. " |cff888888" .. (g.lvl or "?") .. "|r   |cff666666" .. ns.ago(g.u) .. "|r")
            local open = { tank = 0, heal = 0, dps = 0 }
            for _, s in ipairs(Groups.Slots(g)) do if not s.who then open[s.role] = open[s.role] + 1 end end
            local ot = {}
            for _, k in ipairs({ "tank", "heal", "dps" }) do
                if open[k] > 0 then ot[#ot + 1] = K.hex(ROLES[k][2]) .. (open[k] > 1 and (open[k] .. "x ") or "") .. ROLES[k][1] .. "|r" end
            end
            r.cols.note:SetText(#ot > 0 and (L["Noch offen: "] .. table.concat(ot, "  ·  ")) or ("|cff777777" .. L["voll"] .. "|r"))
            r.noteText = g.note
            if g.voice then r.cols.note:SetText(r.cols.note:GetText() .. "   |cff88bbff" .. L["Sprachchat"] .. "|r") end
            local mine = ns.isMe(g.who)
            -- schon in dieser Gruppe (oder Mitglied einer anderen, nicht Leiter): keine Anfrage moeglich
            local inIt = false
            for _, mb in ipairs(members(g)) do if ns.isMe(mb.name) then inIt = true end end
            -- nur wer wirklich in einer WoW-Gruppe ist, ist "dabei" (Karte kann veraltet sein)
            if not (IsInGroup and IsInGroup()) then inIt = false end
            -- auch per Hand/Zusammenfuehren in der Gruppe des Leiters
            if not inIt and not mine and IsInGroup and IsInGroup() and Groups.InMyParty and Groups.InMyParty(g.who) then inIt = true end
            -- bin ich drin, ist meine alte Anfrage erledigt (sonst sperrt "angefragt" die Plaetze)
            if inIt and Groups.joined then Groups.joined[Groups.Key(g)] = nil end
            -- in der Gruppe: freien Platz anklicken = Rolle wechseln; sonst = anfragen
            drawSlots(r.slots, g, mine or inIt or Groups.CanStart())
            r.canClick = (inIt or Groups.CanStart()) and not mine
            local taken = 0
            for _, s in ipairs(Groups.Slots(g)) do if s.who then taken = taken + 1 end end
            r.cnt:SetText(taken .. "/5")
            local pending = Groups.MyRequest(g)
            r.hint:SetText(mine and L["deine Gruppe"] or (inIt and ("|cff66db9e" .. L["du bist dabei"] .. "|r")) or (pending and ("|cffff1200" .. L["angefragt"] .. "|r") or ""))
            local inParty = not mine and IsInGroup and IsInGroup() and Groups.InMyParty and Groups.InMyParty(g.who)
            r.leave:SetShown((inIt or inParty) and not mine and true or false)
            r.cancel:SetShown(pending and not inIt and not mine and true or false)
            r.cancel:SetScript("OnClick", function() Groups.CancelRequest(g) end)
            local my = Groups.Mine()
            local canM = not mine and my and Groups.CanMerge(my, g)
            r.merge:SetShown(canM and true or false)
            if canM then
                local asked = Groups.mergeAsked == g.id
                r.merge:SetLabel(asked and L["angefragt"] or L["Zusammenfuehren"])
                r.merge:SetEnabledState(not asked)
                r.merge:SetScript("OnClick", function() Groups.RequestMerge(g) end)
                r.hint:SetText("")
            end
            r.sel:SetShown(matches(g) and not mine)
        end)
        list:SetPoint("TOPLEFT", 0, -50)
        list:SetPoint("BOTTOMLEFT", 0, 0)
        list:SetWidth(470)
        list.empty:SetText("")
        p.list = list
        -- Leere Liste: wer aus der Gilde ist gerade online und passt zu deinem Ziel? (ein Klick fragt an)
        local mt = CreateFrame("Frame", nil, p)
        mt:SetPoint("TOPLEFT", 0, -50)
        mt:SetSize(470, 330)
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(mt, { 1, 1, 1, 0.025 }, { 1, 1, 1, 0.10 }, 14) end
        p.mates = mt
        mt.t = K.Title(mt, 14, C.text)
        mt.t:SetPoint("TOPLEFT", 16, -14)
        mt.t:SetPoint("RIGHT", -16, 0)
        mt.t:SetWordWrap(false)
        mt.d = K.Text(mt, 11, C.muted)
        mt.d:SetPoint("TOPLEFT", mt.t, "BOTTOMLEFT", 0, -4)
        mt.d:SetPoint("RIGHT", -16, 0)
        mt.d:SetWordWrap(true)
        mt.rows = {}
        for i = 1, 8 do
            local r = CreateFrame("Button", nil, mt)
            r:SetHeight(28)
            r:SetPoint("TOPLEFT", 10, -62 - (i - 1) * 30)
            r:SetPoint("RIGHT", -10, 0)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0.05)
            r.cls = r:CreateTexture(nil, "ARTWORK")
            r.cls:SetSize(18, 18)
            r.cls:SetPoint("LEFT", 6, 0)
            r.name = K.Text(r, 12, C.text)
            r.name:SetPoint("LEFT", 32, 0)
            r.name:SetWidth(170)
            r.name:SetWordWrap(false)
            r.role = r:CreateTexture(nil, "ARTWORK")
            r.role:SetSize(14, 14)
            r.role:SetPoint("LEFT", 210, 0)
            r.zone = K.Text(r, 10, C.dim)
            r.zone:SetPoint("LEFT", 230, 0)
            r.zone:SetPoint("RIGHT", -96, 0)
            r.zone:SetWordWrap(false)
            r.ask = K.Text(r, 11, C.muted, "RIGHT")
            r.ask:SetPoint("RIGHT", -6, 0)
            r.ask:SetText(L["fragen"] .. "  >")
            r:SetScript("OnEnter", function(self)
                self.ask:SetTextColor(C.text[1], C.text[2], C.text[3])
                if self.m and ns.Radar.ShowMemberTip then ns.Radar.ShowMemberTip(self, self.m, { hint = L["Klick: anfluestern und fragen, ob er/sie mitkommt"] }) end
            end)
            r:SetScript("OnLeave", function(self) self.ask:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self)
                if not self.m then return end
                ns.Whisper(self.m.name, (L["Hi! Lust auf %s? Ich stelle gerade eine Gruppe zusammen."]):format(mt.target or L["eine Gruppe"]))
            end)
            mt.rows[i] = r
        end
        mt.none = K.Text(mt, 12, C.muted, "CENTER")
        mt.none:SetPoint("TOP", 0, -90)
        mt.none:SetWidth(420)
        mt.none:SetWordWrap(true)
        mt:Hide()
        -- Geplante Dungeons: Termine aus "Raids & Beute" (Karten + Liste kommen aus Raid.lua)
        p.planBtn = K.Button(p, L["Geplant"], 124, 22, "ghost", function()
            ns.db.settings.grpPlanned = not ns.db.settings.grpPlanned
            ns.RefreshPage("groups")
        end)
        -- rechtsbuendig am Ende der linken Spalte (Liste ist 470 breit), auf Hoehe der Ueberschrift
        p.planBtn:SetPoint("TOPRIGHT", p, "TOPLEFT", 470, -4)

        -- rechts: eigene Gruppe (Schritte 1 Ziel, 2 Rolle, 3 Los; laufend: Statuskarte)
        p:HookScript("OnShow", function(self) self.fresh2 = true end)
        local box = CreateFrame("Frame", nil, p)
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(box, { 1, 1, 1, 0.025 }, { 1, 1, 1, 0.10 }, 14) end
        p.box = box
        box:SetPoint("TOPLEFT", 486, -46)
        box:SetPoint("BOTTOMRIGHT", 0, 0)
        local bh = K.GameHead(box, L["Eigene Gruppe"], C.accent)
        bh.text:SetText(L["Eigene Gruppe"])
        if bh.mark then bh.mark:Hide() end
        bh:SetPoint("TOPLEFT", 12, -10)
        bh:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        p.boxHead = bh

        -- "Automatisch annehmen" gilt immer (auch als Mitglied): eine Zeile unten in der Spalte
        if p.autoAccept then
            optionRow(p.autoAccept, L["Automatisch annehmen"], L["Einladungen von Gruppen, bei denen du angefragt hast, nimmst du automatisch an."])
            p.autoAccept:ClearAllPoints()
            p.autoAccept:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 12, 52)
            p.autoAccept:SetPoint("RIGHT", box, "RIGHT", -12, 0)
            p.autoAccept:SetHeight(20)
        end
        p.optLine = box:CreateTexture(nil, "ARTWORK")
        p.optLine:SetColorTexture(1, 1, 1, 0.06)
        p.optLine:SetHeight(1)
        p.optLine:SetPoint("BOTTOMLEFT", 12, 102)
        p.optLine:SetPoint("BOTTOMRIGHT", -12, 102)

        -- Neue Suche ---------------------------------------------------
        p.newView = CreateFrame("Frame", nil, box)
        p.newView:SetAllPoints()
        local nv = p.newView
        -- Schritt-Kopf
        local st = CreateFrame("Frame", nil, nv)
        st:SetPoint("TOPLEFT", 12, -34)
        st:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        st:SetHeight(22)
        p.steps = {}
        local names = { L["Ziel"], L["Rolle"], L["Los"] }
        for i = 1, 3 do p.steps[i] = stepDot(st, i, names[i]) end
        p.stepLines = {}
        for i = 1, 2 do
            local ln = st:CreateTexture(nil, "ARTWORK")
            ln:SetHeight(2)
            ln:SetPoint("LEFT", p.steps[i].lbl, "RIGHT", 6, 0)
            ln:SetPoint("RIGHT", p.steps[i + 1], "LEFT", -6, 0)
            p.stepLines[i] = ln
        end
        st:SetScript("OnSizeChanged", function(self, w)
            w = (w and w > 50) and w or 260
            for i, s in ipairs(p.steps) do
                s:ClearAllPoints()
                s:SetPoint("LEFT", self, "LEFT", math.floor((i - 1) * (w - 40) / 2), 0)
            end
        end)
        for i, s in ipairs(p.steps) do s:SetPoint("LEFT", st, "LEFT", (i - 1) * 110, 0) end

        -- Filter als Segment statt Dropdown
        p.filterSeg = K.Segments(nv, { { key = "fit", text = L["Passend fuer mich"] }, { key = "all", text = L["Alle"] } }, function()
            p.cardOff = 0
            p.DrawCards()
        end, nil, { size = 11, pad = 16 })
        p.filterSeg:SetPoint("TOPLEFT", 8, -62)
        p.pageInfo = K.Text(nv, 10, C.dim, "RIGHT")
        p.pageInfo:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12, -68)

        -- Ziel-Karten (Anzahl passt sich der Hoehe an, Mausrad blaettert)
        p.cardOff = 0
        p.cardsArea = CreateFrame("Frame", nil, nv)
        p.cardsArea:SetPoint("TOPLEFT", 12, -90)
        p.cardsArea:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -12, 212)
        p.cardsArea:EnableMouseWheel(true)
        p.cardsArea:SetScript("OnMouseWheel", function(_, delta)
            p.cardOff = (p.cardOff or 0) - (delta or 0)
            p.DrawCards()
        end)
        p.cardsEmpty = K.Text(p.cardsArea, 11, C.dim, "CENTER")
        p.cardsEmpty:SetPoint("TOPLEFT", 0, -10)
        p.cardsEmpty:SetPoint("TOPRIGHT", 0, -10)
        p.cardsEmpty:SetWordWrap(true)
        p.cardsEmpty:SetText(L["Nichts in deinem Levelbereich - schalte auf Alle oder tippe ein Ziel ein."])
        local function pick(v)
            pickTitle = (pickTitle ~= v) and v or nil
            p.title:SetText("")
            p.title:ClearFocus()
            ns.RefreshPage("groups")
        end
        p.SelectTarget = function(v) pickTitle = nil pick(v) end
        p.cards = {}
        for i = 1, 6 do
            local c = makeCard(p.cardsArea, pick)
            c:SetPoint("TOPLEFT", 0, -(i - 1) * 36)
            c:SetPoint("RIGHT", p.cardsArea, "RIGHT", 0, 0)
            c:EnableMouseWheel(true)
            c:SetScript("OnMouseWheel", function(_, delta) p.cardOff = (p.cardOff or 0) - (delta or 0) p.DrawCards() end)
            p.cards[i] = c
        end
        function p.DrawCards()
            local list = targetList(p.filterSeg.value or "fit")
            p.cardCount = #list
            local h = p.cardsArea:GetHeight() or 0
            local vis = (h and h > 40) and math.floor((h + 4) / 36) or 4
            vis = math.max(2, math.min(#p.cards, vis))
            local maxOff = math.max(0, #list - vis)
            p.cardOff = math.max(0, math.min(maxOff, p.cardOff or 0))
            for i, c in ipairs(p.cards) do
                local s = (i <= vis) and list[p.cardOff + i]
                if s then c:Fill(s, pickTitle == s.text) c:Show() else c:Hide() end
            end
            p.cardsEmpty:SetShown(#list == 0)
            p.pageInfo:SetText(#list > vis and ((L["%d-%d von %d"]):format(p.cardOff + 1, math.min(#list, p.cardOff + vis), #list)) or "")
        end
        p.cardsArea:SetScript("OnSizeChanged", function() if p.newView:IsShown() then p.DrawCards() end end)

        -- Freitext mit Stift-Symbol
        p.title = K.Input(nv, 240, L["... oder selbst eintippen"], function(t)
            if t ~= "" then pickTitle = nil end
            ns.RefreshPage("groups")
        end)
        p.title:SetPoint("BOTTOMLEFT", 12, 182)
        p.title:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        p.title:SetHeight(26)
        p.title:SetTextInsets(28, 8, 0, 0)
        p.titleIcon = p.title:CreateTexture(nil, "OVERLAY")
        p.titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        p.titleIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        p.titleIcon:SetSize(16, 16)
        p.titleIcon:SetPoint("LEFT", 7, 0)
        p.titleIcon:SetAlpha(0.7)
        p.title.ph:ClearAllPoints()
        p.title.ph:SetPoint("LEFT", 28, 0)
        p.title.ph:SetPoint("RIGHT", -8, 0)
        p.title:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Eigenes Ziel"], L["Zum Beispiel: Questen im Brachland, Elite-Quest, Ruf farmen ..."] }) end)
        p.title:HookScript("OnLeave", function() GameTooltip:Hide() end)

        -- Rollen-Kacheln
        local rr = CreateFrame("Frame", nil, nv)
        rr:SetPoint("BOTTOMLEFT", 12, 128)
        rr:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        rr:SetHeight(48)
        p.roleBtns = {}
        local function pickRole(k)
            myRole = k
            if ns.Profile and ns.Profile.SetMyRole then ns.Profile.SetMyRole(k, true) else
                local r = Groups.MyRoles()
                for _, x in ipairs({ "tank", "heal", "dps" }) do r[x] = (x == k) end
            end
            ns.RefreshPage("groups")
        end
        for i, k in ipairs({ "tank", "heal", "dps" }) do
            local b = roleTile(rr, k, pickRole)
            b:SetPoint("TOPLEFT", (i - 1) * 86, 0)
            b:SetWidth(80)
            p.roleBtns[k] = b
        end
        rr:SetScript("OnSizeChanged", function(_, w)
            w = (w and w > 60) and w or 260
            local tw = math.floor((w - 12) / 3)
            for i, k in ipairs({ "tank", "heal", "dps" }) do
                p.roleBtns[k]:ClearAllPoints()
                p.roleBtns[k]:SetPoint("TOPLEFT", rr, "TOPLEFT", (i - 1) * (tw + 6), 0)
                p.roleBtns[k]:SetWidth(tw)
            end
        end)

        -- Optionen (Zeilen unten; "Automatisch annehmen" liegt darunter, s.o.)
        if ns.db.settings.lfgAuto ~= nil then autoInvite = ns.db.settings.lfgAuto end
        p.auto = K.Toggle(nv, L["Automatisch einladen"], function() return autoInvite end, function(v) autoInvite = v ns.db.settings.lfgAuto = v end)
        optionRow(p.auto, L["Automatisch einladen"], L["Wer sich mit passender Rolle meldet, wird sofort in deine Gruppe eingeladen."])
        p.auto:ClearAllPoints()
        p.auto:SetPoint("BOTTOMLEFT", 12, 100)
        p.auto:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        p.auto:SetHeight(20)

        -- Sprachchat: Vorbelegung aus Blizzards Gruppensuche (nur falls dort schon ein Modus steht)
        if ns.db.settings.lfgVoice == nil then
            local ok, info = pcall(function() return C_LFGList and C_LFGList.GetActiveEntryInfo and C_LFGList.GetActiveEntryInfo() end)
            local v = ok and type(info) == "table" and info.voiceChat
            if type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v ~= "" then ns.db.settings.lfgVoice = true end
            -- 0.5.771: laeuft ein Discord-/Sprachkanal, ist Sprachchat wahrscheinlich gewollt
            if ns.db.settings.lfgVoice == nil and ns.Discord and ns.Discord.VoiceActive and ns.Discord.VoiceActive() then ns.db.settings.lfgVoice = true end
        end
        p.voice = K.Toggle(nv, L["Sprachchat"], function() return ns.db.settings.lfgVoice and true or false end, function(v) ns.db.settings.lfgVoice = v end)
        optionRow(p.voice, L["Sprachchat"], L["Zeigt in der Suche an, dass ihr per Sprache redet (Discord o.ae.). Beitreten regelt weiter Blizzard bzw. dein Gruppenleiter."])
        p.voice:ClearAllPoints()
        p.voice:SetPoint("BOTTOMLEFT", 12, 76)
        p.voice:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        p.voice:SetHeight(20)

        -- Start-Knopf
        p.go = K.Button(nv, L["Gruppe suchen"], 240, 34, "primary", function()
            local t = pickTitle or p.title:GetText()
            Groups.Start(t, myRole or defaultRole(), autoInvite, nil, ns.db.settings.lfgVoice)
            pickTitle = nil
            p.title:SetText("")
        end)
        p.go:SetPoint("BOTTOMLEFT", 12, 10)
        p.go:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        p.go.label:SetFont(K.FONT_HEAD or K.FONT, 13, "")
        p.go.sweep = p.go:CreateTexture(nil, "OVERLAY")
        p.go.sweep:SetTexture(ns.MEDIA .. "shine")
        p.go.sweep:SetBlendMode("ADD")
        p.go.sweep:SetSize(46, 40)
        p.go.sweep:SetAlpha(0)
        p.go:HookScript("OnEnter", function(self)
            if not self:IsEnabled() and self.why then K.ShowTip(self, { L["Noch nicht bereit"], self.why }) end
        end)
        p.go:HookScript("OnLeave", function() GameTooltip:Hide() end)

        -- Laufende Suche: Statuskarte -------------------------------------
        p.runView = CreateFrame("Frame", nil, box)
        p.runView:SetAllPoints()
        local rv = p.runView
        p.hero = CreateFrame("Frame", nil, rv)
        p.hero:SetPoint("TOPLEFT", 12, -34)
        p.hero:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        p.hero:SetHeight(54)
        p.hero.bg = K.Fill(p.hero, C.raised)
        K.Border(p.hero, C.accent2)
        artStrip(p.hero, 150)
        p.hero.art:SetAlpha(0.12)
        p.hero.artFade:Hide()
        if ns.Insta and ns.Insta.Glass then ns.Insta.Glass(p.hero, { 1, 1, 1, 0.04 }, { C.accent[1], C.accent[2], C.accent[3], 0.45 }, 10) end
        p.hero.grad = p.hero:CreateTexture(nil, "BORDER", nil, 3)
        p.hero.grad:Hide()
        p.hero.icon = p.hero:CreateTexture(nil, "ARTWORK")
        p.hero.icon:SetSize(38, 38)
        p.hero.icon:SetPoint("LEFT", 8, 0)
        p.hero.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        p.runTitle = K.Title(p.hero, 14, C.text)
        p.runTitle:SetPoint("TOPLEFT", p.hero.icon, "TOPRIGHT", 10, -2)
        p.runTitle:SetPoint("RIGHT", p.hero, "RIGHT", -8, 0)
        p.runSub = K.Text(p.hero, 11, C.muted)
        p.runSub:SetPoint("BOTTOMLEFT", p.hero.icon, "BOTTOMRIGHT", 10, 2)
        p.runSub:SetPoint("RIGHT", p.hero, "RIGHT", -8, 0)

        -- Plaetze: 5 Slots gleichmaessig ueber die Breite
        local sr = CreateFrame("Frame", nil, rv)
        sr:SetPoint("TOPLEFT", 12, -98)
        sr:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        sr:SetHeight(40)
        p.runSlots = makeSlots(sr, 40)
        local function placeSlots(w)
            w = (w and w > 100) and w or 260
            local gap = math.floor((w - 5 * 40) / 4)
            for i, s in ipairs(p.runSlots) do s:ClearAllPoints() s:SetPoint("TOPLEFT", sr, "TOPLEFT", (i - 1) * (40 + gap), 0) end
        end
        placeSlots(260)
        sr:SetScript("OnSizeChanged", function(_, w) placeSlots(w) end)
        p.runInfo = K.Text(rv, 11, C.muted)
        p.runInfo:SetPoint("TOPLEFT", 12, -144)
        p.runInfo:SetPoint("RIGHT", box, "RIGHT", -12, 0)

        -- eigene Rolle auch waehrend der Suche aendern (wechselt den Platz + Blizzard-Rolle)
        local rl = K.Label(rv, L["Deine Rolle"])
        rl:SetPoint("TOPLEFT", 12, -170)
        p.runRoles = {}
        for i, k in ipairs({ "tank", "heal", "dps" }) do
            local b = roleToggle(rv, k, 40, 26, function() return Groups.MyRoles()[k] and true or false end, function()
                local g = Groups.Mine()
                if g then Groups.SlotClick(g, k) end
                for _, o in pairs(p.runRoles) do o:Refresh() end
            end)
            b.text:Hide()
            b.icon:ClearAllPoints()
            b.icon:SetPoint("CENTER")
            b.icon:SetSize(18, 18)
            b:SetPoint("TOPRIGHT", box, "TOPRIGHT", -12 - (3 - i) * 44, -164)
            b:SetScript("OnEnter", function(self) K.ShowTip(self, { ROLES[k][1], L["Klick: deinen Platz in der Gruppe wechseln"] }) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.runRoles[k] = b
        end

        p.reqHead = K.GameHead(rv, L["Anfragen"], C.mint)
        p.reqHead:SetPoint("TOPLEFT", 12, -200)
        p.reqHead:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        p.req = K.List(rv, 30, function(l)
            local r = K.Row(l)
            r.roleBg = r:CreateTexture(nil, "BORDER")
            r.roleBg:SetSize(22, 22)
            r.roleBg:SetPoint("LEFT", 6, 0)
            r.role = r:CreateTexture(nil, "ARTWORK")
            r.role:SetSize(16, 16)
            r.role:SetPoint("CENTER", r.roleBg)
            r:Col("name", 34, 150, 12)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -104, 0)
            r.cols.name:SetWordWrap(false)
            r.inv = K.Button(r, L["Einladen"], 66, 20, "ghost")
            r.inv:SetPoint("RIGHT", -28, 0)
            r.no = K.IconButton(r, "x", 16, nil, L["Ablehnen"])
            r.no:SetPoint("RIGHT", -6, 0)
            return r
        end, function(r, q)
            r.role:SetTexture(roleTex(q.role) or roleTex("dps"))
            local c = roleColor(q.role)
            r.role:SetVertexColor(c[1], c[2], c[3])
            r.roleBg:SetColorTexture(c[1] * 0.18, c[2] * 0.18, c[3] * 0.18, 1)
            r.cols.name:SetText(ns.colorName(q.name, q.class) .. "  |cff888888" .. (q.lvl or "?") .. "|r"
                .. ((q.ilvl or 0) > 0 and ("  |cff6199ff" .. q.ilvl .. "|r") or ""))
            r.tipLines = { ns.colorName(q.name, q.class), L["Level"] .. ": " .. (q.lvl or "?"), L["Gear"] .. ": " .. ((q.ilvl or 0) > 0 and q.ilvl or "-") }
            r:SetScript("OnEnter", function(self) K.ShowTip(self, self.tipLines) end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r.inv:SetLabel(q.state == "invited" and L["Erneut"] or L["Einladen"])
            if q.state == "invited" then r.cols.name:SetText(r.cols.name:GetText() .. "  |cff66db9e" .. L["eingeladen"] .. "|r") end
            r.inv:SetScript("OnClick", function() Groups.Invite(q.name) end)
            r.no:SetScript("OnClick", function() Groups.Decline(q.name) end)
        end)
        p.req:SetPoint("TOPLEFT", 4, -220)
        p.req:SetPoint("BOTTOMRIGHT", -4, 106)
        p.req.empty:SetText(L["Noch niemand - die Gilde ist informiert."])
        p.req.empty:SetFont(K.FONT, 11, "")
        -- "Suche laeuft"-Anzeige: Radar mit drehendem Bogen + Pulsringe, solange niemand angefragt hat
        local fx = CreateFrame("Frame", nil, p.req)
        fx:SetSize(90, 90)
        fx:SetPoint("CENTER", p.req, "CENTER", 0, 14)
        fx.rings = {}
        for i = 1, 3 do
            local r = fx:CreateTexture(nil, "BACKGROUND")
            r:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            r:SetPoint("CENTER")
            r:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            fx.rings[i] = r
        end
        fx.core = fx:CreateTexture(nil, "ARTWORK")
        fx.core:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        fx.core:SetSize(30, 30)
        fx.core:SetPoint("CENTER")
        fx.core:SetVertexColor(C.accent[1] * 0.35, C.accent[2] * 0.35, C.accent[3] * 0.35)
        fx.icon = fx:CreateTexture(nil, "OVERLAY")
        fx.icon:SetSize(16, 16)
        fx.icon:SetPoint("CENTER")
        fx.icon:SetTexture(ns.ICONS and ns.ICONS.groups or (ns.MEDIA .. "icons\\groups"))
        if ns.SpinRing then fx.spin = ns.SpinRing(fx, fx, 64, 1.6) end
        fx.txt = K.Text(fx, 11, C.muted, "CENTER")
        fx.txt:SetPoint("TOP", fx, "BOTTOM", 0, -2)
        fx.txt:SetWidth(240)
        fx.txt:SetWordWrap(true)
        fx:SetScript("OnUpdate", function(self, el)
            self.t = (self.t or 0) + el
            local still = ns.db and ns.db.settings.noAnim
            for i, r in ipairs(self.rings) do
                local ph = still and (i / 3) or (((self.t / 2.4) + (i - 1) / 3) % 1)
                local s = 30 + 60 * ph
                r:SetSize(s, s)
                r:SetAlpha((1 - ph) * 0.35)
            end
            local dots = still and "..." or string.rep(".", math.floor(self.t * 2) % 4)
            self.txt:SetText(L["Suche laeuft"] .. dots .. (self.sub and ("\n|cff777777" .. self.sub .. "|r") or ""))
        end)
        fx:Hide()
        p.searchFx = fx
        p.runAuto = K.Toggle(rv, L["Automatisch einladen"], function() local g = Groups.Mine() return g and g.auto end, function(v)
            local g = Groups.Mine()
            if g then rewrite(g, function(r) r.auto = v and true or false end) end
            autoInvite = v
            -- nachtraeglich eingeschaltet: wer schon angefragt hat, jetzt einladen
            if v then
                for name, q in pairs(Groups.requests) do
                    if q.state ~= "invited" then Groups.Invite(name) end
                end
            end
            ns.db.settings.lfgAuto = v
            ns.RefreshPage("groups")
        end)
        optionRow(p.runAuto, L["Automatisch einladen"], L["Wer sich mit passender Rolle meldet, wird sofort in deine Gruppe eingeladen."])
        p.runAuto:ClearAllPoints()
        p.runAuto:SetPoint("BOTTOMLEFT", 12, 76)
        p.runAuto:SetPoint("RIGHT", box, "RIGHT", -12, 0)
        p.runAuto:SetHeight(20)
        p.stop = K.Button(rv, L["Suche beenden"], 240, 34, "danger", function() Groups.Stop() end)
        p.stop:SetPoint("BOTTOMLEFT", 12, 10)
        p.stop:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    end,

    refresh = function(p)
        for _, b in pairs(p.myRoles) do b:Refresh() end
        local active = Groups.Active()
        local rows = {}
        for _, g in ipairs(active) do rows[#rows + 1] = g end
        local live = Groups.Live()
        for _, g in ipairs(live) do rows[#rows + 1] = g end
        p.list:SetData(rows)
        -- passende Online-Mitglieder (nur wenn gerade niemand sucht)
        local mt = p.mates
        if mt then
            local planned = ns.db.settings.grpPlanned and true or false
            local show = #active == 0 and #live == 0 and not planned
            mt:SetShown(show)
            if show then
                -- Ziel: gewaehlt > getippt > empfohlen fuer mein Level
                local target = pickTitle or ((p.title and p.title:GetText() ~= "") and p.title:GetText()) or nil
                if not target then for _, x in ipairs(targetList("fit")) do if x.best then target = x.text end end end
                local lo, hi
                local d = target and ns.Dungeons and ns.Dungeons.Match and ns.Dungeons.Match(target)
                if d and d.lo then lo, hi = d.lo - 2, (d.hi or d.lo) + 2 end
                local my = ns.safe(UnitLevel("player")) or 1
                if not lo then lo, hi = my - 4, my + 4 end
                mt.target = target
                local list = {}
                for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
                    local lv = m.level or 0
                    if m.online and not ns.isMe(m.name) and lv >= lo and lv <= hi then list[#list + 1] = m end
                end
                table.sort(list, function(a, b) return math.abs((a.level or 0) - my) < math.abs((b.level or 0) - my) end)
                mt.t:SetText(target and (L["Wer koennte mit: %s"]):format(target) or L["Wer koennte mit?"])
                mt.d:SetText(#list > 0 and (L["%d online in Stufe %d-%d - ein Klick fragt per Fluestern."]):format(#list, lo, hi)
                    or "")
                for i, r in ipairs(mt.rows) do
                    local m = list[i]
                    r.m = m
                    r:SetShown(m ~= nil)
                    if m then
                        local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class or ""]
                        r.cls:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
                        if tc then r.cls:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
                        r.name:SetText(ns.Radar.Colored(m.name) .. "  |cff888888" .. (m.level or "?") .. "|r")
                        local pr = ns.db.members and ns.db.members[m.name]
                        local role = pr and pr.role
                        local rk = (role == "tank" and "tank") or ((role == "heal" or role == "healer") and "heal") or (role and "dps") or nil
                        r.role:SetShown(rk ~= nil)
                        if rk then
                            r.role:SetTexture(roleTex(rk))
                            local c = roleColor(rk)
                            r.role:SetVertexColor(c[1], c[2], c[3])
                        end
                        r.zone:SetText(m.zone or "")
                        if p.fresh2 and K.FadeIn then r.oasisFadedAt = nil K.FadeIn(r, i * 0.03) end
                    end
                end
                mt.none:SetShown(#list == 0)
                mt.none:SetText(L["Gerade ist niemand in deinem Levelbereich online.\nStarte rechts trotzdem eine Gruppe - wer online kommt und passt, bekommt Bescheid."])
                mt:SetHeight(#list > 0 and (70 + math.min(8, #list) * 30) or 150)
            end
            p.fresh2 = false
        end
        local R = ns.Raid
        if R and R.BuildEventList and R.Upcoming and R.IsGroupEvent then
            if not p.plan then
                p.plan = R.BuildEventList(p)
                p.plan:SetPoint("TOPLEFT", 0, -50)
                p.plan:SetPoint("BOTTOMLEFT", 0, 0)
                p.plan:SetWidth(470)
                p.plan.empty:SetText(L["Noch keine Dungeons geplant."])
                p.planNew = K.Button(p, L["Termin anlegen"], 130, 20, "primary", function()
                    R.prefill = { kind = "dungeon", max = 5 }
                    ns.ShowPage("raid")
                    R.SetTab("new")
                end)
                p.planNew:SetPoint("TOPLEFT", 0, -26)
            end
            local evs = {}
            for _, e in ipairs(R.Upcoming()) do if R.IsGroupEvent(e) then evs[#evs + 1] = e end end
            local on = ns.db.settings.grpPlanned and true or false
            local cal = "|T" .. ns.MEDIA .. "icons\\pin:12:12:0:0|t "
            p.planBtn:SetLabel(on and ("< " .. L["Offene Gruppen"]) or (cal .. (L["Geplant (%d)"]):format(#evs)))
            p.planBtn:SetAlpha((on or #evs > 0) and 1 or 0.6)
            p.list:SetShown(not on)
            p.ohInfo:SetShown(not on)
            p.plan:SetShown(on)
            p.planNew:SetShown(on)
            K.LockButton(p.planNew, function() return R.CanLead and R.CanLead() end, "raidlead")
            if on then p.plan:SetData(evs) end
        elseif p.planBtn then
            p.planBtn:Hide()
        end
        local nReq = 0
        for id in pairs(Groups.joined or {}) do if Groups.joined[id] and GetTime() - Groups.joined[id].t < 120 then nReq = nReq + 1 end end
        p.ohInfo:SetText(nReq > 0 and ("|cffff1200" .. (L["Du hast bei %d Gruppen angefragt"]):format(nReq) .. "|r  |cff777777" .. L["- du kannst bei mehreren gleichzeitig anfragen"] .. "|r")
            or ("|cff777777" .. L["Freien Platz (+) anklicken - gern auch bei mehreren Gruppen gleichzeitig."] .. "|r"))
        local mine = Groups.Mine()
        -- Mitglied einer Gruppe (nicht Leiter, keine eigene Suche): rechte Karte ausblenden
        if p.box then
            local showBox = mine ~= nil or Groups.CanStart()
            p.box:SetShown(showBox)
            p.optLine:SetShown(showBox)
            -- ohne Karte: Schalter oben an ihren Platz, sonst als Zeile unten in der Spalte
            if p.autoAccept then
                p.autoAccept:SetFrameLevel(p.box:GetFrameLevel() + 10)
                if showBox ~= p.acceptInBox then
                    p.acceptInBox = showBox
                    p.autoAccept:ClearAllPoints()
                    if showBox then
                        p.autoAccept:SetPoint("BOTTOMLEFT", p.box, "BOTTOMLEFT", 12, 52)
                        p.autoAccept:SetPoint("RIGHT", p.box, "RIGHT", -12, 0)
                    else
                        p.autoAccept:SetPoint("TOPLEFT", p.box, "TOPLEFT", 2, -4)
                        p.autoAccept:SetPoint("RIGHT", p.box, "RIGHT", -12, 0)
                    end
                end
                if p.autoAccept.Refresh then p.autoAccept:Refresh() end
            end
        end
        if p.runAuto and p.runAuto.Refresh then p.runAuto:Refresh() end
        for _, o in pairs(p.runRoles or {}) do o:Refresh() end
        if p.auto and p.auto.Refresh then p.auto:Refresh() end
        local view = mine and "run" or "new"
        local switched = p.lastView ~= view
        p.lastView = view
        -- Trennlinie ueber den Schalterzeilen: die neue Suche hat eine Zeile mehr (Sprachchat)
        if p.optLine and p.optLineView ~= view then
            p.optLineView = view
            local y = (view == "new") and 126 or 102
            p.optLine:ClearAllPoints()
            p.optLine:SetPoint("BOTTOMLEFT", 12, y)
            p.optLine:SetPoint("BOTTOMRIGHT", -12, y)
        end
        p.newView:SetShown(not mine)
        p.runView:SetShown(mine ~= nil)
        if p.boxHead then
            p.boxHead:Live(mine ~= nil)
            p.boxHead:SetCount(mine and L["laeuft"] or "")
        end
        if mine then
            local dg = ns.Dungeons and ns.Dungeons.Match and ns.Dungeons.Match(mine.title)
            local img = dg and dungeonImage(dg) or "Interface\\Icons\\INV_Misc_Book_08"
            p.hero.icon:SetTexture(img)
            p.hero.art:SetTexture(img)
            p.runTitle:SetText((mine.title or "?") .. (dg and dg.level and dg.level ~= "" and ("  |cff777777" .. dg.level .. "|r") or ""))
            local waited = math.max(0, math.floor((ns.now() - (mine.started or ns.now())) / 60))
            local left = math.max(0, math.floor(((mine.exp or 0) - ns.now()) / 60))
            p.runSub:SetText((L["Wartezeit %d Min"]):format(waited) .. "  |cff555555·|r  |cff777777" .. (L["laeuft noch %d Min"]):format(left) .. "|r")
            drawSlots(p.runSlots, mine, false)
            local free, taken = {}, 0
            for _, s in ipairs(Groups.Slots(mine)) do
                if not s.who then free[#free + 1] = ns.Profile.RoleIcon(s.role, 14) else taken = taken + 1 end
            end
            p.runInfo:SetText(K.hex(C.text) .. taken .. "/5|r  " .. (#free > 0 and (L["frei: "] .. table.concat(free, " ")) or ("|cff66db9e" .. L["alle Plaetze besetzt"] .. "|r")))
            local reqs = {}
            -- auch bereits Eingeladene zeigen (bis sie in der Gruppe sind) - sonst wirkt die Liste leer
            for name, q in pairs(Groups.requests) do
                local cn = ns.ChatName(name)
                local joined = UnitInParty and (UnitInParty(cn) or UnitInRaid(cn))
                if not joined then
                    local row = { name = name }
                    for k, v in pairs(q) do row[k] = v end
                    reqs[#reqs + 1] = row
                end
            end
            table.sort(reqs, function(a, b) return (a.t or 0) < (b.t or 0) end)
            p.req:SetData(reqs)
            -- Preloader, solange noch niemand angefragt hat und Plaetze frei sind
            if p.searchFx then
                local busy = #reqs == 0 and #free > 0
                p.searchFx:SetShown(busy)
                p.req.empty:SetShown(not busy and #reqs == 0)
                local on = 0
                for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do if m.online then on = on + 1 end end
                p.searchFx.sub = (L["%d Gildenmitglieder online wurden benachrichtigt"]):format(math.max(0, on - 1))
            end
            p.reqHead:SetCount(#reqs > 0 and #reqs or nil)
            if switched then
                rise(p.hero, 0) rise(p.runSlots[1]:GetParent(), 0.05) rise(p.req, 0.1)
                sweep(p.hero, 0.15)
            end
            return
        end
        if switched then p.cardOff = 0 end
        p.DrawCards()
        for _, b in pairs(p.roleBtns) do b:Refresh() end
        local title = pickTitle or p.title:GetText() or ""
        local hasRole = false
        for _, v in pairs(Groups.MyRoles()) do if v then hasRole = true end end
        local can = Groups.CanStart()
        -- Schritte: erledigte leuchten, der naechste ist markiert
        local done = { title ~= "", hasRole, false }
        local cur
        for i = 1, 3 do
            local state = done[i] and "done" or (not cur and "now" or "todo")
            if state == "now" then cur = i end
            p.steps[i]:Set(state)
        end
        for i, ln in ipairs(p.stepLines) do
            local c = done[i] and C.accent or C.line
            ln:SetColorTexture(c[1], c[2], c[3], done[i] and 0.9 or 1)
        end
        p.newView:SetAlpha(can and 1 or 0.45)
        for _, b in ipairs(p.cards) do b:EnableMouse(can) end
        for _, b in pairs(p.roleBtns) do b:EnableMouse(can) end
        p.title:EnableMouse(can)
        p.filterSeg:EnableMouse(can)
        local ready = can and title ~= "" and hasRole
        p.go:SetEnabledState(ready)
        p.go.why = (not can and L["Nur der Gruppenleiter kann suchen"]) or (title == "" and L["Waehle oben ein Ziel oder tippe eins ein."])
            or (not hasRole and L["Waehle deine Rolle."]) or nil
        p.go:SetLabel(not can and L["Nur der Gruppenleiter kann suchen"]
            or (title == "" and L["Erst ein Ziel waehlen"]) or (not hasRole and L["Erst eine Rolle waehlen"])
            or (L["Gruppe starten: %s"]):format(title))
        -- sobald alles gewaehlt ist: Knopf blendet sichtbar auf + Glanz
        if ready and p.goReady == false and animOn() then
            p.go:SetAlpha(0.45)
            K.Tween(p.go, 0.3, function(q) p.go:SetAlpha(0.45 + 0.55 * q) end, function() p.go:SetAlpha(1) end)
            sweep(p.go, 0.1)
        end
        p.goReady = ready
        if switched then
            for i, c in ipairs(p.cards) do if c:IsShown() then rise(c, 0.03 * i) end end
            for i, k in ipairs({ "tank", "heal", "dps" }) do rise(p.roleBtns[k], 0.15 + 0.04 * i) end
        end
    end,
})

ns.Listen("LOGIN", function()
    ns.Every(60, function()
        Groups.UpdateBadge()
        ns.RefreshPage("groups")
    end)
end)

-- neue/geaenderte Gruppen sofort anzeigen
ns.Listen("STORE", function(coll)
    if coll == "lfg" then ns.Debounce("lfgStore", 0.3, function() ns.RefreshPage("groups") Groups.UpdateBadge() end) end
end)

ns.Listen("ROLES_CHANGED", function()
    local r = Groups.MyRoles()
    for _, k in ipairs({ "tank", "heal", "dps" }) do if r[k] then myRole = k break end end
    ns.RefreshPage("groups")
end)

ns.On("PARTY_LEADER_CHANGED", function() ns.RefreshPage("groups") end)
ns.On("GROUP_ROSTER_UPDATE", function()
    -- in eine fremde Gruppe gekommen (nicht Leiter): eigene Suche beenden
    ns.After(0.5, function()
        if Groups.Mine() and not Groups.CanStart() then
            Groups.Stop()
            K.Toast(L["Suche beendet"], L["Du bist jetzt in einer anderen Gruppe."], C.dim)
        end
        ns.RefreshPage("groups")
    end)
end)

-- Gruppenleiter: Rollen aus Blizzards Gruppe (Rechtsklick > Rolle waehlen) auf die Plaetze der Suche uebertragen
local B2O = { TANK = "tank", HEALER = "heal", DAMAGER = "dps" }
local function syncPartyRoles()
    local g = Groups.Mine()
    if not g or not UnitGroupRolesAssigned then return end
    -- Einheit je Mitglied ueber die Gruppe suchen (Vorname vergleichen: "Mira" / "Mira Stern" / "Mira-Realm")
    local function first(n) return ns.NameKey(n) end
    local units = { player = true }
    local byFirst = { [first(ns.UnitName("player"))] = "player" }
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
        local u = raid and ("raid" .. i) or ("party" .. i)
        local un = UnitExists(u) and ns.UnitName(u)
        if un then byFirst[first(un)] = u end
    end
    Groups.groleAt = Groups.groleAt or {}
    for _, mb in ipairs(members(g)) do
        local unit = ns.isMe(mb.name) and "player" or byFirst[first(mb.name)]
        local want = unit and B2O[UnitGroupRolesAssigned(unit) or ""]
        local key = first(mb.name)
        local locked = (ns.isMe(mb.name) and GetTime() < ((ns.Profile and ns.Profile.lockUntil) or 0))
            or GetTime() - (Groups.groleAt[key] or 0) < 4
        if want and want ~= mb.role and Groups.FreeRoles(g)[want] then
            if locked then
                ns.RoleLog("leader sync skip (lock)", mb.name, mb.role, "->", want)
            else
                ns.RoleLog("leader sync", mb.name, mb.role, "->", want)
                g = assign(g, mb.name, want)
            end
        end
    end
    ns.RefreshPage("groups")
end
Groups.SyncPartyRoles = syncPartyRoles
local syncGen = 0
local function syncSoon(why)
    syncGen = syncGen + 1
    local my = syncGen
    ns.After(0.6, function() if my == syncGen then syncPartyRoles() end end)
end
ns.On("PLAYER_ROLES_ASSIGNED", function() ns.RoleLog("evt PLAYER_ROLES_ASSIGNED") syncSoon() end)
ns.On("ROLE_CHANGED_INFORM", function(changed, from, old, new) ns.RoleLog("evt ROLE_CHANGED_INFORM", changed, old, "->", new) syncSoon() end)
ns.On("GROUP_ROSTER_UPDATE", function() syncSoon() end)

-- Mitglied: eigenen Rollenwechsel direkt an den Leiter der Suche melden (falls dessen WoW das Ereignis nicht liefert)
local function reportMyRole()
    local want = B2O[(UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")) or ""]
    if not want then return end
    if GetTime() < ((ns.Profile and ns.Profile.lockUntil) or 0) then return end
    ns.RoleLog("report to leader", want)
    for _, g in ipairs(Groups.Active()) do
        if not ns.isMe(g.who) then
            for _, mb in ipairs(members(g)) do
                if ns.isMe(mb.name) and mb.role ~= want then
                    Comm.SendEx({ ch = "GUILD", prio = true }, "W", Comm.whoKey(g.who), "GROLE", g.id, want)
                end
            end
        end
    end
end
ns.On("PLAYER_ROLES_ASSIGNED", function() ns.After(0.05, reportMyRole) end)
Comm.On("GROLE", function(sender, _, id, role)
    local g = Groups.Mine()
    ns.RoleLog("recv GROLE", sender, role, g and g.id or "-", id)
    if not g or g.id ~= id or not ROLES[role] then return end
    Groups.groleAt = Groups.groleAt or {}
    Groups.groleAt[ns.NameKey(sender)] = GetTime()
    for _, mb in ipairs(members(g)) do
        if Comm.whoKey(mb.name) == Comm.whoKey(sender) then
            if mb.role ~= role and Groups.FreeRoles(g)[role] then
                assign(g, mb.name, role)
                ns.RefreshPage("groups")
            end
            return
        end
    end
    -- noch nicht auf der Karte, aber in meiner Gruppe: jetzt eintragen
    if Groups.FreeRoles(g)[role] and Groups.InMyParty and Groups.InMyParty(sender) then
        assign(g, sender, role)
        ns.RefreshPage("groups")
    end
end)

local function firstKey(n) return ns.NameKey(n) end
local function inMyParty(name)
    local k = firstKey(name)
    if k == firstKey(ns.UnitName("player")) then return true end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, n do
        local u = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(u) and firstKey(ns.UnitName(u)) == k then return true end
    end
    return false
end
Groups.InMyParty = inMyParty
-- Klick auf einen freien Platz: bin ich in dieser Gruppe -> meine Rolle dorthin wechseln (auch bei Blizzard),
-- sonst anfragen
function Groups.SlotClick(g, role)
    if not g or not ROLES[role] then return end
    ns.RoleLog("SlotClick", g.id, role)
    local inIt = ns.isMe(g.who)
    for _, mb in ipairs(members(g)) do if ns.isMe(mb.name) then inIt = true end end
    -- auch per Hand eingeladen (steht nicht auf der Karte): ich bin in der WoW-Gruppe des Leiters
    if not inIt and IsInGroup and IsInGroup() and inMyParty(g.who) then inIt = true end
    if not inIt then Groups.Join(g, role) return end
    if not Groups.FreeRoles(g)[role] then return end
    myRole = role
    if ns.Profile and ns.Profile.SetMyRole then ns.Profile.SetMyRole(role, true) end
    if ns.isMe(g.who) then
        assign(g, ns.me(), role)
    else
        Comm.SendEx({ ch = "GUILD", prio = true }, "W", Comm.whoKey(g.who), "GROLE", g.id, role)
        -- sofort bei mir anzeigen (die Karte des Leiters kommt kurz danach und ueberschreibt das)
        local rec = ns.Store.Get("lfg", g.id)
        if rec then
            local list, found = {}, false
            for _, mb in ipairs(members(rec)) do
                if ns.isMe(mb.name) then list[#list + 1] = mb.name .. ":" .. KEY_OF[role] found = true
                else list[#list + 1] = mb.name .. ":" .. KEY_OF[mb.role] end
            end
            if not found then list[#list + 1] = ns.me() .. ":" .. KEY_OF[role] end
            rec.m = table.concat(list, ",")
        end
    end
    K.Toast(L["Rolle gewechselt"], ROLES[role][1], C.accent)
    ns.RefreshPage("groups")
end

ns.slash.grp = function()
    local g = Groups.Mine()
    ns.print("Gruppe: " .. (g and (g.id .. " @" .. tostring(g.started) .. " auto=" .. tostring(g.auto)) or "keine eigene Suche"))
    for n, q in pairs(Groups.requests) do ns.print("  Anfrage " .. n .. " " .. tostring(q.role) .. " " .. tostring(q.state)) end
    for id, j in pairs(Groups.joined or {}) do ns.print("  angefragt bei " .. id .. " vor " .. math.floor(GetTime() - j.t) .. "s") end
end

-- Einladung von einem Leiter, bei dessen Suche ich angefragt (oder zusammengefuehrt) habe -> annehmen
ns.On("PARTY_INVITE_REQUEST", function(inviter)
    if ns.db.settings.lfgAccept == false or not inviter then return end
    local key = ns.NameKey(inviter)
    local ok = false
    for id, j in pairs(Groups.joined or {}) do
        local who = id:match("^lfg%-([^@]+)")
        if who and ns.NameKey(who) == key and GetTime() - (j.t or 0) < 600 then ok = true end
    end
    if Groups.mergeAsked and ns.NameKey(Groups.mergeAsked:match("^lfg%-([^@]+)")) == key then ok = true end
    if not ok then return end
    ns.After(0.3, function()
        if AcceptGroup then pcall(AcceptGroup) end
        if StaticPopup_Hide then StaticPopup_Hide("PARTY_INVITE") end
        K.Toast(L["Einladung angenommen"], ns.displayName(inviter), C.mint)
    end)
end)

-- Gruppe verlassen: erst die alten/neuen WoW-Funktionen, sonst "/leave" vorbereiten (Enter druecken)
function Groups.LeaveGroup()
    if LeaveParty then pcall(LeaveParty) end
    if IsInGroup() and C_PartyInfo and C_PartyInfo.LeaveParty then pcall(C_PartyInfo.LeaveParty) end
    if IsInGroup() and C_PartyInfo and C_PartyInfo.LeaveParty and LE_PARTY_CATEGORY_HOME then pcall(C_PartyInfo.LeaveParty, LE_PARTY_CATEGORY_HOME) end
    ns.After(0.6, function()
        if IsInGroup() then
            ns.OpenChat("/leave")
            K.Toast(L["Gruppe verlassen"], L["WoW erlaubt das Addons nicht direkt - Enter druecken zum Verlassen."], C.amber)
        end
    end)
end

-- Leiter: wer die WoW-Gruppe verlassen hat, verschwindet von der Karte
local function pruneLeft()
    local g = Groups.Mine()
    if not g or not Groups.InMyParty then return end
    local changed = false
    local keep = {}
    for _, mb in ipairs(members(g)) do
        if ns.isMe(mb.name) or Groups.InMyParty(mb.name) then keep[#keep + 1] = mb.name .. ":" .. KEY_OF[mb.role]
        else changed = true end
    end
    if changed then
        rewrite(g, function(r)
            r.m = table.concat(keep, ",")
            r.count = math.max(1, GetNumGroupMembers() or 1)
        end)
        ns.RefreshPage("groups")
    end
end
ns.On("GROUP_ROSTER_UPDATE", function() ns.After(0.4, pruneLeft) end)

-- Anfrage zurueckziehen
function Groups.CancelRequest(g)
    if not g then return end
    if Groups.joined then Groups.joined[Groups.Key(g)] = nil end
    Comm.SendEx({ ch = "GUILD", prio = true }, "W", Comm.whoKey(g.who), "JOINCANCEL", g.id)
    if ns.Store then
        local id = g.id .. ":" .. ns.short(ns.me())
        if ns.Store.Get("lfgreq", id) then ns.Store.Delete("lfgreq", id) end
    end
    K.Toast(L["Anfrage zurueckgezogen"], g.title or "", C.dim)
    Groups.UpdateBadge()
    ns.RefreshPage("groups")
end
local function dropRequest(sender)
    for n in pairs(Groups.requests) do
        if Comm.whoKey(n) == Comm.whoKey(sender) then Groups.requests[n] = nil end
    end
    Groups.UpdateBadge()
    ns.RefreshPage("groups")
end
Comm.On("JOINCANCEL", function(sender, _, id)
    local g = Groups.Mine()
    if g and g.id == id then dropRequest(sender) end
end)
ns.Listen("STORE", function(coll, rec)
    if coll == "lfgreq" and rec and rec.del and rec.by and not ns.isMe(rec.by) then
        local g = Groups.Mine()
        if g and rec.gid == g.id then dropRequest(rec.by) end
    end
end)

-- /oa rolelog: die letzten Eintraege im Chat; /oa rolelog clear: leeren
ns.slash.rolelog = function(arg)
    if arg == "clear" then ns.db.roleLog = {} ns.print("Rollen-Log geleert.") return end
    local l = ns.db.roleLog or {}
    ns.print(("Rollen-Log: %d Eintraege (in SavedVariables: roleLog)"):format(#l))
    for i = math.max(1, #l - 25), #l do ns.print("  " .. l[i]) end
end


------------------------------------------------------------------------
-- Buff-Monitor: ausgelagert nach Modules\RaidTools\BuffMonitor.lua (ns.BuffMonitor, toc direkt nach Groups.lua)
------------------------------------------------------------------------


------------------------------------------------------------------------
-- Auto-Marker: markiert die Gegner (Namensplaketten) klug nach Gruppe und Mob
-- Totenkopf/Kreuz = Kill-Reihenfolge (Caster + Elite zuerst, dann Lebenspunkte),
-- CC-Marken nur, wenn die Klasse in der Gruppe ist (Schaf, Eisfalle, Fesseln, Verbannen, Winterschlaf, Kopfnuss)
------------------------------------------------------------------------
do
    local MK = {}
    ns.Marker = MK
    local STAR, CIRCLE, DIAMOND, TRIANGLE, MOON, SQUARE, CROSS, SKULL = 1, 2, 3, 4, 5, 6, 7, 8
    -- Kreaturtypen (englisch + deutsch)
    local TYPE = {
        Humanoid = "humanoid", Humanoide = "humanoid", Beast = "beast", Wildtier = "beast", Undead = "undead", Untoter = "undead",
        Demon = "demon", ["Dämon"] = "demon", Elemental = "elemental", Elementar = "elemental", Dragonkin = "dragonkin", Drachkin = "dragonkin",
        Critter = "critter", Kleintier = "critter", Giant = "giant", Riese = "giant", Mechanical = "mech", Mechanisch = "mech",
    }
    -- Mindeststufe je Kontrolle (Schaf 8, Kopfnuss 10, Winterschlaf 18, Falle/Fesseln 20, Verbannen 28)
    local NEED = { MAGE = 8, ROGUE = 10, DRUID = 18, HUNTER = 20, PRIEST = 20, WARLOCK = 28 }
    local present = {}   -- hoechste Stufe je Klasse in der Gruppe (auch wenn noch zu niedrig)
    local function groupClasses()
        -- Klasse zaehlt nur, wenn jemand die Kontrolle schon gelernt hat (Mindeststufe)
        local c = {}
        wipe(present)
        local function addUnit(u)
            local _, cf = UnitClass(u)
            local lvl = ns.safe(UnitLevel(u)) or 0
            if cf then present[cf] = math.max(present[cf] or 0, lvl) end
            if cf and lvl >= (NEED[cf] or 1) then c[cf] = true end
        end
        addUnit("player")
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        local raid = IsInRaid and IsInRaid()
        for i = 1, n do
            local u = raid and ("raid" .. i) or ("party" .. i)
            if UnitExists(u) and not UnitIsUnit(u, "player") then addUnit(u) end
        end
        return c
    end
    local function canMark()
        if IsInRaid and IsInRaid() then
            return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
        end
        return true
    end
    -- Gegner aus den Namensplaketten (+ Ziel/Maus)
    local function mobs()
        local out, seen = {}, {}
        -- in Instanzen sind GUIDs/Werte teils "geheim" -> alles entschaerfen, doppelte per UnitIsUnit erkennen
        local sf = ns.safe
        local function add(u)
            if not sf(UnitExists(u)) or sf(UnitIsPlayer(u)) or sf(UnitIsDead(u)) or not sf(UnitCanAttack("player", u)) then return end
            local g = sf(UnitGUID(u))
            if g then
                if seen[g] then return end
                seen[g] = true
            else
                for _, m in ipairs(out) do if sf(UnitIsUnit(m.unit, u)) then return end end
                g = u
            end
            local ct = sf(UnitCreatureType(u)) or ""
            local cl = sf(UnitClassification(u)) or "normal"
            local pt = sf(UnitPowerType(u))
            out[#out + 1] = {
                unit = u, guid = g, hp = sf(UnitHealthMax(u)) or 0, type = TYPE[ct] or "other",
                caster = pt == 0 and (sf(UnitPowerMax(u, 0)) or 0) > 0,
                elite = cl == "elite" or cl == "rareelite" or cl == "worldboss",
                fighting = sf(UnitAffectingCombat(u)) or false,
                level = sf(UnitLevel(u)),
                isTarget = sf(UnitIsUnit(u, "target")) or false,
                mark = sf(GetRaidTargetIndex(u)),
            }
        end
        for i = 1, 40 do add("nameplate" .. i) end
        add("target")
        add("mouseover")
        return out
    end
    -- Reihenfolge: dein Ziel zuerst, dann hoehere Stufe (Boss), Caster, Elite, Leben
    local function killScore(m)
        local lvl = m.level or 0
        if lvl < 0 then lvl = 99 end   -- "??" = Boss
        local tgt = (m.isTarget and ns.db.settings.mkTarget ~= false) and 1e12 or 0
        return tgt + lvl * 1e9 + (m.caster and 1e7 or 0) + (m.elite and 1e6 or 0) + m.hp
    end

    local ICONNAME = { "Stern", "Kreis", "Diamant", "Dreieck", "Mond", "Quadrat", "Kreuz", "Totenkopf" }
    -- SetRaidTarget ist in diesem Client Blizzard vorbehalten (Addon wird sonst geblockt):
    -- Oasis markiert nicht selbst, sondern zeigt den Vorschlag im Chat (setzen per /tm oder Blizzard-Tasten)
    function MK.Mark(test)
        test = test or true
        if not canMark() then ns.print(L["Markieren: im Raid nur als Leiter oder Assistent."]) return end
        local list = mobs()
        -- Schnell-Einstellung: nur Gegner, die schon kaempfen (dein Ziel zaehlt immer)
        if ns.db.settings.mkFight then
            local keep = {}
            for _, m in ipairs(list) do if m.fighting or m.isTarget then keep[#keep + 1] = m end end
            list = keep
        end
        if #list == 0 then ns.print(L["Keine Gegner gefunden - Namensplaketten der Gegner einschalten (Taste V)."]) return end
        local cls = groupClasses()
        -- abgeschaltete CC-Marken bzw. CC ganz aus
        local ccOff = ns.db.settings.mkOff or {}
        if ns.db.settings.mkCC == false then cls = {} end
        table.sort(list, function(a, b) return killScore(a) > killScore(b) end)
        local used, plan = {}, {}
        local function give(m, icon) if m and not plan[m.guid] and not used[icon] and not (icon ~= 8 and icon ~= 7 and ccOff[icon]) then plan[m.guid] = icon used[icon] = true m.done = true end end
        -- zuerst Totenkopf und Kreuz: die beiden Gegner, die nacheinander sterben (CC nur auf den Rest)
        do
            local k = 0
            for _, m in ipairs(list) do
                if not m.done then
                    k = k + 1
                    if k == 1 then give(m, SKULL) elseif k == 2 then give(m, CROSS) break end
                end
            end
        end
        -- bei 1-2 Gegnern nur Kill-Reihenfolge
        if #list >= 3 then
            -- CC zuerst auf die, die NICHT zuerst sterben sollen (also von hinten in der Kill-Liste)
            -- nie CC auf dein Ziel oder den Staerksten (Boss, hoehere Stufe als der Rest)
            local minL, maxL = 999, -1
            for _, m in ipairs(list) do
                local l = m.level or 0
                if l < 0 then l = 99 end
                if l < minL then minL = l end
                if l > maxL then maxL = l end
            end
            local function noCC(m)
                local l = m.level or 0
                if l < 0 then l = 99 end
                return m.isTarget or m.type == "boss" or m.elite and l == maxL and maxL > minL or (l == maxL and maxL >= minL + 2)
            end
            local function ccPick(fn, prefer)
                local best
                for i = #list, 2, -1 do
                    local m = list[i]
                    if not m.done and not noCC(m) and (m.type == "other" or fn(m)) then
                        if not best or (prefer and prefer(m) and not prefer(best)) then best = m end
                    end
                end
                return best
            end
            if cls.MAGE then give(ccPick(function(m) return m.type == "humanoid" or m.type == "beast" or m.type == "critter" end, function(m) return m.caster end), MOON) end
            if cls.HUNTER then give(ccPick(function(m) return m.type ~= "mech" end, function(m) return not m.caster end), SQUARE) end
            if cls.PRIEST then give(ccPick(function(m) return m.type == "undead" end), STAR) end
            if cls.WARLOCK then give(ccPick(function(m) return m.type == "demon" or m.type == "elemental" end), DIAMOND) end
            if cls.DRUID then give(ccPick(function(m) return m.type == "beast" or m.type == "dragonkin" end), CIRCLE) end
            if cls.ROGUE then give(ccPick(function(m) return m.type == "humanoid" and not m.fighting end), TRIANGLE) end
        end
        local n = 0
        if test == "plan" then
            local out = {}
            for _, m in ipairs(list) do
                local icon = plan[m.guid]
                if icon and m.mark ~= icon then out[#out + 1] = { unit = m.unit, icon = icon } end
            end
            return out
        end
        if test then
            -- Testmodus: nur im Chat zeigen, was markiert wuerde und warum
            local c = {}
            for k in pairs(cls) do c[#c + 1] = k end
            ns.print((L["Marker-Vorschlag: %d Gegner (setzen: Ziel waehlen, /tm 8 = Totenkopf, /tm 7 = Kreuz ...)"]):format(#list))
            for _, m in ipairs(list) do
                local icon = plan[m.guid]
                ns.print(("  %s %s  |cff888888%s, %d HP%s%s|r"):format(icon and ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. icon .. ":14|t " .. L[ICONNAME[icon]]) or "|cff666666-|r",
                    ns.safe(ns.UnitName(m.unit)) or "?", m.type, m.hp, m.caster and ", Caster" or "", m.elite and ", Elite" or ""))
            end
            return
        end
        for _, m in ipairs(list) do
            local icon = plan[m.guid]
            if icon and m.mark ~= icon then pcall(SetRaidTarget, m.unit, icon) n = n + 1 end
        end
        if n > 0 and ns.Sound then ns.Sound.Play("toast") end
    end
    -- Ansage: welche Marke was bedeutet. Gruppenchat = Sprache des eigenen Clients;
    -- "nur Oasis" geht per Addon-Nachricht, jeder Empfaenger zeigt sie in seiner Sprache.
    local SHOUT_ORDER = { 8, 7, 5, 6, 4, 3, 2, 1 }
    local SHOUT_TEXT = { [8] = "zuerst", [7] = "als Zweites", [5] = "Schaf", [6] = "Eisfalle", [4] = "Kopfnuss",
        [3] = "Verbannen", [2] = "Winterschlaf", [1] = "Fesseln" }
    function MK.ShoutText(icons, forChat)
        local parts = {}
        for _, i in ipairs(SHOUT_ORDER) do
            if icons[i] then parts[#parts + 1] = (forChat and ("{rt" .. i .. "}") or ("|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i .. ":14|t")) .. " " .. L[SHOUT_TEXT[i]] end
        end
        return table.concat(parts, "   ")
    end
    function MK.Shout(plan)
        local S = ns.db.settings
        if not S.mkShout or not IsInGroup() then return end
        local icons, keys = {}, {}
        for _, p in ipairs(plan) do icons[p.icon] = true end
        for i in pairs(icons) do keys[#keys + 1] = i end
        if #keys == 0 then return end
        -- gleiche Ansage nicht alle paar Sekunden wiederholen
        table.sort(keys)
        local sig = table.concat(keys, ",")
        if MK.lastShout == sig and GetTime() - (MK.lastShoutT or 0) < 20 then return end
        MK.lastShout, MK.lastShoutT = sig, GetTime()
        if S.mkShoutOasis then
            ns.Comm.Group("MKCALL", sig)
            ns.print(L["Marken"] .. ":  " .. MK.ShoutText(icons, false))
        else
            local ch = ns.groupChannel()
            if ch then ns.SendChat(MK.ShoutText(icons, true), ch) end
        end
    end
    ns.Comm.On("MKCALL", function(sender, _, sig)
        if ns.isMe(sender) or type(sig) ~= "string" then return end
        if not SEC.Rate("mkcall:" .. sender, 10) then return end   -- keine Chat-Flut
        local icons = {}
        for n in sig:sub(1, 40):gmatch("%d+") do
            n = SEC.Num(n, 1, 8, true)
            if n then icons[n] = true end
        end
        ns.print((ns.displayName and ns.displayName(sender) or ns.short(sender)) .. " - " .. L["Marken"] .. ":  " .. MK.ShoutText(icons, false))
    end)
    function MK.Clear()
        if not canMark() then return end
        ns.print(L["Marken entfernen: Ziel waehlen und /tm 0 - Addons duerfen Marken nicht mehr selbst setzen."])
    end
    -- Automatisch markieren ueber einen sicheren Makro-Knopf (/tm ist erlaubt, SetRaidTarget aus Addons nicht):
    -- Klick setzt auf die sichtbaren Gegner-Plaketten Totenkopf, Kreuz und die CC-Marken der Gruppe.
    -- Das Makro wird nur ausserhalb des Kampfes neu geschrieben.
    local secure
    local function markIcons()
        local cls = groupClasses()
        local icons = { 8, 7 }
        if cls.MAGE then icons[#icons + 1] = 5 end
        if cls.HUNTER then icons[#icons + 1] = 6 end
        if cls.ROGUE then icons[#icons + 1] = 4 end
        if cls.WARLOCK then icons[#icons + 1] = 3 end
        if cls.DRUID then icons[#icons + 1] = 2 end
        if cls.PRIEST then icons[#icons + 1] = 1 end
        return icons
    end
    function MK.UpdateSecure()
        if not secure or InCombatLockdown() then MK.dirty = true return end
        MK.dirty = nil
        local set, clr = {}, {}
        local fw, bw = {}, {}
        for i = 1, 8 do fw[#fw + 1] = ("[@nameplate%d,harm,nodead]"):format(i) end
        for i = 8, 1, -1 do bw[#bw + 1] = ("[@nameplate%d,harm,nodead]"):format(i) end
        set[1] = "/tm " .. table.concat(fw) .. " 8"
        set[2] = "/tm " .. table.concat(bw) .. " 7"
        -- Makros duerfen hoechstens 1023 Zeichen haben (40 Zeilen waren zu lang -> Rechtsklick tat nichts)
        clr[#clr + 1] = "/tm [@target,exists] 0"
        for i = 1, 30 do clr[#clr + 1] = ("/tm [@nameplate%d,exists] 0"):format(i) end
        secure:SetAttribute("type1", "macro")
        secure:SetAttribute("macrotext1", table.concat(set, "\n"))
        secure:SetAttribute("type2", "macro")
        secure:SetAttribute("macrotext2", table.concat(clr, "\n"))
        -- Shift + Linksklick: Auto-Marker-Fenster auf/zu
        secure:SetAttribute("shift-type1", "macro")
        secure:SetAttribute("shift-macrotext1", "/oa mark button")
    end
    -- vor dem Klick (ausserhalb des Kampfes): genauen Plan aus den echten Plaketten ins Makro schreiben
    function MK.PreClick(self, btn)
        if InCombatLockdown() or btn ~= "LeftButton" or IsShiftKeyDown() then return end
        local ok, plan = pcall(MK.Mark, "plan")
        if not ok or type(plan) ~= "table" then return end
        if #plan == 0 then
            ns.print(L["Keine Gegner gefunden - Namensplaketten der Gegner einschalten (Taste V)."])
            self:SetAttribute("macrotext1", "")
            return
        end
        local lines = {}
        for _, p in ipairs(plan) do lines[#lines + 1] = ("/tm [@%s] %d"):format(p.unit, p.icon) end
        self:SetAttribute("macrotext1", table.concat(lines, "\n"))
        MK.lastPlan = plan
    end
    function MK.Secure()
        if secure then return secure end
        if InCombatLockdown() then return nil end
        secure = CreateFrame("Button", "OasisMarkSecure", UIParent, "SecureActionButtonTemplate")
        secure:SetSize(22, 22)
        secure:SetFrameStrata("HIGH")
        -- nur beim Loslassen ausloesen (sonst laeuft das Makro zweimal und /tm schaltet die Marke gleich wieder ab)
        secure:RegisterForClicks("AnyUp")
        secure:SetAttribute("useOnKeyDown", false)
        secure:Hide()
        MK.UpdateSecure()
        secure:SetScript("PreClick", MK.PreClick)
        secure:SetScript("PostClick", function(_, btn)
            if btn == "LeftButton" and MK.lastPlan then pcall(MK.Shout, MK.lastPlan) end
            MK.lastPlan = nil
            if not InCombatLockdown() then MK.UpdateSecure() end
        end)
        return secure
    end
    ns.On("GROUP_ROSTER_UPDATE", function() MK.UpdateSecure() end)
    ns.On("PLAYER_REGEN_ENABLED", function()
        if MK.dirty then MK.UpdateSecure() end
        if MK.afterCombat then local f = MK.afterCombat MK.afterCombat = nil pcall(f) end
    end)
    ns.Listen("LOGIN", function() MK.Secure() end)
    ns.Relabel(function()
        _G["BINDING_NAME_CLICK OasisMarkSecure:LeftButton"] = L["Gegner automatisch markieren"]
        _G["BINDING_NAME_CLICK OasisMarkSecure:RightButton"] = L["Marken entfernen"]
        _G.BINDING_NAME_OASIS_AUTOMARK = L["Gegner automatisch markieren"]
        _G.BINDING_NAME_OASIS_CLEARMARK = L["Marken entfernen"]
    end)

    -- Tastenbelegung (Bindings.xml) ruft diese auf
    _G.OasisAutoMark = function() MK.Mark() end
    _G.OasisClearMarks = function() MK.Clear() end
    _G.BINDING_HEADER_OASIS = "Oasis"

    -- schwebende Box: grosser Marker-Knopf + Schnell-Einstellungen (verschiebbar, nur ausserhalb des Kampfes)
    local btn, box
    local CC = {
        { icon = 5, cls = "MAGE", text = "Mond = Schaf (Magier)" },
        { icon = 6, cls = "HUNTER", text = "Quadrat = Eisfalle (Jaeger)" },
        { icon = 4, cls = "ROGUE", text = "Dreieck = Kopfnuss (Schurke)" },
        { icon = 3, cls = "WARLOCK", text = "Diamant = Verbannen (Hexenmeister)" },
        { icon = 2, cls = "DRUID", text = "Kreis = Winterschlaf (Druide)" },
        { icon = 1, cls = "PRIEST", text = "Stern = Fesseln (Priester)" },
    }
    local function RT(i) return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. i end
    function MK.UpdateBox()
        if not box then return end
        local S = ns.db.settings
        for _, t in ipairs(box.toggles) do t:Refresh() end
        if box.shoutSeg then
            box.shoutSeg:Select(S.mkShoutOasis and "oasis" or "chat")
            box.shoutSeg:SetAlpha(S.mkShout and 1 or 0.35)
        end
        local cls = groupClasses()
        local off = S.mkOff or {}
        local ccOn = S.mkCC ~= false
        for _, c in ipairs(box.cc) do
            local on = ccOn and not off[c.icon]
            local have = cls[c.cls]
            c.tex:SetDesaturated(not on)
            c:SetAlpha(on and (have and 1 or 0.45) or 0.25)
            local K, C = ns.K, ns.K.C
            K.SetBorderColor(c, (on and have) and C.accent or C.line)
        end
    end
    local function buildBox()
        local K, C = ns.K, ns.K.C
        box = CreateFrame("Frame", "OasisMarkerBox", UIParent)
        box:SetSize(262, 314)
        -- ueber dem Oasis-Fenster (HIGH), sonst oeffnet es sich unsichtbar dahinter
        box:SetFrameStrata("DIALOG")
        box:SetClampedToScreen(true)
        box:SetMovable(true)
        box:EnableMouse(true)
        local pos = ns.db.settings.markerPos
        if pos and pos[1] then box:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2]) else box:SetPoint("CENTER", -200, -150) end
        K.Fill(box, { 0.04, 0.04, 0.05, 0.94 })
        K.Border(box, C.line)
        if K.ApplySkin then K.ApplySkin(box, "panel", { 0.04, 0.04, 0.05, 0.94 }) end
        -- Kopf (zum Verschieben)
        local head = CreateFrame("Frame", nil, box)
        head:SetPoint("TOPLEFT") head:SetPoint("TOPRIGHT") head:SetHeight(26)
        head:EnableMouse(true)
        head:RegisterForDrag("LeftButton")
        head:SetScript("OnDragStart", function() if not InCombatLockdown() then box:StartMoving() end end)
        head:SetScript("OnDragStop", function()
            box:StopMovingOrSizing()
            ns.db.settings.markerPos = { box:GetLeft(), box:GetTop() }
        end)
        local bar = head:CreateTexture(nil, "ARTWORK")
        bar:SetPoint("TOPLEFT", 10, -9) bar:SetSize(3, 12)
        bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        local title = K.Text(head, 11, C.text)
        title:SetPoint("LEFT", bar, "RIGHT", 7, 0)
        title:SetText(K.Upper(L["Auto-Marker"]))
        local x = K.CloseButton(box, function()
            if InCombatLockdown() then ns.print(L["Erst nach dem Kampf moeglich."]) return end
            MK.Toggle(false)
        end)
        x:SetPoint("TOPRIGHT", -4, -3)
        -- ueber dem Zieh-Kopf, sonst schluckt der Kopf den Klick aufs X
        x:SetFrameLevel(head:GetFrameLevel() + 5)
        -- grosser sicherer Knopf (gleiches Makro wie die Taste)
        btn = CreateFrame("Button", "OasisMarkerButton", box, "SecureActionButtonTemplate")
        btn:SetSize(48, 48)
        btn:SetPoint("TOPLEFT", 14, -38)
        btn:RegisterForClicks("AnyUp")
        btn:SetAttribute("useOnKeyDown", false)
        btn.bg = K.Fill(btn, { 0.08, 0.08, 0.09, 1 })
        K.Border(btn, C.line)
        btn.icon = btn:CreateTexture(nil, "ARTWORK")
        btn.icon:SetPoint("TOPLEFT", 5, -5)
        btn.icon:SetPoint("BOTTOMRIGHT", -5, 5)
        btn.icon:SetTexture(RT(8))
        local function copy()
            MK.Secure()
            if not secure then return end
            for _, a in ipairs({ "type1", "macrotext1", "type2", "macrotext2" }) do btn:SetAttribute(a, secure:GetAttribute(a)) end
        end
        copy()
        btn:SetScript("PreClick", MK.PreClick)
        btn:SetScript("PostClick", function() if not InCombatLockdown() then MK.UpdateSecure() end end)
        hooksecurefunc(MK, "UpdateSecure", function() if not InCombatLockdown() then copy() end end)
        btn:SetScript("OnEnter", function(self)
            K.SetBorderColor(self, C.accent)
            K.ShowTip(self, { L["Auto-Marker"], L["Linksklick: Gegner markieren (nochmal = Marken weg)"], L["Rechtsklick: Marken entfernen"], " ",
                "|cff888888" .. L["Markiert die sichtbaren Gegner-Plaketten (Taste V) der Reihe nach."] .. "|r",
                "|cff888888" .. L["Totenkopf/Kreuz = zuerst toeten (Caster, Elite, viel Leben)"] .. "|r",
                "|cff888888" .. L["Tastenbelegung: Optionen > Tastaturbelegung > Oasis"] .. "|r" })
        end)
        btn:SetScript("OnLeave", function(self) K.SetBorderColor(self, C.line) GameTooltip:Hide() end)
        -- rechts neben dem Knopf: was er tut (Maus-Symbole statt Fliesstext)
        local function mouseLine(y, atlas, text)
            local ic = box:CreateTexture(nil, "ARTWORK")
            ic:SetSize(14, 14)
            ic:SetPoint("TOPLEFT", btn, "TOPRIGHT", 12, y)
            if not pcall(ic.SetAtlas, ic, atlas) then ic:SetTexture(RT(atlas == "newplayertutorial-icon-mouse-leftbutton" and 8 or 7)) end
            local t = K.Text(box, 11, C.text)
            t:SetPoint("LEFT", ic, "RIGHT", 6, 0)
            t:SetText(text)
        end
        mouseLine(-6, "newplayertutorial-icon-mouse-leftbutton", L["Gegner markieren"])
        mouseLine(-28, "newplayertutorial-icon-mouse-rightbutton", "|cffaaaaaa" .. L["Marken entfernen"] .. "|r")
        local function section(y, text)
            local t = K.Text(box, 10, C.dim)
            t:SetPoint("TOPLEFT", 14, y)
            t:SetText(K.Upper(text))
            local ln = box:CreateTexture(nil, "ARTWORK")
            ln:SetColorTexture(C.line[1], C.line[2], C.line[3], 0.7)
            ln:SetHeight(1)
            ln:SetPoint("LEFT", t, "RIGHT", 8, 0)
            ln:SetPoint("RIGHT", box, "RIGHT", -14, 0)
        end
        section(-100, L["Einstellungen"])
        -- Schnell-Einstellungen
        local S = ns.db.settings
        box.toggles = {}
        local function tg(y, label, key, def, desc)
            if S[key] == nil and def ~= nil then S[key] = def end
            local t = K.Toggle(box, L[label], function() return ns.db.settings[key] and true or false end, function(v)
                ns.db.settings[key] = v
                MK.UpdateBox()
            end)
            t:SetPoint("TOPLEFT", 14, y)
            t:SetPoint("RIGHT", box, "RIGHT", -14, 0)
            if desc then
                t:HookScript("OnEnter", function(self) K.ShowTip(self, { L[label], L[desc] }) end)
                t:HookScript("OnLeave", function() GameTooltip:Hide() end)
            end
            box.toggles[#box.toggles + 1] = t
        end
        tg(-116, "CC-Marken setzen", "mkCC", true, "Aus: nur Totenkopf und Kreuz (Kill-Reihenfolge)")
        tg(-142, "Dein Ziel zuerst", "mkTarget", true, "Dein aktuelles Ziel bekommt den Totenkopf")
        tg(-168, "Nur Gegner im Kampf", "mkFight", false, "Gegner, die noch nicht kaempfen, bleiben ohne Marke")
        tg(-194, "Ansage in die Gruppe", "mkShout", false, "Nach dem Markieren: welche Marke was bedeutet (z.B. Mond = Schaf)")
        -- wohin die Ansage geht: Gruppenchat (alle, eigene Client-Sprache) oder nur Oasis (jeder in seiner Sprache)
        box.shoutSeg = K.Segments(box, { { key = "chat", text = L["Gruppenchat"] }, { key = "oasis", text = L["Nur Oasis-Spieler"] } }, function(k)
            ns.db.settings.mkShoutOasis = (k == "oasis") or nil
            MK.UpdateBox()
        end, nil, { size = 10, pad = 14 })
        box.shoutSeg:SetPoint("TOPLEFT", 52, -220)
        box.shoutSeg:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Ansage"], L["Gruppenchat: alle sehen sie, in deiner Sprache."], L["Nur Oasis-Spieler: jeder sieht sie in seiner eigenen Sprache."] }) end)
        box.shoutSeg:HookScript("OnLeave", function() GameTooltip:Hide() end)
        section(-252, L["CC-Marken (Klick: an/aus)"])
        -- CC-Marken einzeln an/aus
        box.cc = {}
        for i, c in ipairs(CC) do
            local b = CreateFrame("Button", nil, box)
            b:SetSize(32, 32)
            b:SetPoint("TOPLEFT", 14 + (i - 1) * 39, -268)
            K.Fill(b, { 0.08, 0.08, 0.09, 1 })
            K.Border(b, C.line)
            b.tex = b:CreateTexture(nil, "ARTWORK")
            b.tex:SetPoint("TOPLEFT", 3, -3)
            b.tex:SetPoint("BOTTOMRIGHT", -3, 3)
            b.tex:SetTexture(RT(c.icon))
            b.icon, b.cls = c.icon, c.cls
            b:SetScript("OnClick", function()
                local s = ns.db.settings
                s.mkOff = s.mkOff or {}
                s.mkOff[c.icon] = (not s.mkOff[c.icon]) or nil
                MK.UpdateBox()
            end)
            b:SetScript("OnEnter", function(self)
                local have = groupClasses()[c.cls]
                local off = (ns.db.settings.mkOff or {})[c.icon]
                local state
                if off then state = "|cffff5a4a" .. L["abgeschaltet"] .. "|r"
                elseif have then state = "|cff66db9e" .. L["Klasse in der Gruppe"] .. "|r"
                elseif present[c.cls] then
                    -- Klasse ist dabei, aber noch zu niedrig fuer die Faehigkeit
                    state = "|cffffc24d" .. (L["Kann es noch nicht: Stufe %d, lernt man ab Stufe %d"]):format(present[c.cls], NEED[c.cls] or 1) .. "|r"
                else state = "|cff888888" .. L["Klasse gerade nicht in der Gruppe"] .. "|r" end
                K.ShowTip(self, { L[c.text], state,
                    "|cff888888" .. L["Klick: an/aus"] .. "|r" })
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            box.cc[i] = b
        end
        box:Hide()   -- neu gebaute Frames sind sichtbar: erst beim Toggle zeigen
        MK.UpdateBox()
    end
    function MK.Toggle(force)
        if not box then
            if InCombatLockdown() then ns.print(L["Erst nach dem Kampf moeglich."]) return end
            buildBox()
        end
        local show = force
        if show == nil then show = not box:IsShown() end
        if InCombatLockdown() then ns.print(L["Erst nach dem Kampf moeglich."]) return end
        box:SetShown(show)
        ns.db.settings.markerShow = show
        if show then
            box:Raise()
            MK.UpdateBox()
            -- liegt das Fenster ausserhalb des Bildschirms (alte Position), in die Mitte holen
            if not box:GetLeft() or box:GetLeft() < 0 or box:GetTop() > UIParent:GetHeight() then
                box:ClearAllPoints() box:SetPoint("CENTER", 0, 0)
            end
        end
    end
    ns.On("GROUP_ROSTER_UPDATE", function() if box and box:IsShown() then MK.UpdateBox() end end)
    ns.Listen("LOGIN", function() if ns.db.settings.markerShow then MK.Toggle(true) end end)
    ns.slash.mark = function(arg)
        if arg == "debug" then
            local sc = MK.Secure()
            ns.print("Marker: " .. (sc and ((sc:IsShown() and "sichtbar" or "versteckt") .. " @ " .. tostring(sc:GetLeft()) .. "," .. tostring(sc:GetBottom())) or "fehlt"))
            -- 0.5.742: tostring() ohne Wert (GetAttribute lieferte nichts) war der Fehler; Ebene/Strata dazu, damit man sieht, wer oben liegt
            local mt = sc and sc:GetAttribute("macrotext1")
            ns.print(sc and ((tostring(mt or "(leer)")):gsub("\n", " | ")) or "-")
            if sc then ns.print(("Strata %s, Ebene %s, Groesse %sx%s"):format(tostring(sc:GetFrameStrata()), tostring(sc:GetFrameLevel()), tostring(sc:GetWidth()), tostring(sc:GetHeight()))) end
            return
        end
        if arg == "clear" then MK.Clear() elseif arg == "button" then MK.Toggle() elseif arg == "test" then MK.Mark(true) else MK.Mark() end
    end
end

-- Wochenaufgaben: erst werten, wenn die Gruppe wirklich zustande kommt
ns.On("GROUP_ROSTER_UPDATE", function()
    if not (ns.Rewards and ns.Rewards.Credit) then return end
    local j = Groups.weekJoin
    if j and GetTime() - j.t < 1800 and UnitInParty(ns.short(j.who)) then
        Groups.weekJoin = nil
        ns.Rewards.Credit("joined", j.who)
    end
    if Groups.weekStart and GetTime() - Groups.weekStart < 7200 and ns.Badges and ns.Badges.GuildInGroup and ns.Badges.GuildInGroup() > 0 then
        Groups.weekStart = nil
        ns.Rewards.Credit("lfgStarted")
    end
end)

------------------------------------------------------------------------
-- Weltkarte (0.5.934): offene Gruppensuchen als Zeichen am Dungeon-Eingang. Klick oeffnet die Gruppensuche.
-- Eingaenge stammen aus den Dungeon-Quests (QuestLocations: "entrance") - Dungeons ohne solchen Eintrag haben kein Zeichen.
------------------------------------------------------------------------
local entrances
function Groups.Entrances()
    if entrances then return entrances end
    if not (ns.DungeonData and ns.QuestLocations) then return {} end
    entrances = {}
    for _, d in ipairs(ns.DungeonData) do
        for _, q in ipairs(d.quests or {}) do
            local loc = ns.QuestLocations[q.id]
            local e = loc and ((loc.start and loc.start.entrance) or (loc.finish and loc.finish.entrance))
            if e and e.map and e.x and e.y then
                entrances[#entrances + 1] = { d = d, map = e.map, x = e.x / 100, y = e.y / 100 }
                break
            end
        end
    end
    -- Anzeigename aus der Dungeon-Liste (so heisst das Ziel auch in der Gruppensuche)
    for _, ld in ipairs(ns.Dungeons and ns.Dungeons.List and ns.Dungeons.List() or {}) do
        for _, e in ipairs(entrances) do
            if (ld.key and ld.key == e.d.key) or (ld.nameEN and ld.nameEN == e.d.name) then e.alt = ld.name end
        end
    end
    return entrances
end
-- Suchen je Eingang: der Titel der Suche muss den Dungeon-Namen enthalten (englisch, deutsch oder in der eigenen Sprache)
function Groups.AtEntrances()
    local out = {}
    local active = Groups.Active()
    if #active == 0 then return out end
    for _, e in ipairs(Groups.Entrances()) do
        local names = { e.d.name, e.d.de, e.alt }
        local hit
        for _, g in ipairs(active) do
            local title = tostring(g.title or ""):lower()
            for i = 1, 3 do
                local nm = names[i]
                if type(nm) == "string" and #nm > 3 and title:find(nm:lower(), 1, true) then
                    hit = hit or { e = e, groups = {} }
                    hit.groups[#hit.groups + 1] = g
                    break
                end
            end
        end
        if hit then out[#out + 1] = hit end
    end
    return out
end
local lfgPool, lfgUsed = {}, 0
function Groups.DrawWorld()
    for i = 1, lfgUsed do lfgPool[i]:Hide() end
    lfgUsed = 0
    if ns.db.settings.lfgPins == false or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local mapID = WorldMapFrame:GetMapID()
    local canvas = WorldMapFrame:GetCanvas()
    if not mapID or not canvas or not (ns.Map and ns.Map.translate) then return end
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local cscale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    local s = (1 / math.max(cscale, 0.01)) * (ns.db.settings.mapPinScale or 1)
    for _, hit in ipairs(Groups.AtEntrances()) do
        local x, y = ns.Map.translate(hit.e.map, hit.e.x, hit.e.y, mapID)
        if x and x > 0 and x < 1 and y > 0 and y < 1 then
            lfgUsed = lfgUsed + 1
            local p = lfgPool[lfgUsed]
            if not p then
                p = CreateFrame("Button", nil, canvas)
                p:SetSize(22, 22)
                p.bg = p:CreateTexture(nil, "BACKGROUND")
                p.bg:SetTexture(ns.MEDIA .. "pindisc")
                p.bg:SetAllPoints()
                p.bg:SetVertexColor(0.04, 0.04, 0.05, 1)
                p.icon = p:CreateTexture(nil, "ARTWORK")
                p.icon:SetTexture(ns.MEDIA .. "icons\\groups")
                p.icon:SetPoint("TOPLEFT", 5, -5) p.icon:SetPoint("BOTTOMRIGHT", -5, 5)
                p.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
                p.ring = p:CreateTexture(nil, "OVERLAY")
                p.ring:SetTexture(ns.MEDIA .. "pinring")
                p.ring:SetAllPoints()
                p.ring:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
                p.num = K.Text(p, 10, C.text)
                p.num:SetPoint("BOTTOMLEFT", p, "TOPRIGHT", -6, -6)
                p.num:SetShadowOffset(1, -1)
                p:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
                p:SetScript("OnLeave", function() GameTooltip:Hide() end)
                p:SetScript("OnClick", function()
                    ns.ShowPage("groups")
                    if ns.OasisFront then ns.OasisFront() end
                end)
                lfgPool[lfgUsed] = p
            end
            if p:GetParent() ~= canvas then p:SetParent(canvas) end
            local tip = {}
            for _, g in ipairs(hit.groups) do
                local free = {}
                if g.tank then free[#free + 1] = L["Tank"] end
                if g.heal then free[#free + 1] = L["Heiler"] end
                if g.dps then free[#free + 1] = L["DD"] end
                tip[#tip + 1] = "|cffffd24a" .. tostring(g.title or "?") .. "|r"
                tip[#tip + 1] = ns.displayName(g.who or "?") .. (#free > 0 and ("  ·  " .. L["sucht:"] .. " " .. table.concat(free, ", ")) or "")
            end
            tip[#tip + 1] = "|cff888888" .. L["Klick: Gruppensuche oeffnen"] .. "|r"
            p.tip = tip
            p.num:SetText(#hit.groups > 1 and tostring(#hit.groups) or "")
            p:SetScale(s)
            p:ClearAllPoints()
            p:SetPoint("CENTER", canvas, "TOPLEFT", (x * cw) / s, (-y * ch) / s)
            p:SetFrameStrata(canvas:GetFrameStrata())
            p:SetFrameLevel(canvas:GetFrameLevel() + 58)
            p:Show()
        end
    end
end
ns.Listen("LOGIN", function()
    if ns.Map and ns.Map.UpdateWorldPins then hooksecurefunc(ns.Map, "UpdateWorldPins", function() pcall(Groups.DrawWorld) end) end
end)
ns.Listen("STORE", function(coll) if coll == "lfg" and WorldMapFrame and WorldMapFrame:IsShown() then pcall(Groups.DrawWorld) end end)

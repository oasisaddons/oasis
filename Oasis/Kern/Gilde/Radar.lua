-- Oasis Modul 1: Gilden-Radar (Mitglieder, Profile, Level-Rennen)
local ADDON, ns = ...
local L = ns.L
local K, C, Comm = ns.K, ns.K.C, ns.Comm
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

local Radar = {}
ns.Radar = Radar
Radar.roster = {}       -- Liste aus der Gildenliste
Radar.byName = {}
Radar.online, Radar.total = 0, 0

local MILESTONES = { 10, 20, 30, 40, 50, 60 }

------------------------------------------------------------------------
-- Eigenes Profil
------------------------------------------------------------------------
local function myProfessions()
    local out = {}
    if not GetProfessions then return out end
    local ok, a, b, c, d, e = pcall(GetProfessions)
    if not ok then return out end
    for _, idx in ipairs({ a, b, c, d, e }) do
        if idx then
            local name, _, rank, maxRank, _, _, skillLine = ns.safeAll(GetProfessionInfo(idx))
            if name then out[#out + 1] = { name = name, rank = rank or 0, max = maxRank or 0, id = skillLine } end
        end
    end
    return out
end
Radar.myProfessions = myProfessions

local function encodeProfs(list)
    local p = {}
    for _, x in ipairs(list) do p[#p + 1] = x.name .. "/" .. x.rank .. "/" .. x.max .. "/" .. (x.id or 0) end
    return table.concat(p, "+")
end
function Radar.decodeProfs(s)
    local out = {}
    if not s or s == "" then return out end
    for part in s:gmatch("[^+]+") do
        local n, r, m, id = part:match("^(.-)/(%d+)/(%d+)/?(%d*)$")
        if n then
            id = tonumber(id)
            -- Berufsname in der eigenen Sprache, falls die Skill-Line bekannt ist
            if id and id > 0 and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
                local ok, local_ = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, id)
                if ok and ns.safe(local_) and local_ ~= "" then n = local_ end
            end
            out[#out + 1] = { name = n, rank = tonumber(r), max = tonumber(m), id = id }
        end
    end
    return out
end
-- Tooltip fuer die Berufe-Symbole: Symbol, Name, Stufe (/ Hoechststufe)
function Radar.ProfTip(owner, name, raw)
    local profs = Radar.decodeProfs(raw)
    local lines = { L["Berufe"] .. (name and ("  |cff888888" .. ns.displayName(name) .. "|r") or "") }
    if #profs == 0 then lines[#lines + 1] = "|cff777777" .. L["Keine Berufe bekannt"] .. "|r" end
    for _, pf in ipairs(profs) do
        local hasMax = pf.max and pf.max > 0
        local maxed = hasMax and pf.rank >= pf.max
        lines[#lines + 1] = Radar.ProfIcon(pf, 14, maxed and C.amber or C.text) .. "  " .. pf.name .. "   "
            .. (maxed and "|cffe8b44a" or "|cffffffff") .. pf.rank .. "|r" .. (hasMax and ("|cff777777 / " .. pf.max .. "|r") or "")
    end
    K.ShowTip(owner, lines, "ANCHOR_RIGHT")
end
-- unsichtbare Hover-Flaeche ueber einer Berufe-Spalte; Klick geht an die Zeile weiter
function Radar.AttachProfTip(row, fs, getRaw)
    -- genau so breit wie die Symbole (Tooltip haengt dann direkt rechts daneben)
    local h = CreateFrame("Frame", nil, row)
    h:SetPoint("LEFT", fs, "LEFT", -2, 0)
    h:SetHeight(20)
    h:SetWidth(10)
    h:EnableMouse(true)
    hooksecurefunc(fs, "SetText", function(self)
        local w = self:GetStringWidth() or 0
        h:SetWidth(math.max(6, math.min(w + 4, self:GetWidth() > 0 and self:GetWidth() + 4 or w + 4)))
        h:SetShown(w > 12)
    end)
    h:SetScript("OnEnter", function(self)
        local name, raw = getRaw(row)
        if raw and raw ~= "" then Radar.ProfTip(self, name, raw) end
        if row.hl then row:LockHighlight() end
    end)
    h:SetScript("OnLeave", function() GameTooltip:Hide() row:UnlockHighlight() end)
    h:SetScript("OnMouseUp", function(_, btn) local fn = row:GetScript("OnClick") if fn then fn(row, btn) end end)
    return h
end

function Radar.profText(s, short)
    local t = {}
    for _, p in ipairs(Radar.decodeProfs(s)) do
        t[#t + 1] = (short and p.name:sub(1, 6) or p.name) .. " " .. p.rank
    end
    return table.concat(t, "  ")
end

local function encodeMilestones()
    local t = {}
    for lvl, ts in pairs(ns.char.milestones) do t[#t + 1] = lvl .. "@" .. ts end
    return table.concat(t, "+")
end
function Radar.decodeMilestones(s)
    local out = {}
    if not s then return out end
    for lvl, ts in s:gmatch("(%d+)@(%d+)") do out[tonumber(lvl)] = tonumber(ts) end
    return out
end

-- 0.5.531: Ergebnis 5 s zwischenspeichern - wurde bei jedem Aktualisieren der Mitgliederliste komplett neu
-- gebaut (Rang, Abzeichen, Codierung), obwohl dort nur die Gegenstandsstufe gebraucht wird
local myProfCache, myProfAt = nil, -100
local buildMyProfile
function Radar.myProfile()
    local now = GetTime()
    if myProfCache and now - myProfAt < 5 then return myProfCache end
    myProfCache = buildMyProfile()
    myProfAt = now
    return myProfCache
end
function Radar.myProfileFresh() myProfAt = -100 return Radar.myProfile() end
function buildMyProfile()
    local _, classFile = UnitClass("player")
    local avg, equipped = ns.safeAll(GetAverageItemLevel())
    local p = {
        v = ns.version,
        vd = ns.versionDate,   -- Datum der Version (fuer den Update-Hinweis)
        lvl = ns.safe(UnitLevel("player")) or 0,
        -- Fortschritt zum naechsten Level in Prozent (fuer die Mitgliederliste)
        xp = (function()
            local c, m = ns.safe(UnitXP("player")) or 0, ns.safe(UnitXPMax("player")) or 0
            return m > 0 and math.floor(c / m * 100) or 0
        end)(),
        class = ns.safe(classFile) or "",
        zone = ns.safe(GetRealZoneText()) or "",
        profs = encodeProfs(myProfessions()),
        ilvl = equipped and math.floor(equipped + 0.5) or 0,
        ms = encodeMilestones(),
        rh = ns.Crafting and ns.Crafting.myHash() or "",
        lh = ns.Legacy and ns.Legacy.myHash() or "",
        ln = ns.Legacy and ns.Legacy.myDoneCount() or 0,
        map = ns.db.settings.shareMap and true or false,
        gr = ns.Officer and ns.Officer.GearString and ns.Officer.GearString() or nil,
        wk = ns.Rewards and ns.Rewards.WeekSummary and ns.Rewards.WeekSummary() or nil,
        lp = (function()
            -- Schlossknacken (nur Schurken)
            local n = GetNumSkillLines and GetNumSkillLines() or 0
            for i = 1, n do
                local name, isHeader, _, rank = GetSkillLineInfo(i)
                name = ns.safe(name)
                if name and not isHeader and (name == "Schlossknacken" or name == "Lockpicking") then return rank end
            end
        end)(),
    }
    -- Volk + Geschlecht fuer das Kopfbild in der Profilkarte
    local race = UnitRace and ns.safe(select(3, UnitRace("player")))
    local sex = UnitSex and ns.safe(UnitSex("player"))
    if race then p.rc = race p.sx = (sex == 3) and 1 or 0 end
    if ns.Alts then p.main, p.alts, p.xm = ns.Alts.ProfileFields() end   -- xm = gewuenschter Main auf anderem Account (Anfrage)
    p.ao = ns.db.settings.shareAltsOutside and 1 or nil   -- 0.5.617: Twinks ausserhalb der Gilde ausdruecklich freigegeben
    if ns.Groups and ns.Profile then p.rl = ns.Profile.EncodeRoles(ns.Groups.MyRoles()) end
    if ns.Badges then p.bd = ns.Badges.Encode() end
    do
        local sc = ns.db.settings.badgeShowcase
        local ids = {}
        for i = 1, 4 do if sc and sc[i] then ids[#ids + 1] = sc[i] end end
        if #ids > 0 then p.bf = table.concat(ids, ",") end
    end
    if ns.Badges and ns.Badges.SharedStats then p.st = ns.Badges.SharedStats() end
    local st = ns.db.settings
    if ns.Social then
        if st.profShareQuests ~= false then p.qs = ns.Social.EncodeQuests() end
        if ns.Social.IAmNewcomer() then p.nc = true end
    end
    if ns.Market then p.md = ns.Market.MidasVersion() end
    if ns.Trade then ns.Trade.ProfileFields(p) end
    if ns.Rank then ns.Rank.ProfileFields(p) end
    if ns.Insta then ns.Insta.ProfileFields(p) end
    -- eigener Online-Sound (spielen die anderen ab, wenn ich online komme)
    if ns.Sound then
        local es = ns.Sound.ChoiceFor("entrance")
        if es and es ~= "none" then p.es = es end
        -- eigener Todes-Sound (nur Entwickler; die anderen hoeren ihn statt ihres Tod-Sounds)
        local ds = ns.IsDev() and ns.Sound.eventByKey.mydeath and ns.Sound.ChoiceFor("mydeath")
        if ds and ds ~= "none" then p.ds = ds end
    end
    if ns.Deathroll and ns.Deathroll.MyFighter then p.drf = ns.Deathroll.MyFighter() end   -- Deathroll-Kaempfer (Gegnerkarten)
    if ns.Members then p.gs = ns.Members.MyGroupState() p.gnames = ns.Members.MyGroupNames() end
    -- Gruppenleiter? (Gruppen-Seite: "laeuft gerade" - wen anfluestern)
    if UnitIsGroupLeader and IsInGroup and IsInGroup() and ns.safe(UnitIsGroupLeader("player")) then p.gl = 1 end
    if ns.db.settings.birthday then p.gb = ns.db.settings.birthday end
    if ns.Dungeons and st.profShareQuests ~= false then p.dq = ns.Dungeons.EncodeMyDungeonQuests() end
    if st.profShareGear == false then p.gr, p.ilvl = nil, 0 end
    if st.bio and st.bio ~= "" then p.bi = st.bio:gsub("|", ""):sub(1, 80) end
    return p
end

local function storeProfile(name, p)
    p.seen = ns.now()
    p.groupSeen = ns.now()
    ns.db.members[name] = p
    ns.Fire("PROFILE", name, p)
end

-- Update-Hinweis: hat ein Gildenmitglied eine neuere Oasis-Version, einmal am Tag je Version Bescheid sagen
function Radar.VerNum(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.?(%d*)")
    if not a then return 0 end
    return tonumber(a) * 1000000 + tonumber(b) * 1000 + (tonumber(c) or 0)
end
-- Update-Erinnerung: hat jemand in der Gilde eine neuere Version, meldet sich Oasis beim Einloggen
-- und danach alle rdNagMin Minuten (solange man veraltet ist, nicht im Kampf/in Instanzen) mit Hinweis + Chatzeile
ns.GuildOption({ page = "radar", key = "rdNagMin", default = 20, min = 5, max = 240, step = 5, label = "Update-Erinnerung alle",
    desc = "So oft erinnert Oasis Mitglieder mit veralteter Version ans Aktualisieren (nur bei ihnen selbst)",
    fmt = function(v) return v .. " Min" end })
ns.GuildOption({ page = "radar", key = "rdNagChat", default = 15, min = 0, max = 240, step = 5, lead = true, label = "Update-Hinweis im Gildenchat alle",
    desc = "Sind Mitglieder mit alter Oasis-Version online, schreibt EIN Mitglied mit aktueller Version einen Hinweis in den Gildenchat (0 = aus)",
    fmt = function(v) return v == 0 and ns.L["aus"] or (v .. " Min") end })
local function newestDate(v)
    for _, p in pairs(ns.db.members) do
        if type(p) == "table" and p.v == v and p.vd and not p.demo then return tostring(p.vd):sub(1, 12) end
    end
    if v == ns.version then return ns.versionDate end
    if ns.Net and ns.Net.Newest then
        local nv, nd = ns.Net.Newest()
        if nv == v and nd and nd ~= "" then return nd end
    end
end
Radar.NewestDate = newestDate
local function quietNow()
    if ns.inCombat() then return true end
    local inInst, kind = IsInInstance()
    return inInst and (kind == "party" or kind == "raid" or kind == "pvp" or kind == "arena")
end
function Radar.CheckUpdate(force)
    local UPDATE_EVERY = (tonumber(ns.GuildOpt("rdNagMin")) or 20) * 60
    local best, who = Radar.NewestVersion()
    if Radar.VerNum(best) <= Radar.VerNum(ns.version) then return end
    local last = ns.db.updateNag or 0
    if not force and (ns.now() - last < UPDATE_EVERY or quietNow()) then return end
    ns.db.updateNag = ns.now()
    local d = newestDate(best)
    local msg = (L["Oasis %s%s ist da - du hast noch %s. Bitte im Discord herunterladen."]):format(best, d and (" " .. (L["vom %s"]):format(d)) or "", ns.version)
    -- 0.5.717: nur noch als Chatzeile (kein Hinweis mehr mitten im Bild); der Ton bleibt
    if ns.Sound and ns.Sound.Play then pcall(ns.Sound.Play, "announce") end
    ns.print(K.hex(C.amber) .. msg .. "|r")
end

-- Gildenchat-Hinweis fuer Mitglieder mit alter Version (die neue Erinnerung kennen alte Versionen ja noch nicht):
-- nur EIN Mitglied schreibt - das mit der neuesten Version und dem alphabetisch ersten Namen unter den Online-Mitgliedern
-- mit Oasis. Sieht ein anderer den Hinweis im Chat, setzt er seine eigene Uhr zurueck (kein Doppelpost).
local CHAT_MARK = "[Oasis]"
local function outdatedOnline()
    local mine = Radar.VerNum(ns.version)
    local out, newest = {}, {}
    for _, m in ipairs(Radar.roster or {}) do
        if m.online and not ns.isMe(m.name) then
            local p = ns.db.members[m.name]
            if type(p) == "table" and p.v and not p.demo then
                local n = Radar.VerNum(p.v)
                if n < mine then out[#out + 1] = { name = m.name, v = p.v }
                elseif n == mine then newest[#newest + 1] = m.name end
            end
        end
    end
    return out, newest
end
Radar.OutdatedOnline = outdatedOnline
function Radar.ChatUpdateHint(force)
    local every = (tonumber(ns.GuildOpt("rdNagChat")) or 60) * 60
    if every <= 0 and not force then return end
    -- nur Gildenleitung/Entwickler bekommen den Klick-Hinweis (Senden ohne Klick sperrt WoW)
    if not force and not (ns.isOfficer() or (ns.IsDev and ns.IsDev())) then return end
    if not IsInGuild() or quietNow() then return end
    -- nur wer selbst die neueste Version der Gilde hat
    local best = Radar.NewestVersion()
    if Radar.VerNum(best) > Radar.VerNum(ns.version) then return end
    local old, same = outdatedOnline()
    if #old == 0 then return end
    -- Wahl: alphabetisch erster Name unter den Online-Mitgliedern mit aktueller Version, die den Hinweis auch senden duerfen
    -- (Offiziere/Leitung, mich eingeschlossen) - sonst waehlt man jemanden, der nie postet
    local me = ns.short(ns.me()):lower()
    local A = ns.Admin
    for _, n in ipairs(same) do
        local role = A and A.RoleOf and A.RoleOf(n)
        if (role == "lead" or role == "officer") and ns.short(n):lower() < me then return end
    end
    -- gemeinsame Uhr: verChatLast = Zeitpunkt des letzten [Oasis]-Hinweises im Gildenchat (den sehen alle gleichzeitig).
    -- Angebot nicht erneut zeigen, solange der Klick aussteht/abgelehnt wurde (verChatOffer, kurze Pause)
    if not force and ns.now() - (ns.db.verChatLast or 0) < every then return end
    if not force and ns.now() - (ns.db.verChatOffer or 0) < 5 * 60 then return end
    ns.db.verChatOffer = ns.now()
    local names = {}
    for i = 1, math.min(5, #old) do names[#names + 1] = ns.short(old[i].name) .. " (" .. tostring(old[i].v) .. ")" end
    if #old > 5 then names[#names + 1] = "+" .. (#old - 5) end
    local msg = (L["%s Neue Version %s vom %s ist da - bitte im Discord herunterladen. Noch alt: %s"]):format(CHAT_MARK, ns.version,
        ns.versionDate or "?", table.concat(names, ", "))
    -- ohne Klick sperrt WoW das Senden -> Hinweis, Klick schickt die Nachricht in den Gildenchat
    if ns.OfferChat then ns.OfferChat((#old == 1 and L["1 Mitglied mit alter Oasis-Version online"] or (L["%d Mitglieder mit alter Oasis-Version online"]):format(#old)), msg, "GUILD", nil, ns.K.C.amber) end
end
-- 0.5.715: /oa updatehint - zeigt, warum (k)ein Update-Hinweis kommt, und bietet ihn sofort an
ns.slash.updatehint = function()
    local old, same = outdatedOnline()
    local best = Radar.NewestVersion()
    local known = 0
    for _, m in ipairs(Radar.roster or {}) do
        if m.online and not ns.isMe(m.name) then
            local p = ns.db.members[m.name]
            if type(p) == "table" and p.v then known = known + 1 end
        end
    end
    ns.print(("Update-Hinweis: %d online mit alter Version, %d mit gleicher, %d mit bekannter Version. Offizier/Leitung: %s. Neueste in der Gilde: %s (deine: %s). Kampf/Instanz: %s."):format(
        #old, #same, known, tostring(ns.isOfficer() or (ns.IsDev and ns.IsDev()) or false), tostring(best), tostring(ns.version), tostring(quietNow() and true or false)))
    if #old == 0 then ns.print("Nichts zu melden: Eine Version kennt Oasis erst, wenn das Mitglied sich gemeldet hat (kurz nach dem Login). Wer das Addon gar nicht hat, taucht hier nicht auf.") return end
    Radar.ChatUpdateHint(true)
end
-- jemand anderes hat den Hinweis gerade gepostet -> eigene Uhr zuruecksetzen
ns.On("CHAT_MSG_GUILD", function(text, sender)
    text = ns.safe(text)
    if type(text) == "string" and text:sub(1, #CHAT_MARK) == CHAT_MARK and text:find("Discord", 1, true) then
        ns.db.verChatLast = ns.now()
    end
end)
ns.Listen("PROFILE", function(name, p)
    if type(p) ~= "table" or not p.v or p.demo or ns.isMe(name) then return end
    Radar.CheckUpdate()
end)
ns.Listen("LOGIN", function()
    ns.db.updateNag = 0   -- beim Einloggen immer einmal erinnern
    -- frisch eingeloggt kennt man den letzten Hinweis im Chat nicht: erst nach 3 Min mitposten (kein Doppelpost kurz nach einem anderen)
    local every = (tonumber(ns.GuildOpt("rdNagChat")) or 15) * 60
    ns.db.verChatLast = math.max(ns.db.verChatLast or 0, ns.now() - every + 180)
    ns.Every(60, function() Radar.CheckUpdate() end)
    ns.Every(60, function() Radar.ChatUpdateHint() end)
end)
-- neueste Version, die in der Gilde gesehen wurde (fuer die Uebersicht)
-- Schutz gegen gefaelschte Versionsnummern (Dauer-Hinweis fuer alle): eine neuere Version zaehlt erst,
-- wenn sie mindestens zwei Mitglieder haben oder ein Mitglied der Gildenleitung/Offiziere
function Radar.NewestVersion()
    local mine = Radar.VerNum(ns.version)
    local holders, lead = {}, {}
    for name, p in pairs(ns.db.members) do
        if type(p) == "table" and p.v and not p.demo and Radar.VerNum(p.v) > mine then
            local v = tostring(p.v)
            holders[v] = holders[v] or {}
            table.insert(holders[v], name)
            local A = ns.Admin
            local role = A and A.RoleOf and A.RoleOf(name)
            if role == "lead" or role == "officer" then lead[v] = name end
        end
    end
    local best, who = ns.version, nil
    for v, list in pairs(holders) do
        if (#list >= 2 or lead[v]) and Radar.VerNum(v) > Radar.VerNum(best) then best, who = v, lead[v] or list[1] end
    end
    -- realmweit (Oasis-Netz): neuere Version bei Oasis-Nutzern anderer Gilden
    if ns.Net and ns.Net.Newest then
        local nv = ns.Net.Newest()
        if nv and Radar.VerNum(nv) > Radar.VerNum(best) then best, who = nv, ns.Net.Dev() or L["Oasis-Netz"] end
    end
    return best, who
end

function Radar.SendHello(target)
    if not IsInGuild() then return end
    local p = Radar.myProfile()
    -- erst kodieren, dann speichern (storeProfile setzt "seen" -> sonst aendert sich der Stand bei jedem Senden)
    local rec = Comm.encodeRecord(p)
    storeProfile(ns.me(), p)
    -- Kurzmeldung zuerst: eine einzige Nachricht (kommt praktisch immer an), das grosse Profil danach in Teilen
    local hi = ns.hash(rec)
    if target then
        Comm.Whisper(target, "HI", p.v, p.lvl, p.class, p.zone, hi)
        Comm.Whisper(target, "HELLO", rec)
    else
        Comm.SendEx({ ch = "GUILD", key = "hi", prio = true }, "HI", p.v, p.lvl, p.class, p.zone, hi)
        Comm.SendEx({ ch = "GUILD", key = "hello" }, "HELLO", rec)
    end
    Radar.myHelloHash = hi
end

-- Kurzmeldung: Version/Stufe/Klasse/Gebiet sofort aktualisieren; passt das gespeicherte Profil nicht
-- mehr (andere Version oder anderer Profil-Stand), das ganze Profil gezielt nachfordern
local hiAsked = {}
Comm.On("HI", function(sender, _, v, lvl, class, zone, h)
    if ns.isMe(sender) then return end
    -- Felder begrenzen: Version nur "1.2.3", Klasse nur Grossbuchstaben, Gebiet ohne Escape-Sequenzen
    v = tostring(v or ""):match("^%d+%.%d+%.?%d*$") and #v <= 16 and v or nil
    lvl = SEC.Num(lvl, 1, 200, true)
    class = tostring(class or ""):match("^%u+$") and #class <= 16 and class or nil
    zone = zone and SEC.Text(zone, 60) or nil
    h = h and tostring(h):sub(1, 40) or nil
    local p = ns.db.members[sender]
    if not p then
        p = { stub = true }
        ns.db.members[sender] = p
    end
    local stale = p.stub or p.v ~= v or (h and h ~= "" and p.hh ~= h)
    p.v = v or p.v
    p.lvl = tonumber(lvl) or p.lvl
    if class and class ~= "" then p.class = class end
    if zone and zone ~= "" then p.zone = zone end
    p.seen = ns.now()
    p.hh_want = h
    Radar.CheckUpdate()
    if stale and (not hiAsked[sender] or GetTime() - hiAsked[sender] > 60) then
        hiAsked[sender] = GetTime()
        ns.After(math.random(10, 40) / 10, function() Comm.Whisper(sender, "HELLOREQ") end)
    end
    ns.RefreshPage("radar")
end)

-- Profile aufraeumen: nicht (mehr) in der Gildenliste und 60 Tage nicht gesehen -> weg
local function pruneMembers()
    if not (Radar.byName and Radar.roster and #Radar.roster > 0) then return end
    local cut = ns.now() - 60 * 86400
    for _, t in ipairs({ ns.db.members, ns.db.recipes, ns.db.legacy }) do
        for name, p in pairs(t or {}) do
            if not ns.isMe(name) and not rawget(Radar.byName, name) and not (Radar.AliasOf and Radar.AliasOf(name))
                and type(p) == "table" and not p.demo and (p.seen or p.u or 0) < cut then
                t[name] = nil
            end
        end
    end
end
ns.Listen("LOGIN", function() ns.After(90, function() pcall(pruneMembers) end) end)

-- jede Oasis-Nachricht zaehlt als "hat Oasis": fehlt das Profil noch, einen Platzhalter anlegen
-- und das Profil gezielt anfordern (grosse Profile kommen in vielen Teilen, da geht schon mal eins verloren)
local askedProfile = {}
ns.Listen("OASIS_SEEN", function(sender)
    if ns.isMe(sender) then return end
    local p = rawget(ns.db.members, sender) or ns.db.members[sender]
    if p then
        p.seen = ns.now()
        if not p.stub then return end
    else
        ns.db.members[sender] = { stub = true, seen = ns.now() }
        ns.RefreshPage("radar")
    end
    if not askedProfile[sender] or GetTime() - askedProfile[sender] > 120 then
        askedProfile[sender] = GetTime()
        Comm.Whisper(sender, "HELLOREQ")
    end
end)

Comm.On("HELLO", function(sender, channel, rec)
    if not rec then return end
    -- Profile nur von Gildenmitgliedern (Fremde koennten sonst die gespeicherten Daten fuellen)
    if Comm.FromGuild and not Comm.FromGuild(sender) then return end
    Comm.hellos = (Comm.hellos or 0) + 1
    if #rec > 12000 then return end
    local p = Comm.decodeRecord(rec)
    if not p then return end
    -- fremdes Profil entschaerfen: keine Escape-Sequenzen in Texten, Groesse begrenzen, keine Demo-/Platzhalter-Flags
    local n = 0
    for k, v in pairs(p) do
        n = n + 1
        if n > 120 or type(k) ~= "string" or #k > 24 then p[k] = nil
        elseif type(v) == "string" then p[k] = SEC.Text(v, 1500)
        elseif type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) then p[k] = 0 end
    end
    p.demo, p.stub, p.seen, p.groupSeen = nil, nil, nil, nil
    if p.v and not (tostring(p.v):match("^%d+%.%d+%.?%d*$") and #tostring(p.v) <= 16) then p.v = nil end
    if p.class and not tostring(p.class):match("^%u+$") then p.class = nil end
    p.hh = ns.hash(rec)
    local old = ns.db.members[sender]
    storeProfile(sender, p)
    if not old then ns.debug("Neuer Oasis-Nutzer", sender) end
    ns.Debounce("radarProfile", 1.5, function() ns.RefreshPage("radar") end)
end)
-- Diagnose: kommt von jemandem Oasis-Verkehr an, und unter welchem Namen? /oa probe wer <Name oder Teil davon>
ns.probes = ns.probes or {}
ns.probes.wer = function(rest)
    local q = tostring(rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if q == "" then ns.print("/oa probe wer <Name>") return end
    ns.print("|cffe8b44aProbe wer|r  " .. q)
    local target
    for _, m in ipairs(Radar.roster or {}) do
        if type(m.name) == "string" and m.name:lower():find(q, 1, true) then
            target = target or m
            local pr = ns.db.members[m.name]
            ns.print(("  Gildenliste: %s  online=%s  Kurzname=%s"):format(m.name, tostring(m.online), tostring(m.aname)))
            ns.print(("  Profil: %s"):format(pr and (("v%s, zuletzt vor %d s, Gruppe %s"):format(tostring(pr.v), ns.now() - (pr.seen or 0), tostring(pr.gs))) or "KEINS gespeichert"))
        end
    end
    local n = 0
    for raw, e in pairs(Comm.rawSeen or {}) do
        if raw:lower():find((q:match("^(%S+)") or q), 1, true) then
            n = n + 1
            ns.print(("  Oasis-Nachrichten von \"%s\": %d, zuletzt vor %d s -> zugeordnet als %s"):format(raw, e.n, GetTime() - (e.t or 0),
                tostring(ns.ResolveName and ns.ResolveName(raw, true))))
        end
    end
    if n == 0 then ns.print("  In dieser Sitzung KEINE Oasis-Nachricht von einem Absender mit diesem Namen angekommen.") end
    for name in pairs(ns.db.members) do
        if type(name) == "string" and name:lower():find((q:match("^(%S+)") or q), 1, true) and not (Radar.byName and Radar.byName[name]) then
            ns.print("  Profil unter fremdem Namen gespeichert: " .. name)
        end
    end
    if target and target.online then
        Comm.Whisper(target.name, "HELLOREQ")
        ns.print("  Profil bei " .. target.name .. " angefragt - in 10 s nochmal /oa probe wer " .. q)
    end
end
Comm.On("HELLOREQ", function(sender)
    -- grosses Profil je Anfragendem hoechstens alle 30 s (sonst Fluester-Flut auf Zuruf)
    if not SEC.Rate("helloreq:" .. tostring(sender), 30) then return end
    ns.After(math.random(5, 60) / 10, function() Radar.SendHello(sender) end)
end)

------------------------------------------------------------------------
-- Gildenliste
------------------------------------------------------------------------
-- Alte lokale Schluessel nur bei eindeutiger Roster-Zuordnung weiterverwenden.
local function mergeMissing(target, old)
    for k, v in pairs(old) do
        local present = rawget(target, k)
        if present == nil then target[k] = v
        elseif type(present) == "table" and type(v) == "table" and present ~= v then mergeMissing(present, v) end
    end
end
local function migrateNames()
    if not ns.db then return end
    for _, field in ipairs({ "chars", "rsnap", "mnotes", "suspect" }) do
        local data = ns.db[field]
        if type(data) == "table" then
            local moves = {}
            for old, value in pairs(data) do
                if type(old) == "string" and old:sub(1, 2) ~= "__" and type(value) == "table" then
                    -- n ist bei Notizen/Verdachtsmerkern auch ein Zaehler, kein Charaktername.
                    local name = type(value.name) == "string" and value.name
                        or type(value.n) == "string" and value.n or old
                    local full = ns.ResolveName(name)
                    local member = full and Radar.byName[full]
                    if member then
                        local key = field == "chars" and member.name or ns.NameKey(member.name)
                        if key ~= old then moves[#moves + 1] = { old, key, value } end
                    end
                end
            end
            for _, move in ipairs(moves) do
                local old, key, value = move[1], move[2], move[3]
                local target = rawget(data, key)
                if target and target ~= value then mergeMissing(target, value) else data[key] = value end
                data[old] = nil
            end
        end
    end
    if ns.db.settings and ns.db.settings.main then ns.db.settings.main = ns.ResolveName(ns.db.settings.main) end
end

local function readRoster()
    if not IsInGuild() then
        Radar.roster, Radar.byName, Radar.online, Radar.total = {}, {}, 0, 0
        -- Demo-Mitglieder auch ohne Gilde zeigen (/oa demo)
        if ns.Demo and ns.Demo.IsActive() then
            Radar.total, Radar.online = ns.Demo.InjectRoster(Radar.roster, Radar.byName)
        end
        return
    end
    local total, online = GetNumGuildMembers()
    Radar.total, Radar.online = total or 0, online or 0
    local list, by = {}, {}
    local myGuid = ns.safe(UnitGUID and UnitGUID("player"))
    local short = {}   -- Kurzname (nur Vorname) -> Anzahl, um Doppeldeutigkeiten zu erkennen
    for i = 1, (total or 0) do
        -- einmal abfragen (vorher zweimal je Mitglied)
        local name, rankName, rankIndex, level, _, zone, note, onote, isOnline, status, classFile,
            _, _, _, _, _, guid = ns.safeAll(GetGuildRosterInfo(i))
        if name then
            local full = ns.fullName(name)
            local m = {
                name = full, rank = rankName or "", rankIndex = rankIndex or 99, level = level or 0,
                zone = zone or "", note = note or "", online = isOnline and true or false,
                status = status, class = classFile, onote = onote or "", index = i, guid = guid,
            }
            if not m.online and GetGuildRosterLastOnline then
                local y, mo, d, h = GetGuildRosterLastOnline(i)
                if y then m.offDays = (y or 0) * 365 + (mo or 0) * 30 + (d or 0) + (h or 0) / 24 end
            end
            -- Alte Oasis-Daten fuehrten nur Vornamen. Aliase nur fuer eindeutige Alt-Daten behalten.
            local base, realm = full:match("^(.-)%-(.+)$")
            local first = base and base:match("^(%S+)%s")
            if first then
                m.aname = first .. "-" .. realm
                short[m.aname] = (short[m.aname] or 0) + 1
            end
            if (myGuid and guid == myGuid) or ns.SameName(full, ns.me()) then ns._meRoster = full end
            list[#list + 1] = m
            by[full] = m
        end
    end
    -- Kurzform nur eintragen, wenn sie eindeutig ist (zwei "Mira ..." in einer Gilde -> keine Zuordnung)
    for _, m in ipairs(list) do
        if m.aname then
            if short[m.aname] == 1 and not by[m.aname] then by[m.aname] = m
            else m.aname = nil end  -- mehrdeutige Vornamen nie verknuepfen
        end
    end
    if ns.Demo and ns.Demo.IsActive() then
        local t, o = ns.Demo.InjectRoster(list, by)
        Radar.total, Radar.online = Radar.total + t, Radar.online + o
    end
    Radar.roster, Radar.byName = list, by
    Radar.byNameLower = {}
    for name, member in pairs(by) do Radar.byNameLower[name:lower()] = member end
    migrateNames()
    if Radar.RecordLevels then pcall(Radar.RecordLevels, list) end
end

function Radar.RequestRoster()
    -- ohne "Offline anzeigen" liefert WoW nur die Online-Mitglieder -> Filter Alle/Inaktiv waeren leer
    -- 0.5.773: nur einmal je Sitzung versuchen und in die Spur schreiben - ein geschuetzter Aufruf hier wurde sonst bei jeder
    -- Anfrage erneut als "UNKNOWN()" blockiert gemeldet (Login, Zonenwechsel)
    if not Radar.offlineTried and SetGuildRosterShowOffline and GetGuildRosterShowOffline and not GetGuildRosterShowOffline() then
        Radar.offlineTried = true
        ns.Trace("SetGuildRosterShowOffline")
        pcall(SetGuildRosterShowOffline, true)
    end
    if IsInGuild() then ns.RequestGuildRoster() end
end

-- Profile unter beiden Namensformen finden (Forever: "Vorname Nachname-Realm" <-> "Vorname-Realm")
local function aliasOf(name)
    if not name then return end
    local m = Radar.byName and Radar.byName[name]
    if m then
        if m.aname and m.aname ~= name then return m.aname end
        if m.name ~= name then return m.name end
    end
end
Radar.AliasOf = aliasOf
-- gilt fuer alle nach Spielername gespeicherten Oasis-Daten (Profile, Rezepte, Legacy)
local aliasMeta = { __index = function(t, k)
    local a = aliasOf(k)
    if a and a ~= k then return rawget(t, a) end
end }
local function linkMembers()
    if not ns.db then return end
    for _, t in ipairs({ ns.db.members, ns.db.recipes, ns.db.legacy }) do
        if t and not getmetatable(t) then setmetatable(t, aliasMeta) end
    end
end
ns.Listen("DB_READY", linkMembers)
ns.Listen("LOGIN", linkMembers)

-- 0.5.617: nutzt dieser Spieler (irgendein Charakter) Oasis? Fuer Datenschutz: Profile nur von Oasis-Nutzern
function Radar.UsesOasis(name)
    if not name then return false end
    if ns.isMe(name) or (ns.db.chars and ns.db.chars[name]) then return true end
    local p = ns.db.members[name]
    if p and p.v and not p.stub then return true end
    local main = ns.Alts and ns.Alts.Main and ns.Alts.Main(name)
    p = main and ns.db.members[main]
    return p and p.v and not p.stub and true or false
end
-- Mitglied mit Addon und aktuell online?
function Radar.HasAddon(name)
    local p = ns.db.members[name]
    if not p then return false end
    local m = Radar.byName[name]
    return (m and m.online) and (ns.now() - (p.seen or 0) < 1800)
end
function Radar.ClassOf(name)
    local m = Radar.byName[name]
    if m and m.class then return m.class end
    local p = ns.db.members[name]
    return p and p.class
end
function Radar.IsOnline(name)
    local m = Radar.byName[name]
    return m and m.online
end
local function firstOf(n) return ns.displayName(n) end
Radar.FirstName = firstOf
function Radar.Colored(name)
    return ns.colorName(name, Radar.ClassOf(name))
end

local function updateFooter()
    local withAddon = 0
    for _, m in ipairs(Radar.roster) do
        -- sich selbst nicht mitzaehlen (kommt unten fest dazu) - sonst doppelt, seit die
        -- Gildenliste "Vorname Nachname" dem eigenen Profil zugeordnet wird
        if m.online and not ns.isMe(m.name) and Radar.HasAddon(m.name) then withAddon = withAddon + 1 end
    end
    Radar.withAddon = withAddon + 1
    ns.UpdateFooter((L["%s%d|r online  -  %s%d|r mit Oasis"]):format(K.hex(C.mint), Radar.online, K.hex(C.violet), Radar.withAddon))
end

-- Gildenliste sofort neu einlesen (z.B. nach /oa demo)
function Radar.Reload()
    readRoster()
    updateFooter()
    ns.Fire("ROSTER")
    ns.RefreshPage("radar")
end
-- gebuendelt (Performance 0.5.482): das Event kommt bei jedem Ein-/Ausloggen, Zonenwechsel und jeder Anfrage
-- anderer Addons - danach haengen viele Module am "ROSTER"-Signal. Hoechstens einmal je Sekunde neu einlesen.
local rosterPending = false
ns.On("GUILD_ROSTER_UPDATE", function()
    if rosterPending then return end
    rosterPending = true
    ns.After(1, function() rosterPending = false Radar.Reload() end)
end)

------------------------------------------------------------------------
-- Level-Meilensteine
------------------------------------------------------------------------
ns.On("PLAYER_LEVEL_UP", function(level)
    level = tonumber(ns.safe(level))
    if not level then return end
    ns.char.milestones[level] = ns.now()
    Radar.SendHello()
    ns.Fire("LEVEL_UP", level)
end)

-- Rennen: fuer jeden Meilenstein die ersten 3
-- Stufen aus der Gildenliste mitschreiben (auch fuer Mitglieder ohne Oasis):
-- beim allerersten Blick ts = 0 ("schon vorher"), danach Zeitpunkt, an dem die Stufe erstmals gesehen wurde
function Radar.RecordLevels(list)
    if #list == 0 then return end
    ns.db.lvlSeen = ns.db.lvlSeen or {}
    local seen = ns.db.lvlSeen
    local first = not ns.db.lvlSeenInit
    local now = ns.now()
    for _, m in ipairs(list) do
        if not (ns.Demo and ns.Demo.IsActive() and m.demo) then
            local t = seen[m.name]
            for _, lvl in ipairs(MILESTONES) do
                if (m.level or 0) >= lvl then
                    t = t or {}
                    seen[m.name] = t
                    if not t[lvl] then t[lvl] = first and 0 or now end
                end
            end
        end
    end
    ns.db.lvlSeenInit = true
end
-- 0.5.572: einmal je Durchlauf statt je Stufe (vorher 6x alle Mitglieder + Twink-Aufloesung, und Badges rief das je
-- Listenzeile auf -> bis 600 ms je Seitenaufbau). Ergebnis 3 s gemerkt, neue Profile/Gildenliste verwerfen es.
local raceCache, raceAt
function Radar.RaceDirty() raceCache = nil end
function Radar.Race()
    if raceCache and GetTime() - raceAt < 3 then return raceCache end
    local mainOf = {}
    local function M(n)
        local m = mainOf[n]
        if m == nil then m = ns.Alts and ns.Alts.Main(n) or n mainOf[n] = m end
        return m
    end
    local best = {}
    for _, lvl in ipairs(MILESTONES) do best[lvl] = {} end
    -- aus der Gildenliste beobachtet
    for name, t in pairs(ns.db.lvlSeen or {}) do
        for _, lvl in ipairs(MILESTONES) do
            if t[lvl] then
                local main = M(name)
                local bl = best[lvl]
                if not bl[main] then bl[main] = { name = main, char = name, ts = t[lvl], seen = true } end
            end
        end
    end
    for name, p in pairs(ns.db.members) do
        if p.ms then
            local ms = Radar.decodeMilestones(p.ms)
            for _, lvl in ipairs(MILESTONES) do
                if ms[lvl] then
                    local main = M(name)
                    local bl = best[lvl]
                    -- genaue Zeit aus Oasis hat Vorrang vor der Beobachtung
                    if not bl[main] or bl[main].seen or ms[lvl] < bl[main].ts then bl[main] = { name = main, char = name, ts = ms[lvl] } end
                end
            end
        end
    end
    local out = {}
    for _, lvl in ipairs(MILESTONES) do
        local entries = {}
        for _, x in pairs(best[lvl]) do entries[#entries + 1] = x end
        -- unbekannte Zeit (0 = schon vor Oasis) hinten
        table.sort(entries, function(a, b)
            local ax, bx = a.ts > 0 and a.ts or math.huge, b.ts > 0 and b.ts or math.huge
            if ax ~= bx then return ax < bx end
            return a.name < b.name
        end)
        out[#out + 1] = { lvl = lvl, list = entries }
    end
    raceCache, raceAt = out, GetTime()
    return out
end
ns.Listen("PROFILE", function() raceCache = nil end)
ns.Listen("ROSTER", function() raceCache = nil end)

------------------------------------------------------------------------
-- Berufe als Symbole
------------------------------------------------------------------------
local PROF_BY_NAME = {
    schmiedekunst = 164, blacksmithing = 164, bergbau = 186, mining = 186, schneiderei = 197, tailoring = 197,
    verzauberkunst = 333, enchanting = 333, alchemie = 171, alchemy = 171, ["kräuterkunde"] = 182, kraeuterkunde = 182,
    herbalism = 182, ["kürschnerei"] = 393, kuerschnerei = 393, skinning = 393, lederverarbeitung = 165, leatherworking = 165,
    ingenieurskunst = 202, engineering = 202, ["erste hilfe"] = 129, ["first aid"] = 129, kochkunst = 185, cooking = 185,
    angeln = 356, fishing = 356,
}
function Radar.ProfId(pf)
    if pf.id and pf.id > 0 then return pf.id end
    return PROF_BY_NAME[(pf.name or ""):lower()]
end
function Radar.ProfIcon(pf, size, color)
    local id = Radar.ProfId(pf)
    if not id then return "" end
    local c = color or C.muted
    return ("|T%sicons\\prof_%d:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(ns.MEDIA, id, size or 13, size or 13, math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end
-- herstellende Berufe (Sammel- und Nebenberufe zaehlen fuer "wer kann was bauen" nicht)
Radar.CRAFT_PROFS = { [164] = true, [197] = true, [333] = true, [171] = true, [165] = true, [202] = true }
function Radar.IsCraftProf(pf) return Radar.CRAFT_PROFS[Radar.ProfId(pf) or 0] == true end
-- Spalte: nur herstellende Berufe, je Symbol + Stufe
-- Spalte zeigt zusaetzlich die Sammelberufe (Kraeuterkunde 182, Bergbau 186, Kuerschnerei 393)
local GATHER_PROFS = { [182] = true, [186] = true, [393] = true }
function Radar.ProfIcons(raw, size, limit)
    local t = {}
    local list = Radar.decodeProfs(raw)
    if limit then
        -- nur Haupt-/Sammelberufe, hoechste zuerst, hoechstens limit Stueck
        local keep = {}
        for _, pf in ipairs(list) do if Radar.IsCraftProf(pf) or GATHER_PROFS[Radar.ProfId(pf) or 0] then keep[#keep + 1] = pf end end
        table.sort(keep, function(a, b) return (a.rank or 0) > (b.rank or 0) end)
        for i = #keep, limit + 1, -1 do keep[i] = nil end
        list = keep
    end
    for _, pf in ipairs(list) do
      if Radar.IsCraftProf(pf) or GATHER_PROFS[Radar.ProfId(pf) or 0] then
        local maxed = pf.max and pf.rank >= pf.max
        local c = maxed and C.amber or C.muted
        local icon = Radar.ProfIcon(pf, size, c)
        if icon == "" then icon = (pf.name or "?"):sub(1, 3) end
        t[#t + 1] = icon .. (maxed and "|cffe8b44a" or "|cffc8c8c8") .. pf.rank .. "|r"
      end
    end
    if #t == 0 then return "|cff555555-|r" end
    return table.concat(t, "  ")
end

------------------------------------------------------------------------
-- Mitglieder-Karte (0.5.508): eigenes Oasis-Fenster statt GameTooltip - deckend, Kopf in Klassenfarbe
-- mit Klassensymbol und XP-Balken, Abschnitte mit kleiner Ueberschrift, Werte umbrechen statt ueberlaufen.
-- Sitzt neben dem Oasis-Fenster auf Hoehe der Zeile (nicht mehr ueber Minikarte/Questliste).
-- Schliesst sich selbst, sobald die Maus die Zeile verlaesst.
------------------------------------------------------------------------
local DIM = { 0.55, 0.55, 0.6 }
local CARD_W, PAD, LBL_W = 318, 16, 112
local card
local function buildCard()
    local f = CreateFrame("Frame", "OasisMemberCard", UIParent)
    f:SetSize(CARD_W, 200)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    K.Fill(f, { 0.045, 0.045, 0.055, 0.98 })
    K.Border(f, { 1, 1, 1, 0.1 })
    if K.ApplySkin then pcall(K.ApplySkin, f, "panel", { 0.045, 0.045, 0.055, 0.98 }) end
    -- Kopf: Klassenfarbe als weicher Verlauf von links
    f.head = f:CreateTexture(nil, "BORDER")
    f.head:SetPoint("TOPLEFT", 1, -1) f.head:SetPoint("TOPRIGHT", -1, -1) f.head:SetHeight(64)
    f.headLine = f:CreateTexture(nil, "ARTWORK")
    f.headLine:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT") f.headLine:SetPoint("TOPRIGHT", f.head, "BOTTOMRIGHT") f.headLine:SetHeight(1)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(34, 34)
    f.icon:SetPoint("TOPLEFT", PAD, -15)
    f.name = K.Title(f, 15, C.text)
    f.name:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 11, -1)
    f.name:SetPoint("RIGHT", -96, 0)
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)
    f.sub = K.Text(f, 11, C.muted)
    f.sub:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
    f.sub:SetPoint("RIGHT", -PAD, 0)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetWordWrap(false)
    f.state = K.Text(f, 11, C.muted, "RIGHT")
    f.state:SetPoint("TOPRIGHT", -PAD, -17)
    f.rank = K.Text(f, 10, DIM, "RIGHT")
    f.rank:SetPoint("TOPRIGHT", f.state, "BOTTOMRIGHT", 0, -4)
    -- XP-Balken am unteren Kopfrand
    f.xpBg = f:CreateTexture(nil, "ARTWORK")
    f.xpBg:SetPoint("BOTTOMLEFT", f.head, "BOTTOMLEFT", 0, 0) f.xpBg:SetPoint("BOTTOMRIGHT", f.head, "BOTTOMRIGHT", 0, 0)
    f.xpBg:SetHeight(2)
    f.xpBg:SetColorTexture(1, 1, 1, 0.06)
    f.xp = f:CreateTexture(nil, "ARTWORK", nil, 1)
    f.xp:SetPoint("BOTTOMLEFT", f.head, "BOTTOMLEFT", 0, 0)
    f.xp:SetHeight(2)
    f.pool = { lbl = {}, val = {}, sec = {}, txt = {}, num = {}, cap = {}, line = {} }
    -- 0.5.523: Karte haengt am Mauszeiger (rechts daneben, bei wenig Platz links) und folgt ihm
    function f:Follow()
        local cx, cy = GetCursorPosition()
        local us = UIParent:GetEffectiveScale()
        local s = self:GetEffectiveScale()
        cx, cy = cx / s, cy / s
        local w = self:GetWidth() or CARD_W
        local sw = (UIParent:GetRight() or (GetScreenWidth and GetScreenWidth()) or 1920) * us / s
        self:ClearAllPoints()
        if cx + 22 + w < sw then
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx + 22, cy + 14)
        else
            self:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", cx - 18, cy + 14)
        end
    end
    -- Rechtsklick (Menue) oder Klick: Karte weg und bleibt weg, bis die Maus die Zeile verlaesst
    f.mute = CreateFrame("Frame")
    f.mute:Hide()
    f.mute:SetScript("OnUpdate", function(self)
        local o = f.muted
        if not o or not o:IsVisible() or not o:IsMouseOver() then f.muted = nil self:Hide() end
    end)
    f:SetScript("OnUpdate", function(self)
        local o = self.owner
        if not o or not o:IsVisible() or not o:IsMouseOver() then self:Hide() return end
        if IsMouseButtonDown and (IsMouseButtonDown("RightButton") or IsMouseButtonDown("LeftButton")) then
            self.muted = o
            self.mute:Show()
            self:Hide()
            return
        end
        self:Follow()
    end)
    card = f
    return f
end
local function take(f, kind, size, color, justify)
    local p = f.pool[kind]
    f.used[kind] = (f.used[kind] or 0) + 1
    local fs = p[f.used[kind]]
    if not fs and kind == "line" then
        fs = f:CreateTexture(nil, "ARTWORK")
        fs:SetHeight(1)
        fs:SetColorTexture(1, 1, 1, 0.07)
        p[f.used[kind]] = fs
    elseif not fs then
        fs = (kind == "sec") and K.Text(f, 9, DIM) or K.Text(f, size, color, justify)
        fs:SetWordWrap(true)
        fs:SetJustifyV("TOP")
        p[f.used[kind]] = fs
    end
    fs:ClearAllPoints()
    fs:Show()
    return fs
end
-- sections: { { title, rows = { {label, value} ... }, text = "..." } ... }
local function renderCard(owner, h, sections, foot)
    local f = card or buildCard()
    if f.muted == owner then return end
    f.owner = owner
    f.used = {}
    for _, list in pairs(f.pool) do for _, fs in ipairs(list) do fs:Hide() end end
    -- Kopf
    local cr, cg, cb = ns.classColor(h.class)
    if not K.Gradient(f.head, "HORIZONTAL", { cr, cg, cb, 0.28 }, { cr, cg, cb, 0.02 }) then f.head:SetColorTexture(cr, cg, cb, 0.12) end
    f.headLine:SetColorTexture(cr, cg, cb, 0.35)
    local tc = h.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[h.class]
    if tc then
        f.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        f.icon:SetTexCoord(unpack(tc))
    else
        f.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    f.name:SetText(h.name)
    f.sub:SetText(h.sub)
    f.state:SetText(h.state or "")
    f.rank:SetText(h.rank or "")
    if h.xp then
        f.xp:SetWidth(math.max(1, (CARD_W - 2) * math.min(1, h.xp / 100)))
        f.xp:SetColorTexture(cr, cg, cb, 0.9)
        f.xp:Show() f.xpBg:Show()
    else
        f.xp:Hide() f.xpBg:Hide()
    end
    -- Inhalt
    local y = -64 - 14
    local valW = CARD_W - PAD * 2 - LBL_W
    -- 0.6.270: Kennzahlen-Leiste (grosse Zahl, kleine Beschriftung) direkt unter dem Kopf
    local stats = sections.stats
    if stats and #stats > 0 then
        local colW = (CARD_W - PAD * 2) / #stats
        for i, st in ipairs(stats) do
            local x = PAD + (i - 1) * colW
            local n = take(f, "num", 16, C.text)
            n:SetPoint("TOPLEFT", x, y)
            n:SetWidth(colW - 6)
            n:SetJustifyH("LEFT")
            n:SetWordWrap(false)
            n:SetText(st[1])
            local c = take(f, "cap", 10, DIM)
            c:SetPoint("TOPLEFT", x, y - 21)
            c:SetWidth(colW - 6)
            c:SetJustifyH("LEFT")
            c:SetWordWrap(false)
            c:SetText(st[2])
        end
        y = y - 21 - 13 - 16
    end
    for _, s in ipairs(sections) do
        if (s.rows and #s.rows > 0) or (s.text and s.text ~= "") then
            if s.title then
                -- ruhige Ueberschrift: grau, mit feiner Linie bis zum rechten Rand
                local t = take(f, "sec")
                t:SetPoint("TOPLEFT", PAD, y)
                t:SetText(K.Upper(s.title))
                t:SetWordWrap(false)
                local c = s.color or DIM
                t:SetTextColor(c[1], c[2], c[3])
                local ln = take(f, "line")
                ln:SetPoint("LEFT", t, "RIGHT", 8, 0)
                ln:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
                y = y - 18
            end
            for _, r in ipairs(s.rows or {}) do
                local l = take(f, "lbl", 11, DIM)
                l:SetPoint("TOPLEFT", PAD, y)
                l:SetWidth(LBL_W - 8)
                l:SetText(r[1])
                local v = take(f, "val", 11, C.text)
                v:SetPoint("TOPLEFT", PAD + LBL_W, y)
                v:SetWidth(valW)
                v:SetJustifyH("LEFT")
                v:SetText(r[2])
                local hgt = math.max(l:GetStringHeight() or 12, v:GetStringHeight() or 12, 12)
                y = y - hgt - 8
            end
            if s.text and s.text ~= "" then
                local t = take(f, "txt", 11, { 0.85, 0.85, 0.88 })
                t:SetPoint("TOPLEFT", PAD, y)
                t:SetWidth(CARD_W - PAD * 2)
                t:SetJustifyH("LEFT")
                t:SetText(s.text)
                y = y - (t:GetStringHeight() or 12) - 6
            end
            y = y - 10
        end
    end
    -- Fuss
    for _, line in ipairs(foot) do
        local t = take(f, "txt", 10, { 0.45, 0.45, 0.5 })
        t:SetPoint("TOPLEFT", PAD, y)
        t:SetWidth(CARD_W - PAD * 2)
        t:SetJustifyH("LEFT")
        t:SetText(line)
        y = y - (t:GetStringHeight() or 11) - 3
    end
    f:SetHeight(-y + 12)
    -- Platz: am Mauszeiger
    f:Follow()
    f:Show()
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    if K.FadeIn and not (f.lastOwner == owner) then f.oasisFadedAt = nil pcall(K.FadeIn, f, 0, 4) end
    f.lastOwner = owner
end
function Radar.HideMemberTip() if card then card:Hide() end end

function Radar.ShowMemberTip(owner, m, opts)
    opts = opts or {}
    local pr = ns.db.members[m.name]
    local M = ns.Members
    -- Kopf
    local cls = (LOCALIZED_CLASS_NAMES_MALE and m.class and LOCALIZED_CLASS_NAMES_MALE[m.class]) or ""
    local sub = L["Level "] .. (m.level or "?") .. " " .. cls
    if ns.Welcome and ns.Welcome.IsNew(m.name) then sub = sub .. "  |cff66db9e" .. L["NEU"] .. "|r" end
    local st
    if m.online then st = "|cff66db9e" .. L["Online"] .. "|r"
    elseif m.offDays then st = m.offDays < 1 and L["heute"] or (L["vor %d Tg"]):format(m.offDays) end
    local h = { name = Radar.Colored(m.name), sub = sub, state = st, rank = m.rank, class = m.class,
        xp = (opts.xpPct and (m.level or 0) < 60) and opts.xpPct or nil }
    local sections = {}
    -- 0.6.270: XP-Stand in die Unterzeile, Rang/Gegenstandsstufe/Legacy als Kennzahlen-Leiste
    if h.xp then h.sub = h.sub .. "  |cff8a8a90·  " .. ("%d %%"):format(math.floor(h.xp)) .. " " .. L["bis Level "] .. ((m.level or 0) + 1) .. "|r" end
    local stats = {}
    if ns.Rank then
        local orl, verified = ns.Rank.Of(m.name)
        if orl then
            local fr = ns.Rank.Frame(orl)
            local hex = ("|cff%02x%02x%02x"):format(fr.color[1] * 255, fr.color[2] * 255, fr.color[3] * 255)
            stats[#stats + 1] = { hex .. orl .. "|r", verified and ns.Rank.Title(orl) or ("|cffe68c4d" .. L["ungeprueft"] .. "|r") }
        end
    end
    if pr and (pr.ilvl or 0) > 0 then stats[#stats + 1] = { tostring(pr.ilvl), L["Gegenstandsstufe"] } end
    if pr and (pr.ln or 0) > 0 then stats[#stats + 1] = { tostring(pr.ln), L["Legacy-Challenges"] } end
    sections.stats = stats
    -- Jetzt
    local now = { title = L["Jetzt"], rows = {} }
    sections[#sections + 1] = now
    if m.online then
        local zone = (m.zone ~= "" and m.zone) or "?"
        if not ns.isMe(m.name) and m.zone ~= "" and m.zone == (ns.safe(GetRealZoneText()) or "") then
            zone = zone .. "  |cff66db9e(" .. L["bei dir"] .. ")|r"
        end
        now.rows[#now.rows + 1] = { L["Gebiet"], zone }
        if M then
            local icon, stt = M.StatusIcon(m.name, 12)
            if stt then now.rows[#now.rows + 1] = { L["Status"], icon .. stt } end
        end
        local sh = ns.short(m.name)
        if not ns.isMe(m.name) and (UnitInParty(sh) or UnitInRaid(sh)) then now.rows[#now.rows + 1] = { L["Gruppe"], "|cff66db9e" .. L["in deiner Gruppe"] .. "|r" } end
    end
    if M then
        local today, week = M.PlayToday(m.name), M.PlayWeek(m.name)
        if today > 0 or week > 0 then
            local t = {}
            if today > 0 then t[#t + 1] = L["heute"] .. " " .. M.FmtDuration(today) end
            if week > 0 then t[#t + 1] = L["Woche"] .. " " .. M.FmtDuration(week) end
            now.rows[#now.rows + 1] = { L["Spielzeit"], table.concat(t, "  ·  ") }
        end
        local peak = M.Peak(m.name)
        if peak then now.rows[#now.rows + 1] = { L["Meist aktiv"], (peak:gsub("^" .. L["meist"] .. " ", "")) } end
        local gain = M.LevelGain(m.name, 7, m.level)
        if gain > 0 then now.rows[#now.rows + 1] = { L["Level-Tempo"], "|cff66db9e" .. (L["+%d in 7 Tagen"]):format(gain) .. "|r" } end
    end
    -- letzter Abgleich mit diesem Mitglied (nur Oasis-Nutzer)
    if pr and not ns.isMe(m.name) and ns.Comm and ns.Comm.PeerSync then
        local t, _, _, fresh = ns.Comm.PeerSync(m.name)
        local busy = ns.Comm.PeerBusy and ns.Comm.PeerBusy(m.name)
        local txt
        if busy then txt = "|cff66db9e" .. L["gleicht gerade ab ..."] .. "|r"
        elseif t then
            local cur = m.online and (ns.now() - t) < 900
            txt = (cur and "|cff66db9e" or "|cffc8c8c8") .. ns.ago(t) .. "|r" .. (cur and ("  |cff66db9e" .. L["aktuell"] .. "|r") or "")
        else txt = "|cff8a8a90" .. L["noch nie"] .. "|r" end
        now.rows[#now.rows + 1] = { L["Abgleich"], txt }
    end
    -- Charakter
    local ch = { title = L["Charakter"], rows = {} }
    sections[#sections + 1] = ch
    if ns.Profile then
        local ri = ns.Profile.RoleIcons(m.name, 15)
        if ri ~= "" then ch.rows[#ch.rows + 1] = { L["Rollen"], ri } end
    end
    local rawProfs = pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[m.name])
    local profs = Radar.decodeProfs(rawProfs)
    if #profs > 0 then
        local t = {}
        for _, pf in ipairs(profs) do
            local maxed = pf.max and pf.max > 0 and pf.rank >= pf.max
            local icon = Radar.ProfIcon(pf, 14, maxed and C.amber or C.text)
            if icon == "" then icon = (pf.name or "?"):sub(1, 3) .. " " end
            t[#t + 1] = icon .. " " .. (maxed and "|cffe8b44a" or "") .. pf.rank .. (maxed and "|r" or "")
        end
        ch.rows[#ch.rows + 1] = { L["Berufe"], table.concat(t, "   ") }
    end
    if ns.Alts then
        local main = ns.Alts.Main(m.name)
        local chars = ns.Alts.CharsOf(main)
        if #chars > 1 then
            -- 0.6.270: Twink zeigt "Twink von <Main>" plus die uebrigen Chars, kein doppelter Main mehr
            local isMain = ns.Alts.SameChar(main, ns.Alts.Canon(m.name))
            local function lv(c) local rm = Radar.byName[c] return rm and (" |cff888888" .. rm.level .. "|r") or "" end
            if isMain then
                ch.rows[#ch.rows + 1] = { L["Rolle"], "|cffe8b44a" .. L["Main"] .. "|r" }
            else
                ch.rows[#ch.rows + 1] = { L["Twink von"], Radar.Colored(main) .. lv(main) }
            end
            local t = {}
            for _, c in ipairs(chars) do
                if c ~= m.name and c ~= main then t[#t + 1] = Radar.Colored(c) .. lv(c) end
            end
            if #t > 0 then ch.rows[#ch.rows + 1] = { isMain and L["Twinks"] or L["Weitere Chars"], table.concat(t, ", ") } end
        end
    end
    -- Gilde
    local gi = { title = L["Gilde"], rows = {} }
    sections[#sections + 1] = gi
    if ns.Badges then
        local icons, n = ns.Badges.Inline(m.name, 8, 15)
        if n > 0 then gi.rows[#gi.rows + 1] = { L["Abzeichen"], icons } end
    end
    if M then
        local since = M.MemberSince(m.name)
        if since and since ~= "" then gi.rows[#gi.rows + 1] = { L["In der Gilde seit"], since } end
        local b = M.Birthday(m.name)
        if b then gi.rows[#gi.rows + 1] = { L["Geburtstag"], b .. (M.IsBirthday(m.name) and "  |cffff77aa" .. L["heute!"] .. "|r" or "") } end
    end
    if (m.note or "") ~= "" then gi.rows[#gi.rows + 1] = { L["Notiz"], m.note } end
    if M and (m.onote or "") ~= "" and (m.demo or M.CanSeeOfficerNote()) then gi.rows[#gi.rows + 1] = { "|cffff7a5c" .. L["Offiziersnotiz"] .. "|r", m.onote } end
    -- 0.5.537: kein Fussbereich mehr (Abgleich/Version/Klick-Hinweise) - Karte endet nach "Gilde"
    local foot = {}
    if opts.extra then foot[#foot + 1] = opts.extra end
    local ok, e = pcall(renderCard, owner, h, sections, foot)
    if not ok then ns.err("Mitglieder-Karte", e) end
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local filter, search = "all", ""
-- Zusatzfilter (nil = alle) und Sortierung
local F = { class = nil, level = nil, role = nil, prof = nil }
local sortKey, sortDesc = nil, false

local LEVELS = {
    { key = "1-19", text = "1 - 19", lo = 1, hi = 19 }, { key = "20-29", text = "20 - 29", lo = 20, hi = 29 },
    { key = "30-39", text = "30 - 39", lo = 30, hi = 39 }, { key = "40-49", text = "40 - 49", lo = 40, hi = 49 },
    { key = "50-59", text = "50 - 59", lo = 50, hi = 59 }, { key = "60", text = "60", lo = 60, hi = 60 },
}
local function levelOk(lvl)
    if not F.level then return true end
    if F.level == "near" then
        local me = ns.safe(UnitLevel("player")) or 0
        return math.abs(lvl - me) <= 5
    end
    for _, r in ipairs(LEVELS) do if r.key == F.level then return lvl >= r.lo and lvl <= r.hi end end
    return true
end
local function profsOf(name)
    local pr = ns.db.members[name]
    local raw = pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[name])
    return Radar.decodeProfs(raw)
end
function Radar.FilterItems(kind)
    local out, seen = {}, {}
    if kind == "class" then
        for _, m in ipairs(Radar.roster) do
            local c = m.class
            if c and c ~= "" and not seen[c] then
                seen[c] = true
                local nameTxt = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c
                out[#out + 1] = { key = c, text = ns.colorName(nameTxt, c), sort = nameTxt }
            end
        end
    elseif kind == "level" then
        out[1] = { key = "near", text = L["um mein Level (+-5)"] }
        for _, r in ipairs(LEVELS) do out[#out + 1] = { key = r.key, text = r.text } end
        return out
    elseif kind == "role" then
        return { { key = "tank", text = L["Tank"] }, { key = "heal", text = L["Heiler"] }, { key = "dps", text = L["Schaden"] } }
    elseif kind == "prof" then
        for _, m in ipairs(Radar.roster) do
            for _, pf in ipairs(profsOf(m.name)) do
                if not seen[pf.name] then seen[pf.name] = true out[#out + 1] = { key = pf.name, text = pf.name, sort = pf.name } end
            end
        end
    end
    table.sort(out, function(a, b) return (a.sort or a.text) < (b.sort or b.text) end)
    return out
end
local function nearMe(m)
    local me = ns.safe(UnitLevel("player")) or 0
    return m.online and not ns.isMe(m.name) and math.abs((m.level or 0) - me) <= 3
end
Radar.NearMe = nearMe
local function extraOk(m)
    if F.near and not nearMe(m) then return false end
    if F.class and m.class ~= F.class then return false end
    if not levelOk(m.level or 0) then return false end
    if F.role and ns.Profile then
        local r = ns.Profile.RolesOf(m.name)
        if not r[F.role] then return false end
    end
    if F.prof then
        local hit = false
        for _, pf in ipairs(profsOf(m.name)) do if pf.name == F.prof then hit = true end end
        if not hit then return false end
    end
    return true
end

-- Gruppenbloecke bleiben innerhalb der gewaehlten Sortierung zusammen.
-- Eigene Live-Gruppe hat Vorrang, fremde Meldungen verfallen nach zehn Minuten.
function Radar.GroupRows(list)
    local byKey, assignments = {}, {}
    for _, m in ipairs(list) do if m.online then byKey[ns.NameKey(m.name)] = m end end
    local function assign(raw, sender, overwrite)
        if type(raw) ~= "string" or #raw > 1500 then return end
        local keys, seen, contains = {}, {}, false
        for key in raw:gmatch("[^,]+") do
            if #keys >= 40 or #key > 120 or key:find("[%c|]") then return end
            key = ns.NameKey(key)
            if not seen[key] then keys[#keys + 1] = key seen[key] = true end
            if key == sender then contains = true end
        end
        if #keys < 2 or not contains then return end
        table.sort(keys)
        local id = table.concat(keys, ",")
        for _, key in ipairs(keys) do
            if byKey[key] and (overwrite or (not ns.isMe(key) and not assignments[key])) then assignments[key] = id end
        end
    end
    local own = ns.Members and ns.Members.MyGroupNames() or ""
    assign(own, ns.NameKey(ns.me()), true)
    local reports = {}
    for _, m in ipairs(Radar.roster or list) do
        local p = ns.db.members[m.name]
        if m.online and not ns.isMe(m.name) and p and type(p.groupSeen) == "number" and ns.now() - p.groupSeen <= 600 then
            reports[#reports + 1] = { name = m.name, p = p }
        end
    end
    table.sort(reports, function(a, b)
        if a.p.groupSeen ~= b.p.groupSeen then return a.p.groupSeen > b.p.groupSeen end
        return a.name < b.name
    end)
    for _, r in ipairs(reports) do assign(r.p.gnames, ns.NameKey(r.name), false) end
    local blocks, order = {}, {}
    for _, m in ipairs(list) do
        local key = assignments[ns.NameKey(m.name)] or m.name
        if not blocks[key] then blocks[key] = {} order[#order + 1] = key end
        blocks[key][#blocks[key] + 1] = m
    end
    local out, marks = {}, {}
    for _, key in ipairs(order) do
        local block = blocks[key]
        for i, m in ipairs(block) do
            out[#out + 1] = m
            if #block > 1 and assignments[ns.NameKey(m.name)] then
                marks[m.name] = { first = i == 1, last = i == #block, id = key }
            end
        end
    end
    return out, marks
end

local function buildList()
    local out = {}
    local q = search:lower()
    local source = Radar.roster
    if filter == "players" and ns.Alts then
        -- pro Spieler eine Zeile: bevorzugt der eingeloggte Charakter, sonst der Main
        local pick = {}
        for _, m in ipairs(Radar.roster) do
            local main = ns.Alts.Main(m.name)
            local cur = pick[main]
            if not cur or (m.online and not cur.online) or (m.online == cur.online and m.name == main) then pick[main] = m end
        end
        source = {}
        for _, m in pairs(pick) do source[#source + 1] = m end
    end
    for _, m in ipairs(source) do
        local inactiveOk = filter ~= "inactive" or (not m.online and (m.offDays or 0) >= (ns.db.settings.inactiveDays or 30))
        if (filter ~= "online" or m.online) and inactiveOk and extraOk(m) then
            local p = ns.db.members[m.name]
            local hay = (m.name .. " " .. m.zone .. " " .. (p and p.profs or "")):lower()
            if q == "" or hay:find(q, 1, true) then out[#out + 1] = m end
        end
    end
    table.sort(out, function(a, b)
        if sortKey then
            local va, vb
            if sortKey == "name" then va, vb = a.name:lower(), b.name:lower()
            elseif sortKey == "level" then va, vb = a.level or 0, b.level or 0
            elseif sortKey == "zone" then va, vb = (a.zone or ""):lower(), (b.zone or ""):lower()
            elseif sortKey == "last" then va, vb = (a.online and -1 or (a.offDays or 9999)), (b.online and -1 or (b.offDays or 9999))
            elseif sortKey == "rank" then va, vb = a.rankIndex or 99, b.rankIndex or 99 end
            if va ~= vb then
                if sortDesc then return va > vb end
                return va < vb
            end
        end
        if a.online ~= b.online then return a.online end
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    out, Radar.groupRows = Radar.GroupRows(out)
    return out
end

-- 2026: Glas-Optik wie Profil/Sammlungen/Abzeichen/Legacy (Helfer aus ns.Insta; fehlen sie, bleibt die alte Flaeche)
local function hasGlass() return ns.Insta and ns.Insta.Glass and true or false end
local function glass(f, fill, line, r) if hasGlass() then ns.Insta.Glass(f, fill, line, r) end end
local function round(t, box, r) if K.RoundMask and t then K.RoundMask(t, box or t, r) end end
local GLASS_ON = function() local a = C.accent return { a[1], a[2], a[3], 0.15 }, { a[1], a[2], a[3], 0.45 } end
local function calmBtn(b)
    if not (b and hasGlass()) then return b end
    if b.sheen then b.sheen:Hide() end
    glass(b, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.10 }, 8)
    b:SetScript("OnEnter", function(self) glass(self, { 1, 1, 1, 0.09 }, { 1, 1, 1, 0.20 }) end)
    b:SetScript("OnLeave", function(self) glass(self, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.10 }) end)
    return b
end
-- Gebiets-Pille in der Fusszeile
local function chipLook(c, hover)
    if not hasGlass() then
        c.bg:SetColorTexture(1, 1, 1, hover and 0.12 or (c.mine and 0.1 or 0.05))
        return
    end
    local m = C.mint
    if c.mine then
        glass(c, { m[1], m[2], m[3], hover and 0.16 or 0.10 }, { m[1], m[2], m[3], hover and 0.5 or 0.35 }, 9)
    else
        glass(c, { 1, 1, 1, hover and 0.09 or 0.045 }, { 1, 1, 1, hover and 0.2 or 0.09 }, 9)
    end
end

ns.RegisterPage({
    key = "radar", title = "Mitglieder", order = 1,
    sub = "Wer ist online, wo, mit welchen Berufen - und wer gewinnt das Level-Rennen",
    build = function(p)
        p:SetScript("OnShow", function(self) self.fresh = true end)
        p.fresh = true
        -- 0.5.572: nur sichtbare Zeilen neu zeichnen (Abgleich-Symbol) - ohne die ganze Seite neu aufzubauen
        Radar.RefreshRows = function()
            if p:IsVisible() and p.list and p.list.Refresh then p.list:Refresh() end
        end
        p.cards = {}
        local defs = {
            { ns.ICONS.radar, "Jetzt online", C.mint }, { ns.ICONS.social, "Mitglieder", C.blue },
            { ns.ICONS.home, "Mit Oasis", C.accent }, { ns.ICONS.badges, "Gear-Level 60er (Schnitt)", C.amber },
        }
        for i, d in ipairs(defs) do
            local c = K.HudTile(p, d[1], L[d[2]], d[3])
            c:SetSize(150, 62)
            c:SetPoint("TOPLEFT", (i - 1) * 160, 0)
            p.cards[i] = c
        end
        -- Kacheln entfallen: Zahlen stehen rechts in der Leiste "Wo ist die Gilde"
        for _, c in ipairs(p.cards) do c:Hide() c.Show = function() end end
        p.cards[4]:SetScript("OnClick", function()
            if p.cards[4].tip == nil then return end
            F.near = not F.near or nil
            if F.near and filter ~= "online" then filter = "online" end
            ns.RefreshPage("radar")
        end)
        p:HookScript("OnSizeChanged", function(self, w)
            -- Kachel "Mit Oasis" ausgeblendet -> drei Kacheln
            local vis = { self.cards[1], self.cards[2], self.cards[4] }
            local tw = math.floor(((w or 750) - 20) / 3)
            for i, c in ipairs(vis) do
                c:SetWidth(tw)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", (i - 1) * (tw + 10), 0)
            end
        end)

        -- "Spieler" (ein Eintrag je Spieler) entfaellt: Alle zuerst und als Standard
        local segItems = { { key = "all", text = L["Alle"], icon = "groups" }, { key = "online", text = L["Online"], icon = "radar" } }
        if ns.isOfficer() then segItems[#segItems + 1] = { key = "inactive", text = L["Inaktiv"], icon = "eye_off" } end
        local function onSeg(k)
            filter = k
            p.onlyList = true
            ns.RefreshPage("radar", true)
        end
        local seg
        if ns.Insta and ns.Insta.ProfileTabs then
            seg = ns.Insta.ProfileTabs(p, segItems, onSeg)
            seg:SetWidth(#segItems * 130)
            seg.isGlass = true
        else
            seg = K.Segments(p, segItems, onSeg, 80)
        end
        seg.items = segItems
        local ROWY = seg.isGlass and -44 or -32     -- Filterzeile unter den Reitern
        p.seg = seg
        seg:SetPoint("TOPLEFT", 0, -138)
        local s = K.Input(p, 250, L["Suchen: Name, Gebiet, Beruf ..."], function(t)
            search = t
            ns.RefreshPage("radar")
        end)
        s:SetPoint("LEFT", seg, "RIGHT", 12, 0)
        p.search = s

        -- Filterleiste: Klasse, Level, Rolle, Beruf
        p.drops = {}
        local defs = {
            { "class", L["Klasse"], 128 }, { "level", L["Level"], 118 }, { "role", L["Rolle"], 108 }, { "prof", L["Beruf"], 120 },
        }
        local x = 0
        for _, d in ipairs(defs) do
            local kind = d[1]
            local dd = K.Dropdown(p, d[3], d[2], function() return Radar.FilterItems(kind) end,
                function() return F[kind] end,
                function(v) F[kind] = v p.onlyList = true ns.RefreshPage("radar", true) end)
            dd:SetPoint("TOPLEFT", seg, "TOPLEFT", x, ROWY)
            x = x + d[3] + 6
            if hasGlass() then
                -- Glas-Dropdown: aktiver Filter dezent in Akzentfarbe
                glass(dd, { 1, 1, 1, 0.045 }, { 1, 1, 1, 0.10 }, 8)
                local upd = dd.Update
                function dd:Update(...)
                    upd(self, ...)
                    if F[kind] ~= nil then glass(self, GLASS_ON()) else glass(self, { 1, 1, 1, 0.045 }, { 1, 1, 1, 0.10 }) end
                end
            end
            p.drops[#p.drops + 1] = dd
        end
        p.reset = K.Button(p, L["Filter aus"], 0, 24, "ghost", function()
            F.class, F.level, F.role, F.prof, F.near = nil, nil, nil, nil, nil
            search = ""
            if p.search then p.search:SetText("") end
            ns.RefreshPage("radar")
        end)
        p.reset:SetWidth(math.max(70, p.reset.label:GetStringWidth() + 20))
        calmBtn(p.reset)
        glass(p.search, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.10 }, 8)
        -- Suche rechts neben den Filtern (gleiche Zeile)
        p.search:ClearAllPoints()
        p.search:SetPoint("TOPLEFT", seg, "TOPLEFT", x, ROWY)
        x = x + (p.search:GetWidth() or 250) + 6
        p.reset:SetPoint("TOPLEFT", seg, "TOPLEFT", x, ROWY)

        -- Spaltenkoepfe (Klick: sortieren)
        local hdr = CreateFrame("Frame", nil, p)
        local TBLY = ROWY - 36                        -- Oberkante der Tabellen-Glasflaeche
        p.tbl = CreateFrame("Frame", nil, p)
        p.tbl:SetPoint("TOPLEFT", seg, "TOPLEFT", 0, TBLY)
        p.tbl:SetPoint("BOTTOMRIGHT", 0, 38)
        p.tbl:SetFrameLevel(math.max(0, p:GetFrameLevel()))
        -- 0.5.539: dunkle Flaeche hinter der Liste (vorher fast durchsichtig - Spielwelt schien durch)
        function Radar.ApplyListBg()
            local a = ns.db.settings.memberListAlpha or 0.82
            glass(p.tbl, { 0.02, 0.02, 0.028, a }, nil, 12)
        end
        Radar.ApplyListBg()
        if not hasGlass() then p.tbl:Hide() end
        hdr:SetPoint("TOPLEFT", seg, "TOPLEFT", 18, TBLY - (hasGlass() and 6 or 2))
        hdr:SetPoint("RIGHT", p, "RIGHT", 0, 0)
        hdr:SetHeight(18)
        p.heads = {}
        p.hdr, p.headBy = hdr, {}
        local function h(t, x, key, id)
            local b = CreateFrame("Button", nil, hdr)
            b:SetHeight(18)
            b.text = K.Text(b, hasGlass() and 11 or 10, C.dim)
            b.text:SetPoint("LEFT", 0, 0)
            if not hasGlass() then t = K.Upper(t) end
            b.text:SetText(t)
            b:SetPoint("LEFT", x, 0)
            b:SetWidth(b.text:GetStringWidth() + 14)
            if key then
                b.key, b.base = key, t
                b:SetScript("OnClick", function()
                    if sortKey == key then
                        if sortDesc == (key ~= "level") then sortKey, sortDesc = nil, false else sortDesc = not sortDesc end
                    else
                        sortKey, sortDesc = key, key == "level"
                    end
                    ns.RefreshPage("radar")
                end)
                b:SetScript("OnEnter", function(self) self.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
                b:SetScript("OnLeave", function(self) ns.RefreshPage("radar") end)
                p.heads[#p.heads + 1] = b
            end
            if id then p.headBy[id] = b end
        end
        h(L["Name"], hasGlass() and 58 or 54, "name", "name") h(L["Rang"], 196, "rank", "grank") h(L["Lvl"], 306, "level", "lvl") h(L["Gebiet"], 368, "zone", "zone") h(L["Zuletzt"], 484, "last", "last") h(L["Rollen"], 562, nil, "roles") h(L["Berufe"], 606, nil, "profs")
        -- rechts: Abzeichen + Oasis-Punkt
        local hb = K.Text(hdr, 11, C.dim, "RIGHT")
        hb:SetPoint("RIGHT", hasGlass() and -52 or -26, 0)
        hb:SetText(hasGlass() and L["Abzeichen"] or K.Upper(L["Abzeichen"]))
        p.hb = hb
        local ho = CreateFrame("Frame", nil, hdr)
        ho:SetSize(22, 18)
        ho:SetPoint("RIGHT", hasGlass() and -26 or 0, 0)
        p.ho = ho
        ho.t = ho:CreateTexture(nil, "ARTWORK")
        ho.t:SetTexture(ns.MEDIA .. "logo64")
        ho.t:SetSize(20, 20)   -- 0.6.440
        ho.t:SetPoint("CENTER")
        ho.t:SetDesaturated(true)
        ho.t:SetAlpha(0.6)
        ho:EnableMouse(true)
        ho:SetScript("OnEnter", function(self)
            local logo = "|T" .. ns.MEDIA .. "logo64:14:14|t "
            K.ShowTip(self, { L["Oasis"], logo .. L["nutzt Oasis, gerade aktiv"], "|T" .. ns.MEDIA .. "logo64:14:14:0:0:64:64:0:64:0:64:120:120:120|t " .. L["nutzt Oasis, gerade nicht aktiv"], "|cff666666-|r  " .. L["kein Oasis"] })
        end)
        ho:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.count = K.Text(p, 11, C.dim)
        p.count:SetPoint("LEFT", p.reset, "RIGHT", 10, 0)

        -- 0.5.606: Glas-Karten je Zeile (44 px), Platz-Nummer mit Medaille, groesseres Avatar, Menue- und Einladen-Knopf
        local list = K.List(p, hasGlass() and 40 or 30, function(l)   -- 0.6.415: mehr Luft
            local r = K.Row(l)
            if hasGlass() then
                if r.stripe then r.stripe:SetAlpha(0) end
                r.card = CreateFrame("Frame", nil, r)
                r.card:SetPoint("TOPLEFT", 0, -3)
                r.card:SetPoint("BOTTOMRIGHT", 0, 3)
                r.card:SetFrameLevel(math.max(0, r:GetFrameLevel() - 1))
                r.card:EnableMouse(false)
                glass(r.card, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.04 }, 10)
                -- Menue (wie Rechtsklick)
                r.more = CreateFrame("Button", nil, r)
                r.more:SetSize(22, 20)
                r.more:SetPoint("RIGHT", r, "RIGHT", -46, 0)
                r.more:SetFrameLevel(r:GetFrameLevel() + 5)
                r.more.t = K.Title(r.more, 14, C.muted, "CENTER")
                r.more.t:SetPoint("CENTER", 0, 3)
                r.more.t:SetText("...")
                r.more:SetScript("OnClick", function(self)
                    local row = self:GetParent()
                    if row.item and ns.Members and ns.Members.ShowMenu then GameTooltip:Hide() ns.Members.ShowMenu(row, row.item) end
                end)
                r.more:SetScript("OnEnter", function(self) self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) K.ShowTip(self, L["Menue"]) end)
                r.more:SetScript("OnLeave", function(self) self.t:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
            end
            r.online = r:CreateTexture(nil, "ARTWORK")
            r.online:SetTexture(ns.MEDIA .. "dot")
            r.online:SetSize(14, 14)
            r.online:SetPoint("LEFT", 7, 0)
            if hasGlass() then
                -- Avatar-Kreis mit Klassensymbol, kleine Online-Markierung unten rechts
                r.av = r:CreateTexture(nil, "ARTWORK", nil, 1)
                r.av:SetSize(26, 26)
                r.av:SetPoint("LEFT", 8, 0)
                if r.av.SetMask then pcall(r.av.SetMask, r.av, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask") end K.MaskSafe(r.av)
                r.avDisc = r:CreateTexture(nil, "ARTWORK", nil, 0)
                r.avDisc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                r.avDisc:SetSize(26, 26)
                r.avDisc:SetPoint("CENTER", r.av)
                r.newDot = r:CreateTexture(nil, "OVERLAY", nil, 3)
                r.newDot:SetTexture(ns.MEDIA .. "dot")
                r.newDot:SetSize(8, 8)
                r.newDot:SetPoint("CENTER", r.av, "TOPLEFT", 2, -2)
                r.newDot:SetVertexColor(C.mint[1], C.mint[2], C.mint[3], 1)
                r.newDot:Hide()
                r.avIni = K.Text(r, 11, C.text, "CENTER")
                r.avIni:SetPoint("CENTER", r.av, "CENTER", 0, 0)
                r.avIni:SetWidth(26)
                r.online:ClearAllPoints()
                r.online:SetSize(9, 9)
                r.online:SetPoint("CENTER", r.av, "BOTTOMRIGHT", -3, 3)
                r.online:SetDrawLayer("OVERLAY", 3)
                r.onRing = r:CreateTexture(nil, "OVERLAY", nil, 2)
                r.onRing:SetTexture(ns.MEDIA .. "dot")
                r.onRing:SetSize(12, 12)
                r.onRing:SetPoint("CENTER", r.online)
                r.onRing:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 1)
                -- Hover/Auswahl als runde Glas-Zeile
                r.hl:SetColorTexture(1, 1, 1, 0.045)
                round(r.hl, r, 8)
            end
            -- Oasis-Rang-Emblem vor dem Namen: Kreis in Rahmenfarbe mit Rangnummer
            r.remb = r:CreateTexture(nil, "ARTWORK")
            r.remb:SetSize(20, 20)
            r.remb:SetPoint("LEFT", hasGlass() and 42 or 27, 0)
            r.remb:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            r.rembIn = r:CreateTexture(nil, "OVERLAY")
            r.rembIn:SetSize(16, 16)
            r.rembIn:SetPoint("CENTER", r.remb, "CENTER")
            r.rembIn:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            r.rembIn:SetVertexColor(0.07, 0.07, 0.08)
            r.rembNum = r:CreateFontString(nil, "OVERLAY", nil, 2)
            K.SetFontSafe(r.rembNum, K.FONT, 8, "", K.FONT)
            r.rembNum:SetShadowOffset(1, -1)
            r.rembNum:SetShadowColor(0, 0, 0, 0.9)
            r.rembNum:SetPoint("CENTER", r.remb, "CENTER", 0, 0)
            -- Rahmen je Oasis-Rang (Holz, Bronze, Silber, Gold mit Steinen, Smaragd/Saphir mit Schein,
            -- Amethyst/Rubin/Diamant doppelt, Legende/Herz mit Funken) - wie auf Profil und Uebersicht
            if K.RankEmblem then
                r.remblem = K.RankEmblem(r, 20)
                r.remblem:SetPoint("CENTER", r.remb, "CENTER", 0, 0)
                r.remblem:SetFrameLevel(r:GetFrameLevel() + 2)
                r.remblem:Hide()
            end
            r:Col("name", hasGlass() and 72 or 54, hasGlass() and 136 or 140, 13)
            -- "Neu" als kleine Pille hinter dem Namen
            r.newPill = CreateFrame("Frame", nil, r)
            -- Abgleich-Symbol (0.5.515): gruen = gerade/heute abgeglichen, gelb = laenger her, grau = nutzt Oasis, noch nie
            r.sync = r:CreateTexture(nil, "OVERLAY")
            r.sync:SetTexture(ns.MEDIA .. "icons\\sync")
            r.sync:SetSize(9, 9)
            r.sync:Hide()
            r.newPill:SetSize(30, 15)
            glass(r.newPill, { C.mint[1], C.mint[2], C.mint[3], 0.14 }, { C.mint[1], C.mint[2], C.mint[3], 0.45 }, 7)
            r.newPill.t = K.Text(r.newPill, 9, C.mint, "CENTER")
            r.newPill.t:SetPoint("CENTER", 0, 0)
            r.newPill.t:SetText(L["Neu"])
            r.newPill:Hide()
            r:Col("grank", 196, 104, 12, C.muted)
            -- Klassenfarbe als Streifen ganz links
            r.cstripe = r:CreateTexture(nil, "ARTWORK")
            r.cstripe:SetPoint("TOPLEFT", 0, -4)
            r.cstripe:SetPoint("BOTTOMLEFT", 0, 4)
            r.cstripe:SetWidth(2)
            if hasGlass() then r.cstripe:SetAlpha(0) end
            -- Level als kleines Abzeichen, Kante unten in der Farbe des Oasis-Rahmens
            r.lvlBg = r:CreateTexture(nil, "ARTWORK")
            r.lvlBg:SetSize(34, 17)
            r.lvlBg:SetPoint("LEFT", 304, 0)
            r.lvlBg:SetColorTexture(C.raised[1], C.raised[2], C.raised[3], 1)
            r.rankLine = r:CreateTexture(nil, "OVERLAY")
            r.rankLine:SetPoint("BOTTOMLEFT", r.lvlBg, "BOTTOMLEFT")
            r.rankLine:SetPoint("BOTTOMRIGHT", r.lvlBg, "BOTTOMRIGHT")
            r.rankLine:SetHeight(2)
            if hasGlass() then
                -- Level als ruhige Zahl, XP als feine runde Leiste darunter
                r.lvlBg:SetAlpha(0)
                r.rankLine:SetAlpha(0)
            end
            r:Col("lvl", 304, 44, 12, C.text)
            r.cols.lvl:ClearAllPoints()
            r.cols.lvl:SetPoint("LEFT", r.lvlBg, "LEFT", 0, 0)
            r.cols.lvl:SetWidth(34)
            -- Fortschritt zum naechsten Level: Fuellung hinter der Zahl
            r.xpFill = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.xpFill:SetPoint("TOPLEFT", r.lvlBg, "TOPLEFT")
            r.xpFill:SetPoint("BOTTOMLEFT", r.lvlBg, "BOTTOMLEFT")
            r.xpFill:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.28)
            r.xpFill:Hide()
            r.cols.lvl:SetJustifyH("CENTER")
            if hasGlass() then
                r.xpTrack = r:CreateTexture(nil, "ARTWORK")
                r.xpTrack:SetColorTexture(1, 1, 1, 0.08)
                r.xpTrack:SetPoint("BOTTOMLEFT", r.lvlBg, "BOTTOMLEFT", 5, -1)
                r.xpTrack:SetSize(24, 2)
                r.xpTrack:Hide()
                r.xpFill:ClearAllPoints()
                r.xpFill:SetPoint("LEFT", r.xpTrack, "LEFT", 0, 0)
                r.xpFill:SetHeight(2)
                r.xpFill:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.8)
                K.SetFontSafe(r.cols.lvl, K.FONT_HEAD or K.FONT, 16, "", K.FONT)
                -- Level-Strahl: runde Spur, Fuellung als Verlauf, weicher Schein am Ende (dezent)
                r.xpTrack:ClearAllPoints()
                r.xpTrack:SetPoint("BOTTOMLEFT", r.lvlBg, "BOTTOMLEFT", 3, -4)
                r.xpTrack:SetSize(28, 3)
                r.xpTrack:SetColorTexture(1, 1, 1, 0.07)
                round(r.xpTrack, r.xpTrack, 2)
                r.xpFill:SetHeight(3)
                if not K.Gradient(r.xpFill, "HORIZONTAL", { C.mint[1], C.mint[2], C.mint[3], 0.35 }, { C.mint[1], C.mint[2], C.mint[3], 1 }) then
                    r.xpFill:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.8)
                end
                round(r.xpFill, r.xpTrack, 2)
                r.xpGlow = r:CreateTexture(nil, "ARTWORK", nil, 3)
                r.xpGlow:SetTexture(ns.MEDIA .. "softglow")
                r.xpGlow:SetBlendMode("ADD")
                r.xpGlow:SetSize(14, 10)
                r.xpGlow:SetPoint("CENTER", r.xpFill, "RIGHT", 0, 0)
                r.xpGlow:SetVertexColor(C.mint[1] * 0.55, C.mint[2] * 0.55, C.mint[3] * 0.55, 1)
                r.xpGlow:Hide()
            end
            r.gain = K.Text(r, hasGlass() and 11 or 10, C.mint)
            r.gain:SetPoint("LEFT", r.lvlBg, "RIGHT", 3, 0)
            r:Col("zone", 368, 110, 12, C.muted)
            r.cols.zone:SetWordWrap(false)
            r:Col("last", 484, 74, 11, C.muted)
            -- 0.5.782: gleiche Quest wie ich - kleines gelbes Quest-Ausrufezeichen unten rechts am Klassensymbol (der gelbe Strich am
            -- Zeilenrand war nicht als Hinweis erkennbar und wirkte wie ein Darstellungsfehler)
            r.qbar = r:CreateTexture(nil, "OVERLAY", nil, 6)
            r.qbar:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
            r.qbar:SetSize(15, 15)
            r.qbar:SetPoint("LEFT", 33, -10)
            r:Col("roles", 562, 40, 12)
            r:Col("profs", 606, 100, 11, C.muted)
            Radar.AttachProfTip(r, r.cols.profs, function(row)
                local m = row.item
                if not m then return end
                local pr = ns.db.members[m.name]
                return m.name, pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[m.name])
            end)
            r:Col("badges", 0, 60, 12, C.text, "RIGHT")
            r.cols.badges:ClearAllPoints()
            r.cols.badges:SetPoint("RIGHT", hasGlass() and -52 or -26, 0)
            -- Oasis-Emblem: farbig = aktiv, blass = installiert aber gerade nicht aktiv, Strich = kein Oasis
            r.addon = r:CreateTexture(nil, "ARTWORK")
            r.addon:SetTexture(ns.MEDIA .. "logo64")
            r.addon:SetSize(22, 22)   -- 0.6.440: Logo lesbar
            r.addon:SetPoint("RIGHT", hasGlass() and -29 or -3, 0)
            r.noAddon = K.Text(r, 12, C.dim, "CENTER")
            r.noAddon:SetPoint("CENTER", r.addon, "CENTER", 0, 0)
            r.noAddon:SetText("-")
            r:RegisterForClicks("AnyUp")
            r:SetScript("OnClick", function(self, btn)
                if not self.item then return end
                if btn == "RightButton" and ns.Members then
                    GameTooltip:Hide()
                    ns.Members.ShowMenu(self, self.item)
                    return
                end
                local m = self.item
                local now = GetTime()
                if self.lastClick and now - self.lastClick < 0.35 then
                    -- Doppelklick: anfluestern (nur online und nicht man selbst)
                    self.lastClick = nil
                    self.clickId = (self.clickId or 0) + 1
                    if m.online and not ns.isMe(m.name) then ns.Whisper(m.name) end
                    return
                end
                self.lastClick = now
                self.clickId = (self.clickId or 0) + 1
                local id = self.clickId
                ns.After(0.36, function()
                    if self.clickId == id and self.item == m and ns.Profile then ns.Profile.Show(m.name) end
                end)
            end)
            -- beim Drueberfahren: kleiner Einladen-Knopf
            r.inv = CreateFrame("Button", nil, r)
            -- rechts am Zeilenende (wie eine Aktion), mit weichem Auslauf ueber die Abzeichen
            r.inv:SetSize(84, 20)
            r.inv:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.inv:SetFrameLevel(r:GetFrameLevel() + 5)
            r.inv.fade = r.inv:CreateTexture(nil, "BACKGROUND", nil, -1)
            r.inv.fade:SetPoint("TOPRIGHT", r.inv, "TOPLEFT", 0, 2)
            r.inv.fade:SetPoint("BOTTOMRIGHT", r.inv, "BOTTOMLEFT", 0, -2)
            r.inv.fade:SetWidth(50)
            if not K.Gradient(r.inv.fade, "HORIZONTAL", { C.panel[1], C.panel[2], C.panel[3], 0 }, { C.panel[1], C.panel[2], C.panel[3], 1 }) then r.inv.fade:Hide() end
            r.inv.back = r.inv:CreateTexture(nil, "BACKGROUND", nil, -2)
            r.inv.back:SetPoint("TOPLEFT", 0, 2) r.inv.back:SetPoint("BOTTOMRIGHT", 8, -2)
            r.inv.back:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
            r.inv.bg = K.Fill(r.inv, { C.mint[1] * 0.25, C.mint[2] * 0.25, C.mint[3] * 0.25, 0.95 })
            K.Border(r.inv, C.mint)
            r.inv.t = K.Text(r.inv, 10, C.mint, "CENTER")
            r.inv.t:SetPoint("CENTER")
            r.inv.t:SetText("+  " .. K.Upper(L["Einladen"]))
            if hasGlass() then
                -- 2026: kleiner runder Icon-Knopf ganz rechts (eigene Aktionsspalte), ueberdeckt nichts
                r.inv.fade:Hide()
                r.inv.back:Hide()
                r.inv.t:SetText("")
                r.inv:ClearAllPoints()
                r.inv:SetSize(20, 20)
                r.inv:SetPoint("RIGHT", r, "RIGHT", -8, 0)
                -- schlichtes Plus (zwei Striche) statt Gruppen-Symbol
                local ico = CreateFrame("Frame", nil, r.inv)
                ico:SetAllPoints()
                ico.h = ico:CreateTexture(nil, "OVERLAY") ico.h:SetSize(10, 2) ico.h:SetPoint("CENTER")
                ico.v = ico:CreateTexture(nil, "OVERLAY") ico.v:SetSize(2, 10) ico.v:SetPoint("CENTER")
                function ico:SetVertexColor(cr, cg, cb) self.h:SetColorTexture(cr, cg, cb, 1) self.v:SetColorTexture(cr, cg, cb, 1) end
                ico:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
                r.inv.ico = ico
                glass(r.inv, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.14 }, 10)
            end
            r.inv:Hide()
            r.inv:SetScript("OnClick", function(self)
                local m = self:GetParent().item
                if not m then return end
                ns.InviteName(m.name)
                self:Hide()
            end)
            r.inv:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            if not hasGlass() then r.inv:SetFrameStrata("DIALOG") end
            r.inv:SetScript("OnEnter", function(self)
                if hasGlass() then
                    glass(self, { C.mint[1], C.mint[2], C.mint[3], 0.16 }, { C.mint[1], C.mint[2], C.mint[3], 0.6 })
                    self.ico:SetVertexColor(C.mint[1], C.mint[2], C.mint[3])
                    K.ShowTip(self, L["In Gruppe einladen"])
                    return
                end
                self.bg:SetColorTexture(C.mint[1] * 0.4, C.mint[2] * 0.4, C.mint[3] * 0.4, 1)
            end)
            r.inv:SetScript("OnLeave", function(self)
                if hasGlass() then
                    glass(self, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.14 })
                    self.ico:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
                    GameTooltip:Hide()
                    return
                end
                self.bg:SetColorTexture(C.mint[1] * 0.25, C.mint[2] * 0.25, C.mint[3] * 0.25, 0.95)
                if not self:GetParent():IsMouseOver() then self:Hide() end
            end)
            r:SetScript("OnEnter", function(self)
                if not self.item then return end
                -- Level-Fortschritt, Gruppe, Status stehen jetzt im Tooltip selbst (nicht doppelt anhaengen)
                Radar.ShowMemberTip(self, self.item, { xpPct = self.xpPct, hint = L["Klick: Profil  ·  Doppelklick: anfluestern  ·  Rechtsklick: Menue"] })
                local m = self.item
                self.inv:SetShown(m.online and not ns.isMe(m.name) and not (UnitInParty(ns.short(m.name)) or UnitInRaid(ns.short(m.name))))
            end)
            r:SetScript("OnLeave", function(self)
                GameTooltip:Hide()
                if not hasGlass() and not self.inv:IsMouseOver() then self.inv:Hide() end
            end)
            return r
        end, function(r, m, idx)
            -- 2026: Spalten nach aktueller Aufteilung (nur wenn sie sich geaendert hat)
            if p.ApplyCols then p.ApplyCols(r) end
            -- teure Werte je Mitglied einmal je Seiten-Refresh berechnen (Scrollen nutzt den Cache)
            local cx = p.RowData(m)
            local group = Radar.groupRows and Radar.groupRows[m.name]
            if not r.groupLine then
                -- Die Liste schneidet alles ausserhalb ihrer Flaeche ab (SetClipsChildren) - der Strich sitzt aber 10 px LINKS
                -- neben der Zeile und war deshalb nie zu sehen. Darum an die Seite haengen (nicht abgeschnitten), an der Zeile ausrichten.
                local list = r:GetParent()
                local host = (list and list:GetParent()) or r
                r.groupLine = host:CreateTexture(nil, "OVERLAY")
                r.groupLine:SetColorTexture(0.35, 0.62, 0.95, 0.6)
                r.groupLine:SetWidth(2)
                r.groupCap = host:CreateTexture(nil, "OVERLAY")
                r.groupCap:SetColorTexture(0.35, 0.62, 0.95, 0.6)
                r.groupCap:SetSize(6, 2)
                r.groupCap:SetPoint("LEFT", r, "LEFT", -10, 0)
                -- Zeile ausgeblendet (Liste kuerzer, Seite gewechselt): Strich mit ausblenden
                r:HookScript("OnHide", function(self) self.groupLine:Hide() self.groupCap:Hide() end)
                r:HookScript("OnShow", function(self) local on = self.groupOn and true or false self.groupLine:SetShown(on) self.groupCap:SetShown(on) end)
            end
            r.groupOn = group ~= nil
            r.groupLine:SetShown(group ~= nil and r:IsVisible())
            r.groupCap:SetShown(group ~= nil and r:IsVisible())
            if group then
                r.groupLine:ClearAllPoints()
                -- Eigene linke Spalte: Verbindung endet vor Karte und Portraet.
                r.groupLine:SetPoint("TOPLEFT", r, group.first and "LEFT" or "TOPLEFT", -10, 0)
                r.groupLine:SetPoint("BOTTOMLEFT", r, group.last and "LEFT" or "BOTTOMLEFT", -10, 0)
            end
            -- Spaltenbreite geaendert: Twink-Zusatz passend neu kuerzen
            if cx.altMain and cx.labelGen ~= p.colGen then
                cx.label = p.TwinkLabel(m.name, cx.altMain)
                cx.labelGen = p.colGen
                cx.labelW = nil
            end
            local pr = cx.pr
            r.cols.grank:SetText(m.rank or "")
            if hasGlass() then
                local np = p.colPos and p.colPos.name
                if cx.twTxt and np then
                    if not r.tw then
                        r.tw = K.Text(r, 10, C.dim)
                        r.tw:SetWordWrap(false)
                        r.tw:SetJustifyH("LEFT")
                    end
                    r.cols.name:ClearAllPoints()
                    r.cols.name:SetPoint("LEFT", r, "LEFT", np.x, 6)
                    r.tw:ClearAllPoints()
                    r.tw:SetPoint("LEFT", r, "LEFT", np.x, -7)
                    r.tw:SetWidth(np.w - 14)
                    r.tw:SetText(cx.twTxt)
                    r.tw:Show()
                    r.twOn = true
                    r.cols.name:SetText(cx.plain)
                else
                    if r.twOn and np then
                        r.twOn = nil
                        r.cols.name:ClearAllPoints()
                        r.cols.name:SetPoint("LEFT", r, "LEFT", np.x, 0)
                    end
                    if r.tw then r.tw:Hide() end
                    r.cols.name:SetText(cx.label)
                end
                if cx.isNew then
                    -- Breite einmal je Mitglied messen (GetStringWidth ist teuer)
                    cx.labelW = cx.labelW or (r.cols.name:GetStringWidth() or 0)
                    r.newPill:ClearAllPoints()
                    r.newPill:SetPoint("LEFT", r.cols.name, "LEFT", math.max(0, math.min((r.cols.name:GetWidth() or 136) - 32, cx.labelW)) + 6, 0)
                end
                r.newPill:Hide()
                if r.newDot then r.newDot:SetShown(cx.isNew and true or false) end
                -- Avatar: Klassensymbol rund, sonst Initiale auf Scheibe in gedaempfter Klassenfarbe
                if r.avClass ~= (m.class or "") then
                    r.avClass = m.class or ""
                    local GI = ns.GuildInfo
                    r.avOk = m.class and GI and GI.SetClassIcon and GI.SetClassIcon(r.av, m.class) and true or false
                end
                r.av:SetShown(r.avOk)
                if r.avOk then
                    r.avDisc:SetVertexColor(0, 0, 0, 0.4)
                    r.avIni:Hide()
                else
                    local ar, ag, ab = cx.cr, cx.cg, cx.cb
                    r.avDisc:SetVertexColor((ar or 0.5) * 0.35, (ag or 0.5) * 0.35, (ab or 0.5) * 0.35, 1)
                    r.avIni:SetText(cx.initial)
                    r.avIni:Show()
                end
                r.av:SetDesaturated(not m.online)
                r.av:SetAlpha(m.online and 1 or 0.75)
                r.onRing:SetShown(m.online and true or false)
                r.online:SetShown(m.online and true or false)
            else
                r.cols.name:SetText((cx.isNew and ("|cff66db9e" .. L["NEU"] .. "|r ") or "") .. cx.label)
            end
            -- Abgleich mit diesem Mitglied
            do
                local me = ns.isMe(m.name)
                local t, _, _, fresh = (not me and ns.Comm and ns.Comm.PeerSync) and ns.Comm.PeerSync(m.name)
                r.sync:ClearAllPoints()
                r.sync:SetPoint("RIGHT", r.cols.name, "RIGHT", 0, 0)
                if me then
                    -- eigene Zeile: letzter Abgleich mit der Gilde (0.5.552)
                    local last = ns.db.meta.lastSync or 0
                    local cur = last > 0 and (ns.now() - last) < 900
                    local c = cur and C.mint or C.dim
                    r.sync:SetVertexColor(c[1], c[2], c[3], cur and 0.95 or (last > 0 and 0.55 or 0.3))
                    r.sync:Show()
                    r.syncName = nil
                    if ns.Comm and ns.Comm.syncing and not r.syncSpin then
                        r.syncSpin = 0
                        r.syncAnim = r.syncAnim or CreateFrame("Frame", nil, r)
                        r.syncAnim:SetScript("OnUpdate", function(self, el)
                            r.syncSpin = (r.syncSpin or 0) + el
                            r.sync:SetRotation(-r.syncSpin * 6)
                            -- hoechstens 15 s drehen (ein langer Abgleich laeuft gedrosselt im Hintergrund weiter)
                            if (not (ns.Comm and ns.Comm.syncing) and r.syncSpin > 1.2) or r.syncSpin > 15 then r.sync:SetRotation(0) r.syncSpin = nil self:SetScript("OnUpdate", nil) end
                        end)
                    end
                elseif not t and not pr then
                    r.sync:Hide()
                else
                    -- gruen nur, wenn aktuell: online und in den letzten 15 Min abgeglichen; sonst grau
                    local age = t and (ns.now() - t) or nil
                    local fresh15 = age and age < 900 and m.online
                    local c = fresh15 and C.mint or C.dim
                    r.sync:SetVertexColor(c[1], c[2], c[3], fresh15 and 0.95 or (age and 0.55 or 0.3))
                    r.sync:Show()
                    r.syncT, r.syncName = t, m.name
                    -- Ladeanzeige: dreht sich, solange mit ihm abgeglichen wird (und kurz danach)
                    if (fresh or ns.Comm.PeerBusy(m.name)) and not r.syncSpin and not (r.syncCool and GetTime() - r.syncCool < 60) then
                        r.syncSpin = 0
                        r.syncAnim = r.syncAnim or CreateFrame("Frame", nil, r)
                        r.syncAnim:SetScript("OnUpdate", function(self, el)
                            r.syncSpin = (r.syncSpin or 0) + el
                            r.sync:SetRotation(-r.syncSpin * 6)
                            r.sync:SetVertexColor(C.mint[1], C.mint[2], C.mint[3], 1)
                            local busy = r.syncName and ns.Comm.PeerBusy(r.syncName)
                            if (not busy and r.syncSpin > 1.2) or r.syncSpin > 15 then
                                r.sync:SetRotation(0) r.syncSpin = nil self:SetScript("OnUpdate", nil)
                                r.syncCool = GetTime()   -- danach erst in 60 s wieder anfangen zu drehen
                            end
                        end)
                    end
                end
            end
            r.cols.roles:SetText(cx.roleTxt)
            r.cols.badges:SetText(cx.badges)
            r.cols.lvl:SetText(m.level)
            r.xpPct = cx.xpPct
            local xpW = r.xpTrack and 28 or 34
            if cx.xpPct and (m.level or 0) < 60 then
                r.xpFill:SetWidth(math.max(1, xpW * math.min(1, cx.xpPct / 100)))
                r.xpFill:Show()
            else
                r.xpFill:Hide()
            end
            if r.xpTrack then r.xpTrack:SetShown(r.xpFill:IsShown()) end
            if r.xpGlow then r.xpGlow:SetShown(r.xpFill:IsShown() and m.online and true or false) end
            r.gain:SetText(cx.gain > 0 and ("+" .. cx.gain) or "")
            if hasGlass() then r.gain:SetTextColor(C.mint[1], C.mint[2], C.mint[3], 0.75) end
            r.cstripe:SetColorTexture(cx.cr or 0.5, cx.cg or 0.5, cx.cb or 0.5, m.online and 1 or 0.4)
            local orl, st = cx.orl, cx.st
            if orl then
                r.rankLine:SetColorTexture(st.color[1], st.color[2], st.color[3], 1)
                r.rankLine:Show()
                r.remb:SetVertexColor(st.color[1], st.color[2], st.color[3])
                r.rembNum:SetText(cx.verified and orl or "?")
                r.rembNum:SetTextColor(math.min(1, st.color[1] + 0.25), math.min(1, st.color[2] + 0.25), math.min(1, st.color[3] + 0.25))
            else
                r.rankLine:Hide()
            end
            if r.remblem then
                -- Wappen je Rang-Stufe ersetzt den einfachen Kreis (nur neu zeichnen, wenn sich der Rang aendert)
                r.remb:Hide()
                r.rembIn:Hide()
                r.rembNum:Hide()
                if orl then
                    if r.lastOrl ~= orl or not r.remblem:IsShown() then r.remblem:SetRank(orl) end
                else
                    r.remblem:Hide()
                end
                r.lastOrl = orl
            else
                r.remb:SetShown(orl ~= nil)
                r.rembIn:SetShown(orl ~= nil)
                r.rembNum:SetShown(orl ~= nil)
            end
            r.qbar:Hide()   -- Quest-Ausrufezeichen entfernt
            r.cols.zone:SetText(cx.zoneTxt)
            r.cols.last:SetText(cx.lastTxt)
            r.cols.profs:SetText(cx.profTxt)
            local dc = m.online and C.mint or C.dim
            r.online:SetVertexColor(dc[1], dc[2], dc[3])
            r.online:SetAlpha(m.online and 1 or 0.4)
            r.addon:SetShown(cx.has)
            r.noAddon:SetShown(false)
            r.addon:SetDesaturated(not cx.active)
            r.addon:SetAlpha(cx.active and 1 or 0.45)
            if hasGlass() then
                -- Sehr dezente Klassenfarbe links, zur rechten Kartenhaelfte dunkel auslaufend.
                -- Zwei Haelften halten jede Textur unter WoWs Grenze von drei Masken.
                if not r.classTint then
                    r.classTint = {}
                    for i = 1, 2 do
                        local t = r.card:CreateTexture(nil, "BACKGROUND", nil, 2)
                        if i == 1 then
                            t:SetPoint("TOPLEFT", r.card, "TOPLEFT")
                            t:SetPoint("BOTTOMRIGHT", r.card, "BOTTOM")
                        else
                            t:SetPoint("TOPLEFT", r.card, "TOP")
                            t:SetPoint("BOTTOMRIGHT", r.card, "BOTTOMRIGHT")
                        end
                        if K.RoundMask then K.RoundMask(t, t, 10, i == 1 and { "tl", "bl" } or { "tr", "br" }) end
                        r.classTint[i] = t
                    end
                end
                local cr, cg, cb = cx.cr or 0.5, cx.cg or 0.5, cx.cb or 0.5
                if group then cr, cg, cb = 0.25, 0.58, 1 end
                local mid = { cr, cg, cb, 0.025 }
                if not K.Gradient(r.classTint[1], "HORIZONTAL", { cr, cg, cb, group and 0.12 or 0.06 }, mid) then
                    r.classTint[1]:SetColorTexture(cr, cg, cb, 0.045)
                end
                if not K.Gradient(r.classTint[2], "HORIZONTAL", mid, { 0, 0, 0, 0.045 }) then
                    r.classTint[2]:SetColorTexture(0, 0, 0, 0.025)
                end
                -- Einladen nur fuer online, nicht ich, nicht schon in der Gruppe
                r.inv:SetShown(cx.canInvite)
                r.more:Show()
                -- Karte: eigene Zeile mit Akzentrand, sonst ruhig (Platz-Nummern entfernt)
                local me = ns.isMe(m.name)
                if me then
                    -- 0.6.415: ruhiger - eigene Zeile nur leicht betont
                    glass(r.card, { C.accent[1], C.accent[2], C.accent[3], 0.05 }, { C.accent[1], C.accent[2], C.accent[3], 0.32 })
                else
                    glass(r.card, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.04 })
                end
            end
            -- online deutlich hervorheben: leichter gruener Schimmer; offline klar zurueckgenommen
            if not r.onBg then
                r.onBg = r:CreateTexture(nil, "BACKGROUND", nil, 1)
                r.onBg:SetAllPoints()
                if not K.Gradient(r.onBg, "HORIZONTAL", { C.mint[1], C.mint[2], C.mint[3], 0.12 }, { C.mint[1], C.mint[2], C.mint[3], 0 }) then
                    r.onBg:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.06)
                end
            end
            r.onBg:SetShown(m.online and not hasGlass() and true or false)
            -- offline gedaempft, aber lesbar
            local offA = hasGlass() and 0.62 or 0.42
            r:SetAlpha(m.online and 1 or offA)
            if p.fresh then
                local target = m.online and 1 or offA
                r:SetAlpha(0)
                K.Tween(r, 0.3, function(q) r:SetAlpha(target * q) end, function() r:SetAlpha(target) end, math.min(0.6, (idx or 1) * 0.03))
                ns.After(1.6, function() if r.item == m then r:SetAlpha(target) end end)
            end
        end)
        -- Je-Mitglied-Cache fuer die Zeilen (wird bei jedem Seiten-Refresh geleert: Roster, Profile, Filter)
        p.rowCache = {}
        function p.TwinkLabel(name, main)
            local w = p.colPos and p.colPos.name and p.colPos.name.w or 140
            local mn = ns.displayName(main) or ""
            -- Main-Namen kuerzen (UTF-8-sicher)
            local maxC = w >= 160 and 14 or 10
            local chars = {}
            for ch in mn:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
            if #chars > maxC then mn = table.concat(chars, "", 1, maxC - 1) .. "\226\128\166" end
            local tag = (w >= 160) and (L["Twink von %s"]):format(mn) or ("\226\134\179 " .. mn)
            return Radar.Colored(name) .. "  |cff7c7c86" .. tag .. "|r"
        end
        function p.RowData(m)
            local cx = p.rowCache[m]
            if cx then return cx end
            cx = {}
            local name = m.name
            local me = ns.isMe(name)
            local pr = ns.db.members[name]
            cx.pr = pr
            cx.isNew = ns.Welcome and ns.Welcome.IsNew(name) or false
            cx.label = Radar.Label and Radar.Label(name) or Radar.Colored(name)
            -- online Twink: klein grau "Twink von <Main>" (Kurzform "↳ <Main>" bei schmaler Namensspalte)
            if ns.Alts and ns.Alts.IsAlt(name) then
                cx.altMain = ns.Alts.Main(name)
                cx.label = p.TwinkLabel(name, cx.altMain)
                cx.labelGen = p.colGen
                -- 0.5.567: Glas-Liste zeigt Twinks zweizeilig: Name oben, darunter "Twink von <Main>"
                cx.plain = Radar.Colored(name)
                cx.twTxt = "|cff9a8fc4" .. (L["Twink von %s"]):format(ns.displayName(cx.altMain) or "?") .. "|r"
            end
            cx.cr, cx.cg, cx.cb = ns.classColor(m.class)
            cx.initial = ((ns.short(name or "?")):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"):upper()
            local roleTxt = ns.Profile and ns.Profile.RoleIcons(name, 14) or ""
            if roleTxt == "" and not (pr or me) then roleTxt = "|cff444444?|r" end
            cx.roleTxt = roleTxt
            local bt = ns.Badges and ns.Badges.CountText(name, 12) or ""
            cx.badges = bt:find("|T", 1, true) and bt or ""
            cx.gain = ns.Members and ns.Members.LevelGain(name, 7, m.level) or 0
            if me then
                local c, mx = ns.safe(UnitXP("player")) or 0, ns.safe(UnitXPMax("player")) or 0
                cx.xpPct = mx > 0 and c / mx * 100 or nil
            elseif pr and tonumber(pr.xp) and tonumber(pr.lvl) == m.level then
                cx.xpPct = tonumber(pr.xp)
            end
            cx.verified = true
            if ns.Rank then cx.orl, cx.verified = ns.Rank.Of(name) end
            if cx.orl then cx.st = ns.Rank.Frame(cx.orl) end
            -- gelber Strich links: gleiche Quest wie ich - nur bei Mitgliedern, die gerade online sind (mit wem kann ich JETZT losziehen)
            cx.shared = ns.Members and not me and m.online and #ns.Members.SharedQuests(name) > 0
            local short = ns.short(name)
            local inGroup = not me and (UnitInParty(short) or UnitInRaid(short)) and true or false
            if m.online then
                local icon = ns.Members and ns.Members.StatusIcon(name, 12) or ""
                if inGroup then icon = ("|T%sicons\\groups:12:12:0:0:64:64:0:64:0:64:102:219:158|t "):format(ns.MEDIA)
                elseif icon == "" and Radar.groupRows and Radar.groupRows[name] then
                    -- steht in einer gemeldeten Gruppe (Klammer links), hat aber selbst kein Oasis: gleiches Symbol wie die anderen
                    -- ist jemand aus derselben Gruppe im Dungeon (und im selben Gebiet), gilt das auch hier
                    local gid, inst = Radar.groupRows[name].id, false
                    for other, mk in pairs(Radar.groupRows) do
                        if other ~= name and mk.id == gid and ns.Members and ns.Members.Status(other) == "inst" then
                            local om = Radar.byName and Radar.byName[other]
                            if not om or (om.zone or "") == (m.zone or "") then inst = true break end
                        end
                    end
                    local c = inst and C.accent or C.amber
                    icon = ("|T%sicons\\%s:12:12:0:0:64:64:0:64:0:64:%d:%d:%d|t "):format(ns.MEDIA, inst and "dungeons" or "groups", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
                end
                local here = m.zone ~= "" and not me and m.zone == (ns.safe(GetRealZoneText()) or "")
                local lay = here and ns.Map and ns.Map.SameLayer and ns.Map.SameLayer(name)
                local layTag = lay == true and ("  |cff5f9f74" .. L["gleicher Layer"] .. "|r") or (lay == false and ("  |cffb06a5e" .. L["anderer Layer"] .. "|r") or "")
                cx.zoneTxt = icon .. (here and ("|cff66db9e" .. m.zone .. "|r  |cff66db9e" .. ("|T%sdot:8:8|t"):format(ns.MEDIA) .. " " .. L["hier"] .. "|r" .. layTag) or m.zone)
                cx.lastTxt = "|cff66db9e" .. L["jetzt"] .. "|r"
            else
                cx.zoneTxt = "|cff666666" .. (m.zone or "") .. "|r"
                if m.offDays then
                    local h = m.offDays * 24
                    local col = m.offDays >= (ns.db.settings.inactiveDays or 30) and "|cffd9786b" or "|cff888888"
                    cx.lastTxt = col .. (h < 1 and L["gerade eben"] or h < 24 and (L["vor %d Std"]):format(math.floor(h))
                        or (L["vor %d Tg"]):format(math.floor(m.offDays))) .. "|r"
                else
                    cx.lastTxt = ""
                end
            end
            local raw = pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[name])
            if hasGlass() then
                -- kompakt: nur die zwei hoechsten Berufe (Symbol + Zahl), alles Weitere im Tooltip
                cx.profTxt = Radar.ProfIcons(raw, 13, 2)
            else
                cx.profTxt = Radar.ProfIcons(raw, 13)
                if m.class == "ROGUE" and pr and tonumber(pr.lp) then
                    cx.profTxt = cx.profTxt .. "  |cffd9c27a" .. L["Schloss"] .. " " .. pr.lp .. "|r"
                end
            end
            cx.has = pr ~= nil or me
            cx.active = me or Radar.HasAddon(name)
            cx.canInvite = (m.online and not me and not inGroup) and true or false
            p.rowCache[m] = cx
            return cx
        end
        -- 0.5.626: Messung (/oa leistung) + Vorberechnung im Hintergrund (je Bild hoechstens ~3 ms),
        -- damit beim Scrollen keine Zeile erst ihre Daten ausrechnen muss
        local rawRowData = p.RowData
        function p.RowData(m)
            local hit = p.rowCache[m]
            if hit then return hit end
            local t0 = ns.prof and debugprofilestop()
            local cx = rawRowData(m)
            if t0 and ns.prof then ns.prof.add(nil, "Mitglieder: Zeilendaten", debugprofilestop() - t0) end
            return cx
        end
        local warm = CreateFrame("Frame", nil, p)
        warm:Hide()
        warm:SetScript("OnUpdate", function(self)
            local data = p.list and p.list.data
            if not data or not p:IsVisible() then self:Hide() return end
            local clock = debugprofilestop or function() return GetTime() * 1000 end
            local t0 = clock()
            -- zuerst um die aktuelle Position herum, dann den Rest
            local start = math.max(1, (p.list.offset or 0) - 2)
            local n = #data
            for k = 0, n - 1 do
                local i = (start - 1 + k) % n + 1
                local m = data[i]
                if m and not p.rowCache[m] then
                    pcall(p.RowData, m)
                    if clock() - t0 > 3 then return end
                end
            end
            self:Hide()
        end)
        p.WarmRows = function() warm:Show() end
        -- 0.5.620: Mausrad kommt jetzt aus K.List (weich, pixelgenau) - eigene 2-Zeilen-Spruenge entfernt
        -- Spaltenaufteilung 2026: proportional zur Breite, Mindestbreiten, 14 px Abstand; bei Platzmangel
        -- faellt zuerst "Zuletzt", dann "Rollen" weg. Abzeichen + Oasis-Punkt teilen sich eine Spalte.
        if hasGlass() then
            local X0, GAP, INV = 72, 16, 116   -- 0.5.946: nochmal breiter -- 0.5.940: rechts mehr Luft (Abzeichen-Zahl, Oasis-Punkt, Menue, Einladen klebten aneinander) -- 0.5.607: kompakter (ohne Platz-Nummer), rechts Menue + Einladen
            local SPEC = {
                -- 0.5.939: Name breiter (mit Aktualisieren-Symbol und Twink-Zeile wurde es eng) - der Platz kommt aus "Gebiet",
                -- Rang/Level/Gebiet/Berufe ruecken dadurch nach rechts
                { k = "name", min = 144, w = 2.2, max = 250 }, { k = "grank", min = 70, w = 0.7, max = 120 },
                { k = "lvl", fix = 50 }, { k = "zone", min = 90, w = 1.0 },
                { k = "last", fix = 62, drop = 2 }, { k = "roles", fix = 44, drop = 1 },
                { k = "profs", fix = 116 }, { k = "badges", fix = 82 },
            }
            p.colGen = 0
            function p.LayoutCols(W)
                W = math.floor(W or 0)
                local guess = W < 300
                if guess then W = 860 end
                if p.colW == W then return end
                p.colW = (not guess) and W or nil
                local avail = W - X0 - INV
                local function need(skip)
                    local s, n = 0, 0
                    for _, c in ipairs(SPEC) do
                        if not (c.drop and c.drop <= skip) then s = s + (c.fix or c.min) n = n + 1 end
                    end
                    return s + (n - 1) * GAP
                end
                local skip = 0
                while skip < 2 and need(skip) > avail do skip = skip + 1 end
                local extra = math.max(0, avail - need(skip))
                local wsum = 0
                for _, c in ipairs(SPEC) do if c.w and not (c.drop and c.drop <= skip) then wsum = wsum + c.w end end
                local pos, x, left = {}, X0, extra
                local widths = {}
                for _, c in ipairs(SPEC) do
                    if not (c.drop and c.drop <= skip) then
                        local w = c.fix or c.min
                        if c.w then
                            local add = math.floor(extra * c.w / wsum)
                            if c.max then add = math.min(add, c.max - c.min) end
                            w = w + add
                            left = left - add
                        end
                        widths[c.k] = w
                    end
                end
                if left > 0 and widths.zone then widths.zone = widths.zone + left end
                for _, c in ipairs(SPEC) do
                    local w = widths[c.k]
                    if w then pos[c.k] = { x = x, w = w } x = x + w + GAP end
                end
                p.colPos = pos
                p.colGen = p.colGen + 1
                -- Spaltenkoepfe exakt ueber den Spalten
                for k, b in pairs(p.headBy or {}) do
                    local ps = pos[k]
                    b:SetShown(ps ~= nil)
                    if ps then
                        b:ClearAllPoints()
                        b:SetPoint("LEFT", p.hdr, "LEFT", ps.x, 0)
                    end
                end
                p.hb:ClearAllPoints()
                p.hb:SetPoint("RIGHT", p.hdr, "LEFT", W - 8 - 104, 0)
                p.ho:ClearAllPoints()
                p.ho:SetPoint("CENTER", p.hdr, "LEFT", W - 8 - 84, 0)
            end
            function p.ApplyCols(r)
                -- 0.5.947: Breite von der Zeile selbst nehmen - die Aufteilung rechnete teils mit einer anderen Breite als die
                -- Zeile hat, dann lagen Abzeichen, Oasis-Punkt, Menue und Einladen uebereinander
                local rw = r:GetWidth()
                if rw and rw > 300 and math.abs((p.colW or 0) - math.floor(rw + 8)) > 1 then p.LayoutCols(rw + 8) end
                local pos = p.colPos
                if not pos or r.colGen == p.colGen then return end
                r.colGen = p.colGen
                for _, k in ipairs({ "name", "grank", "zone", "last", "roles", "profs" }) do
                    local fs, ps = r.cols[k], pos[k]
                    fs:SetShown(ps ~= nil)
                    if ps then
                        fs:ClearAllPoints()
                        fs:SetPoint("LEFT", r, "LEFT", ps.x, 0)
                        fs:SetWidth(ps.w)
                        fs:SetWordWrap(false)
                    end
                end
                local lp = pos.lvl
                r.lvlBg:ClearAllPoints()
                r.lvlBg:SetPoint("LEFT", r, "LEFT", lp.x - 4, 0)
                local bp = pos.badges
                r.cols.badges:ClearAllPoints()
                r.cols.badges:SetPoint("RIGHT", r, "RIGHT", -104, 0)
                r.cols.badges:SetWidth(bp.w - 4)
                -- Oasis als kleiner Punkt (Logo 10 px) direkt hinter den Abzeichen
                r.addon:ClearAllPoints()
                r.addon:SetSize(10, 10)
                r.addon:SetPoint("CENTER", r, "RIGHT", -84, 0)
            end
        end
        list:SetPoint("TOPLEFT", seg, "TOPLEFT", 18, TBLY - (hasGlass() and 26 or 20))
        list:SetPoint("BOTTOMRIGHT", hasGlass() and -4 or 0, hasGlass() and 44 or 40)
        p.listInset = hasGlass()
        if p.LayoutCols then
            list:HookScript("OnSizeChanged", function(self, w) p.LayoutCols(w) self:Refresh() end)
        end
        local zb = CreateFrame("Frame", nil, p)
        zb:SetPoint("BOTTOMLEFT", 0, 0)
        zb:SetPoint("BOTTOMRIGHT", 0, 0)
        zb:SetHeight(30)
        zb.fill = K.Fill(zb, { 1, 1, 1, 0.025 })
        zb.head = K.Text(zb, hasGlass() and 11 or 10, C.dim)
        zb.head:SetPoint("LEFT", 12, 0)
        zb.head:SetText(hasGlass() and L["Wo ist die Gilde"] or K.Upper(L["Wo ist die Gilde"]))
        zb.head:Hide()   -- 0.5.595: "Wo ist die Gilde" + Gebiets-Kacheln entfernt, nur die Zahlen rechts bleiben
        if hasGlass() then zb.fill:Hide() end
        -- rechts: online / Mitglieder / Questpartner (Klick auf Questpartner = Filter)
        zb.stats = CreateFrame("Button", nil, zb)
        zb.stats:SetPoint("RIGHT", -10, 0)
        zb.stats:SetHeight(24)
        zb.stats.t = K.Text(zb.stats, 11, C.text, "RIGHT")
        zb.stats.t:SetPoint("RIGHT", 0, 0)
        zb.stats:SetScript("OnClick", function() if p.cards[4].tip then p.cards[4]:GetScript("OnClick")(p.cards[4]) end end)
        zb.stats:SetScript("OnEnter", function(self) if p.cards[4].tip then K.ShowTip(self, p.cards[4].tip) end end)
        zb.stats:SetScript("OnLeave", function() GameTooltip:Hide() end)
        zb.chips = {}
        p.zoneBar = zb
        local rc = CreateFrame("Frame", nil, p)
        rc:SetPoint("BOTTOMLEFT", 0, 40)
        rc:SetPoint("BOTTOMRIGHT", 0, 40)
        rc:SetHeight(54)
        K.Fill(rc, { 1, 1, 1, 0.02 })
        rc.head = K.GameHead(rc, L["Zuletzt online"], C.blue)
        rc.head:SetPoint("TOPLEFT", 10, -6)
        rc.head:SetWidth(200)
        rc.chips = {}
        rc:Hide()
        p.recent = rc
        list.empty:SetText(L["Keine Mitglieder gefunden."])
        p.list = list

        -- Level-Rennen
        local race = CreateFrame("Frame", nil, p)
        race:SetPoint("TOPLEFT", 0, -2)
        race:SetPoint("TOPRIGHT", 0, -2)
        race:SetHeight(158)   -- luftiger (08.10.): mehr Platz unter den Plaketten
        race:SetClipsChildren(true)
        -- einklappbar (Standard: offen); alles darunter haengt an der Unterkante
        p.seg:ClearAllPoints()
        p.seg:SetPoint("TOPLEFT", race, "BOTTOMLEFT", 0, -8)
        race.keep = {}   -- bleibt beim Einklappen sichtbar: Kopf, Hintergrund, Griff
        local function raceFold()
            local closed = ns.db.settings.raceClosed
            race:SetHeight(closed and 34 or 158)
            if race.arrow then race.arrow:SetText("") end
            if race.handle then race.handle:SetClosed(closed) end
            -- alles andere (Plaketten, Linie, "Du"-Markierung, Avatare) aus-/einblenden - ragte sonst unten heraus
            for _, c in ipairs({ race:GetChildren() }) do
                if not race.keep[c] and c ~= race.fold and c ~= race.handle then
                    if closed then
                        if not c.foldHidden then c.foldHidden = true c.foldA = c:GetAlpha() c:SetAlpha(0) end
                    elseif c.foldHidden then
                        c.foldHidden = nil
                        c:SetAlpha(c.foldA or 1)
                    end
                end
            end
        end
        race.Fold = raceFold
        -- eingeklappt: kurz danach nochmal anwenden (Teile entstehen spaeter / Animationen setzen Alpha neu)
        local guard = CreateFrame("Frame", nil, race)
        guard.t = 0
        guard:SetScript("OnUpdate", function(self, el)
            self.t = self.t + el
            if self.t < 0.5 then return end
            self.t = 0
            if not ns.db.settings.raceClosed then return end
            for _, c in ipairs({ race:GetChildren() }) do
                if not race.keep[c] and c ~= race.fold and c ~= race.handle and c ~= self and c:GetAlpha() > 0 then
                    c.foldHidden = true
                    c.foldA = c.foldA or c:GetAlpha()
                    c:SetAlpha(0)
                end
            end
        end)
        race.keep[guard] = true
        race.fold = CreateFrame("Button", nil, race)
        race.fold:SetPoint("TOPLEFT", 0, 0)
        race.fold:SetPoint("TOPRIGHT", 0, 0)
        race.fold:SetHeight(32)
        race.fold:SetFrameLevel(race:GetFrameLevel() + 20)
        race.arrow = K.Title(race.fold, 16, C.muted, "RIGHT")
        race.arrow:SetPoint("RIGHT", -100, 0)
        race.fold:SetScript("OnClick", function()
            ns.db.settings.raceClosed = not ns.db.settings.raceClosed or nil
            raceFold()
        end)
        race.fold:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Level-Rennen"], "|cff888888" .. L["Klick: ein-/ausklappen"] .. "|r" }) end)
        race.fold:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Griff unten mittig: kleine Pille mit Pfeil (zeigt nach oben = einklappen, nach unten = aufklappen)
        do
            local h = CreateFrame("Button", nil, race)
            h:SetSize(46, 14)
            h:SetPoint("BOTTOM", race, "BOTTOM", 0, 3)
            h:SetFrameLevel(race:GetFrameLevel() + 25)
            h.bg = h:CreateTexture(nil, "BACKGROUND")
            h.bg:SetAllPoints()
            h.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            h.bg:SetVertexColor(1, 1, 1, 0.05)
            if K.ApplySkin then pcall(K.ApplySkin, h, "panel", { 1, 1, 1, 0.05 }) end
            -- Pfeil aus zwei kurzen Strichen
            h.l1 = h:CreateTexture(nil, "ARTWORK") h.l1:SetSize(7, 1.5)
            h.l2 = h:CreateTexture(nil, "ARTWORK") h.l2:SetSize(7, 1.5)
            local function col(c, a) h.l1:SetColorTexture(c[1], c[2], c[3], a) h.l2:SetColorTexture(c[1], c[2], c[3], a) end
            function h:SetClosed(closed)
                self.closed = closed
                -- ^ (offen -> einklappen) bzw. v (zu -> aufklappen)
                local up = not closed
                self.l1:ClearAllPoints() self.l2:ClearAllPoints()
                self.l1:SetPoint("CENTER", self, "CENTER", -2.4, 0)
                self.l2:SetPoint("CENTER", self, "CENTER", 2.4, 0)
                self.l1:SetRotation(up and 0.6 or -0.6)
                self.l2:SetRotation(up and -0.6 or 0.6)
                col(C.muted, 0.9)
            end
            h:SetScript("OnClick", function() race.fold:GetScript("OnClick")(race.fold) end)
            h:SetScript("OnEnter", function(self)
                col(C.text, 1)
                h.bg:SetVertexColor(1, 1, 1, 0.12)
                K.ShowTip(self, { L["Level-Rennen"], self.closed and L["Klick: aufklappen"] or L["Klick: einklappen"] })
            end)
            h:SetScript("OnLeave", function() col(C.muted, 0.9) h.bg:SetVertexColor(1, 1, 1, 0.05) GameTooltip:Hide() end)
            race.handle = h
        end
        raceFold()
        local LEFTW = 300   -- Breite der Online-Aufstellung, rechts davon das Level-Rennen
        -- zwei Karten mit Farbverlauf und Akzentlinie oben
        local function raceCard(color)
            local c = CreateFrame("Frame", nil, race)
            c:SetFrameLevel(math.max(0, race:GetFrameLevel() - 1))   -- unter den Texten der Flaeche
            K.Fill(c, C.panel)
            c.grad = c:CreateTexture(nil, "BORDER")
            c.grad:SetAllPoints()
            if not K.Gradient(c.grad, "VERTICAL", { color[1], color[2], color[3], 0 }, { color[1], color[2], color[3], 0.07 }) then c.grad:Hide() end
            c.top = c:CreateTexture(nil, "ARTWORK")
            c.top:SetPoint("TOPLEFT") c.top:SetPoint("TOPRIGHT") c.top:SetHeight(2)
            c.top:SetColorTexture(color[1], color[2], color[3], 0.8)
            K.Border(c, C.line)
            if hasGlass() then c.grad:Hide() c.top:Hide() glass(c, nil, nil, 12) end
            return c
        end
        local cardL, cardR = raceCard(C.mint), raceCard(C.amber)
        race.keep[cardL], race.keep[cardR] = true, true
        cardL:SetPoint("TOPLEFT") cardL:SetPoint("BOTTOMLEFT")
        cardL:SetWidth(LEFTW + 12)
        -- Online-Aufstellung entfernt: Level-Rennen nutzt die ganze Breite
        local RX = 0
        cardL:Hide()
        cardR:SetPoint("TOPLEFT", RX, 0) cardR:SetPoint("BOTTOMRIGHT")
        -- 0.5.604: dezentes Hintergrundbild (Wettrennen der Voelker), fuellt die Karte ohne Verzerrung (Ausschnitt per
        -- feste Hoehe), nach links ausgeblendet; Ecken oben/rechts maskiert (WoW nimmt max. 3 Masken, links blendet es aus)
        do
            local bg = cardR:CreateTexture(nil, "BACKGROUND", nil, 4)
            bg:SetTexture(ns.MEDIA .. "race_bg")
            -- feste Hoehe (aufgeklappt): maskierte Texturen ignorieren SetTexCoord, also kein Ausschnitt moeglich;
            -- eingeklappt schneidet die Box das Bild einfach ab statt es zu stauchen
            bg:SetPoint("TOPLEFT", 1, -1)
            bg:SetPoint("TOPRIGHT", -1, -1)
            bg:SetHeight(156)
            if bg.SetGradient and CreateColor then
                pcall(bg.SetGradient, bg, "HORIZONTAL", CreateColor(1, 1, 1, 0.05), CreateColor(1, 1, 1, 0.30))
            else
                bg:SetAlpha(0.18)
            end
            if K.RoundMask then K.RoundMask(bg, cardR, 12, { "tl", "tr", "br" }) end
            -- unten dunkler, damit Plaketten und Namen gut lesbar bleiben
            local shade = cardR:CreateTexture(nil, "BACKGROUND", nil, 5)
            shade:SetAllPoints(bg)
            if not K.Gradient(shade, "VERTICAL", { 0, 0, 0, 0.45 }, { 0, 0, 0, 0.05 }) then shade:Hide() end
            if K.RoundMask then K.RoundMask(shade, cardR, 12, { "tl", "tr", "br" }) end
            race.bgArt = bg
        end
        -- Online-Aufstellung: Zahl gross, Klassenbalken, drei Rollen-Kacheln
        local ch = K.GameHead(race, L["Online-Aufstellung"], C.mint)
        ch:SetPoint("TOPLEFT", 12, -12)
        ch:SetWidth(170)
        ch:Live(true)
        p.compCount = K.Title(race, 20, C.text, "RIGHT")
        p.compCount:SetPoint("TOPRIGHT", race, "TOPLEFT", LEFTW, -8)
        p.compBar = CreateFrame("Frame", nil, race)
        p.compBar:SetPoint("TOPLEFT", 12, -36)
        p.compBar:SetPoint("TOPRIGHT", race, "TOPLEFT", LEFTW, -36)
        p.compBar:SetHeight(10)
        p.compBar:SetClipsChildren(true)
        K.Fill(p.compBar, C.field)
        p.compBar:EnableMouse(true)
        p.compBar:SetScript("OnEnter", function(self)
            if not self.lines then return end
            K.ShowTip(self, self.lines)
        end)
        p.compBar:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.compSegs = {}
        -- Rollen-Kacheln
        p.roleTiles = {}
        local ROLE = { { "tank", "Tank", C.blue }, { "heal", "Heiler", C.mint }, { "dps", "Schaden", C.red } }
        for i, rd in ipairs(ROLE) do
            local t = CreateFrame("Button", nil, race)
            t:SetHeight(44)
            t.hl = t:CreateTexture(nil, "HIGHLIGHT")
            t.hl:SetAllPoints()
            t.hl:SetColorTexture(rd[3][1], rd[3][2], rd[3][3], 0.10)
            t.bg = K.Fill(t, C.raised)
            t.grad = t:CreateTexture(nil, "BORDER")
            t.grad:SetAllPoints()
            if not K.Gradient(t.grad, "VERTICAL", { rd[3][1], rd[3][2], rd[3][3], 0 }, { rd[3][1], rd[3][2], rd[3][3], 0.14 }) then t.grad:Hide() end
            t.top = t:CreateTexture(nil, "ARTWORK")
            t.top:SetPoint("TOPLEFT") t.top:SetPoint("TOPRIGHT") t.top:SetHeight(2)
            t.top:SetColorTexture(rd[3][1], rd[3][2], rd[3][3], 0.9)
            K.Border(t, C.line)
            -- quer: Symbol links, Zahl + Beschriftung daneben (nichts ueberlappt)
            t.disc = t:CreateTexture(nil, "ARTWORK", nil, 1)
            t.disc:SetTexture(ns.MEDIA .. "dot")
            t.disc:SetSize(28, 28)
            t.disc:SetPoint("LEFT", 6, 0)
            t.disc:SetVertexColor(rd[3][1], rd[3][2], rd[3][3], 0.22)
            t.icon = K.Glyph(t, 16, ns.MEDIA .. "icons\\role_" .. rd[1], rd[3])
            t.icon:SetPoint("CENTER", t.disc, "CENTER", 0, 0)
            t.icon:SetDrawLayer("ARTWORK", 2)
            t.num = K.Title(t, 18, C.text, "LEFT")
            t.num:SetPoint("TOPLEFT", t.disc, "TOPRIGHT", 7, 4)
            t.lbl = K.Text(t, 9, C.muted, "LEFT")
            t.lbl:SetPoint("TOPLEFT", t.num, "BOTTOMLEFT", 0, -1)
            t.lbl:SetPoint("RIGHT", -4, 0)
            t.lbl:SetWordWrap(false)
            t.lbl:SetText(K.Upper(L[rd[2]]))
            t.key, t.color = rd[1], rd[3]
            t:SetScript("OnClick", function(self)
                if self.missing then
                    ns.ShowPage("groups")
                    local def = ns.PageDef and ns.PageDef("groups")
                    local gp = def and def.frame
                    if gp and gp.title and gp.title.SetFocus then gp.title:SetFocus() end
                    return
                end
                F.role = (F.role ~= self.key) and self.key or nil
                ns.RefreshPage("radar")
            end)
            t:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
            t:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.roleTiles[i] = t
        end
        p.compHint = K.Text(race, 10, C.muted)
        p.compHint:SetPoint("TOPLEFT", 12, -106)
        p.compHint:SetWidth(LEFTW - 12)
        p.compHint:SetWordWrap(false)
        p.compBtn = CreateFrame("Button", nil, race)
        p.compBtn:SetAllPoints(p.compHint)
        p.compBtn:SetScript("OnClick", function()
            if not p.compMissing then return end
            ns.ShowPage("groups")
            local def = ns.PageDef and ns.PageDef("groups")
            local gp = def and def.frame
            if gp and gp.title and gp.title.SetFocus then gp.title:SetFocus() end
        end)
        p.compBtn:SetScript("OnEnter", function(self)
            if p.compMissing then K.ShowTip(self, { L["Gruppensuche starten"], L["Klick: zu den Gruppen - dort Aktivitaet eintragen und starten"] }) end
        end)
        p.compBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        for _, w in ipairs({ ch, p.compCount, p.compBar, p.compHint, p.compBtn }) do w:Hide() end
        for _, t in ipairs(p.roleTiles) do t:Hide() end
        -- Trennlinie zwischen Aufstellung und Level-Rennen
        local vsep = race:CreateTexture(nil, "ARTWORK")
        vsep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        vsep:SetPoint("TOPLEFT", LEFTW + 12, -12)
        vsep:SetPoint("BOTTOMLEFT", LEFTW + 12, 12)
        vsep:SetWidth(1)
        vsep:Hide()   -- jetzt zwei getrennte Karten

        -- Level-Rennen als Zeitleiste
        local rh = K.GameHead(race, L["Level-Rennen"], C.amber)
        race.keep[rh] = true
        if hasGlass() then rh.text:SetText(L["Level-Rennen"]) if rh.mark then rh.mark:SetSize(3, 12) end end
        rh:SetPoint("TOPLEFT", RX + 14, -12)
        rh:SetWidth(170)
        local since = K.Text(race, hasGlass() and 11 or 9, C.dim, "RIGHT")
        since:SetPoint("TOPRIGHT", -12, -16)
        since:SetText(L["seit Oasis"])
        p.raceLines = {}
        for i = 1, 6 do
            -- Verbindungslinie zur naechsten Stufe (gruen, wenn beide erreicht) - waagerecht
            local seg
            if i < 6 then
                seg = race:CreateTexture(nil, "BACKGROUND", nil, 1)
                seg:SetHeight(hasGlass() and 2 or 4)
            end
            local badge = CreateFrame("Frame", nil, race)
            badge:SetSize(34, 34)
            badge:SetFrameLevel(race:GetFrameLevel() + 4)
            badge.bg = badge:CreateTexture(nil, "BACKGROUND")
            badge.bg:SetTexture(ns.MEDIA .. "dot")
            badge.bg:SetAllPoints()
            badge.ring = badge:CreateTexture(nil, "BORDER")
            badge.ring:SetTexture(ns.MEDIA .. "ring")
            badge.ring:SetPoint("TOPLEFT", -2, 2)
            badge.ring:SetPoint("BOTTOMRIGHT", 2, -2)
            -- Schein hinter erreichten Stufen (pulsiert bei der hoechsten)
            badge.glow = badge:CreateTexture(nil, "BACKGROUND", nil, -1)
            badge.glow:SetTexture(ns.MEDIA .. "dot")
            badge.glow:SetPoint("CENTER")
            badge.glow:SetSize(56, 56)
            badge.glow:SetBlendMode("ADD")
            badge.glow:Hide()
            -- Zahl genau mittig: ueber die ganze Plakette gespannt, waagerecht und senkrecht zentriert
            -- Zahl aus Ziffern-Grafiken: immer exakt mittig (Schrift sitzt je nach Font schief)
            badge.lvl = K.DigitText(badge, 13)
            -- feiner innerer Lichtrand fuer mehr Tiefe
            badge.shine = badge:CreateTexture(nil, "ARTWORK", nil, 1)
            badge.shine:SetTexture(ns.MEDIA .. "ring")
            badge.shine:SetPoint("TOPLEFT", 3, -3)
            badge.shine:SetPoint("BOTTOMRIGHT", -3, 3)
            badge.shine:SetVertexColor(1, 1, 1, 0.12)
            if hasGlass() then badge.shine:Hide() badge.calm = true end
            badge:SetScript("OnUpdate", function(self)
                if not self.pulse then return end
                self.glow:SetAlpha(0.25 + 0.2 * math.sin(GetTime() * 3))
            end)
            -- drei feste Plaetze untereinander: Nummer in eigener Spalte, Name daneben
            -- zwei Zeilen unter der Plakette, zentriert: Name (bzw. "offen") + Detail
            local slots = {}
            -- drei Zeilen: Platz 1-3 (bzw. Anzahl / "wer ist dran")
            for j = 1, 3 do
                local name = K.Text(race, j == 1 and 11 or 10, j == 1 and C.text or C.dim, "CENTER")
                name:SetPoint("TOP", badge, "BOTTOM", 0, -10 - (j - 1) * 17)
                name:SetWordWrap(false)
                slots[j] = { name = name }
            end
            badge:EnableMouse(true)
            badge:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
            badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.raceLines[i] = { badge = badge, slots = slots, seg = seg }
        end
        p.race = race
        -- Energiestrahl: von der hoechsten erreichten Stufe bis 60 laufen Lichtimpulse ueber die Linie
        local beam = CreateFrame("Frame", nil, race)
        beam:SetAllPoints(race)
        beam:SetFrameLevel(race:GetFrameLevel() + 3)
        beam:EnableMouse(false)
        beam.core = beam:CreateTexture(nil, "ARTWORK")
        beam.core:SetHeight(2)
        beam.core:SetBlendMode("ADD")
        -- Impulse als kleine Kometen: heller Kopf + zwei verblassende Schweif-Punkte
        beam.pulses = {}
        for i = 1, 3 do
            local pu = {}
            for j = 1, 3 do
                local t = beam:CreateTexture(nil, "OVERLAY")
                t:SetTexture(ns.MEDIA .. "dot")
                t:SetBlendMode("ADD")
                local w = ({ 22, 14, 9 })[j]
                t:SetSize(w, ({ 8, 6, 4 })[j])
                pu[j] = t
            end
            beam.pulses[i] = pu
        end
        -- feine Funken, die gelegentlich von der Linie aufsteigen
        beam.sparks = {}
        for i = 1, 6 do
            local t = beam:CreateTexture(nil, "OVERLAY")
            t:SetTexture(ns.MEDIA .. "dot")
            t:SetBlendMode("ADD")
            t:SetSize(3, 3)
            t:SetAlpha(0)
            beam.sparks[i] = { t = t, life = 0 }
        end
        beam:SetScript("OnUpdate", function(self, elx)
            -- 0.5.625: 30 Bilder/s statt jedes Bild, Pause waehrend gescrollt wird (Positionsabfragen erzwingen Layout)
            self.acc = (self.acc or 0) + (elx or 0)
            if self.acc < 0.033 then return end
            self.acc = 0
            if ns.ListBusy and ns.ListBusy() then return end
            local a, b = self.from, self.to
            if not (a and b and a:GetLeft() and b:GetLeft() and race:GetLeft()) then return end
            local rl, rt = race:GetLeft(), race:GetTop()
            local x1 = (a:GetLeft() + a:GetRight()) / 2 - rl
            local x2 = (b:GetLeft() + b:GetRight()) / 2 - rl
            local y = (a:GetTop() + a:GetBottom()) / 2 - rt
            self.core:ClearAllPoints()
            self.core:SetPoint("LEFT", race, "TOPLEFT", x1, y)
            self.core:SetWidth(math.max(1, x2 - x1))
            local now = GetTime()
            self.core:SetAlpha(0.12 + 0.08 * math.sin(now * 6))
            -- Farbe entlang der Linie: Stufenfarben ineinander uebergehend
            local tiers, n = self.tiers or {}, math.max(1, (self.top or 2) - 1)
            local function colAt(ph)
                local f = ph * n
                local i = math.min(n, math.floor(f)) + 1
                local a1, a2 = tiers[i] or { 1, 1, 1 }, tiers[i + 1] or tiers[i] or { 1, 1, 1 }
                local t = f - (i - 1)
                return a1[1] + (a2[1] - a1[1]) * t, a1[2] + (a2[2] - a1[2]) * t, a1[3] + (a2[3] - a1[3]) * t
            end
            for i, pu in ipairs(self.pulses) do
                local ph = (now * 0.32 + (i - 1) / #self.pulses) % 1
                local fade = math.sin(ph * math.pi)
                local r, g, b2 = colAt(ph)
                for j, t in ipairs(pu) do
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", race, "TOPLEFT", x1 + (x2 - x1) * ph - (j - 1) * 9, y)
                    t:SetVertexColor(math.min(1, r + 0.35), math.min(1, g + 0.35), math.min(1, b2 + 0.35))
                    t:SetAlpha(fade * ({ 0.85, 0.45, 0.22 })[j])
                end
            end
            local el = now - (self.last or now)
            self.last = now
            for _, sp in ipairs(self.sparks) do
                if sp.life <= 0 then
                    if math.random() < el * 0.9 then
                        sp.life, sp.max = 1, 0.6 + math.random() * 0.6
                        sp.x, sp.yy = x1 + (x2 - x1) * math.random(), y
                        sp.vx, sp.vy = (math.random() - 0.5) * 10, 10 + math.random() * 14
                        local r, g, b2 = colAt((sp.x - x1) / math.max(1, x2 - x1))
                        sp.t:SetVertexColor(r, g, b2)
                    else
                        sp.t:SetAlpha(0)
                    end
                else
                    sp.life = sp.life - el / sp.max
                    sp.x, sp.yy = sp.x + sp.vx * el, sp.yy + sp.vy * el
                    sp.t:ClearAllPoints()
                    sp.t:SetPoint("CENTER", race, "TOPLEFT", sp.x, sp.yy)
                    sp.t:SetAlpha(math.max(0, sp.life) * 0.7)
                end
            end
        end)
        beam:Hide()
        -- 2026: keine Lichtimpulse/Funken mehr ueber der Linie
        p.beam = (not hasGlass()) and beam or nil
        p.raceFill = race:CreateTexture(nil, "BACKGROUND", nil, 2)
        p.raceFill:SetHeight(hasGlass() and 2 or 4)
        p.raceFill:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.45)
        local function marker(color, ring)
            local m = CreateFrame("Frame", nil, race)
            m:SetSize(12, 12)
            m:SetFrameLevel(race:GetFrameLevel() + 8)
            m.ring = m:CreateTexture(nil, "ARTWORK")
            m.ring:SetTexture(ns.MEDIA .. "dot")
            m.ring:SetAllPoints()
            m.ring:SetVertexColor(0.05, 0.05, 0.06)
            m.dot = m:CreateTexture(nil, "OVERLAY")
            m.dot:SetTexture(ns.MEDIA .. "dot")
            m.dot:SetPoint("CENTER")
            m.dot:SetSize(8, 8)
            m.dot:SetVertexColor(color[1], color[2], color[3])
            m.lbl = K.Text(m, 9, ring or C.muted, "CENTER")
            m.lbl:SetPoint("BOTTOM", m, "TOP", 0, 1)
            m:EnableMouse(true)
            m:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
            m:SetScript("OnLeave", function() GameTooltip:Hide() end)
            m:Hide()
            return m
        end
        p.leadMark = marker(C.mint, C.mint)
        p.meMark = marker(C.amber, C.amber)
        -- weitere Online-Mitglieder als kleine Punkte in Klassenfarbe (unter Du/Spitzenreiter)
        p.onMarks = {}
        function p.OnMark(i)
            local m = p.onMarks[i]
            if not m then
                m = marker(C.muted)
                m:SetSize(10, 10)
                m.dot:SetSize(6, 6)
                m:SetFrameLevel(race:GetFrameLevel() + 6)
                p.onMarks[i] = m
            end
            return m
        end
        -- Breite verteilen: Rollen-Kacheln links, 6 Stufen rechts nebeneinander
        race:SetScript("OnSizeChanged", function(self)
            local W = self:GetWidth() or 750
            if W < 100 then W = 750 end
            local tw = math.max(40, (LEFTW - 12 - 12) / 3)
            for i, t in ipairs(p.roleTiles) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", 12 + (i - 1) * (tw + 6), -54)
                t:SetWidth(tw)
            end
            local x0 = RX + 14
            local colW = math.floor((W - x0 - 12) / 6)
            p.raceX0, p.raceColW = x0 + colW / 2, colW
            for i, line in ipairs(p.raceLines) do
                local x = x0 + (i - 1) * colW
                line.badge:ClearAllPoints()
                line.badge:SetPoint("TOP", self, "TOPLEFT", x + colW / 2, -46)
                for _, sl in ipairs(line.slots) do sl.name:SetWidth(math.max(20, colW - 6)) end
                if line.seg then
                    line.seg:ClearAllPoints()
                    line.seg:SetPoint("LEFT", line.badge, "RIGHT", 0, 0)
                    line.seg:SetWidth(math.max(2, colW - 34))
                end
            end
        end)
        race:GetScript("OnSizeChanged")(race)

        ----------------------------------------------------------------
        -- Level-Rennen 2026: Glas-Knoten, driftender Hintergrund, Lichtstrahl, Avatare auf der Strecke
        -- (Bewegung nur bei sichtbarer Karte, gedrosselt auf ~30 fps; settings.noAnim = statisch)
        ----------------------------------------------------------------
        if hasGlass() then
            local function animOK() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
            local BADGE_Y = -63                          -- Mitte der Knoten (oben -46, 34 hoch)
            local LVKEY = { "1-19", "20-29", "30-39", "40-49", "50-59", "60" }
            local fxTier = { { 0.85, 0.53, 0.27 }, { 0.80, 0.83, 0.90 }, { 1.00, 0.80, 0.25 }, { 0.30, 0.88, 0.50 }, { 0.35, 0.58, 1.00 }, { 1.00, 0.45, 0.10 } }
            -- weicher, langsam driftender Hintergrund (in der Karte, Ecken rund)
            local bgf = CreateFrame("Frame", nil, cardR)
            bgf:SetAllPoints(cardR)
            bgf:SetFrameLevel(cardR:GetFrameLevel())
            p.raceBlobs = {}
            local bcol = { C.accent, C.amber, C.blue }
            for i = 1, 3 do
                local t = bgf:CreateTexture(nil, "BACKGROUND", nil, 3)
                -- Nebelband aus Media\fx (eigene CC0-Grafik), weich getoent
                t:SetTexture(ns.MEDIA .. "fx\\mist256")
                t:SetSize(460, 150)
                local c = bcol[i] or C.accent
                t:SetVertexColor(c[1], c[2], c[3], 1)
                t:SetAlpha(i == 1 and 0.10 or 0.07)
                round(t, cardR, 12)
                p.raceBlobs[i] = t
            end
            local function placeBlobs(tm)
                local W, H = race:GetWidth() or 750, race:GetHeight() or 128
                if W < 100 then W = 750 end
                local pos = {
                    { 0.25 + 0.12 * math.sin(tm * 0.07), 0.45 + 0.20 * math.cos(tm * 0.05) },
                    { 0.70 + 0.10 * math.cos(tm * 0.06), 0.55 + 0.22 * math.sin(tm * 0.08) },
                    { 0.48 + 0.18 * math.sin(tm * 0.045 + 2), 0.35 + 0.15 * math.cos(tm * 0.065 + 1) },
                }
                for i, t in ipairs(p.raceBlobs) do
                    t:ClearAllPoints()
                    t:SetPoint("CENTER", race, "TOPLEFT", W * pos[i][1], -H * pos[i][2])
                end
            end
            placeBlobs(0)

            -- Fortschrittslinie + Lichtstrahl (ueber der Strecke, unter Knoten und Avataren)
            local lf = CreateFrame("Frame", nil, race)
            lf:SetAllPoints(race)
            lf:SetFrameLevel(race:GetFrameLevel() + 2)
            lf:EnableMouse(false)
            p.raceProg = lf:CreateTexture(nil, "ARTWORK")
            p.raceProg:SetHeight(3)
            p.raceProg:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.85)
            round(p.raceProg, p.raceProg, 1)
            p.raceProg:Hide()
            p.raceShine = lf:CreateTexture(nil, "OVERLAY")
            p.raceShine:SetTexture(ns.MEDIA .. "shine")
            p.raceShine:SetBlendMode("ADD")
            p.raceShine:SetSize(70, 14)
            p.raceShine:SetAlpha(0)
            -- 2026-FX (Media\fx, eigene CC0-Sprites): Komet mit Schweif, Funkeln + Funken an der Spitze,
            -- Schein hinter der Zielstufe, langsam aufsteigende Lichtteilchen. ADD-Blend, gedaempft ueber die Farbe.
            local FX = ns.MEDIA .. "fx\\"
            p.raceShine:SetTexture(FX .. "comet256")
            p.raceShine:SetSize(150, 18)
            -- Verlauf im Hintergrund: oben leicht Akzent, nach unten klar
            p.raceGrad = bgf:CreateTexture(nil, "BACKGROUND", nil, 2)
            p.raceGrad:SetAllPoints(cardR)
            if not K.Gradient(p.raceGrad, "VERTICAL", { C.accent[1], C.accent[2], C.accent[3], 0 }, { C.accent[1], C.accent[2], C.accent[3], 0.07 }) then p.raceGrad:Hide() end
            round(p.raceGrad, cardR, 12)
            p.raceTip = lf:CreateTexture(nil, "OVERLAY", nil, 2)
            p.raceTip:SetTexture(FX .. "twinkle_4x4")
            p.raceTip:SetBlendMode("ADD")
            p.raceTip:SetSize(30, 30)
            p.raceTip:SetPoint("CENTER", p.raceProg, "RIGHT", 0, 0)
            p.raceTip:SetTexCoord(0, 0.25, 0, 0.25)
            p.raceTip:SetAlpha(0)
            p.raceTarget = race:CreateTexture(nil, "BACKGROUND", nil, 5)
            p.raceTarget:SetTexture(FX .. "glow128")
            p.raceTarget:SetBlendMode("ADD")
            p.raceTarget:SetSize(76, 76)
            p.raceTarget:Hide()
            p.raceSparks = {}
            for i = 1, 8 do
                local t = lf:CreateTexture(nil, "OVERLAY", nil, 1)
                t:SetTexture(FX .. "spark32")
                t:SetBlendMode("ADD")
                t:SetSize(6, 6)
                t:SetAlpha(0)
                p.raceSparks[i] = { t = t, life = 0 }
            end
            p.raceMotes = {}
            for i = 1, 10 do
                local t = bgf:CreateTexture(nil, "BACKGROUND", nil, 6)
                t:SetTexture(FX .. "spark32")
                t:SetBlendMode("ADD")
                t:SetSize(4, 4)
                t:SetAlpha(0)
                p.raceMotes[i] = { t = t, life = 0 }
            end
            if p.raceFill then p.raceFill:SetAlpha(0) end

            -- Knoten als runde Glas-Buttons mit grosser Zahl
            for i, line in ipairs(p.raceLines) do
                local b = line.badge
                b.bg:Hide() b.ring:Hide() b.shine:Hide() b.glow:Hide()
                b.calm = true
                glass(b, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.14 }, 17)
                -- deckende Scheibe unter dem Glas: die Verbindungslinie soll nicht durch den Kreis scheinen
                b.back = b:CreateTexture(nil, "BACKGROUND", nil, -8)
                b.back:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                b.back:SetPoint("TOPLEFT", 1, -1)
                b.back:SetPoint("BOTTOMRIGHT", -1, 1)
                b.back:SetVertexColor(0.075, 0.08, 0.095, 1)
                b.inner = b:CreateTexture(nil, "ARTWORK", nil, 1)
                b.inner:SetTexture(ns.MEDIA .. "softglow")
                b.inner:SetSize(30, 22)
                b.inner:SetPoint("TOP", 0, -1)
                round(b.inner, b, 17)
                b.inner:Hide()
                b.num = K.Title(b, 15, C.text, "CENTER")
                if K.CenterNum then K.CenterNum(b.num, b, "CENTER", 0, 0) else b.num:SetPoint("CENTER", 0, 0) end
                -- Stellvertreter: die alte Ziffern-Grafik wird nie gezeichnet, die Zahl kommt aus der Schrift
                b.lvl = {
                    SetText = function(_, v) b.num:SetText(v) end,
                    SetTextColor = function(_, r, g, bb) b.num:SetTextColor(r, g, bb) end,
                }
                b.pulseRing = race:CreateTexture(nil, "BACKGROUND", nil, 4)
                b.pulseRing:SetTexture(ns.MEDIA .. "ring")
                b.pulseRing:SetPoint("CENTER", b, "CENTER")
                b.pulseRing:SetSize(40, 40)
                b.pulseRing:Hide()
                b.idx = i
                -- Hover: leicht anheben; Klick: Tabelle auf diesen Levelbereich filtern
                b:HookScript("OnEnter", function(self)
                    local pt, rel, rp, x, y = self:GetPoint(1)
                    if pt and not self.lifted then self.lifted = true self:SetPoint(pt, rel, rp, x, (y or -40) + 2) end
                end)
                b:HookScript("OnLeave", function(self)
                    local pt, rel, rp, x, y = self:GetPoint(1)
                    if pt and self.lifted then self.lifted = nil self:SetPoint(pt, rel, rp, x, (y or -38) - 2) end
                end)
                b:SetScript("OnMouseUp", function(self)
                    local key = LVKEY[self.idx]
                    F.level = (F.level ~= key) and key or nil
                    ns.RefreshPage("radar")
                end)
            end

            -- Avatare statt Punkte
            local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
            function p.SetAv(m, cls)
                if not m.av then
                    m.av = m:CreateTexture(nil, "OVERLAY", nil, 2)
                    m.av:SetPoint("TOPLEFT", 1.5, -1.5)
                    m.av:SetPoint("BOTTOMRIGHT", -1.5, 1.5)
                    if m.av.SetMask then pcall(m.av.SetMask, m.av, MASK) end K.MaskSafe(m.av)
                    m.ring:SetVertexColor(C.bg[1], C.bg[2], C.bg[3], 1)
                end
                local GI = ns.GuildInfo
                local ok = cls and GI and GI.SetClassIcon and GI.SetClassIcon(m.av, cls)
                m.av:SetShown(ok and true or false)
                m.dot:SetShown(not ok)
                m.dot:SetSize((m:GetWidth() or 12) - 4, (m:GetHeight() or 12) - 4)
            end
            p.leadMark:SetSize(18, 18)
            p.meMark:SetSize(20, 20)
            local onMark = p.OnMark
            function p.OnMark(i)
                local m = onMark(i)
                if not m.fxSized then m.fxSized = true m:SetSize(16, 16) end
                return m
            end
            -- "Du" als kleine Akzent-Pille mit Pfeil
            local me = p.meMark
            me.lbl:SetAlpha(0)
            me.pill = CreateFrame("Frame", nil, me)
            me.pill:SetSize(26, 15)
            me.pill:SetPoint("BOTTOM", me, "TOP", 0, 6)
            local ac = C.accent
            glass(me.pill, { ac[1], ac[2], ac[3], 0.30 }, { ac[1], ac[2], ac[3], 0.75 }, 7)
            me.pill.t = K.Text(me.pill, 10, C.text, "CENTER")
            me.pill.t:SetPoint("CENTER", 0, 0)
            me.pill.t:SetText(L["Du"])
            me.pill.arrow = me.pill:CreateTexture(nil, "ARTWORK")
            me.pill.arrow:SetTexture(ns.MEDIA .. "diamond")
            me.pill.arrow:SetSize(7, 7)
            me.pill.arrow:SetPoint("CENTER", me.pill, "BOTTOM", 0, -1)
            me.pill.arrow:SetVertexColor(ac[1], ac[2], ac[3], 0.85)

            -- Geometrie wie im Refresh (xOf): Position eines Levels auf der Strecke
            local function xOfLv(lv)
                if not (p.raceX0 and p.raceColW) then return nil end
                if lv >= 60 then return p.raceX0 + 5 * p.raceColW end
                if lv % 10 == 0 then return p.raceX0 + (lv / 10 - 1) * p.raceColW end
                local t = math.max(0, math.min(5, (lv - 10) / 10))
                local seg = math.min(4, math.floor(t))
                return p.raceX0 + seg * p.raceColW + 17 + 8 + (t - seg) * math.max(0, p.raceColW - 34 - 16)
            end

            -- Aktualisieren nach jedem Refresh
            function p.RaceFX(races, top, fresh)
                local target = (top or 0) + 1
                for i, line in ipairs(p.raceLines) do
                    local b = line.badge
                    local tc = fxTier[i] or C.mint
                    local done = races[i] and #races[i].list > 0
                    local sel = F.level == LVKEY[i]
                    if done then
                        glass(b, { tc[1], tc[2], tc[3], 0.24 }, sel and { ac[1], ac[2], ac[3], 0.95 } or { tc[1], tc[2], tc[3], 0.85 })
                        b.inner:SetVertexColor(tc[1], tc[2], tc[3], 1)
                        b.inner:SetAlpha(0.35)
                        b.inner:Show()
                        b.num:SetTextColor(1, 1, 1)
                    else
                        glass(b, { 1, 1, 1, 0.04 }, sel and { ac[1], ac[2], ac[3], 0.95 } or (i == target and { tc[1], tc[2], tc[3], 0.55 } or { 1, 1, 1, 0.14 }))
                        b.inner:Hide()
                        b.num:SetTextColor(tc[1] * 0.55 + 0.25, tc[2] * 0.55 + 0.25, tc[3] * 0.55 + 0.25)
                    end
                    -- 0.5.572: Stufen-Abzeichen tragen die Zahl selbst -> Glaskreis, Scheibe und Zahl weg
                    if b.art then
                        glass(b, { 0, 0, 0, 0 }, sel and { ac[1], ac[2], ac[3], 0.95 } or { 0, 0, 0, 0 })
                        b.num:Hide()
                        b.inner:Hide()
                        if b.back then b.back:Hide() end
                    end
                    b.pulseRing:SetVertexColor(tc[1], tc[2], tc[3])
                    b.pulseRing:SetShown(i == target and target <= 6)
                    if not animOK() then b.pulseRing:SetSize(42, 42) b.pulseRing:SetAlpha(0.3) end
                    if b.tip then
                        b.tip[#b.tip + 1] = " "
                        b.tip[#b.tip + 1] = "|cff888888" .. (sel and L["Klick: Levelfilter aus"] or L["Klick: Tabelle auf diesen Levelbereich filtern"]) .. "|r"
                    end
                    if line.seg then line.seg:SetColorTexture(1, 1, 1, 0.08) end
                end
                -- Fortschritt bis zum Spitzenreiter
                local lead = 0
                for _, m in ipairs(Radar.roster or {}) do if (m.level or 0) > lead then lead = m.level end end
                local x0, x1 = p.raceX0, lead >= 10 and xOfLv(lead) or nil
                if x0 and x1 and x1 > x0 then
                    p.raceProgW = x1 - x0
                    p.raceProg:ClearAllPoints()
                    p.raceProg:SetPoint("LEFT", race, "TOPLEFT", x0, BADGE_Y)
                    p.raceProg:SetWidth(p.raceProgW)
                    p.raceProg:Show()
                    local tc = fxTier[math.max(1, math.min(6, top or 1))] or C.mint
                    -- Linie laeuft nach links dunkel aus (rechts volle Stufenfarbe)
                    if not K.Gradient(p.raceProg, "HORIZONTAL", { tc[1] * 0.15, tc[2] * 0.15, tc[3] * 0.15, 0.1 }, { tc[1], tc[2], tc[3], 0.9 }) then
                        p.raceProg:SetColorTexture(tc[1], tc[2], tc[3], 0.8)
                    end
                    p.raceTC = tc
                    if fresh and animOK() then
                        p.raceProg:SetWidth(1)
                        p.raceT0 = GetTime()
                    end
                else
                    p.raceProgW = nil
                    p.raceProg:Hide()
                end
                -- sanfter Schein hinter der Zielstufe (in ihrer Farbe, gedaempft)
                local tl = p.raceLines[target]
                if tl then
                    local tc = fxTier[target] or C.mint
                    p.raceTarget:ClearAllPoints()
                    p.raceTarget:SetPoint("CENTER", tl.badge, "CENTER", 0, 0)
                    p.raceTarget:SetVertexColor(tc[1] * 0.45, tc[2] * 0.45, tc[3] * 0.45)
                    p.raceTarget:SetAlpha(1)
                    p.raceTarget:Show()
                else
                    p.raceTarget:Hide()
                end
                -- eigener Avatar
                local _, myCls = UnitClass("player")
                if p.meMark:IsShown() then p.SetAv(p.meMark, myCls) end
            end

            -- Animation: gedrosselt, nur wenn die Karte sichtbar und offen ist
            local drv = CreateFrame("Frame", nil, race)
            drv.acc = 0
            drv:SetScript("OnUpdate", function(self, el)
                self.acc = self.acc + (el or 0)
                if self.acc < 0.033 then return end
                self.acc = 0
                if ns.ListBusy and ns.ListBusy() then return end
                if not animOK() or ns.db.settings.raceClosed or not race:IsVisible() then
                    p.raceShine:SetAlpha(0)
                    p.raceTip:SetAlpha(0)
                    for _, s in ipairs(p.raceSparks) do s.life = 0 s.t:SetAlpha(0) end
                    for _, s in ipairs(p.raceMotes) do s.life = 0 s.t:SetAlpha(0) end
                    if p.raceT0 then p.raceT0 = nil if p.raceProgW then p.raceProg:SetWidth(p.raceProgW) end end
                    return
                end
                local tm = GetTime()
                placeBlobs(tm)
                local full = p.raceProgW
                -- Einfahren beim Oeffnen (Ease-Out)
                local cur = full
                if p.raceT0 and full then
                    local q = math.min(1, (tm - p.raceT0) / 0.9)
                    local e = 1 - (1 - q) * (1 - q) * (1 - q)
                    cur = math.max(1, full * e)
                    p.raceProg:SetWidth(cur)
                    if q >= 1 then p.raceT0 = nil end
                end
                -- Lichtstrahl laeuft den erreichten Teil entlang (Pause zwischen den Laeufen)
                if full and full > 40 and not p.raceT0 then
                    local ph = (tm % 3.6) / 2.2
                    if ph <= 1 then
                        -- Komet: Kopf rechts am Laufpunkt, Schweif zieht nach links nach; Helligkeit ueber die Farbe
                        local e = 1 - (1 - ph) * (1 - ph)
                        local tc = p.raceTC or C.mint
                        local k = 0.75 * math.sin(ph * math.pi)
                        p.raceShine:ClearAllPoints()
                        p.raceShine:SetPoint("RIGHT", p.raceProg, "LEFT", e * full + 10, 0)
                        p.raceShine:SetVertexColor(math.min(1, tc[1] * k + 0.15 * k), math.min(1, tc[2] * k + 0.15 * k), math.min(1, tc[3] * k + 0.15 * k))
                        p.raceShine:SetAlpha(1)
                    else
                        p.raceShine:SetAlpha(0)
                    end
                else
                    p.raceShine:SetAlpha(0)
                end
                -- Spitze: Funkel-Flipbook (4x4) + kleine Funken, die nach oben wegstieben
                local tc = p.raceTC or C.mint
                local el = 0.033
                if full and p.raceProg:IsShown() then
                    local fr = math.floor(tm * 14) % 16
                    local u, v = (fr % 4) * 0.25, math.floor(fr / 4) * 0.25
                    p.raceTip:SetTexCoord(u, u + 0.25, v, v + 0.25)
                    p.raceTip:SetVertexColor(tc[1] * 0.6 + 0.15, tc[2] * 0.6 + 0.15, tc[3] * 0.6 + 0.15)
                    p.raceTip:SetAlpha(1)
                    for _, s in ipairs(p.raceSparks) do
                        if s.life <= 0 then
                            if math.random() < 0.06 then
                                s.life, s.max = 1, 0.5 + math.random() * 0.6
                                s.x, s.y = (cur or full), 0
                                s.vx, s.vy = -6 - math.random() * 14, 6 + math.random() * 16
                            else
                                s.t:SetAlpha(0)
                            end
                        else
                            s.life = s.life - el / s.max
                            s.x, s.y = s.x + s.vx * el, s.y + s.vy * el
                            s.t:ClearAllPoints()
                            s.t:SetPoint("CENTER", p.raceProg, "LEFT", s.x, s.y)
                            local k = math.max(0, s.life) * 0.8
                            s.t:SetVertexColor(tc[1] * k + 0.1 * k, tc[2] * k + 0.1 * k, tc[3] * k + 0.1 * k)
                            s.t:SetAlpha(1)
                        end
                    end
                else
                    p.raceTip:SetAlpha(0)
                end
                -- langsam aufsteigende Lichtteilchen im Hintergrund
                local W, H = race:GetWidth() or 750, race:GetHeight() or 128
                for _, s in ipairs(p.raceMotes) do
                    if s.life <= 0 then
                        if math.random() < 0.02 then
                            s.life, s.max = 1, 4 + math.random() * 4
                            s.x, s.y = math.random() * W, -H + 4
                            s.vx, s.vy = (math.random() - 0.5) * 4, 10 + math.random() * 8
                        end
                        s.t:SetAlpha(0)
                    else
                        s.life = s.life - el / s.max
                        s.x, s.y = s.x + s.vx * el, s.y + s.vy * el
                        s.t:ClearAllPoints()
                        s.t:SetPoint("CENTER", race, "TOPLEFT", s.x, s.y)
                        local k = math.sin(math.max(0, s.life) * math.pi) * 0.35
                        s.t:SetVertexColor(k, k * 0.95, k * 0.85)
                        s.t:SetAlpha(1)
                    end
                end
                -- Schein hinter der Zielstufe atmet langsam
                if p.raceTarget:IsShown() then p.raceTarget:SetAlpha(0.75 + 0.25 * math.sin(tm * 1.6)) end
                -- Zielstufe pulsiert sanft
                local ph = (tm % 2.2) / 2.2
                for _, line in ipairs(p.raceLines) do
                    local pr = line.badge.pulseRing
                    if pr:IsShown() then
                        pr:SetSize(36 + 14 * ph, 36 + 14 * ph)
                        pr:SetAlpha(0.45 * (1 - ph))
                    end
                end
            end)
        end
    end,
    refresh = function(p)
        -- 0.5.578: Abschnitte einzeln in /oa leistung (nur waehrend einer Messung)
        local PT = ns.prof and debugprofilestop()
        local function PM(lbl) if PT and ns.prof then local t = debugprofilestop() ns.prof.add(nil, "Mitglieder: " .. lbl, t - PT) PT = t end end
        -- 0.5.535: nur Filter gewechselt -> Liste neu, Kacheln/Gebiete/Klassen/Rollen bleiben (vorher ruckelte jeder Wechsel)
        local quick = p.onlyList
        p.onlyList = nil
        if p.seg and p.seg.value ~= filter then p.seg:Select(filter) end
        p.rowCache = {}
        if p.LayoutCols then p.LayoutCols(p.list:GetWidth()) end
        PM("Spalten")
        if p.seg and p.seg.isGlass and p.seg.buttons then
            -- Zahlen an den Reitern: alle / online / inaktiv
            local nAll, nOn, nIn = 0, 0, 0
            local lim = ns.db.settings.inactiveDays or 30
            for _, m in ipairs(Radar.roster or {}) do
                nAll = nAll + 1
                if m.online then nOn = nOn + 1 end
                if not m.online and m.offDays and m.offDays >= lim then nIn = nIn + 1 end
            end
            local cnt = { all = nAll, online = nOn, inactive = nIn }
            local changed = false
            for i, b in ipairs(p.seg.buttons) do
                local it = p.seg.items[i]
                local txt = L[it.key == "all" and "Alle" or it.key == "online" and "Online" or "Inaktiv"] .. "  |cff888888" .. (cnt[it.key] or 0) .. "|r"
                if b.label:GetText() ~= txt then b.label:SetText(txt) changed = true end
            end
            if changed and p.seg.Layout then p.seg:Layout() end
        end
        local list = buildList()
        PM("Liste filtern/sortieren")
        p.list:SetData(list)
        if p.WarmRows then p.WarmRows() end
        PM("Liste fuellen")
        for _, dd in ipairs(p.drops) do dd:Update() end
        local any = F.class or F.level or F.role or F.prof or F.near or search ~= ""
        p.reset:SetShown(any and true or false)
        p.count:SetText(any and (L["%d Treffer"]):format(#list) or "")
        for _, b in ipairs(p.heads) do
            local on = sortKey == b.key
            b.text:SetText(b.base .. (on and (sortDesc and " v" or " ^") or ""))
            local c = on and C.accent or C.dim
            b.text:SetTextColor(c[1], c[2], c[3])
        end
        if quick then return end
        local lvSum, lvN = 0, 0
        for _, m in ipairs(Radar.roster) do
            if m.online then lvSum, lvN = lvSum + m.level, lvN + 1 end
        end
        local fresh = p.fresh
        p.cards[1]:Set(Radar.online or 0, "/ " .. (Radar.total or 0), (Radar.total or 0) > 0 and (Radar.online or 0) / Radar.total or 0, fresh)
        p.statOnline = ("|cff66db9e%d|r|cff888888 / %d %s|r"):format(Radar.online or 0, Radar.total or 0, L["online"])
        p.cards[2]:Set(Radar.total or 0, nil, nil, fresh)
        p.cards[3]:Set(Radar.withAddon or 1, nil, (Radar.online or 0) > 0 and (Radar.withAddon or 1) / Radar.online or nil, fresh)
        -- Schnitt der Gegenstandsstufe aller, die sie per Oasis teilen
        local gSum, gN = 0, 0
        local mine = Radar.myProfile and Radar.myProfile()
        -- nur Level-60-Charaktere
        if mine and (tonumber(mine.ilvl) or 0) > 0 and (ns.safe(UnitLevel("player")) or 0) >= 60 then gSum, gN = gSum + mine.ilvl, gN + 1 end
        for _, m in ipairs(Radar.roster) do
            local pr = not ns.isMe(m.name) and (m.level or 0) >= 60 and (ns.db.members[m.name] or (m.aname and ns.db.members[m.aname]))
            local v = pr and tonumber(pr.ilvl)
            if v and v > 0 then gSum, gN = gSum + v, gN + 1 end
        end
        if gN > 0 then
            p.cards[4].label:SetText(K.Upper(L["Gear-Level 60er (Schnitt)"]))
            p.cards[4]:Set(("%.1f"):format(gSum / gN), "· " .. (L["%d Spieler"]):format(gN))
            p.gearTxt = ("%.1f"):format(gSum / gN)
            p.cards[4].tip = nil
        else
            -- noch keine 60er: wer passt gerade zum Questen (online, +-3 Level)?
            local near, tip = 0, { L["Questpartner"], "|cff888888" .. L["online und hoechstens 3 Level von dir entfernt"] .. "|r", " " }
            for _, m in ipairs(Radar.roster) do
                if nearMe(m) then
                    near = near + 1
                    if near <= 12 then tip[#tip + 1] = ns.colorName(m.name, m.class) .. "  |cff888888" .. (m.level or "?") .. "  ·  " .. (m.zone or "") .. "|r" end
                end
            end
            if near == 0 then tip[#tip + 1] = "|cff888888" .. L["gerade niemand"] .. "|r" end
            tip[#tip + 1] = " "
            tip[#tip + 1] = "|cff66db9e" .. (F.near and L["Klick: Filter aus"] or L["Klick: nur diese anzeigen"]) .. "|r"
            p.cards[4].label:SetText(K.Upper(L["Questpartner"]) .. (F.near and "  |cff66db9e" .. L["Filter an"] .. "|r" or ""))
            p.cards[4]:Set(near, "· " .. L["passen zu dir"])
            p.nearN = near
            p.cards[4].tip = tip
        end
        do
            local sep = "   |cff444444·|r   "
            local third
            if p.cards[4].tip then
                third = ("|cffe8b44a%d|r |cff888888%s|r"):format(p.nearN or 0, L["Questpartner"]) .. (F.near and " |cff66db9e(" .. L["Filter an"] .. ")|r" or "")
            else
                third = "|cff888888" .. L["Gear-Level 60er (Schnitt)"] .. "|r " .. (p.gearTxt or "")
            end
            p.zoneBar.stats.t:SetText((p.statOnline or "") .. sep .. ("%d |cff888888%s|r"):format(Radar.total or 0, L["Mitglieder"]) .. sep .. third)
            p.zoneBar.stats:SetWidth(p.zoneBar.stats.t:GetStringWidth() + 4)
        end
        PM("Kacheln")
        -- Zuletzt online: nur in der Online-Ansicht und wenn Platz ist
        do
            local rc = p.recent
            local listH = (p:GetHeight() or 600) - 296 - 40
            local show = false   -- ersetzt durch die Spalte "Zuletzt"
            local off = {}
            if show then
                for _, m in ipairs(Radar.roster) do if not m.online and m.offDays then off[#off + 1] = m end end
                table.sort(off, function(a, b) return a.offDays < b.offDays end)
                show = #off > 0
            end
            rc:SetShown(show)
            for _, c in ipairs(rc.chips) do c:Hide() end
            if show then
                local x = 10
                local maxW = (rc:GetWidth() or 700) - 10
                for i = 1, math.min(6, #off) do
                    local m = off[i]
                    local c = rc.chips[i]
                    if not c then
                        c = CreateFrame("Button", nil, rc)
                        c:SetHeight(20)
                        c.bg = K.Fill(c, { 1, 1, 1, 0.05 })
                        c.t = K.Text(c, 11, C.text)
                        c.t:SetPoint("CENTER")
                        c:SetScript("OnClick", function(self) if self.name and ns.Profile then ns.Profile.Show(self.name) end end)
                        c:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.12) if self.m then Radar.ShowMemberTip(self, self.m) end end)
                        c:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.05) GameTooltip:Hide() end)
                        rc.chips[i] = c
                    end
                    local h = m.offDays * 24
                    local ago = h < 1 and L["gerade eben"] or h < 24 and (L["vor %d Std"]):format(math.floor(h)) or (L["vor %d Tg"]):format(math.floor(m.offDays))
                    c.name, c.m = m.name, m
                    c.t:SetText(Radar.Colored(m.name) .. "  |cff777777" .. (m.level or "") .. "  ·  " .. ago .. "|r")
                    local w = c.t:GetStringWidth() + 18
                    if x + w > maxW then break end
                    c:SetWidth(w)
                    c:ClearAllPoints()
                    c:SetPoint("BOTTOMLEFT", rc, "BOTTOMLEFT", x, 7)
                    c:Show()
                    x = x + w + 6
                end
            end
            p.list:SetPoint("BOTTOMRIGHT", p.listInset and -4 or 0, show and 100 or (p.listInset and 44 or 40))
        end
        PM("Zuletzt online")
        -- Gebiete der Online-Mitglieder, meiste zuerst - 0.5.595 abgeschaltet
        if false then
            local zb = p.zoneBar
            local cnt, order = {}, {}
            for _, m in ipairs(Radar.roster) do
                if m.online and (m.zone or "") ~= "" then
                    if not cnt[m.zone] then cnt[m.zone] = 0 order[#order + 1] = m.zone end
                    cnt[m.zone] = cnt[m.zone] + 1
                end
            end
            table.sort(order, function(a, b) if cnt[a] ~= cnt[b] then return cnt[a] > cnt[b] end return a < b end)
            local myZone = ns.safe(GetRealZoneText()) or ""
            local x, maxW = zb.head:GetStringWidth() + 22, (zb:GetWidth() or 700) - 10
            for _, c in ipairs(zb.chips) do c:Hide() end
            for i, z in ipairs(order) do
                local c = zb.chips[i]
                if not c then
                    c = CreateFrame("Button", nil, zb)
                    c:SetHeight(hasGlass() and 22 or 20)
                    c.bg = K.Fill(c, { 1, 1, 1, 0.05 })
                    c.t = K.Text(c, 11, C.text)
                    c.t:SetPoint("CENTER")
                    chipLook(c)
                    c:SetScript("OnClick", function(self)
                        search = (search == self.zone) and "" or self.zone
                        if p.search then p.search:SetText(search) end
                        ns.RefreshPage("radar")
                    end)
                    c:SetScript("OnEnter", function(self) chipLook(self, true) K.ShowTip(self, { self.zone, L["Klick: Liste nach diesem Gebiet filtern"] }) end)
                    c:SetScript("OnLeave", function(self) chipLook(self) GameTooltip:Hide() end)
                    zb.chips[i] = c
                end
                c.zone, c.mine = z, (z == myZone)
                c.t:SetText((c.mine and "|cff66db9e" or "") .. z .. (c.mine and "|r" or "") .. "  |cffe8b44a" .. cnt[z] .. "|r")
                local w = c.t:GetStringWidth() + 18
                if x + w > maxW then break end
                c:SetWidth(w)
                chipLook(c)
                c:ClearAllPoints()
                c:SetPoint("LEFT", zb, "LEFT", x, 0)
                c:Show()
                x = x + w + 6
            end
        end
        if ns.Members then
            local comp = ns.Members.Composition()
            local barW = p.compBar:GetWidth()
            if not barW or barW <= 0 then barW = 200 end
            local x, tip = 0, { (L["%d online"]):format(comp.total) }
            for _, seg in ipairs(p.compSegs) do seg:Hide() end
            for i, cls in ipairs(comp.order) do
                local seg = p.compSegs[i]
                if not seg then
                    seg = p.compBar:CreateTexture(nil, "ARTWORK")
                    seg:SetHeight(8)
                    p.compSegs[i] = seg
                end
                local w = barW * comp.classes[cls] / math.max(1, comp.total)
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
                seg:SetColorTexture(cc and cc.r or 0.5, cc and cc.g or 0.5, cc and cc.b or 0.5, 1)
                seg:ClearAllPoints()
                seg:SetPoint("LEFT", p.compBar, "LEFT", x, 0)
                seg:SetWidth(math.max(1, w - 1))
                if fresh then
                    local sw, sx = math.max(1, w - 1), x
                    seg:SetWidth(1)
                    K.Tween(seg, 0.8, function(q)
                        seg:ClearAllPoints()
                        seg:SetPoint("LEFT", p.compBar, "LEFT", sx * q, 0)
                        seg:SetWidth(math.max(1, sw * q))
                    end, nil, 0.2)
                end
                seg:Show()
                x = x + w
                local cname = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]) or cls
                tip[#tip + 1] = ns.colorName(cname, cls) .. "  " .. comp.classes[cls]
            end
            p.compBar.lines = tip
            p.compCount:SetText(comp.total .. " |cff888888" .. L["online"] .. "|r")
            local R = comp.roles
            -- wer hat welche Rolle (fuer die Tooltips)
            local who = { tank = {}, heal = {}, dps = {} }
            if ns.Profile then
                for _, m in ipairs(Radar.roster) do
                    if m.online then
                        local r, known = ns.Profile.RolesOf(m.name)
                        if known then for k in pairs(who) do if r[k] then table.insert(who[k], Radar.Colored(m.name)) end end end
                    end
                end
            end
            for _, t in ipairs(p.roleTiles) do
                local n = R[t.key] or 0
                local missing = comp.total > 0 and n == 0 and t.key ~= "dps"
                t.missing = missing
                local tip = { K.Upper(L[t.key == "tank" and "Tank" or t.key == "heal" and "Heiler" or "Schaden"]) .. "  " .. n }
                for j, nm in ipairs(who[t.key]) do if j > 10 then break end tip[#tip + 1] = nm end
                if n == 0 then tip[#tip + 1] = "|cff888888" .. L["gerade niemand online"] .. "|r" end
                tip[#tip + 1] = " "
                tip[#tip + 1] = missing and ("|cff66db9e" .. L["Klick: Gruppensuche starten"] .. "|r")
                    or ("|cff66db9e" .. (F.role == t.key and L["Klick: Filter aus"] or L["Klick: Liste nach dieser Rolle filtern"]) .. "|r")
                t.tip = tip
                t.lbl:SetText(missing and ("|cffff5a4a" .. K.Upper(L["fehlt"]) .. "|r")
                    or (K.Upper(L[t.key == "tank" and "Tank" or t.key == "heal" and "Heiler" or "Schaden"]) .. (F.role == t.key and "  |cff66db9e" .. L["Filter"] .. "|r" or "")))
                if fresh then K.CountUp(t.num, n, 0.8) else t.num:SetText(n) end
                -- fehlender Tank/Heiler: Kachel rot umrandet; gefilterte Rolle in ihrer Farbe
                K.SetBorderColor(t, (F.role == t.key and t.color) or C.line)
                local tc = missing and C.red or t.color
                t.top:SetColorTexture(tc[1], tc[2], tc[3], missing and 1 or 0.9)
                t.top:SetHeight(missing and 3 or 2)
                local nc = missing and C.red or (n == 0 and C.dim or C.text)
                t.num:SetTextColor(nc[1], nc[2], nc[3])
                t.icon:SetAlpha(n == 0 and 0.45 or 1)
                -- fehlende Rolle: ganze Kachel rot getoent, Kreis rot
                local bgc = missing and { C.red[1] * 0.22, C.red[2] * 0.22, C.red[3] * 0.22, 1 } or C.raised
                t.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], 1)
                local dc = missing and C.red or t.color
                t.disc:SetVertexColor(dc[1], dc[2], dc[3], missing and 0.35 or 0.22)
                if missing then K.SetBorderColor(t, { C.red[1] * 0.8, C.red[2] * 0.8, C.red[3] * 0.8, 1 }) end
            end
            local miss = {}
            if comp.total > 0 then
                if R.tank == 0 then miss[#miss + 1] = L["Tank"] end
                if R.heal == 0 then miss[#miss + 1] = L["Heiler"] end
            end
            if #miss > 0 then
                p.compHint:SetText("|cffff5a4a" .. L["Es fehlt: "] .. table.concat(miss, ", ") .. "|r   |cff66db9e" .. L["Gruppe suchen"] .. " >|r")
                p.compMissing = true
                if R.unknown > 0 then p.compHint:SetText(p.compHint:GetText() .. "   |cff666666" .. (L["%d ohne Rolle"]):format(R.unknown) .. "|r") end
            elseif R.unknown > 0 then
                p.compMissing = nil
                p.compHint:SetText((L["%d ohne Rollenangabe"]):format(R.unknown))
            else
                p.compMissing = nil
                p.compHint:SetText("")
            end
        end
        PM("Gebiete/Klassen/Rollen")
        -- Rennen separat zeichnen: Tabellen-/Gebietsaufbau und Avatare teilen sich kein Script-Zeitbudget.
        p.raceRefresh = (p.raceRefresh or 0) + 1
        local raceRefresh = p.raceRefresh
        ns.After(0, function()
        if not p:IsVisible() or p.raceRefresh ~= raceRefresh then return end
        PT = ns.prof and debugprofilestop()
        -- Level-Rennen: erreichte Stufen gruen, Plaetze 1-3 fest untereinander, offene zeigen, wer am naechsten dran ist
        local MEDAL = { "ffd24a", "c9d1ff", "d98a4a" }
        -- jede Stufe eigene Farbe: Bronze, Silber, Gold, Smaragd, Saphir, Legendaer
        local TIER = { { 0.85, 0.53, 0.27 }, { 0.80, 0.83, 0.90 }, { 1.00, 0.80, 0.25 }, { 0.30, 0.88, 0.50 }, { 0.35, 0.58, 1.00 }, { 1.00, 0.45, 0.10 } }
        local races = Radar.Race()
        PM("Rennen berechnen")
        -- 0.5.626: nur neu zeichnen, wenn sich etwas geaendert hat (vorher bei jedem Seiten-Refresh ~0,4 s)
        do
            local parts = { tostring(p.raceColW or 0), ns.db.settings.raceClosed and "c" or "o", ns.db.settings.noAnim and "n" or "a", tostring(ns.safe(UnitLevel("player")) or 0) }
            for _, r in ipairs(races) do
                parts[#parts + 1] = r.lvl .. ":" .. #r.list
                for j = 1, math.min(3, #r.list) do parts[#parts + 1] = r.list[j].name .. "@" .. (r.list[j].ts or 0) end
            end
            for _, m in ipairs(Radar.roster or {}) do
                local lv = m.level or 0
                if lv >= 10 then parts[#parts + 1] = (m.name or "") .. lv .. (m.online and "+" or "-") end
            end
            local sig = table.concat(parts, "|")
            if sig == p.raceSig and not p.fresh then
                PM("Level-Rennen (unveraendert)")
                return
            end
            p.raceSig = sig
        end
        local top = 0
        for i, r in ipairs(races) do if #r.list > 0 then top = i end end
        if p.beam then
            -- Energie fliesst durch den schon erreichten Teil (10 bis zur hoechsten erreichten Stufe)
            local first = p.raceLines[1]
            local reach = p.raceLines[top]
            if top >= 2 and first and reach and not (ns.db and ns.db.settings.noAnim) then
                p.beam.core:SetColorTexture(1, 1, 1, 0.5)
                p.beam.tiers, p.beam.top = TIER, top
                p.beam.from, p.beam.to = first.badge, reach.badge
                p.beam:Show()
            else
                p.beam:Hide()
            end
        end
        for i, r in ipairs(races) do
            local line = p.raceLines[i]
            local b = line.badge
            local done = #r.list > 0
            b.lvl:SetText(r.lvl)
            local tc = TIER[i] or C.mint
            if done then
                b.ring:SetVertexColor(tc[1], tc[2], tc[3], 1)
                b.bg:SetVertexColor(tc[1] * 0.38, tc[2] * 0.38, tc[3] * 0.38, 1)
                b.lvl:SetTextColor(1, 1, 1)
                b.glow:SetVertexColor(tc[1], tc[2], tc[3])
                b.glow:SetAlpha(0.3)
                b.glow:SetShown(not b.calm)
                b.pulse = (i == top) and not b.calm
                if b.calm then b.bg:SetVertexColor(tc[1] * 0.22, tc[2] * 0.22, tc[3] * 0.22, 1) end
            else
                b.ring:SetVertexColor(tc[1] * 0.4, tc[2] * 0.4, tc[3] * 0.4, 1)
                b.bg:SetVertexColor(C.side[1], C.side[2], C.side[3], 1)
                b.lvl:SetTextColor(tc[1] * 0.55, tc[2] * 0.55, tc[3] * 0.55)
                b.glow:Hide()
                b.pulse = nil
            end
            -- 0.5.572: Stufen-Abzeichen statt Kreis (erreicht farbig, offen grau und blass)
            local art = ns.LevelBadges and ns.LevelBadges.Exact(r.lvl, true)
            if art then
                if not b.art then
                    b.art = b:CreateTexture(nil, "ARTWORK", nil, 3)
                    b.art:SetSize(43, 43)
                    b.art:SetPoint("CENTER", 0, 0)
                end
                b.art:SetTexture(art)
                b.art:SetDesaturated(not done)
                b.art:SetAlpha(done and 1 or 0.35)
                b.art:Show()
                b.bg:Hide() b.ring:Hide() b.shine:Hide()
                if b.lvl.Hide then b.lvl:Hide() end
                b.glow:SetSize(70, 70)
            end
            -- Linie zur naechsten Stufe: Farbverlauf zwischen den Stufenfarben, wenn beide erreicht
            if line.seg then
                local nextDone = races[i + 1] and #races[i + 1].list > 0
                local nc = TIER[i + 1] or tc
                if done and nextDone and b.calm then
                    line.seg:SetColorTexture(tc[1], tc[2], tc[3], 0.7)
                elseif done and nextDone then
                    line.seg:SetColorTexture(1, 1, 1, 1)
                    if not K.Gradient(line.seg, "HORIZONTAL", { tc[1], tc[2], tc[3], 1 }, { nc[1], nc[2], nc[3], 1 }) then
                        line.seg:SetColorTexture(tc[1], tc[2], tc[3], 1)
                    end
                else
                    line.seg:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
                    if b.calm then line.seg:SetColorTexture(1, 1, 1, 0.10) end
                    if line.seg.SetGradient and CreateColor then pcall(line.seg.SetGradient, line.seg, "HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 1)) end
                end
            end
            -- Anzeige: erreicht -> Erster (Vorname) + Datum; die erste offene Stufe -> wer ist am naechsten dran
            local s1, s2, s3 = line.slots[1].name, line.slots[2].name, line.slots[3].name
            local tip = { (L["Level %d"]):format(r.lvl) }
            if done then
                -- Siegertreppchen: nur wer eine bekannte Zeit hat, bekommt einen Platz (Gold, Silber, Bronze)
                local known = {}
                for _, x in ipairs(r.list) do if x.ts > 0 then known[#known + 1] = x end end
                local slots3 = { s1, s2, s3 }
                for j = 1, 3 do slots3[j]:SetText("") end
                if #known == 0 then
                    -- wer zuerst da war, ist unbekannt -> nur zaehlen
                    s1:SetText("|cff66db9e" .. (L["%d Spieler"]):format(#r.list) .. "|r")
                    s2:SetText("|cff666666" .. L["erreicht"] .. "|r")
                else
                    local n = math.min(3, #known)
                    for j = 1, n do
                        local x = known[j]
                        slots3[j]:SetText("|cff" .. MEDAL[j] .. j .. ".|r " .. ns.colorName(x.name, Radar.ClassOf(x.name)))
                    end
                    local rest = #r.list - n
                    if rest > 0 and n < 3 then slots3[n + 1]:SetText("|cff666666+" .. rest .. " " .. L["weitere"] .. "|r")
                    elseif rest > 0 then slots3[3]:SetText(slots3[3]:GetText() .. "  |cff666666+" .. rest .. "|r") end
                end
                for j, x in ipairs(r.list) do
                    if j > 10 then tip[#tip + 1] = "|cff777777" .. (L["+ %d weitere"]):format(#r.list - 10) .. "|r" break end
                    -- Reihenfolge nur, wenn die Zeit bekannt ist; sonst einfach auflisten
                    tip[#tip + 1] = (x.ts > 0 and (j .. ".  ") or "·  ") .. Radar.Colored(x.name) .. (x.ts > 0 and ("  |cff888888" .. date(L["%d.%m. %H:%M"], x.ts) .. "|r") or "")
                end
            else
                s1:SetText("|cff555555" .. L["offen"] .. "|r")
                s2:SetText("")
                s3:SetText("")
                local firstOpen = not (races[i - 1] and #races[i - 1].list == 0)
                local best
                for _, m in ipairs(Radar.roster) do
                    if (m.level or 0) < r.lvl and (not best or m.level > best.level) then best = m end
                end
                if best then
                    if firstOpen then
                    -- erste offene Stufe: wer als Naechstes ankommt
                    s1:SetText(ns.colorName(firstOf(best.name), best.class))
                    s2:SetText("|cff777777" .. (L["Level %d"]):format(best.level) .. "|r")
                end
                    tip[#tip + 1] = (L["Am naechsten dran: %s (Level %d)"]):format(Radar.Colored(best.name), best.level)
                else
                    tip[#tip + 1] = L["noch offen"]
                end
            end
            b.tip = tip
            if fresh then K.FadeIn(b, 0.2 + i * 0.07) end
        end
        -- Spitzenreiter und du auf der Strecke (zwischen den Stufen anteilig)
        if p.raceX0 then
            -- Position auf der Strecke; nie auf einer Plakette (Abstand zu beiden Seiten), damit keine Zahl verdeckt wird
            -- Strecke zwischen zwei Plaketten = von Rand zu Rand (Plakette 34 breit), Punkte 8 px Abstand zum Rand
            local function segStart(seg) return p.raceX0 + seg * p.raceColW + 17 end
            local function xOf(lv)
                local t = math.max(0, math.min(5, ((lv or 1) - 10) / 10))
                local seg = math.min(4, math.floor(t))
                local frac = t - seg
                local len = p.raceColW - 34
                return segStart(seg) + 8 + frac * math.max(0, len - 16), seg
            end
            local lead
            for _, m in ipairs(Radar.roster) do if not lead or (m.level or 0) > (lead.level or 0) then lead = m end end
            local myLv = ns.safe(UnitLevel("player")) or 1
            local badgeY = -63   -- Mitte der Plaketten (oben -46, 34 hoch)
            if lead and (lead.level or 0) >= 10 then
                -- nur das angefangene Teilstueck fuellen; ganze Strecken faerben schon die Segmente
                local lx, lseg = xOf(lead.level)
                p.raceFill:ClearAllPoints()
                p.raceFill:SetPoint("LEFT", p.race, "TOPLEFT", segStart(lseg), badgeY)
                p.raceFill:SetWidth(math.max(1, lx - segStart(lseg)))
                p.raceFill:SetShown(lead.level % 10 ~= 0 and lead.level < 60)
                p.leadMark:ClearAllPoints()
                p.leadMark:SetPoint("CENTER", p.race, "TOPLEFT", lx, badgeY)
                p.leadMark.lbl:SetText("")
                local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[lead.class or ""]
                p.leadMark.dot:SetVertexColor(cc and cc.r or C.mint[1], cc and cc.g or C.mint[2], cc and cc.b or C.mint[3])
                if p.SetAv then p.SetAv(p.leadMark, lead.class) end
                p.leadMark.tip = { L["Spitzenreiter"], Radar.Colored(lead.name) .. "  |cff888888" .. (L["Level %d"]):format(lead.level) .. "|r" }
                p.leadMark:SetShown(not ns.isMe(lead.name) and lead.level % 10 ~= 0)
            else
                p.raceFill:Hide()
                p.leadMark:Hide()
            end
            -- Online-Mitglieder AUF der Linie, Offline-Mitglieder ausgegraut darueber/darunter.
            -- Nahe beieinander -> EIN Knoten mit Anzahl (sonst Knaeuel bei vielen auf aehnlicher Stufe).
            for _, m in ipairs(p.onMarks) do m:Hide() end
            local function cluster(online)
                local list = {}
                for _, m in ipairs(Radar.roster) do
                    local lv = m.level or 0
                    if (m.online and true or false) == online and not ns.isMe(m.name) and lv >= 10 and lv < 60 and lv % 10 ~= 0 and m ~= lead then
                        list[#list + 1] = { m = m, x = xOf(lv), lv = lv }
                    end
                end
                table.sort(list, function(a, b) return a.x < b.x end)
                local groups, cur = {}, nil
                for _, o in ipairs(list) do
                    if cur and o.x - cur.x0 < 20 then cur.list[#cur.list + 1] = o
                    else cur = { x0 = o.x, list = { o } } groups[#groups + 1] = cur end
                end
                return groups
            end
            local mi = 0
            -- jeder einzeln, klein und genau an seinem Level; gleiches Level -> senkrecht gestapelt
            -- (online: auf der Linie, abwechselnd knapp darueber/darunter; offline: weiter aussen, ausgegraut)
            local SZ = 11
            local function draw(groups, online)
                local col = {}
                for _, g in ipairs(groups) do
                    for _, o in ipairs(g.list) do
                        mi = mi + 1
                        local markerIndex = mi
                        -- Pro Timer nur einen Marker aufbauen; alte Refresh-Auftraege verwerfen.
                        ns.After(markerIndex * 0.02, function()
                        if not p:IsVisible() or p.raceRefresh ~= raceRefresh then return end
                        local mk = p.OnMark(markerIndex)
                        mk:SetSize(SZ, SZ)
                        local key = math.floor(o.x + 0.5)
                        local k = col[key] or 0
                        col[key] = k + 1
                        local dy
                        if online then
                            dy = (k == 0) and 0 or (((k % 2 == 1) and 1 or -1) * math.ceil(k / 2) * (SZ - 2))
                        else
                            local side = (k % 2 == 0) and 1 or -1
                            dy = side * (15 + math.floor(k / 2) * (SZ - 2))
                        end
                        mk:ClearAllPoints()
                        mk:SetPoint("CENTER", p.race, "TOPLEFT", o.x, badgeY + dy)
                        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[o.m.class or ""]
                        mk.dot:SetVertexColor(cc and cc.r or 0.7, cc and cc.g or 0.7, cc and cc.b or 0.7)
                        if p.SetAv then p.SetAv(mk, o.m.class) end
                        if mk.av then mk.av:SetDesaturated(not online) end
                        mk:SetAlpha(online and 1 or 0.4)
                        mk:SetFrameLevel(p.race:GetFrameLevel() + (online and 7 or 5))
                        if mk.cnt then mk.cnt:Hide() mk.cntBg:Hide() end
                        mk.tip = { Radar.Colored(o.m.name) .. (online and "" or ("  |cff777777" .. L["offline"] .. "|r")),
                            (L["Level %d"]):format(o.lv) .. "  |cff888888· " .. (L["noch %d bis Level %d"]):format(10 - o.lv % 10, o.lv - o.lv % 10 + 10) .. "|r" }
                        mk:Show()
                        end)
                    end
                end
            end
            draw(cluster(true), true)
            draw(cluster(false), false)
            if myLv >= 10 and myLv < 60 then
                p.meMark:ClearAllPoints()
                p.meMark:SetPoint("CENTER", p.race, "TOPLEFT", xOf(myLv), badgeY)
                p.meMark.lbl:SetText(myLv % 10 ~= 0 and L["Du"] or "")
                p.meMark.tip = { L["Du"], (L["Level %d"]):format(myLv) .. "  |cff888888· " .. (L["noch %d bis Level %d"]):format(10 - myLv % 10, myLv - myLv % 10 + 10) .. "|r" }
                p.meMark:SetShown(myLv % 10 ~= 0)
            else
                p.meMark:Hide()
            end
        end
        PM("Level-Rennen")
        if p.RaceFX then
            ns.After(0, function()
                if p:IsVisible() and p.raceRefresh == raceRefresh then p.RaceFX(races, top, fresh) end
            end)
        end
        PM("Level-Rennen-Effekte")
        p.fresh = false
        end)
    end,
})

------------------------------------------------------------------------
-- Start und Takt
------------------------------------------------------------------------
ns.Listen("LOGIN", function()
    ns.After(3, function()
        Radar.RequestRoster()
        Radar.SendHello()
        Comm.Guild("HELLOREQ")
    end)
    ns.Every(300, function() Radar.SendHello() end)
    ns.Every(20, function() Radar.RequestRoster() end)   -- 0.5.788: 20 s statt 45 s (WoW erlaubt alle 10 s) - Online-Wechsel schneller bemerken
end)
ns.On("SKILL_LINES_CHANGED", function() ns.After(2, function() Radar.SendHello() end) end)
ns.On("ZONE_CHANGED_NEW_AREA", function() ns.After(3, function() Radar.SendHello() end) end)
ns.On("PLAYER_GUILD_UPDATE", function() ns.After(2, Radar.RequestRoster) end)
-- 0.6.376: frisch einer Gilde beigetreten -> sofort mit Oasis melden und den Gildenstand holen (sonst erst
-- beim naechsten Login bzw. nach bis zu 5 Min sichtbar)
do
    local wasIn
    ns.Listen("LOGIN", function() wasIn = IsInGuild() end)
    ns.On("PLAYER_GUILD_UPDATE", function()
        local now = IsInGuild()
        if wasIn == false and now then
            ns.After(4, function()
                Radar.RequestRoster()
                Radar.SendHello()
                Comm.Guild("HELLOREQ")
                if Comm.RequestSync then Comm.RequestSync(true) end
            end)
        end
        wasIn = now
    end)
    -- 0.6.402: Sicherheitsnetz - alle 5 Min Online-Mitglieder ohne jede Oasis-Meldung einmal pro Sitzung leise
    -- fragen (erkennt auch, wer Oasis erst waehrend des Spielens einschaltet); hoechstens 5 je Runde, versetzt
    local askedNet = {}
    ns.Listen("LOGIN", function()
        ns.Every(300, function()
            if not IsInGuild() or ns.inCombat() then return end
            local n = 0
            for _, m in ipairs(Radar.roster or {}) do
                if n >= 5 then break end
                if m.online and m.name and not ns.isMe(m.name) and not askedNet[m.name] then
                    local pr = rawget(ns.db.members, m.name)
                    if not pr or not pr.seen then
                        askedNet[m.name] = true
                        n = n + 1
                        local who = m.name
                        ns.After(n * 2, function() Comm.Whisper(who, "HELLOREQ") end)
                    end
                end
            end
        end)
    end)
    -- jemand ist der Gilde beigetreten: gezielt fragen, ob er Oasis hat (Antwort = sein Profil)
    local JOIN = ERR_GUILD_JOIN_S and ERR_GUILD_JOIN_S:gsub("%%s", "(.+)"):gsub("%.", "%%.")
    ns.On("CHAT_MSG_SYSTEM", function(msg)
        msg = ns.safe(msg)
        if not (JOIN and type(msg) == "string") then return end
        local who = msg:match("^" .. JOIN .. "$")
        if not who or ns.isMe(who) then return end
        -- erst die Gildenliste holen, damit seine Antwort als "aus der Gilde" erkannt wird
        Radar.RequestRoster()
        ns.After(3, Radar.RequestRoster)
        ns.After(8, function()
            local full = ns.fullName and ns.fullName(who) or who
            Comm.Whisper(full, "HELLOREQ")
        end)
    end)
end
ns.Listen("MAIN_SHOWN", function() Radar.RequestRoster() end)

-- Filter von aussen setzen (z.B. Uebersicht -> "Inaktiv")
function Radar.SetFilter(k)
    filter = k
    ns.RefreshPage("radar", true)
end
function Radar.SetFilterOnly(k) filter = k end

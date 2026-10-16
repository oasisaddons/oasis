-- Oasis: Dashboard (Startseite) - Helden-Banner mit Ladebildschirm, Kacheln, Wer ist online,
-- Was gerade passiert, Als Naechstes; dazu Blizzard-Gildendaten (MOTD, Info, News als Chronik, Kalender)
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local Info = {}
ns.GuildInfo = Info

------------------------------------------------------------------------
-- Blizzard-Daten
------------------------------------------------------------------------
local cachedMOTD, cachedInfoText = "", ""
function Info.MOTD()
    -- Forever sperrt diese Gildenabfragen im Kampf, auch innerhalb von pcall.
    if ns.inCombat() then return cachedMOTD end
    local m = C_GuildInfo and C_GuildInfo.GetMOTD and C_GuildInfo.GetMOTD() or (GetGuildRosterMOTD and GetGuildRosterMOTD())
    cachedMOTD = ns.safe(m) or ""
    return cachedMOTD
end
-- Gildennachricht im Spiel bearbeiten (nur mit Recht CanEditMOTD)
-- NIE "StaticPopupDialogs = ..." zuweisen: das verseucht Blizzards Dialogliste -> Esc/Ausloggen blockiert (0.5.478)
StaticPopupDialogs["OASIS_EDIT_MOTD"] = {
    text = "%s", button1 = OKAY or "OK", button2 = CANCEL or "Abbrechen", hasEditBox = true, maxLetters = 128,
    OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText(Info.MOTD()) eb:HighlightText() end end,
    OnAccept = function(self)
        local eb = self.editBox or self.EditBox
        local t = eb and eb:GetText() or ""
        if C_GuildInfo and C_GuildInfo.SetMOTD then pcall(C_GuildInfo.SetMOTD, t) elseif GuildSetMOTD then pcall(GuildSetMOTD, t) end
    end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
function Info.EditMOTD()
    if not (CanEditMOTD and ns.safe(CanEditMOTD())) then return end
    StaticPopup_Show("OASIS_EDIT_MOTD", L["Gildennachricht bearbeiten"])
end
function Info.Text()
    if ns.inCombat() then return cachedInfoText end
    local t = C_GuildInfo and C_GuildInfo.GetInfoText and C_GuildInfo.GetInfoText() or (GetGuildInfoText and GetGuildInfoText())
    cachedInfoText = ns.safe(t) or ""
    return cachedInfoText
end
ns.On("PLAYER_REGEN_ENABLED", function()
    Info.MOTD()
    Info.Text()
    ns.RefreshPage("home")
end)
function Info.Reputation()
    if not (C_Reputation and C_Reputation.GetGuildFactionData) then return nil end
    local ok, d = pcall(C_Reputation.GetGuildFactionData)
    if not ok or type(d) ~= "table" or not d.name then return nil end
    return d
end

-- Blizzard-News: Typen laut Blizzard-Konstanten (mit Rueckfall auf die bekannten Zahlen)
local NT = {
    looted = NEWS_ITEM_LOOTED or 0, crafted = NEWS_ITEM_CRAFTED or 1, purchased = NEWS_ITEM_PURCHASED or 2,
    guildAch = NEWS_GUILD_ACHIEVEMENT or 4, playerAch = NEWS_PLAYER_ACHIEVEMENT or 5,
    encounter = NEWS_DUNGEON_ENCOUNTER or 6, legendary = NEWS_LEGENDARY_LOOTED or 9,
}
local NEWS_TEXT = {
    [NT.looted] = "hat erbeutet:", [NT.legendary] = "hat erbeutet:", [NT.crafted] = "hat hergestellt:",
    [NT.purchased] = "hat gekauft:", [NT.guildAch] = "Gildenerfolg errungen:", [NT.playerAch] = "hat den Erfolg errungen:",
    [NT.encounter] = "hat besiegt:",
}
function Info.News()
    local out = {}
    if not (GetNumGuildNews and C_GuildInfo and C_GuildInfo.GetGuildNewsInfo) then return out end
    for i = 1, (GetNumGuildNews() or 0) do
        local ok, n = pcall(C_GuildInfo.GetGuildNewsInfo, i)
        if ok and type(n) == "table" and not n.isHeader and NEWS_TEXT[n.newsType] then
            local y = n.year or 0
            if y < 1000 then y = 2000 + y end
            local ts = time({ year = y, month = (n.month or 0) + 1, day = (n.day or 0) + 1, hour = 12 })
            out[#out + 1] = { type = n.newsType, who = ns.safe(n.whoText) or "?", what = ns.safe(n.whatText) or "", ts = ts, data = n.newsDataID }
        end
    end
    return out
end

-- News lokal in die Chronik uebernehmen (alle sehen dieselben News, daher kein Versand)
local function importNews()
    for _, n in ipairs(Info.News()) do
        local id = ("news-%d-%s-%s-%s"):format(n.type, date("%y%m%d", n.ts), n.who, tostring(n.data or n.what:match("item:(%d+)") or n.what:sub(1, 20)))
        if not Store.Get("chronicle", id) then
            local who = n.type == NT.guildAch and (GetGuildInfo("player") or "Oasis") or ns.fullName(n.who)
            Store.merge("chronicle", { id = id, kind = "news", who = who, tk = NEWS_TEXT[n.type], item = n.what, ts = n.ts, u = n.ts, by = "blizzard" })
        end
    end
end
ns.On("GUILD_NEWS_UPDATE", function() ns.After(1, importNews) ns.RefreshPage("home") end)
ns.On("GUILD_MOTD", function() ns.RefreshPage("home") end)
-- Gildenliste kommt nach Login/Reload erst verzoegert -> "Wer ist online" danach neu zeichnen (0.5.536)
ns.Listen("ROSTER", function() ns.Debounce("homeRoster", 1, function() ns.RefreshPage("home") end) end)

------------------------------------------------------------------------
-- Kalender (Blizzard-Gildentermine)
------------------------------------------------------------------------
function Info.CalendarEvents()
    local out = {}
    if not (C_Calendar and C_Calendar.GetNumGuildEvents) then return out end
    for i = 1, (C_Calendar.GetNumGuildEvents() or 0) do
        local ok, e = pcall(C_Calendar.GetGuildEventInfo, i)
        if ok and type(e) == "table" and e.title then
            local ts = time({ year = e.year, month = e.month, day = e.monthDay, hour = e.hour or 0, min = e.minute or 0 })
            out[#out + 1] = { id = "cal-" .. (e.eventID or i), title = e.title, ts = ts, cal = true }
        end
    end
    return out
end
ns.On("CALENDAR_UPDATE_GUILD_EVENTS", function() ns.RefreshPage("home") ns.RefreshPage("raid") end)

------------------------------------------------------------------------
-- Inaktive Mitglieder
------------------------------------------------------------------------
function Info.Inactive(days)
    days = days or ns.db.settings.inactiveDays or 30
    local out = {}
    for _, m in ipairs(ns.Radar.roster) do
        if not m.online and (m.offDays or 0) >= days then out[#out + 1] = m end
    end
    table.sort(out, function(a, b) return (a.offDays or 0) > (b.offDays or 0) end)
    return out
end

------------------------------------------------------------------------
-- Daten fuer das Dashboard
------------------------------------------------------------------------
local KIND_COLOR = {
    level = C.blue, loot = C.pink, legacy = C.violet, boss = C.amber, guild = C.mint,
    duel = C.red, badge = C.accent, news = { 0.55, 0.68, 0.85 },
}
local KIND_ICON = {
    level = "badges", loot = "wants", legacy = "legacy", boss = "raid", guild = "radar",
    duel = "deathroll", badge = "badges", news = "chronicle",
}

-- Vorschlaege "Fuer dich"
local function suggestions()
    local out = {}
    local lvl = ns.safe(UnitLevel("player")) or 0
    if ns.Crafting and (ns.Crafting.badge or 0) > 0 then
        out[#out + 1] = { icon = ns.ICONS.crafting, page = "crafting",
            text = (L["%d Handwerks-Auftraege warten auf dich"]):format(ns.Crafting.badge) }
    end
    if ns.Polls then
        local n = 0
        for _, p in ipairs(ns.Polls.All()) do if ns.Polls.IsOpen(p) and not next(ns.Polls.MyPick(p)) then n = n + 1 end end
        if n > 0 then out[#out + 1] = { icon = ns.ICONS.polls, page = "polls", text = (L["%d Umfragen warten auf deine Stimme"]):format(n) } end
    end
    if ns.Dungeons then
        for _, d in ipairs(ns.Dungeons and ns.Dungeons.List() or {}) do
            if not d.closed and d.lo and lvl >= d.lo - 1 and lvl <= (d.hi or d.lo) then
                out[#out + 1] = { icon = ns.ICONS.dungeons, text = (L["Passender Dungeon: %s (%s)"]):format(d.name, d.level),
                    fn = function() ns.Dungeons.ShowDungeon(d.key) end }
                break
            end
        end
    end
    if ns.Social then
        local p = ns.Social.Partners()
        local on = 0
        for _, e in ipairs(p) do if #e.online > 0 then on = on + 1 end end
        if on > 0 then out[#out + 1] = { icon = ns.ICONS.social, page = "social", text = (L["%d deiner Quests hat gerade auch jemand aus der Gilde"]):format(on) } end
    end
    if ns.Wants then
        local n = 0
        for _, w in ipairs(ns.Store.List("wants")) do if not ns.isMe(w.who) and ns.Wants.Count(w.itemID) > 0 then n = n + 1 end end
        if n > 0 then out[#out + 1] = { icon = ns.ICONS.wants, page = "wants", text = (L["Du hast %d Items, die jemand sucht"]):format(n) } end
    end
    if ns.Badges then
        local mine, s = ns.Badges.Mine(true)
        local best, bestR
        for _, b in ipairs(ns.Badges.LIST) do
            local tier = mine[b.id] or 0
            local need = b.tiers[tier + 1]
            if need then
                local v = s[b.stat] or 0
                local r = v / need
                if r >= 0.5 and (not bestR or r > bestR) then best, bestR = { b = b, tier = tier + 1, v = v, need = need }, r end
            end
        end
        if best then
            out[#out + 1] = { icon = ns.ICONS.badges, page = "badges",
                text = (L["Fast geschafft: %s (%d/%d)"]):format(ns.Badges.Label(best.b.id, best.tier), best.v, best.need) }
        end
    end
    if ns.isOfficer() then
        local ina = #Info.Inactive()
        if ina > 0 then out[#out + 1] = { icon = ns.ICONS.radar, fn = function() ns.ShowPage("radar") ns.Radar.SetFilter("inactive") end,
            text = (L["%d Mitglieder seit %d+ Tagen inaktiv"]):format(ina, ns.db.settings.inactiveDays or 30) } end
    end
    return out
end

-- "Als Naechstes": Events (mit Zusagen), Double XP, Geburtstage, offene Gruppensuchen
local function signupInfo(ev)
    if not (ns.Raid and ev.id and not ev.cal) then return "" end
    local n, t, h = 0, 0, 0
    for _, sg in ipairs(ns.Raid.Signups(ev.id)) do
        if sg.status == "yes" then
            n = n + 1
            if sg.role == "tank" then t = t + 1 elseif sg.role == "heal" then h = h + 1 end
        end
    end
    local maxs = (ev.max or 0) > 0 and ("|cff777777/" .. ev.max .. "|r") or ""
    return "  |cff888888·|r  " .. n .. maxs .. "  |cff6199ff" .. t .. "T|r |cff66db9e" .. h .. "H|r"
end
local function eventList()
    local list = {}
    if ns.Raid then
        for _, e in ipairs(ns.Raid.Events()) do list[#list + 1] = e end
        if ns.Raid.CalendarOnly then for _, e in ipairs(ns.Raid.CalendarOnly()) do list[#list + 1] = e end end
    end
    table.sort(list, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return list
end
local function upcoming()
    local out = {}
    local list = eventList()
    for i = 1, math.min(3, #list) do
        local e = list[i]
        local k = ns.Raid.KIND and ns.Raid.KIND[e.kind or ((e.max or 5) > 5 and "raid" or "dungeon")]
        out[#out + 1] = { ts = e.ts, icon = ns.ICONS.raid, page = "raid", ev = (not e.cal) and e or nil, color = k and k.color or C.amber,
            text = (e.title or "?") .. signupInfo(e) }
    end
    local RW = ns.Rewards
    local until2 = RW and RW.DoubleUntil and RW.DoubleUntil()
    local ps = RW and RW.DoublePlanned and RW.DoublePlanned()
    if until2 then
        out[#out + 1] = { icon = ns.ICONS.rank, color = C.amber, page = "rank",
            text = "|cffffd24a" .. L["Double XP laeuft"] .. "|r  |cff888888· " .. (L["noch %d h"]):format(math.ceil((until2 - ns.now()) / 3600)) .. "|r" }
    elseif ps then
        out[#out + 1] = { ts = ps, icon = ns.ICONS.rank, color = C.amber, page = "rank", text = "|cffffd24a" .. L["Double XP"] .. "|r  |cff888888" .. L["geplant"] .. "|r" }
    end
    if ns.Members and ns.Members.Birthday and ns.Radar then
        for d = 0, 7 do
            local day = date("%d.%m", ns.now() + d * 86400)
            for _, m in ipairs(ns.Radar.roster) do
                if ns.Members.Birthday(m.name) == day then
                    out[#out + 1] = { icon = ns.ICONS.social, color = C.pink, page = "radar",
                        text = (d == 0 and ("|cffff78b4" .. L["Heute Geburtstag:"] .. "|r ") or ("|cff888888" .. ns.weekday(ns.now() + d * 86400, true) .. " " .. day .. "|r  " .. L["Geburtstag:"] .. " ")) .. ns.Radar.Colored(m.name) }
                end
            end
        end
    end
    if ns.Groups then
        for i, g in ipairs(ns.Groups.Active()) do
            if i > 3 then break end
            local free = ns.Groups.FreeRoles and ns.Groups.FreeRoles(g) or {}
            local fr = {}
            if free.tank then fr[#fr + 1] = "|cff6199ffT|r" end
            if free.heal then fr[#fr + 1] = "|cff66db9eH|r" end
            if free.dps then fr[#fr + 1] = "|cffff7a5aD|r" end
            out[#out + 1] = { icon = ns.ICONS.groups, color = C.mint, page = "groups", lfg = g,
                text = ns.Radar.Colored(g.who) .. " " .. L["sucht:"] .. " " .. (g.title or "?") .. (#fr > 0 and ("  |cff888888" .. L["frei:"] .. "|r " .. table.concat(fr, " ")) or "") }
        end
    end
    return out
end

-- Restzeit kurz: "2T 4h" / "3h 05m" / "12m" / "jetzt"
local function countdown(sec)
    sec = math.floor(sec or 0)
    if sec <= 0 then return L["jetzt"] end
    local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
    if d > 0 then return (L["%dT %dh"]):format(d, h) end
    if h > 0 then return (L["%dh %02dm"]):format(h, m) end
    return (L["%dm"]):format(math.max(1, m))
end
-- naechster Raid (sonst naechster Termin)
local function nextRaid()
    local now, first = ns.now(), nil
    for _, e in ipairs(eventList()) do
        if (e.ts or 0) > now - 1800 then
            first = first or e
            if e.kind == "raid" or (not e.kind and (e.max or 5) > 5) then return e, true end
        end
    end
    return first, false
end
-- ungelesene Gildenchat-Nachrichten (aus dem Navigations-Abzeichen)
local function chatUnread()
    local s = tostring(ns._badges and ns._badges.chat or "")
    return tonumber(s:match("(%d+)")) or 0, s:find("@", 1, true) ~= nil
end
local function greeting()
    local h = tonumber(date("%H")) or 12
    if h < 5 then return L["Gute Nacht"] elseif h < 11 then return L["Guten Morgen"]
    elseif h < 18 then return L["Guten Tag"] elseif h < 23 then return L["Guten Abend"] end
    return L["Gute Nacht"]
end

------------------------------------------------------------------------
-- Banner-Hintergrund: Blizzard-Ladebildschirme aus dem Client
------------------------------------------------------------------------
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local EMBER = ns.MEDIA .. "ember"
local LS = "Interface\\Glues\\LoadingScreens\\"
local CAM = LS .. "camelot160\\main\\loadscreen_camelot_"
-- { Pfad, Seitenverhaeltnis, Bildmitte senkrecht }
local BG = {
    oasis = { ns.MEDIA .. "dash_banner", 3, 0.5, 342 / 512 },   -- eigenes Oasis-Banner Horde (Bild nur im oberen Teil der Datei)
    oasisally = { ns.MEDIA .. "dash_banner_ally", 2000 / 654, 0.5, 335 / 512 },   -- dasselbe mit Allianz-Bannern
    kalimdor = { CAM .. "kalimdor", 16 / 9, 0.45 },
    east = { CAM .. "easternkingdom", 16 / 9, 0.45 },
    lordaeron = { CAM .. "ruinsoflordaeron", 16 / 9, 0.45 },
    ogri = { LS .. "LoadScreenOrgrimmar", 4 / 3, 0.42 },
    oldkal = { LS .. "LoadScreenKalimdor", 4 / 3, 0.42 },
    oldeast = { LS .. "LoadScreenEasternKingdom", 4 / 3, 0.42 },
}
local ORDER_HORDE = { "oasis", "kalimdor", "lordaeron", "east", "ogri", "oldkal", "oldeast" }
local ORDER_ALLY = { "oasisally", "east", "lordaeron", "kalimdor", "oldeast", "oldkal", "ogri" }
local BG_NAMES = {
    { "auto", "Automatisch (nach Fraktion)" }, { "oasis", "Oasis (Horde)" }, { "oasisally", "Oasis (Allianz)" }, { "kalimdor", "Kalimdor" }, { "east", "Oestliche Koenigreiche" },
    { "lordaeron", "Ruinen von Lordaeron" }, { "ogri", "Orgrimmar (klassisch)" }, { "none", "Nur Farbverlauf" },
}

local function S() return ns.db and ns.db.settings or {} end
-- Midas-Banner (0.5.927): eigene Wahl gilt (settings.hideMidasAd true = aus, false = an). Ohne Wahl: in der oeffentlichen
-- Version AUS (Werbung im Spiel soll niemand ungefragt sehen - CurseForge-Regeln), mit Gildenmodul wie bisher an.
local function adWanted()
    local h = S().hideMidasAd
    if h == true then return false elseif h == false then return true end
    return ns.GuildPack and true or false
end
local function animOn() return not S().noAnim end
local function moving() return animOn() and S().dashStill ~= true end

-- bekannt im Client? true/false, nil = nicht pruefbar
local function fileKnown(path)
    if not GetFileIDFromPath then return nil end
    local ok, id = pcall(GetFileIDFromPath, path)
    if not ok then return nil end
    return (id ~= nil and id ~= 0) and true or false
end
local function bgOrder()
    local pick = S().dashBg
    if pick == "none" then return {} end
    local fac = UnitFactionGroup and select(1, pcall(UnitFactionGroup, "player")) and UnitFactionGroup("player")
    local base = fac == "Alliance" and ORDER_ALLY or ORDER_HORDE
    if pick and BG[pick] then
        local o = { pick }
        for _, k in ipairs(base) do if k ~= pick then o[#o + 1] = k end end
        return o
    end
    return base
end
-- Textur setzen: erst Dateien, die der Client sicher kennt, dann alles, was SetTexture annimmt
local function pickBackground(tex)
    local order = bgOrder()
    local anyCheck = false
    for _, k in ipairs(order) do
        local known = fileKnown(BG[k][1])
        if known ~= nil then anyCheck = true end
        if known then
            local ok, r = pcall(tex.SetTexture, tex, BG[k][1])
            if ok and r ~= false then return k end
        end
    end
    -- Pruef-API fehlt oder kennt nichts davon: auf die Rueckgabe von SetTexture verlassen
    for _, k in ipairs(order) do
        if not anyCheck or fileKnown(BG[k][1]) == nil then
            local ok, r = pcall(tex.SetTexture, tex, BG[k][1])
            if ok and r then return k end
        end
    end
    return nil
end

ns.Probes = ns.Probes or {}
ns.Probes.dashboard = function()
    ns.print("Dashboard: GetFileIDFromPath=" .. tostring(GetFileIDFromPath ~= nil) .. "  Fraktion=" .. tostring(UnitFactionGroup and UnitFactionGroup("player")))
    local t = UIParent:CreateTexture(nil, "BACKGROUND")
    for _, k in ipairs(ORDER_HORDE) do
        local id = GetFileIDFromPath and select(2, pcall(GetFileIDFromPath, BG[k][1]))
        local ok, r = pcall(t.SetTexture, t, BG[k][1])
        ns.print(("  %s: FileID=%s  SetTexture=%s"):format(k, tostring(id), ok and tostring(r) or "Fehler"))
    end
    t:Hide()
    local okM, mdl = pcall(CreateFrame, "PlayerModel", nil, UIParent)
    if okM and mdl then
        local okU, eU = pcall(mdl.SetUnit, mdl, "player")
        ns.print(("  PlayerModel: ok  SetUnit=%s  SetRotation=%s  SetLight=%s  CreateVector3D=%s"):format(okU and "ok" or tostring(eU),
            tostring(mdl.SetRotation ~= nil), tostring(mdl.SetLight ~= nil), tostring(CreateVector3D ~= nil)))
        mdl:Hide()
    else
        ns.print("  PlayerModel: nicht verfuegbar (" .. tostring(mdl) .. ")")
    end
    ns.print("  gewaehlt: " .. tostring(pickBackground(t)) .. "  (Einstellung: " .. tostring(S().dashBg or "auto") .. ")")
    -- Held der Woche
    local okS, list = pcall(Info.HeroScores)
    list = okS and list or {}
    ns.print(("  Held der Woche: %d Kandidaten (Chronik 7 Tage)%s"):format(#list, okS and "" or ("  FEHLER " .. tostring(list))))
    for i = 1, math.min(5, #list) do
        local s = list[i]
        local det = {}
        for k, v in pairs(s.n) do det[#det + 1] = k .. "=" .. v end
        table.sort(det)
        ns.print(("    %d. %s  %d Punkte  (%s)"):format(i, ns.displayName(s.name), s.score, table.concat(det, " ")))
    end
    local okH, h = pcall(Info.Hero)
    if okH and h then
        local pr = ns.db.members and ns.db.members[h.name]
        local unit = Info.UnitFor and Info.UnitFor(h.name)
        ns.print(("  -> %s  Grund: %s%s  Einheit=%s  Profil rc=%s sx=%s  SetCustomRace=%s  Darstellung=%s"):format(ns.displayName(h.name), h.reason or "",
            h.byRank and " (nach Rang)" or "", tostring(unit), tostring(pr and pr.rc), tostring(pr and pr.sx),
            tostring(okM and mdl and mdl.SetCustomRace ~= nil), tostring(Info.heroMethod or "noch nicht geladen")))
    else
        ns.print("  -> kein Held" .. (okH and "" or (" FEHLER " .. tostring(h))) .. (S().dashHero == false and " (abgeschaltet)" or ""))
    end
    local okA, aInfo = pcall(function() return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("classicon-warrior") end)
    ns.print(("  Klassensymbol: CLASS_ICON_TCOORDS=%s  Atlas classicon-warrior=%s"):format(tostring(CLASS_ICON_TCOORDS ~= nil), tostring(okA and aInfo ~= nil)))
    local okL, layers = pcall(function() return C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(1414) end)
    ns.print(("  Karte: GetMapRectOnMap=%s  ArtLayers(Kalimdor)=%s  Kacheln=%s"):format(tostring(C_Map and C_Map.GetMapRectOnMap ~= nil),
        tostring(okL and type(layers) == "table" and #layers or "nein"),
        tostring(select(2, pcall(function() local x = C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(1414, 1) return x and #x or "nein" end)))))
    local okC, ts, title = pcall(Info.CountdownTarget)
    ns.print(("  Countdown: %s  %s"):format(okC and ts and date("%d.%m.%Y %H:%M", ts) or "kein Ziel", okC and tostring(title or "") or tostring(ts)))
end

------------------------------------------------------------------------
-- Bausteine
------------------------------------------------------------------------
local function box(parent, title, color)
    local f = K.Panel(parent, C.panel)
    if f.bg then f.bg:SetAlpha(0.8) end   -- leicht durchscheinend: Dashboard-Hintergrundbild schimmert durch
    f.head = K.GameHead(f, title, color)
    f.head:SetPoint("TOPLEFT", 12, -12)
    f.head:SetPoint("RIGHT", -12, 0)
    return f
end
local function ease(t) return 1 - (1 - t) ^ 3 end

-- Klickmenue zu einem Mitglied (wie in der Mitgliederliste)
local function memberMenu(owner, m)
    if not m then return end
    local items = {}
    if not ns.isMe(m.name) then
        items[#items + 1] = { text = L["Fluestern"], fn = function() ns.Whisper(m.name) end }
        items[#items + 1] = { text = L["In Gruppe einladen"], fn = function()
            local n = ns.ChatName and ns.ChatName(m.name) or ns.short(m.name)
            if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, n)
            elseif InviteUnit then pcall(InviteUnit, n) end
        end }
    end
    if ns.Profile and ns.Profile.Show then items[#items + 1] = { text = L["Profil ansehen"], fn = function() ns.Profile.Show(m.name) end } end
    if ns.Talents then items[#items + 1] = { text = L["Talente ansehen"], fn = function() ns.Talents.Show(m.name) end } end
    if ns.Map and ns.Map.ShowMember then items[#items + 1] = { text = L["Auf der Karte zeigen"], fn = function() ns.Map.ShowMember(m.name, m.zone, m.aname) end } end
    K.ShowMenu(owner, items, ns.displayName(m.name), 150)
end

-- genau EIN Klassensymbol: Atlas "classicon-<klasse>" (falls der Client ihn kennt), sonst Ausschnitt
-- aus dem Symbolblatt; false = nichts Passendes (dann Buchstabe in Klassenfarbe)
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local knownAtlases = {}
local function atlasKnown(a)
    if knownAtlases[a] ~= nil then return knownAtlases[a] end
    if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
    local ok, info = pcall(C_Texture.GetAtlasInfo, a)
    if ok then knownAtlases[a] = type(info) == "table" end
    return knownAtlases[a] or false
end
local function setClassIcon(tex, class)
    if type(class) ~= "string" or class == "" then return false end
    local atlas = "classicon-" .. class:lower()
    if tex.SetAtlas and atlasKnown(atlas) and pcall(tex.SetAtlas, tex, atlas) then return true end
    local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if tc then
        -- maskierte Texturen (runde Avatare) duerfen keinen Ausschnitt setzen -> dann lieber Buchstabe
        if tex.oasisSafeTC then return false end   -- maskiert: Ausschnitt wuerde still ignoriert (ganzes Symbolblatt)
        local okTC = pcall(tex.SetTexCoord, tex, tc[1] + 0.015, tc[2] - 0.015, tc[3] + 0.015, tc[4] - 0.015)
        if not okTC then return false end
        tex:SetTexture(CLASS_SHEET)
        return true
    end
    return false
end
Info.SetClassIcon = setClassIcon

-- runder Klassenkreis fuer "Wer ist online"
local function memberCell(parent)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(48, 58)
    c.glow = c:CreateTexture(nil, "BACKGROUND")
    c.glow:SetTexture(EMBER)
    c.glow:SetBlendMode("ADD")
    c.glow:SetSize(64, 64)
    c.glow:SetPoint("CENTER", c, "TOP", 0, -21)
    c.glow:SetAlpha(0)
    c.ring = c:CreateTexture(nil, "BORDER")
    c.ring:SetTexture(CIRCLE)
    c.ring:SetSize(40, 40)
    c.ring:SetPoint("TOP", 0, -1)
    c.inner = c:CreateTexture(nil, "ARTWORK")
    c.inner:SetTexture(CIRCLE)
    c.inner:SetVertexColor(0.07, 0.07, 0.08)
    c.inner:SetSize(36, 36)
    c.inner:SetPoint("CENTER", c.ring)
    -- Klassensymbol OHNE Maske: mit Kreismaske ignorierte der Client den Ausschnitt (SetTexCoord)
    -- und zeigte das komplette Symbolblatt aller Klassen. Quadrat passt in den inneren Kreis.
    c.icon = c:CreateTexture(nil, "ARTWORK", nil, 1)
    c.icon:SetSize(24, 24)
    c.icon:SetPoint("CENTER", c.ring)
    c.letter = K.Title(c, 15, C.text, "CENTER")
    c.letter:SetPoint("CENTER", c.ring)
    -- 0.6.178: Ornament-Ring (Gildenmodul) statt Farbkreis; Klassensymbol fuellt die Oeffnung (ohne Maske -
    -- Ecken liegen unter dem Ring). Oeffnung ~74 %, Ring bis ~90 % des Bildes.
    if ns.GuildPack then
        c.frame = c:CreateTexture(nil, "OVERLAY", nil, 1)
        c.frame:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\online_ring")
        c.frame:SetPoint("CENTER", c.ring)
    end
    c.lvlBg = c:CreateTexture(nil, "OVERLAY")
    c.lvlBg:SetTexture(CIRCLE)
    c.lvlBg:SetVertexColor(0.06, 0.06, 0.07)
    c.lvlBg:SetSize(17, 17)
    c.lvlBg:SetPoint("CENTER", c.ring, "BOTTOMRIGHT", -5, 5)
    c.lvl = c:CreateFontString(nil, "OVERLAY", nil, 2)
    K.SetFontSafe(c.lvl, K.FONT_HEAD or K.FONT, 8, "OUTLINE", K.FONT)
    c.lvl:SetPoint("CENTER", c.lvlBg)
    c.lvl:SetTextColor(1, 1, 1)
    c.lfg = c:CreateTexture(nil, "OVERLAY", nil, 3)
    c.lfg:SetTexture(CIRCLE)
    c.lfg:SetVertexColor(C.mint[1], C.mint[2], C.mint[3])
    c.lfg:SetSize(9, 9)
    c.lfg:SetPoint("CENTER", c.ring, "TOPRIGHT", -5, -5)
    c.name = K.Text(c, 9, C.muted, "CENTER")
    c.name:SetPoint("TOP", c.ring, "BOTTOM", 0, -3)
    c.name:SetWidth(48)
    c.name:SetWordWrap(false)
    c:SetScript("OnEnter", function(self)
        self.glow:SetAlpha(0.55)
        local m = self.member
        if self.more then
            K.ShowTip(self, { (L["%d weitere online"]):format(self.more), L["Klick: alle Mitglieder"] })
            return
        end
        if not m then return end
        local lines = { ns.Radar.Colored and ns.Radar.Colored(m.name) or ns.displayName(m.name),
            (L["Level %d"]):format(m.level or 0) .. "  " .. (m.className or (m.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[m.class]) or "") }
        if (m.zone or "") ~= "" then lines[#lines + 1] = "|cffa3a3a8" .. m.zone .. "|r" end
        local r = ns.Rank and ns.Rank.Of(m.name)
        if r then lines[#lines + 1] = "|cffffd24a" .. (L["Oasis-Rang %d"]):format(type(r) == "table" and (r.level or 0) or r) .. "|r" end
        if self.lfgOn then lines[#lines + 1] = "|cff66db9e" .. L["sucht Gruppe"] .. "|r" end
        lines[#lines + 1] = "|cff666666" .. L["Klick: Fluestern, Profil, Karte ...  ·  Rechtsklick: alle Aktionen"] .. "|r"
        K.ShowTip(self, lines)
    end)
    c:SetScript("OnLeave", function(self) self.glow:SetAlpha(0) GameTooltip:Hide() end)
    c:RegisterForClicks("AnyUp")
    c:SetScript("OnClick", function(self, btn)
        if self.more then ns.ShowPage("radar") return end
        -- Rechtsklick = volles Mitglieder-Menue (wie in der Mitgliederliste), Linksklick = Schnellmenue
        if btn == "RightButton" and self.member and ns.Members and ns.Members.ShowMenu then
            GameTooltip:Hide()
            ns.Members.ShowMenu(self, self.member)
            return
        end
        memberMenu(self, self.member)
    end)
    -- Groesse je nach Anzahl: 44 (mit Name), 34 (Kurzname), 26 (ohne Name, Name im Tooltip)
    c.mode = 44
    function c:SetMode(s)
        if self.modeSet == s then return end
        self.modeSet, self.mode = s, s
        local cw, chh = (s == 44 and 48) or (s == 34 and 40) or 30, (s == 44 and 58) or (s == 34 and 48) or 30
        self:SetSize(cw, chh)
        self.ring:ClearAllPoints()
        self.ring:SetSize(s, s)
        self.ring:SetPoint("TOP", 0, -1)
        self.inner:SetSize(s - 4, s - 4)
        self.icon:SetSize(math.floor(s * 0.6), math.floor(s * 0.6))
        if self.frame then
            local f = math.floor(s * 0.86)   -- etwas kleiner als der alte Kreis
            self.frame:SetSize(f, f)
            self.ring:SetAlpha(0)
            self.inner:SetSize(math.floor(f * 0.76), math.floor(f * 0.76))
            self.icon:SetSize(math.floor(f * 0.64), math.floor(f * 0.64))
        end
        self.glow:SetSize(s * 1.6, s * 1.6)
        self.glow:ClearAllPoints()
        self.glow:SetPoint("CENTER", self.ring)
        local bs = s >= 34 and 17 or 12
        self.lvlBg:SetSize(bs, bs)
        self.lvlBg:ClearAllPoints()
        self.lvlBg:SetPoint("CENTER", self.ring, "BOTTOMRIGHT", -s * 0.12, s * 0.12)
        K.SetFontSafe(self.lvl, K.FONT_HEAD or K.FONT, s >= 34 and 8 or 7, "OUTLINE", K.FONT)
        if K.CenterNum then K.CenterNum(self.lvl, self.lvlBg) else self.lvl:ClearAllPoints() self.lvl:SetPoint("CENTER", self.lvlBg) end
        self.lfg:ClearAllPoints()
        self.lfg:SetPoint("CENTER", self.ring, "TOPRIGHT", -s * 0.12, -s * 0.12)
        K.SetFontSafe(self.letter, K.FONT_HEAD or K.FONT, s >= 34 and 15 or 11, nil, K.FONT)
        self.name:SetWidth(cw)
        self.name:SetShown(s > 26)
        if self.member then self:SetMember(self.member) elseif self.more then self:SetMore(self.more) end
    end
    function c:SetMember(m)
        self.member, self.more = m, nil
        local cr, cg, cb = ns.classColor(m.class)
        cr, cg, cb = cr or 0.6, cg or 0.6, cb or 0.6
        self.ring:SetVertexColor(cr, cg, cb)
        self.glow:SetVertexColor(cr, cg, cb)
        if self.frame then self.frame:SetVertexColor(cr, cg, cb) end   -- 0.6.179: Ring in Klassenfarbe
        if setClassIcon(self.icon, m.class) then
            self.icon:Show()
            self.letter:Hide()
        else
            self.icon:Hide()
            self.letter:SetText(K.Upper((ns.displayName(m.name) or "?"):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"))
            self.letter:SetTextColor(cr, cg, cb)
            self.letter:Show()
        end
        self.lvl:SetText(m.level or "")
        self.lvlBg:Show() self.lvl:Show()
        local dn = ns.displayName(m.name) or "?"
        self.name:SetText(dn)
        self.name:SetTextColor(cr * 0.8 + 0.2, cg * 0.8 + 0.2, cb * 0.8 + 0.2)
        self.name:SetShown(self.mode > 26)
        local lfg = false
        if ns.Groups and ns.Groups.Active then for _, g in ipairs(ns.Groups.Active()) do if g.who == m.name then lfg = true break end end end
        self.lfgOn = lfg
        self.lfg:SetShown(lfg)
        self:Show()
    end
    function c:SetMore(n)
        self.member, self.more = nil, n
        self.ring:SetVertexColor(C.line[1], C.line[2], C.line[3])
        if self.frame then self.frame:SetVertexColor(0.6, 0.6, 0.62) end
        self.icon:Hide()
        self.letter:SetText("+" .. n)
        self.letter:SetTextColor(C.text[1], C.text[2], C.text[3])
        self.letter:Show()
        self.lvlBg:Hide() self.lvl:Hide() self.lfg:Hide()
        self.name:SetText(L["mehr"])
        self.name:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        self.name:SetShown(self.mode > 26)
        self:Show()
    end
    return c
end

-- Leerzustand: Symbol + kurzer Satz + Aktionsknoepfe, kompakt oben im Kasten
-- acts = { { "Text", "seite" oder function }, ... }
local function emptyState(parent, icon, color, text, acts)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(64)
    f:SetPoint("TOPLEFT", 14, -42)
    f:SetPoint("RIGHT", -14, 0)
    f.halo = f:CreateTexture(nil, "BACKGROUND")
    f.halo:SetTexture(EMBER)
    f.halo:SetBlendMode("ADD")
    f.halo:SetSize(46, 46)
    f.halo:SetPoint("CENTER", f, "TOPLEFT", 15, -15)
    f.halo:SetVertexColor(color[1], color[2], color[3])
    f.halo:SetAlpha(0.35)
    f.disc = f:CreateTexture(nil, "BORDER")
    f.disc:SetTexture(CIRCLE)
    f.disc:SetSize(30, 30)
    f.disc:SetPoint("TOPLEFT", 0, 0)
    f.disc:SetVertexColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25)
    f.icon = K.Glyph(f, 16, icon, color)
    f.icon:SetPoint("CENTER", f.disc)
    f.text = K.Text(f, 12, C.muted)
    f.text:SetPoint("TOPLEFT", 40, -1)
    f.text:SetPoint("RIGHT", 0, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetWordWrap(true)
    f.text:SetText(text)
    f.btns = {}
    local prev
    for i, a in ipairs(acts or {}) do
        local b = K.Button(f, L[a[1]], 10, 20, i == 1 and "primary" or "ghost")
        local tw = b.label and b.label.GetStringWidth and b.label:GetStringWidth() or 0
        b:SetWidth(math.max(70, math.min(120, (tonumber(tw) or 0) + 22)))
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 40, -34) end
        b:SetScript("OnClick", function()
            if type(a[2]) == "function" then a[2]() else ns.ShowPage(a[2]) end
        end)
        f.btns[i] = b
        prev = b
    end
    f:Hide()
    return f
end

-- Glas-Kaertchen (Durchsage / Nachricht des Tages) unten rechts im Banner
local function glassCard(parent)
    local m = CreateFrame("Button", nil, parent)
    m:SetSize(250, 58)
    m.bg = m:CreateTexture(nil, "BACKGROUND")
    m.bg:SetAllPoints()
    if not K.Gradient(m.bg, "VERTICAL", { 0.02, 0.02, 0.04, 0.78 }, { 0.10, 0.10, 0.13, 0.55 }) then
        m.bg:SetColorTexture(0.03, 0.03, 0.05, 0.65)
    end
    m.gloss = m:CreateTexture(nil, "BORDER")
    m.gloss:SetPoint("TOPLEFT") m.gloss:SetPoint("TOPRIGHT")
    m.gloss:SetHeight(18)
    if not K.Gradient(m.gloss, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.07 }) then m.gloss:Hide() end
    K.Border(m, { 1, 1, 1, 0.14 })
    m.bar = m:CreateTexture(nil, "ARTWORK")
    m.bar:SetPoint("TOPLEFT", 0, 0) m.bar:SetPoint("BOTTOMLEFT", 0, 0)
    m.bar:SetWidth(2)
    m.label = K.Text(m, 9, C.accent)
    m.label:SetPoint("TOPLEFT", 10, -7)
    m.label:SetPoint("RIGHT", -8, 0)
    m.label:SetWordWrap(false)
    m.text = K.Text(m, 11, C.text)
    m.text:SetPoint("TOPLEFT", 10, -21)
    m.text:SetPoint("BOTTOMRIGHT", -8, 6)
    m.text:SetJustifyV("TOP")
    m.text:SetJustifyH("LEFT")
    m.text:SetWordWrap(true)
    m:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m:SetScript("OnClick", function(self) if self.page then ns.ShowPage(self.page) end end)
    return m
end

-- 3D-Modell des eigenen Charakters (freigestellt, per Ziehen drehbar); nil, wenn der Client keins kann
local function heroModel(parent)
    if not CreateFrame then return nil end
    local ok, mdl = pcall(CreateFrame, "PlayerModel", nil, parent)
    if not ok or not mdl or not mdl.SetUnit then return nil end
    mdl.rot = -0.35
    -- self.look = { race, sex } (Held ohne greifbare Einheit) oder self.unit (Standard: eigener Charakter)
    function mdl:Apply()
        pcall(self.ClearModel, self)
        local okU
        if self.look then
            okU = self.SetCustomRace and pcall(self.SetCustomRace, self, self.look.race, self.look.sex or 0)
        else
            okU = pcall(self.SetUnit, self, self.unit or "player")
        end
        if not okU then self.failed = true return end
        self.failed = nil
        pcall(self.SetPortraitZoom, self, 0)
        pcall(self.SetCamDistanceScale, self, 1.55)
        pcall(self.SetPosition, self, 0, 0, -0.05)
        if self.SetRotation then pcall(self.SetRotation, self, self.rot) elseif self.SetFacing then pcall(self.SetFacing, self, self.rot) end
        pcall(self.SetAnimation, self, 0)
        -- weiches Licht von vorne links (nur wenn der Client die neue Licht-API hat)
        if self.SetLight and CreateVector3D and CreateColor then
            pcall(self.SetLight, self, true, {
                omnidirectional = false, point = CreateVector3D(-0.6, 1, -0.6),
                ambientIntensity = 0.75, ambientColor = CreateColor(1, 0.95, 0.9),
                diffuseIntensity = 0.95, diffuseColor = CreateColor(1, 0.88, 0.72),
            })
        end
    end
    function mdl:Turn(r)
        self.rot = r
        if self.SetRotation then pcall(self.SetRotation, self, r) elseif self.SetFacing then pcall(self.SetFacing, self, r) end
    end
    mdl:SetScript("OnModelLoaded", function(self)
        pcall(self.SetCamDistanceScale, self, 1.55)
        self:Turn(self.rot)
    end)
    if mdl.EnableMouse then mdl:EnableMouse(true) end
    mdl:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        local x = GetCursorPosition and GetCursorPosition() or 0
        self.dragX, self.dragR, self.moved = x, self.rot, 0
        self:SetScript("OnUpdate", function(s)
            local cx = GetCursorPosition and GetCursorPosition() or 0
            s.moved = math.max(s.moved or 0, math.abs(cx - s.dragX))
            s:Turn(s.dragR + (cx - s.dragX) / 70)
        end)
    end)
    mdl:SetScript("OnMouseUp", function(self, btn)
        self:SetScript("OnUpdate", nil)
        -- kurzer Klick (ohne Drehen) auf den Helden: Profilkarte
        if self.who and btn == "LeftButton" and (self.moved or 0) < 4 and ns.Profile and ns.Profile.Show then ns.Profile.Show(self.who) end
    end)
    mdl:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    mdl:SetScript("OnEnter", function(self)
        if self.who then
            K.ShowTip(self, { L["Held der Woche"], ns.Radar.Colored and ns.Radar.Colored(self.who) or ns.displayName(self.who), self.why or "",
                "|cff888888" .. L["Klick: Profil  ·  Ziehen zum Drehen"] .. "|r" })
            return
        end
        K.ShowTip(self, { ns.displayName(ns.me()), "|cff888888" .. L["Ziehen zum Drehen"] .. "|r" })
    end)
    mdl:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return mdl
end

------------------------------------------------------------------------
-- Seite: Dashboard
------------------------------------------------------------------------
-- Wer ist online: EINE Liste fuer Kachel, Kopfzeile und Raster (eigener Charakter zaehlt immer mit)
-- (auch beim Anordnen aufrufbar - vorher konnte das Raster vor dem ersten Fuellen "niemand online" zeigen)
local function computeOnline()
    local R = ns.Radar or {}
    local ok, res = pcall(function()
        local on, meIn = {}, false
        for _, x in ipairs(R.roster or {}) do
            if x.online then
                on[#on + 1] = x
                if ns.isMe(x.name) then meIn = true end
            end
        end
        if not meIn and ns.me then
            local okMe, myName = pcall(ns.me)
            if okMe and myName then
                local _, cf = UnitClass("player")
                on[#on + 1] = (R.byName and R.byName[myName]) or { name = myName, online = true, class = ns.safe(cf),
                    level = ns.safe(UnitLevel("player")), zone = GetZoneText and GetZoneText() or "" }
            end
        end
        table.sort(on, function(a, b)
            local ma, mb = ns.isMe(a.name), ns.isMe(b.name)
            if ma ~= mb then return ma end
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return (a.name or "") < (b.name or "")
        end)
        return on
    end)
    if ok and type(res) == "table" then return res end
    -- Notfall: wenigstens ich selbst
    local okMe, myName = pcall(ns.me)
    local _, cf = UnitClass("player")
    return { { name = okMe and myName or "?", online = true, class = ns.safe(cf), level = ns.safe(UnitLevel("player")), zone = "" } }
end

------------------------------------------------------------------------
-- WOW-Daten: Held der Woche, Raid-Countdown, Begruessung, Gilden-Puls, Tagesziel, Rekorde
------------------------------------------------------------------------
local STRIDE = 1.6   -- Meter je Schritt (wie Insta.lua CH.STRIDE)
local function fmtNum(n)
    n = math.floor(tonumber(n) or 0)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end
local function demoOn() return ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() end
local function isMember(name)
    if not name then return false end
    if ns.isMe(name) then return true end
    local R = ns.Radar
    return (R and R.byName and R.byName[name] ~= nil) or (ns.db.members and type(ns.db.members[name]) == "table") or false
end

-- Held der Woche: Punkte aus der Chronik der letzten 7 Tage (bei allen gleich), Gleichstand -> Name
local HERO_PTS = { level = 3, boss = 5, loot = 2, badge = 4, rank = 2, legacy = 4, duel = 1 }
local HERO_TXT = { { "level", "%d Level-Ups", "1 Level-Up" }, { "boss", "%d Bosse", "1 Boss" }, { "badge", "%d Abzeichen" }, { "loot", "%d Beute" },
    { "legacy", "%d Legacy-Challenges", "1 Legacy-Challenge" }, { "rank", "%d Rang-Aufstiege", "1 Rang-Aufstieg" }, { "duel", "%d Todeswuerfeln" } }
function Info.HeroScores()
    local since, sc, list = ns.now() - 7 * 86400, {}, {}
    for _, e in ipairs(Store.List("chronicle")) do
        local w = e.who
        if w and (e.ts or 0) > since and isMember(w) then
            local k = (e.kind == "level" and e.rank) and "rank" or e.kind
            local pts = HERO_PTS[k]
            if pts then
                local s = sc[w]
                if not s then s = { name = w, score = 0, n = {} } sc[w] = s list[#list + 1] = s end
                s.score = s.score + pts
                s.n[k] = (s.n[k] or 0) + 1
            end
        end
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return a.name < b.name
    end)
    return list
end
function Info.Hero()
    local h = Info.HeroScores()[1]
    if h then
        local parts = {}
        for _, t in ipairs(HERO_TXT) do
            local n = h.n[t[1]]
            if n and #parts < 3 then parts[#parts + 1] = (n == 1 and t[3]) and L[t[3]] or (L[t[2]]):format(n) end
        end
        h.reason = table.concat(parts, "  ·  ")
        return h
    end
    -- ruhige Woche: hoechste Oasis-Rang-XP laut Profil (fuer alle gleich)
    local best
    for name, pr in pairs(ns.db.members or {}) do
        local x = type(pr) == "table" and tonumber(pr.orx)
        if x and isMember(name) and (not best or x > best.xp or (x == best.xp and name < best.name)) then
            best = { name = name, xp = x, orl = tonumber(pr.orl) }
        end
    end
    if not best then return nil end
    local lvl = best.orl
    if not lvl and ns.Rank and ns.Rank.LevelFor then lvl = select(1, ns.Rank.LevelFor(best.xp)) end
    return { name = best.name, score = 0, n = {}, reason = (L["Oasis-Rang %d"]):format(lvl or 0), byRank = true }
end
-- Pechvogel der Woche: meiste Tode der letzten 7 Tage (Gegenstueck zum Helden)
function Info.Unlucky()
    local since, by, best = ns.now() - 7 * 86400, {}, nil
    for _, d in ipairs((ns.Deaths and ns.Deaths.List and ns.Deaths.List()) or Store.List("deaths")) do
        local w = d.who
        if w and (d.ts or 0) > since and isMember(w) then
            local s2 = by[w] or { name = w, n = 0, killers = {} }
            by[w] = s2
            s2.n = s2.n + 1
            if (d.killer or "") ~= "" then s2.killers[d.killer] = (s2.killers[d.killer] or 0) + 1 end
            if not best or s2.n > best.n or (s2.n == best.n and w < best.name) then best = s2 end
        end
    end
    if not best then return nil end
    local kn, kc = nil, 0
    for k, c in pairs(best.killers) do if c > kc then kn, kc = k, c end end
    best.reason = (best.n == 1 and L["1 Tod"] or (L["%d Tode"]):format(best.n)) .. (kn and ("  ·  " .. (L["meist durch %s"]):format(kn)) or "")
    return best
end
-- Einheit zum Namen (Gruppe/Ziel), damit das echte Modell samt Ausruestung erscheint
local function unitFor(name)
    if not name then return nil end
    if ns.isMe(name) then return "player" end
    local toks = { "target", "focus", "mouseover", "party1", "party2", "party3", "party4" }
    if IsInRaid and IsInRaid() then for i = 1, 40 do toks[#toks + 1] = "raid" .. i end end
    for _, t in ipairs(toks) do
        local ok, hit = pcall(function()
            if UnitExists(t) and UnitIsPlayer(t) then
                local n = ns.safe(GetUnitName(t, true))
                return n ~= nil and ns.fullName(n) == ns.fullName(name)
            end
            return false
        end)
        if ok and hit then return t end
    end
end
Info.UnitFor = unitFor

-- Countdown: vor dem Release "WoW Forever Start", danach nur noch ein echter eingetragener Raid-Termin
-- (kein fester Raid-Start mehr - ohne Termin keine Uhr).
-- Zeiten als UTC-Sekunden; date() zeigt sie automatisch in der Ortszeit des Spielers.
-- Release 04.11.2026: Blizzard startet Classic-Versionen weltweit gleichzeitig (15:00 Pazifik = 00:00 MEZ
-- = 08:00 Korea). Je Region (GetCurrentRegion, sonst Client-Sprache) eigener Eintrag, falls Blizzard abweicht.
local RELEASE_UTC = {
    us = 1793833200,   -- 04.11.2026 15:00 PST
    eu = 1793833200,   -- 05.11.2026 00:00 MEZ
    kr = 1793833200,   -- 05.11.2026 08:00 KST
    tw = 1793833200,
    cn = 1793833200,
}
local function region()
    local ok, r = pcall(GetCurrentRegion)
    r = ok and tonumber(r) or nil
    if r == 1 then return "us" elseif r == 2 then return "kr" elseif r == 3 then return "eu" elseif r == 4 then return "tw" elseif r == 5 then return "cn" end
    local loc = GetLocale and GetLocale() or "enUS"
    if loc == "enUS" or loc == "esMX" or loc == "ptBR" then return "us" end
    if loc == "koKR" then return "kr" end
    if loc == "zhTW" then return "tw" end
    if loc == "zhCN" then return "cn" end
    return "eu"
end
Info.Region = region
function Info.CountdownTarget()
    local now = ns.now()
    local rel = RELEASE_UTC[region()] or RELEASE_UTC.eu
    if now < rel then return rel, L["WoW Forever Start"], nil end
    local ev, isRaid = nextRaid()
    if ev and isRaid and (ev.ts or 0) > now then return ev.ts, ev.title or L["Naechster Raid"], ev end
end
-- Gilden-Bereitschaft: Stufe 60, Onyxia freigeschaltet (Lockouts), Raid-Vorbereitung gruen (RaidPrep)
function Info.Readiness()
    local total, n60, names = 0, 0, {}
    for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
        total = total + 1
        if (m.level or 0) >= 60 then n60 = n60 + 1 names[#names + 1] = m.name end
    end
    local out = { total = total, lvl60 = n60 }
    local LK = ns.Lockouts
    if LK and LK.StateOf then
        local n = 0
        for _, name in ipairs(names) do
            local ok, st = pcall(LK.StateOf, name, "ony", 60)
            if ok and (st == "free" or st == "bound") then n = n + 1 end
        end
        out.unlocked = n
    end
    local RP = ns.RaidPrep
    if RP and RP.Participants then
        local okE, ev = pcall(function() return RP.NextEvent and RP.NextEvent() or nil end)
        local ok, list = pcall(RP.Participants, okE and ev or nil)
        if ok and type(list) == "table" and #list > 0 then
            local g = 0
            for _, x in ipairs(list) do if x.rec and x.rec.light == "g" and not x.old then g = g + 1 end end
            out.prepG, out.prepN = g, #list
        end
    end
    return out
end

-- Begruessung mit Kontext seit dem letzten Besuch
local function awayText(sec)
    local d = math.floor(sec / 86400)
    if d >= 2 then return (L["%d Tage"]):format(d) elseif d == 1 then return L["1 Tag"] end
    local h = math.floor(sec / 3600)
    if h >= 2 then return (L["%d Stunden"]):format(h) elseif h == 1 then return L["1 Stunde"] end
    return (L["%d Minuten"]):format(math.max(1, math.floor(sec / 60)))
end
function Info.WelcomeText(last)
    local now = ns.now()
    local lv, evn, chat = 0, 0, 0
    for _, e in ipairs(Store.List("chronicle")) do
        if e.kind == "level" and not e.rank and (e.ts or 0) > last and not ns.isMe(e.who or "") then lv = lv + 1 end
    end
    for _, e in ipairs(Store.List("events")) do
        if (e.created or e.u or 0) > last and (e.ts or 0) > now then evn = evn + 1 end
    end
    for _, m in ipairs(ns.db.gchat or {}) do
        if type(m) == "table" and (m.ts or 0) > last and m.k ~= "sys" and not ns.isMe(m.s or "") then chat = chat + 1 end
    end
    if demoOn() and chat == 0 then chat = 14 end   -- Demo: Beispielwert, der Demo-Chat wird nicht mitgeschrieben
    local parts = {}
    if lv > 0 then parts[#parts + 1] = lv == 1 and L["1 Level-Up in der Gilde"] or (L["%d Level-Ups in der Gilde"]):format(lv) end
    if evn > 0 then parts[#parts + 1] = evn == 1 and L["1 neuer Termin"] or (L["%d neue Termine"]):format(evn) end
    if chat > 0 then parts[#parts + 1] = chat == 1 and L["1 Chat-Nachricht"] or (L["%d Chat-Nachrichten"]):format(chat) end
    local s = (L["Du warst %s weg."]):format(awayText(now - last))
    if #parts > 0 then return s .. " " .. L["Seitdem:"] .. " " .. table.concat(parts, ", ") end
    return s .. " " .. L["Seitdem war es ruhig in der Gilde."]
end

-- Gilden-Puls: heute je halbe Stunde hoechstens gleichzeitig online (eigener Mitschnitt alle 5 min)
-- + typischer Tagesverlauf aus der Spielzeit-Statistik (Members: ns.db.play[name].h)
local function slotOf(ts) local t = date("*t", ts) return t.hour * 2 + ((t.min or 0) >= 30 and 1 or 0) end
local function slotText(k) k = k % 48 return ("%d:%02d"):format(math.floor(k / 2), (k % 2) * 30) end
function Info.SamplePulse()
    if not ns.db then return end
    local day = date("%Y-%m-%d")
    local d = ns.db.dashPulse
    if type(d) ~= "table" or d.day ~= day then d = { day = day, s = {} } ns.db.dashPulse = d end
    local n = 0
    for _, m in ipairs(computeOnline()) do if not m.demo then n = n + 1 end end
    local k = slotOf(ns.now())
    if n > (d.s[k] or 0) then d.s[k] = n end
end
function Info.Pulse()
    local today, typ = {}, {}
    local d = ns.db.dashPulse
    if type(d) == "table" and d.day == date("%Y-%m-%d") then for k, v in pairs(d.s or {}) do today[tonumber(k) or -1] = v end end
    local hrs = {}
    local okP, play = pcall(function() return ns.Members and ns.Members.Store and (ns.Members.Store()) end)
    if okP and type(play) == "table" then
        for _, e in pairs(play) do
            if type(e) == "table" and type(e.h) == "table" and (not e.demo or demoOn()) then
                for h, sec in pairs(e.h) do
                    h = tonumber(h)
                    if h and h >= 0 and h < 24 then hrs[h] = (hrs[h] or 0) + (tonumber(sec) or 0) end
                end
            end
        end
    end
    local typMax = 0
    for k = 0, 47 do typ[k] = hrs[math.floor(k / 2)] or 0 typMax = math.max(typMax, typ[k]) end
    local cur = slotOf(ns.now())
    local nOn = #computeOnline()
    -- Demo: heutigen Verlauf aus dem typischen Verlauf ableiten (fester Wert je Halbstunde)
    if demoOn() and typMax > 0 then
        for k = 0, cur do
            local v = math.floor(typ[k] / typMax * nOn * (0.75 + ((k * 37) % 10) / 40) + 0.5)
            if v > (today[k] or 0) then today[k] = v end
        end
    end
    if nOn > (today[cur] or 0) then today[cur] = nOn end
    local dayMax = 0
    for k = 0, 47 do dayMax = math.max(dayMax, today[k] or 0) end
    -- Stosszeit: staerkstes 2-Stunden-Fenster (typisch, sonst heute)
    local src = typMax > 0 and typ or today
    local bestK, bestV = nil, 0
    for k = 0, 44 do
        local v = (src[k] or 0) + (src[k + 1] or 0) + (src[k + 2] or 0) + (src[k + 3] or 0)
        if v > bestV then bestK, bestV = k, v end
    end
    return { today = today, typ = typ, typMax = typMax, dayMax = dayMax, cur = cur, now = nOn,
        peak = bestK and (slotText(bestK) .. "–" .. slotText(bestK + 4)) or nil }
end

-- Tagesziel: Schritte (Insta-Schrittzaehler), XP heute (eigener Tageszaehler), Wochenaufgaben
function Info.DailyGoal()
    local day = date("%Y-%m-%d")
    local c = ns.char or ns.db
    local walk = c and c.walk
    local steps = math.floor((type(walk) == "table" and tonumber(walk[day]) or 0) / STRIDE)
    local lvl = ns.safe(UnitLevel("player")) or 0
    local xp = UnitXP and ns.safe(UnitXP("player")) or 0
    local mx = UnitXPMax and ns.safe(UnitXPMax("player")) or 0
    local x = c and c.dashXP
    if type(x) ~= "table" or x.day ~= day then x = { day = day, lvl = lvl, xp = xp, max = mx, acc = 0 } if c then c.dashXP = x end end
    if lvl > (x.lvl or lvl) then
        x.acc = (x.acc or 0) + math.max(0, (x.max or 0) - (x.xp or 0))
        x.lvl, x.xp = lvl, 0
    end
    if (mx or 0) > 0 then x.max = mx end
    local gained = math.max(0, (x.acc or 0) + (xp or 0) - (x.xp or 0))
    local xpGoal = (lvl >= 60 or (mx or 0) <= 0) and 0 or math.floor(mx * 0.5)
    local done, tn = 0, 3
    if ns.Rewards and ns.Rewards.Tasks then
        local ok, tasks = pcall(ns.Rewards.Tasks)
        if ok and type(tasks) == "table" then
            tn = math.max(3, #tasks)
            for _, tk in ipairs(tasks) do if tk.done or (tk.have or 0) >= (tk.need or 1) then done = done + 1 end end
        end
    end
    local g = { steps = steps, stepGoal = 10000, xp = gained, xpGoal = xpGoal, tasks = done, taskN = tn }
    if demoOn() then
        g.steps = math.max(g.steps, 10480)
        if g.xpGoal <= 0 then g.xpGoal = 6000 end
        g.xp = math.max(g.xp, math.floor(g.xpGoal * 1.04))
        g.tasks = g.taskN
    end
    g.r1 = math.min(1, g.steps / g.stepGoal)
    g.r2 = g.xpGoal > 0 and math.min(1, g.xp / g.xpGoal) or 1
    g.r3 = math.min(1, g.tasks / math.max(1, g.taskN))
    g.full = g.r1 >= 1 and g.r2 >= 1 and g.r3 >= 1
    return g
end

-- Gilden-Rekorde
function Info.Records()
    local out = {}
    local DR = ns.Deathroll
    local best
    if DR and DR.Ranking then
        local ok, list = pcall(DR.Ranking)
        if ok and type(list) == "table" then
            for _, s in ipairs(list) do
                if (s.best or 0) > 0 and (not best or s.best > best.best or (s.best == best.best and s.name < best.name)) then best = s end
            end
        end
    end
    out[#out + 1] = { icon = ns.ICONS.deathroll, color = C.red, page = "deathroll", title = L["Laengste Todeswuerfel-Serie"],
        who = best and best.name, value = best and (L["%d Siege in Folge"]):format(best.best) }
    local c = ns.char or {}
    local bd, bm
    if type(c.walk) == "table" then
        for d, m in pairs(c.walk) do m = tonumber(m) if m and (not bm or m > bm) then bd, bm = d, m end end
    end
    if demoOn() and not bm then bd, bm = date("%Y-%m-%d", ns.now() - 3 * 86400), 23850 * STRIDE end
    local okMe, me = pcall(ns.me)
    out[#out + 1] = { icon = ns.ICONS.map, color = C.mint, title = L["Meiste Schritte an einem Tag"],
        who = bm and okMe and me or nil, value = bm and ((L["%s Schritte"]):format(fmtNum(bm / STRIDE)) .. "  |cff888888" .. tostring(bd):sub(9, 10) .. "." .. tostring(bd):sub(6, 7) .. ".|r") }
    local fast
    for _, e in ipairs(Store.List("chronicle")) do
        if e.kind == "boss" and e.a2 then
            local mm, ss = tostring(e.a2):match("^(%d+):(%d%d)$")
            local sec = mm and (tonumber(mm) * 60 + tonumber(ss))
            if sec and sec > 0 and (not fast or sec < fast.sec or (sec == fast.sec and (e.who or "") < (fast.who or ""))) then
                fast = { sec = sec, who = e.who, boss = e.a1, txt = e.a2 }
            end
        end
    end
    out[#out + 1] = { icon = ns.ICONS.raid, color = C.amber, page = "chronicle", title = L["Schnellster Boss-Kill"],
        who = fast and fast.who, value = fast and ((fast.boss or "?") .. "  |cffffd24a" .. fast.txt .. "|r") }
    local top
    local function consider(name, lvl)
        lvl = tonumber(lvl)
        if name and lvl and lvl > 0 and (not top or lvl > top.lvl or (lvl == top.lvl and name < top.name)) then top = { name = name, lvl = lvl } end
    end
    if ns.Rank and ns.Rank.Mine and okMe then local ok, m = pcall(ns.Rank.Mine) if ok and m then consider(me, m.level) end end
    for name, pr in pairs(ns.db.members or {}) do
        if type(pr) == "table" and (pr.orx or pr.orl) and isMember(name) and not ns.isMe(name) then
            local ok, lvl = false, nil
            if ns.Rank and ns.Rank.Of then ok, lvl = pcall(ns.Rank.Of, name) end
            consider(name, ok and lvl or pr.orl)
        end
    end
    out[#out + 1] = { icon = ns.ICONS.badges, color = C.violet or C.accent, page = "rank", title = L["Hoechster Oasis-Rang"],
        who = top and top.name, value = top and (L["Oasis-Rang %d"]):format(top.lvl) }
    return out
end

-- Gildenkarte: Kontinent + Position je Mitglied
local CONT = { [1414] = "Kalimdor", [1415] = "Oestliche Koenigreiche" }
local CONT_BY_INST = { [1] = 1414, [0] = 1415 }
local function contOf(mapID)
    local id, guard = mapID, 0
    while id and guard < 8 do
        if CONT[id] then return id end
        local ok, info = pcall(C_Map.GetMapInfo, id)
        id = ok and type(info) == "table" and info.parentMapID or nil
        guard = guard + 1
    end
end
local function vecXY(v)
    if not v then return nil end
    if v.GetXY then local ok, x, y = pcall(v.GetXY, v) if ok and x then return x, y end end
    return v.x, v.y
end
-- Position auf dem Kontinent (0..1) + Kontinent
local function posOnCont(mapID, x, y)
    if not (C_Map and mapID and x and y) then return nil end
    local cont = contOf(mapID)
    if cont and cont == mapID then return x, y, cont end
    if cont and C_Map.GetMapRectOnMap then
        local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, mapID, cont)
        if ok and minX and maxX and maxX > minX and minY and maxY then return minX + x * (maxX - minX), minY + y * (maxY - minY), cont end
    end
    if C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok, inst, wp = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
        cont = cont or CONT_BY_INST[inst]
        if ok and wp and cont then
            local ok2, _, mp = pcall(C_Map.GetMapPosFromWorldPos, inst, wp, cont)
            local cx, cy = vecXY(ok2 and mp or nil)
            if cx then return cx, cy, cont end
        end
    end
end
Info.PosOnCont = posOnCont
Info.CONT = CONT
function Info.MapPoints()
    local pts, count = {}, { [1414] = 0, [1415] = 0 }
    local now = GetTime and GetTime() or 0
    local seen = {}
    local function add(name, mapID, x, y, live)
        if seen[name] then return end
        local cx, cy, cont = posOnCont(mapID, x, y)
        if cx and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
            seen[name] = true
            count[cont] = (count[cont] or 0) + 1
            pts[#pts + 1] = { name = name, x = cx, y = cy, cont = cont, me = live }
        end
    end
    local okMe, me = pcall(ns.me)
    if okMe and me and C_Map and C_Map.GetBestMapForUnit then
        local id = ns.safe(C_Map.GetBestMapForUnit("player"))
        local ok, pos = pcall(C_Map.GetPlayerMapPosition, id, "player")
        local x, y = vecXY(ok and pos or nil)
        if id and x then add(me, id, x, y, true) end
    end
    if ns.Map and type(ns.Map.pos) == "table" then
        for name, p in pairs(ns.Map.pos) do
            if type(p) == "table" and p.mapID and (now - (p.t or 0)) < 300 and (not p.demo or demoOn()) then add(name, p.mapID, p.x, p.y) end
        end
    end
    local best = (count[1415] or 0) > (count[1414] or 0) and 1415 or 1414
    return pts, best, count
end

ns.RegisterPage({
    key = "home", title = "Dashboard", order = 0.5,
    sub = "Alles Wichtige der Gilde auf einen Blick",
    build = function(p)
        p.fresh = true
        p.cells = {}
        -- ganz schwaches Landschaftsbild hinter dem ganzen Dashboard (Media\dash_bg, 2:1)
        -- 0.5.536: fuellt den ganzen Inhaltsbereich des Fensters (bis an die Raender), deutlich sichtbarer,
        -- mit dunklem Verlauf darueber, damit die Karten lesbar bleiben
        local host = p:GetParent() or p
        p.pageBg = p:CreateTexture(nil, "BACKGROUND", nil, -8)
        p.pageBg:SetTexture(ns.MEDIA .. "dash_bg")
        p.pageBg:SetPoint("TOPLEFT", host, "TOPLEFT", -24, 24)
        p.pageBg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 20, -36)   -- 0.5.562: endet innerhalb des Fensters (ragte unten ueber den Rand)
        p.pageBg:SetAlpha(0.28)
        p.pageShade = p:CreateTexture(nil, "BACKGROUND", nil, -7)
        p.pageShade:SetAllPoints(p.pageBg)
        if not K.Gradient(p.pageShade, "VERTICAL", { 0, 0, 0, 0.55 }, { 0, 0, 0, 0.15 }) then p.pageShade:SetColorTexture(0, 0, 0, 0.35) end
        local function fit(self)
            local w, h = self.pageBg:GetWidth(), self.pageBg:GetHeight()
            if not (w and h and w > 0 and h > 0) then return end
            -- Seitenverhaeltnis halten: Bild 2:1 mittig zuschneiden (fuellt immer ganz)
            local r = (w / h) / 2
            if r >= 1 then local c = (1 - 1 / r) / 2 self.pageBg:SetTexCoord(0, 1, c, 1 - c)
            else local c = (1 - r) / 2 self.pageBg:SetTexCoord(c, 1 - c, 0, 1) end
        end
        p:HookScript("OnSizeChanged", fit)
        p:HookScript("OnShow", fit)

        ----------------------------------------------------------------
        -- Helden-Banner
        ----------------------------------------------------------------
        local ban = CreateFrame("Frame", nil, p)
        ban:SetPoint("TOPLEFT")
        ban:SetPoint("TOPRIGHT")
        ban:SetHeight(190)
        ban:SetClipsChildren(true)
        p.ban = ban
        ban.base = ban:CreateTexture(nil, "BACKGROUND", nil, -2)
        ban.base:SetAllPoints()
        if not K.Gradient(ban.base, "HORIZONTAL", { C.accent[1] * 0.35, C.accent[2] * 0.35, C.accent[3] * 0.35, 1 }, { 0.05, 0.05, 0.07, 1 }) then
            ban.base:SetColorTexture(0.08, 0.08, 0.1, 1)
        end
        ban.img = ban:CreateTexture(nil, "BACKGROUND", nil, 0)
        if K.BgImg then K.BgImg(ban.img) end   -- 0.6.227: Helligkeit einstellbar
        ban.img:SetAllPoints()
        -- Abdunklung: unten kraeftig (Text), links fuer die Schrift, Vignette oben/rechts
        local function shade(layer, sub, dir, a, b, pts)
            local t = ban:CreateTexture(nil, layer, nil, sub)
            for _, pt in ipairs(pts) do t:SetPoint(pt[1], pt[2] or 0, pt[3] or 0) end
            if not K.Gradient(t, dir, a, b) then t:SetColorTexture(0, 0, 0, math.max(a[4], b[4]) * 0.5) end
            return t
        end
        -- Bild soll leuchten: nur links ein dezenter Verlauf hinter der Schrift, unten ein kurzer Uebergang,
        -- oben ein Hauch fuer die Kopfzeile. Kein Schleier ueber dem ganzen Bild.
        ban.dimLeft = shade("BORDER", 0, "HORIZONTAL", { 0, 0, 0, 0.62 }, { 0, 0, 0, 0 }, { { "TOPLEFT" }, { "BOTTOMLEFT" } })
        ban.dimLeft:SetWidth(340)
        ban.dimBottom = shade("BORDER", 1, "VERTICAL", { 0.02, 0.02, 0.03, 0.70 }, { 0, 0, 0, 0 }, { { "BOTTOMLEFT" }, { "BOTTOMRIGHT" } })
        ban.dimBottom:SetHeight(46)
        ban.vigTop = shade("BORDER", 1, "VERTICAL", { 0, 0, 0, 0 }, { 0, 0, 0, 0.32 }, { { "TOPLEFT" }, { "TOPRIGHT" } })
        ban.vigTop:SetHeight(34)
        -- Akzentlinie unten mit wanderndem Lichtpunkt
        ban.line = ban:CreateTexture(nil, "ARTWORK")
        ban.line:SetPoint("BOTTOMLEFT") ban.line:SetPoint("BOTTOMRIGHT")
        ban.line:SetHeight(2)
        ban.line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.85)
        ban.spark = ban:CreateTexture(nil, "OVERLAY")
        ban.spark:SetTexture(ns.MEDIA .. "shine")
        ban.spark:SetBlendMode("ADD")
        ban.spark:SetSize(120, 6)
        ban.spark:SetVertexColor(math.min(1, C.accent[1] + 0.4), math.min(1, C.accent[2] + 0.4), math.min(1, C.accent[3] + 0.4))
        ban.line:Hide()   -- keine Akzentlinie unten (der Ticker schliesst das Banner ab)
        -- feiner Lichtrand: abgeschaltet (Kanten unsichtbar), nur noch Halter fuer die Umlaeufer
        local edge = CreateFrame("Frame", nil, ban)
        edge:SetAllPoints()
        edge:EnableMouse(false)
        edge:SetAlpha(0)
        ban.edge = edge
        local GOLD = { 1, 0.82, 0.5 }
        for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
            local t = edge:CreateTexture(nil, "OVERLAY")
            t:SetPoint(e[1]) t:SetPoint(e[2])
            if e[3] then t:SetHeight(1) else t:SetWidth(1) end
            t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.16)
        end
        ban.runners = {}
        for i = 1, 2 do
            local r = edge:CreateTexture(nil, "OVERLAY", nil, 2)
            r:SetTexture(EMBER)
            r:SetBlendMode("ADD")
            r:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
            r:Hide()
            ban.runners[i] = r
        end

        -- Glut-/Lichtpartikel
        local pf = CreateFrame("Frame", nil, ban)
        pf:SetAllPoints()
        pf:EnableMouse(false)
        ban.pf = pf
        ban.dots = {}
        local function emberColor()
            local c = C.accent
            local warm = math.random() * 0.55
            return math.min(1, c[1] + (1 - c[1]) * warm), math.min(1, c[2] + (0.8 - c[2]) * warm * 0.8), math.min(1, c[3] * (1 - warm * 0.5) + 0.1)
        end
        local function resetDot(d, anywhere)
            local w, h = ban:GetWidth() or 760, ban:GetHeight() or 190
            if w < 50 then w = 760 end
            d.x = math.random() * w
            d.y = anywhere and math.random() * h * 0.8 or (-6 - math.random() * 30)
            d.vy = 10 + math.random() * 22
            d.vx = (math.random() - 0.5) * 8
            d.sway, d.phase, d.freq = 2 + math.random() * 8, math.random() * 6.28, 0.6 + math.random() * 1.4
            d.life = 0.6 + math.random() * 0.5
            d.a = 0.35 + math.random() * 0.5
            d.flick = math.random() * 6.28
            local sz = 3 + math.random() * 8
            d.t:SetSize(sz, sz)
            d.t:SetVertexColor(emberColor())
        end
        for i = 1, 30 do
            local t = pf:CreateTexture(nil, "OVERLAY")
            t:SetTexture(i % 4 == 0 and (ns.MEDIA .. "dot") or EMBER)
            t:SetBlendMode("ADD")
            local d = { t = t }
            resetDot(d, true)
            ban.dots[i] = d
        end

        -- Glanz, der ueber das Banner zieht
        local sheen = CreateFrame("Frame", nil, ban)
        sheen:SetSize(220, 10)
        sheen:SetPoint("TOP") sheen:SetPoint("BOTTOM")
        local s1 = sheen:CreateTexture(nil, "OVERLAY")
        s1:SetPoint("TOPLEFT") s1:SetPoint("BOTTOMLEFT") s1:SetWidth(110)
        s1:SetBlendMode("ADD")
        local s2 = sheen:CreateTexture(nil, "OVERLAY")
        s2:SetPoint("TOPRIGHT") s2:SetPoint("BOTTOMRIGHT") s2:SetWidth(110)
        s2:SetBlendMode("ADD")
        local okA = K.Gradient(s1, "HORIZONTAL", { 1, 1, 1, 0 }, { 1, 0.95, 0.85, 0.09 })
        local okB = K.Gradient(s2, "HORIZONTAL", { 1, 0.95, 0.85, 0.09 }, { 1, 1, 1, 0 })
        sheen.ok = okA and okB
        sheen:Hide()
        ban.sheen = sheen

        -- Text links: Gildenname (Logo), Begruessung, Kurzzeile
        local tf = CreateFrame("Frame", nil, ban)
        tf:SetPoint("TOPLEFT") tf:SetPoint("BOTTOMRIGHT")
        tf:SetFrameLevel(pf:GetFrameLevel() + 2)
        ban.tf = tf
        ban.kicker = K.Text(tf, 10, { 1, 1, 1, 0.7 })
        ban.kicker:SetPoint("TOPLEFT", 20, -16)
        ban.kicker:Hide()   -- "OASIS · DASHBOARD" doppelt zum Seitentitel
        ban.kicker.SetText = function() end
        ban.clock = K.Text(tf, 11, { 1, 1, 1, 0.82 }, "RIGHT")
        ban.clock:SetPoint("TOPRIGHT", -18, -14)
        if ban.clock.SetShadowColor then ban.clock:SetShadowColor(0, 0, 0, 0.9) ban.clock:SetShadowOffset(1, -1) end
        ban.line2 = K.Text(tf, 12, { 0.86, 0.86, 0.88 })
        ban.line2:SetPoint("BOTTOMLEFT", 20, 18)
        ban.line2:SetWordWrap(false)
        if ban.line2.SetShadowColor then ban.line2:SetShadowColor(0, 0, 0, 0.9) ban.line2:SetShadowOffset(1, -1) end
        ban.greet = K.Title(tf, 17, C.text)
        ban.greet:SetPoint("BOTTOMLEFT", ban.line2, "TOPLEFT", 0, 6)
        ban.greet:SetWordWrap(false)
        if ban.greet.SetShadowColor then ban.greet:SetShadowColor(0, 0, 0, 0.9) ban.greet:SetShadowOffset(1, -1) end
        -- Gildenname: kleiner und eleganter, weicher Schatten + warmer Schein dahinter
        ban.logoGlow = tf:CreateTexture(nil, "BACKGROUND")
        ban.logoGlow:SetTexture(EMBER)
        ban.logoGlow:SetBlendMode("ADD")
        ban.logoGlow:SetVertexColor(C.accent[1], C.accent[2] * 0.8 + 0.1, C.accent[3] * 0.6 + 0.05)
        ban.logoGlow:SetAlpha(0.28)
        ban.logoShadow = tf:CreateTexture(nil, "BACKGROUND", nil, -1)
        ban.logoShadow:SetTexture(CIRCLE)
        ban.logoShadow:SetVertexColor(0, 0, 0)
        ban.logoShadow:SetAlpha(0.45)
        -- keine Ellipse (Schein/Schatten) hinter dem Logo
        ban.logoGlow:Hide() ban.logoGlow.Show = function() end ban.logoGlow.SetShown = function() end
        ban.logoShadow:Hide() ban.logoShadow.Show = function() end ban.logoShadow.SetShown = function() end
        if ns.GuildLogo then
            local ok, lg = pcall(ns.GuildLogo, tf, 190, 29, true)
            if ok and lg then
                ban.logo = lg
                lg:SetPoint("BOTTOMLEFT", ban.greet, "TOPLEFT", 0, 12)
            end
        end
        if not ban.logo then
            ban.logoText = K.Title(tf, 24, C.accent)
            ban.logoText:SetPoint("BOTTOMLEFT", ban.greet, "TOPLEFT", 0, 10)
            if ban.logoText.SetShadowColor then ban.logoText:SetShadowColor(0, 0, 0, 0.9) ban.logoText:SetShadowOffset(1, -1) end
        end
        local la = ban.logo or ban.logoText
        ban.logoGlow:SetPoint("TOPLEFT", la, "TOPLEFT", -30, 18)
        ban.logoGlow:SetPoint("BOTTOMRIGHT", la, "BOTTOMRIGHT", 30, -18)
        ban.logoShadow:SetPoint("TOPLEFT", la, "TOPLEFT", -40, 26)
        ban.logoShadow:SetPoint("BOTTOMRIGHT", la, "BOTTOMRIGHT", 40, -26)
        -- Lichtstreifen ueber dem Gildennamen
        ban.nameShine = tf:CreateTexture(nil, "OVERLAY", nil, 6)
        ban.nameShine:SetTexture(ns.MEDIA .. "shine")
        ban.nameShine:SetBlendMode("ADD")
        ban.nameShine:SetSize(50, 38)
        ban.nameShine:SetAlpha(0)

        -- 0.6.176: Banner im Ornament-Stil - leuchtender Zierrahmen (wie das Hauptfenster, mit Schimmer),
        -- goldene Raute mit auslaufenden Linien ueber dem Gildennamen, Trennlinie mit Raute darunter
        local GOLD = { 1, 0.78, 0.42 }
        if K.FrameLines then ban.frameLines = K.FrameLines(ban, 12) end
        local function diamond(parent, size, layer)
            local d = parent:CreateTexture(nil, layer or "OVERLAY", nil, 6)
            d:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
            d:SetSize(size, size)
            if d.SetRotation then pcall(d.SetRotation, d, math.pi / 4) end
            return d
        end
        local function hline(parent, w, a1, a2)
            local t = parent:CreateTexture(nil, "OVERLAY", nil, 5)
            t:SetHeight(1) t:SetWidth(w)
            if not K.Gradient(t, "HORIZONTAL", { GOLD[1], GOLD[2], GOLD[3], a1 }, { GOLD[1], GOLD[2], GOLD[3], a2 }) then t:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.4) end
            return t
        end
        do
            local la2 = ban.logo or ban.logoText
            -- Ornament ueber dem Namen: Raute, links/rechts auslaufende Linien, kleiner Schein dahinter
            local orn = CreateFrame("Frame", nil, tf)
            orn:SetSize(120, 14)
            orn:SetPoint("BOTTOM", la2, "TOP", 0, 6)
            orn:SetPoint("LEFT", la2, "LEFT", 0, 0)
            orn.glow = orn:CreateTexture(nil, "ARTWORK")
            orn.glow:SetTexture(EMBER) orn.glow:SetBlendMode("ADD")
            orn.glow:SetVertexColor(GOLD[1], GOLD[2] * 0.8, GOLD[3] * 0.5)
            orn.glow:SetSize(46, 30) orn.glow:SetAlpha(0.45)
            orn.d = diamond(orn, 8)
            orn.d:SetPoint("CENTER", orn, "LEFT", 28, 0)
            orn.glow:SetPoint("CENTER", orn.d)
            orn.dIn = orn:CreateTexture(nil, "OVERLAY", nil, 7)
            orn.dIn:SetColorTexture(0.12, 0.07, 0.04, 1) orn.dIn:SetSize(4, 4)
            if orn.dIn.SetRotation then pcall(orn.dIn.SetRotation, orn.dIn, math.pi / 4) end
            orn.dIn:SetPoint("CENTER", orn.d)
            orn.l = hline(orn, 22, 0, 0.8) orn.l:SetPoint("RIGHT", orn.d, "LEFT", -4, 0)
            orn.r = hline(orn, 70, 0.8, 0) orn.r:SetPoint("LEFT", orn.d, "RIGHT", 4, 0)
            ban.orn = orn
            -- Trennlinie zwischen Name und Begruessung: kleine Raute links, Linie laeuft nach rechts aus
            local div = CreateFrame("Frame", nil, tf)
            div:SetSize(200, 8)
            div:SetPoint("BOTTOMLEFT", ban.greet, "TOPLEFT", -2, 3)
            div.d = diamond(div, 5)
            div.d:SetPoint("LEFT", 0, 0)
            div.l = hline(div, 170, 0.75, 0) div.l:SetPoint("LEFT", div.d, "RIGHT", 4, 0)
            ban.div = div
            -- Name etwas hoeher, damit die Trennlinie Luft hat
            la2:ClearAllPoints()
            la2:SetPoint("BOTTOMLEFT", ban.greet, "TOPLEFT", 0, ban.logo and 16 or 14)
        end
        -- rechts im Banner: der eigene Charakter als 3D-Modell auf einem Lichtkegel
        local stage = CreateFrame("Frame", nil, ban)
        -- Buehne ragt rechts ueber den Bannerrand (wird dort abgeschnitten) -> Figur steht weit rechts
        stage:SetPoint("TOPRIGHT", 34, 0)
        stage:SetPoint("BOTTOMRIGHT", 34, 0)
        stage:SetWidth(150)
        stage:SetFrameLevel(tf:GetFrameLevel() + 1)
        ban.stage = stage
        stage.halo = stage:CreateTexture(nil, "BACKGROUND")
        stage.halo:SetTexture(EMBER)
        stage.halo:SetBlendMode("ADD")
        stage.halo:SetSize(200, 170)
        stage.halo:SetPoint("CENTER", stage, "BOTTOM", 0, 56)
        stage.halo:SetVertexColor(1, 0.72, 0.42)
        stage.halo:SetAlpha(0.22)
        stage.floor = stage:CreateTexture(nil, "BORDER")
        stage.floor:SetTexture(EMBER)   -- weicher, verwischter Schatten statt harter Scheibe
        stage.floor:SetVertexColor(0, 0, 0)
        stage.floor:SetAlpha(0.85)
        stage.floor:SetSize(150, 34)
        stage.floor:SetPoint("CENTER", stage, "BOTTOM", 0, 16)
        stage.ring = stage:CreateTexture(nil, "ARTWORK")
        stage.ring:SetTexture(EMBER)
        stage.ring:SetBlendMode("ADD")
        stage.ring:SetVertexColor(C.accent[1], math.min(1, C.accent[2] + 0.3), math.min(1, C.accent[3] + 0.2))
        stage.ring:SetSize(124, 18)
        stage.ring:SetPoint("CENTER", stage.floor)
        stage.ring:SetAlpha(0.35)
        ban.model = heroModel(stage)
        if ban.model then
            ban.model:SetPoint("TOPLEFT", 0, -22)
            ban.model:SetPoint("BOTTOMRIGHT", 0, 4)
        else
            stage:Hide()
        end

        -- Gildeninfo klein oben rechts unter der Uhr (nur wenn hinterlegt)
        ban.info = K.Button(tf, L["Gildeninfo"], 66, 16, "ghost")
        -- 0.6.176: Info-Symbol rechts im Knopf
        ban.info:SetWidth(82)
        ban.info.ico = ban.info:CreateTexture(nil, "OVERLAY")
        ban.info.ico:SetTexture("Interface\\FriendsFrame\\InformationIcon")
        ban.info.ico:SetSize(11, 11) ban.info.ico:SetPoint("RIGHT", -6, 0)
        ban.info.ico:SetDesaturated(true) ban.info.ico:SetVertexColor(1, 1, 1, 0.85)
        ban.info:SetPoint("RIGHT", ban.clock, "LEFT", -12, 0)
        ban.info:SetFrameLevel(stage:GetFrameLevel() + 3)
        ban.info:SetScript("OnEnter", function(self)
            local t = Info.Text()
            K.ShowTip(self, { L["Gildeninfo"], t ~= "" and t or L["Keine Gildeninfo hinterlegt."] })
        end)
        ban.info:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- unten rechts: Durchsage / Nachricht des Tages als Glas-Kaertchen (nur wenn vorhanden)
        local motd = glassCard(tf)
        motd:SetPoint("BOTTOMRIGHT", -14, 14)
        motd:SetFrameLevel(stage:GetFrameLevel() + 4)
        motd:Hide()
        ban.motd = motd

        -- Held der Woche: zweites Modell auf derselben Buehne, im Wechsel mit dem eigenen Charakter
        local GOLDC = { 1, 0.82, 0.42 }
        ban.hero = heroModel(stage)
        if ban.hero then
            ban.hero:SetPoint("TOPLEFT", 0, -22)
            ban.hero:SetPoint("BOTTOMRIGHT", 0, 4)
            ban.hero.rot = 0.35
            ban.hero:Hide()
        end
        -- Ersatz, wenn kein Modell kommt: Portraet-Kreis in Klassenfarbe
        local hport = CreateFrame("Button", nil, stage)
        hport:SetSize(70, 70)
        hport:SetPoint("CENTER", stage, "CENTER", -17, 8)
        hport.glow = hport:CreateTexture(nil, "BACKGROUND")
        hport.glow:SetTexture(EMBER) hport.glow:SetBlendMode("ADD")
        hport.glow:SetSize(120, 120) hport.glow:SetPoint("CENTER")
        hport.glow:Hide()   -- ruhig: kein Leuchten hinter dem Portraet
        -- weicher Schatten unter dem Kreis (hebt ihn vom Bannerbild ab, ohne zu leuchten)
        hport.shadow = hport:CreateTexture(nil, "BACKGROUND", nil, -1)
        hport.shadow:SetTexture(CIRCLE) hport.shadow:SetVertexColor(0, 0, 0, 0.45)
        hport.shadow:SetSize(78, 78) hport.shadow:SetPoint("CENTER", 0, -2)
        hport.ring = hport:CreateTexture(nil, "BORDER")
        hport.ring:SetTexture(CIRCLE) hport.ring:SetAllPoints()
        hport.inner = hport:CreateTexture(nil, "ARTWORK")
        hport.inner:SetTexture(CIRCLE) hport.inner:SetVertexColor(0.09, 0.09, 0.11)
        hport.inner:SetSize(66, 66) hport.inner:SetPoint("CENTER")
        hport.icon = hport:CreateTexture(nil, "ARTWORK", nil, 1)
        hport.icon:SetSize(36, 36) hport.icon:SetPoint("CENTER")
        hport.letter = K.Title(hport, 26, C.text, "CENTER")
        hport.letter:SetPoint("CENTER")
        hport:SetScript("OnClick", function(self) if self.who and ns.Profile and ns.Profile.Show then ns.Profile.Show(self.who) end end)
        hport:SetScript("OnEnter", function(self) if self.who then K.ShowTip(self, { L["Held der Woche"], ns.Radar.Colored(self.who), self.why or "", "|cff888888" .. L["Klick: Profil"] .. "|r" }) end end)
        hport:SetScript("OnLeave", function() GameTooltip:Hide() end)
        hport:Hide()
        ban.heroPort = hport
        -- Krone ueber dem Kopf + Namensschild am Fuss der Buehne
        local crown = CreateFrame("Frame", nil, stage)
        crown:SetSize(40, 30)
        crown:SetPoint("TOP", stage, "TOP", -17, -18)
        crown:SetFrameLevel(stage:GetFrameLevel() + 6)
        crown.glow = crown:CreateTexture(nil, "BACKGROUND")
        crown.glow:SetTexture(EMBER) crown.glow:SetBlendMode("ADD")
        crown.glow:SetVertexColor(GOLDC[1], GOLDC[2], GOLDC[3])
        crown.glow:SetSize(90, 54) crown.glow:SetPoint("CENTER")
        crown.glow:Hide()
        crown.icon = crown:CreateTexture(nil, "ARTWORK")
        crown.icon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
        crown.icon:SetSize(18, 18) crown.icon:SetPoint("CENTER")
        crown:Hide()
        ban.crown = crown
        local plate = CreateFrame("Button", nil, stage)
        plate:SetSize(200, 40)
        plate:SetPoint("BOTTOM", stage, "BOTTOM", -17, 26)
        plate:SetFrameLevel(stage:GetFrameLevel() + 6)
        -- Namensschild: ruhige dunkle Glasflaeche, Breite folgt dem Text (LoadHero)
        plate:SetHeight(48)
        plate.bg = plate:CreateTexture(nil, "BACKGROUND")
        plate.bg:SetAllPoints()
        plate.bg:SetColorTexture(0.04, 0.04, 0.05, 0.78)
        if not K.ApplySkin(plate, "panel", { 0.04, 0.04, 0.05, 0.78 }) then
            plate.bg:ClearAllPoints() plate.bg:SetPoint("TOPLEFT", 20, 0) plate.bg:SetPoint("BOTTOMRIGHT", -20, 0)
        end
        plate.kick = K.Text(plate, 9, GOLDC, "CENTER")
        plate.kick:SetPoint("TOP", 0, -6)
        plate.kick:SetText(L["Held der Woche"])
        plate.name = K.Title(plate, 14, C.text, "CENTER")
        plate.name:SetPoint("TOP", 0, -17)
        plate.name:SetWidth(180) plate.name:SetWordWrap(false)
        plate.why = K.Text(plate, 9, C.muted, "CENTER")
        plate.why:SetPoint("TOP", 0, -34)
        plate.why:SetWidth(190) plate.why:SetWordWrap(false)
        for _, fs in ipairs({ plate.kick, plate.name, plate.why }) do if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) fs:SetShadowOffset(1, -1) end end
        plate:SetScript("OnClick", function() local h = ban.heroData if h and ns.Profile and ns.Profile.Show then ns.Profile.Show(h.name) end end)
        plate:SetScript("OnEnter", function(self)
            local h = ban.heroData
            if not h then return end
            K.ShowTip(self, { L["Held der Woche"], ns.Radar.Colored(h.name), h.reason or "",
                "|cff888888" .. L["Aktivstes Mitglied der letzten 7 Tage (Level-Ups, Bosse, Beute, Abzeichen)"] .. "|r", "|cff666666" .. L["Klick: Profil"] .. "|r" })
        end)
        plate:SetScript("OnLeave", function() GameTooltip:Hide() end)
        plate:Hide()
        ban.heroPlate = plate

        -- Live-Ticker am unteren Bannerrand (Mausueber haelt an, Klick: Chronik)
        local tk = CreateFrame("Button", nil, ban)
        tk:SetPoint("BOTTOMLEFT", 0, 0)
        tk:SetPoint("BOTTOMRIGHT", 0, 0)
        tk:SetHeight(22)
        tk:SetFrameLevel(stage:GetFrameLevel() + 8)
        tk.bg = tk:CreateTexture(nil, "BACKGROUND")
        tk.bg:SetAllPoints()
        tk.bg:SetColorTexture(0.03, 0.03, 0.04, 0.72)
        tk.top = tk:CreateTexture(nil, "BORDER")
        tk.top:SetPoint("TOPLEFT") tk.top:SetPoint("TOPRIGHT") tk.top:SetHeight(1)
        tk.top:SetColorTexture(1, 1, 1, 0.08)
        tk.chip = tk:CreateTexture(nil, "ARTWORK")
        tk.chip:SetTexture(CIRCLE)
        tk.chip:SetSize(6, 6)
        tk.chip:SetPoint("LEFT", 12, 0)
        tk.chip:SetVertexColor(C.mint[1], C.mint[2], C.mint[3], 1)
        tk.live = K.Text(tk, 10, C.muted, "LEFT")
        tk.live:SetPoint("LEFT", tk.chip, "RIGHT", 6, 0)
        tk.live:SetText(L["Live"])
        tk.clip = CreateFrame("Frame", nil, tk)
        tk.clip:SetPoint("TOPLEFT", 58, 0)
        tk.clip:SetPoint("BOTTOMRIGHT", -6, 0)
        tk.clip:SetClipsChildren(true)
        tk.items, tk.off, tk.n = {}, 0, 0
        -- eigenes OnUpdate in voller Bildrate (die Banner-Animation laeuft gedrosselt mit 30 fps -> ruckelte)
        tk:SetScript("OnUpdate", function(self, el)
            if self.place then self.place(math.min(el, 0.1)) end
        end)
        tk:SetScript("OnEnter", function(self) self.paused = true K.ShowTip(self, { L["Live aus der Gilde"], "|cff888888" .. L["Angehalten - Klick: Chronik"] .. "|r" }) end)
        tk:SetScript("OnLeave", function(self) self.paused = false GameTooltip:Hide() end)
        tk:SetScript("OnClick", function() ns.ShowPage("chronicle") end)
        tk:Hide()
        ban.ticker = tk
        -- Glas/Modern: Banner mit runden Ecken (Bild, Abdunklungen, Ticker an den Ecken abgeschnitten)
        do
            local sk = K.Skin and K.Skin("panel")
            if sk and sk.fill == "round_fill" and K.RoundMask then
                for _, t in ipairs({ ban.base, ban.img, ban.dimLeft, ban.dimBottom, ban.vigTop, tk.bg }) do K.RoundMask(t, ban, 12) end
            end
        end

        -- Willkommen zurueck (einmal je Sitzung, Schreibmaschine) an der Stelle der Kurzzeile
        ban.welcome = K.Text(tf, 12, { 1, 0.9, 0.72 })
        ban.welcome:SetJustifyH("LEFT")
        ban.welcome:SetJustifyV("BOTTOM")
        ban.welcome:SetWordWrap(true)
        ban.welcome:SetHeight(30)
        if ban.welcome.SetShadowColor then ban.welcome:SetShadowColor(0, 0, 0, 1) ban.welcome:SetShadowOffset(1, -1) end
        ban.welcome:Hide()

        ----------------------------------------------------------------
        -- Kachelreihe
        ----------------------------------------------------------------
        p.tiles = {}
        local defs = {
            { ns.ICONS.radar, "Online jetzt", C.mint, "radar" },
            { ns.ICONS.social or ns.ICONS.radar, "Mitglieder", C.blue, "radar" },
            { ns.ICONS.raid, "Naechster Termin", C.accent, "raid" },
            { ns.MEDIA .. "icons\\announce", "Gildennachricht", C.amber, "radar", 2 },   -- doppelt breit
        }
        for i, d in ipairs(defs) do
            local t
            t = K.HudTile(p, d[1], L[d[2]], d[3], function() ns.ShowPage(t.page or d[4]) end)
            t.page = d[4]
            t.dy, t.lift = 0, 0
            local c = d[3]
            -- Wertigkeit: Verlauf in Kachelfarbe, leuchtendes Symbol, Balken-Spur, Hover-Glow, Glanz-Sweep
            t.grad = t:CreateTexture(nil, "BORDER", nil, 1)
            t.grad:SetAllPoints()
            if not K.Gradient(t.grad, "HORIZONTAL", { c[1], c[2], c[3], 0.16 }, { c[1], c[2], c[3], 0.02 }) then t.grad:Hide() end
            t.iconGlow = t:CreateTexture(nil, "BORDER", nil, 2)
            t.iconGlow:SetTexture(EMBER)
            t.iconGlow:SetBlendMode("ADD")
            t.iconGlow:SetSize(58, 58)
            t.iconGlow:SetPoint("CENTER", t.icon)
            t.iconGlow:SetVertexColor(c[1], c[2], c[3])
            t.iconGlow:SetAlpha(0.35)
            t.icon:SetAlpha(1)
            t.track = t:CreateTexture(nil, "ARTWORK", nil, -1)
            t.track:SetPoint("BOTTOMLEFT") t.track:SetPoint("BOTTOMRIGHT")
            t.track:SetHeight(3)
            t.track:SetColorTexture(1, 1, 1, 0.05)
            t.track:Hide()
            t.bar:SetHeight(3)
            t.hov = t:CreateTexture(nil, "BORDER", nil, 3)
            t.hov:SetAllPoints()
            if not K.Gradient(t.hov, "VERTICAL", { c[1], c[2], c[3], 0.22 }, { c[1], c[2], c[3], 0 }) then t.hov:SetColorTexture(c[1], c[2], c[3], 0.08) end
            t.hov:SetAlpha(0)
            t.sweep = t:CreateTexture(nil, "OVERLAY", nil, 5)
            t.sweep:SetTexture(ns.MEDIA .. "shine")
            t.sweep:SetBlendMode("ADD")
            t.sweep:SetSize(46, 64)
            t.sweep:SetAlpha(0)
            local function hover(on)
                local from, to = t.lift or 0, on and 3 or 0
                local g0, g1 = t.hov:GetAlpha() or 0, on and 1 or 0
                if animOn() then
                    K.Tween(t.hov, 0.18, function(q)
                        t.lift = from + (to - from) * q
                        t.hov:SetAlpha(g0 + (g1 - g0) * q)
                        t.iconGlow:SetAlpha(0.35 + 0.35 * (t.hov:GetAlpha() or 0))
                        p:PlaceTile(t)
                    end)
                else
                    t.lift = to
                    t.hov:SetAlpha(g1)
                    t.iconGlow:SetAlpha(on and 0.7 or 0.35)
                    p:PlaceTile(t)
                end
            end
            t:HookScript("OnEnter", function() hover(true) t.icon:SetAlpha(1) end)
            t:HookScript("OnLeave", function() hover(false) t.icon:SetAlpha(1) end)
            t.span = d[5] or 1
            p.tiles[i] = t
        end
        -- Gildennachricht-Kachel: zweizeiliger Text statt Zahl, voller Text im Tooltip
        do
            local t = p.tiles[4]
            t.value:Hide()
            t.sub:Hide()
            t.msg = K.Text(t, 12, C.text)
            t.msg:SetPoint("TOPLEFT", 12, -9)
            t.msg:SetPoint("RIGHT", t.icon, "LEFT", -10, 0)
            t.msg:SetJustifyH("LEFT")
            t.msg:SetJustifyV("TOP")
            t.msg:SetWordWrap(true)
            if t.msg.SetMaxLines then t.msg:SetMaxLines(2) end
            t.msg:SetHeight(30)
            t:SetScript("OnClick", function(self) ns.ShowPage(self.page or "radar") end)
        end
        -- Glanz-Sweep ueber eine Kachel (beim Oeffnen nacheinander)
        function p:SweepTile(t, delay)
            if not animOn() then return end
            local w = t:GetWidth() or 140
            if w < 40 then w = 140 end
            K.Tween(t.sweep, 0.7, function(q)
                t.sweep:ClearAllPoints()
                t.sweep:SetPoint("CENTER", t, "LEFT", 20 + (w - 40) * q, 0)
                t.sweep:SetAlpha(0.55 * math.sin(q * math.pi))
            end, function() t.sweep:SetAlpha(0) end, delay)
        end

        ----------------------------------------------------------------
        -- Spalte 1: Wer ist online
        ----------------------------------------------------------------
        local online = box(p, L["Wer ist online"], C.mint)
        online.head:Live(true)
        -- 0.6.177: Hintergrundbild (naechtliche Oase mit eigenem Zierrahmen, Gildenmodul) - gestreckt auf die Box,
        -- die eigene Kante der Box tritt zurueck, damit es keinen Doppelrahmen gibt
        if ns.GuildPack then
            online.art = online:CreateTexture(nil, "BACKGROUND", nil, 2)
            if K.BgImg then K.BgImg(online.art) end   -- 0.6.227: Helligkeit einstellbar
            online.art:SetAllPoints()
            online.art:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\online_bg")
            if K.RoundMask then pcall(K.RoundMask, online.art, online, 8) end
            if online.bg then online.bg:SetAlpha(0) end
            if online.borders then for _, b in ipairs(online.borders) do b:SetAlpha(0) end end
            if online.skinLine then for _, b in ipairs(online.skinLine) do b:SetAlpha(0) end end
        end
        -- 0.5.778: Discord Voice rechtsbuendig in der Kopfzeile (vor dem Trennstrich zum Helden der Woche), mit Symbol, ohne Rahmen
        online.voice = CreateFrame("Button", nil, online)
        online.voice:SetHeight(16)
        online.voice:SetPoint("TOPRIGHT", online, "TOPRIGHT", -12, -10)   -- 0.6.171: Held/Pechvogel in eigener Box
        online.voice.label = K.Text(online.voice, 10, C.muted, "RIGHT")
        online.voice.label:SetPoint("RIGHT", 0, 0)
        online.voice.icon = online.voice:CreateTexture(nil, "ARTWORK")
        online.voice.icon:SetSize(12, 12)
        online.voice.icon:SetTexture(ns.MEDIA .. "icons\\speaker")
        online.voice.icon:SetVertexColor(0.45, 0.52, 0.95)   -- Discord-Blau
        online.voice.icon:SetPoint("RIGHT", online.voice.label, "LEFT", -5, 0)
        online.voice:SetScript("OnEnter", function(self)
            local ln = ns.Discord and ns.Discord.Tip and ns.Discord.Tip()
            if ln then K.ShowTip(self, ln) end
        end)
        online.voice:SetScript("OnLeave", function() GameTooltip:Hide() end)
        local function updVoice()
            local line = ns.Discord and ns.Discord.Line and ns.Discord.Line() or ""
            online.voice.label:SetText(line)
            online.voice:SetWidth(line ~= "" and ((online.voice.label:GetStringWidth() or 100) + 20) or 10)
            online.voice:SetShown(line ~= "")
        end
        updVoice()
        ns.Listen("DISCORD_VOICE", function() pcall(updVoice) end)
        ns.Every(30, function() if online:IsVisible() then pcall(updVoice) end end)
        online.grid = CreateFrame("Frame", nil, online)
        online.grid:SetPoint("TOPLEFT", 8, -38)
        online.grid:SetPoint("BOTTOMRIGHT", -8, 6)
        -- rechts: Held der Woche <-> Pechvogel der Woche, blenden alle 8 s ineinander ueber
        -- 0.6.171: eigene Box neben "Wer ist online" (vorher im selben Kasten mit Trennstrich)
        local spotBox = K.Panel(p, C.panel)
        if spotBox.bg then spotBox.bg:SetAlpha(0.8) end
        spotBox:Hide()
        p.spotBox = spotBox
        local sp = CreateFrame("Button", nil, spotBox)
        sp:SetPoint("TOPLEFT", 1, -1)
        sp:SetPoint("BOTTOMRIGHT", -1, 1)
        sp.div = sp:CreateTexture(nil, "ARTWORK")   -- Trennstrich entfaellt (eigene Box), bleibt als leeres Objekt
        sp.div:Hide()
        -- 0.6.171: Stil wie eine Karte - Kopfzeile mit Symbol, Bild rechts (nur Pechvogel, Gildenmodul), nach links
        -- dunkel auslaufend; Klassenring links, Name gross in Gold, darunter der Grund
        local ART_W, ART_H = 1024, 356   -- Bildteil in unlucky_bg.tga (1024x512)
        local function layer()
            local f = CreateFrame("Frame", nil, sp)
            f:SetAllPoints()
            f.art = f:CreateTexture(nil, "BACKGROUND", nil, 1)
            if K.BgImg then K.BgImg(f.art) end   -- 0.6.227: Helligkeit einstellbar
            f.art:SetAllPoints()
            f.art:Hide()
            f.shade = f:CreateTexture(nil, "BACKGROUND", nil, 2)
            f.shade:SetAllPoints()
            if not K.Gradient(f.shade, "HORIZONTAL", { 0.04, 0.04, 0.05, 0.96 }, { 0.04, 0.04, 0.05, 0.05 }) then f.shade:SetColorTexture(0, 0, 0, 0.5) end
            f.shade:Hide()
            if K.RoundMask then pcall(K.RoundMask, f.art, spotBox, 8) pcall(K.RoundMask, f.shade, spotBox, 8) end
            function f:FitArt()
                local w, h = self:GetWidth() or 0, self:GetHeight() or 0
                if w <= 0 or h <= 0 then return end
                local aw, ah, th = self.artW or ART_W, self.artH or ART_H, self.artTH or 512
                local r = (w / h) / (aw / ah)
                local v1 = ah / th
                if r >= 1 then
                    local cut = (1 - 1 / r) / 2 * v1
                    self.art:SetTexCoord(0, 1, cut, v1 - cut)
                else
                    self.art:SetTexCoord((1 - r) / 2, 1 - (1 - r) / 2, 0, v1)
                end
            end
            f:SetScript("OnSizeChanged", function(self) self:FitArt() end)
            f.headIcon = f:CreateTexture(nil, "ARTWORK")
            f.headIcon:SetSize(13, 13) f.headIcon:SetPoint("TOPLEFT", 12, -11)
            f.kick = K.Text(f, 10, C.text)
            f.kick:SetPoint("LEFT", f.headIcon, "RIGHT", 6, 0)
            if f.kick.SetSpacing then pcall(f.kick.SetSpacing, f.kick, 0) end
            f.ring = f:CreateTexture(nil, "BORDER")
            f.ring:SetTexture(CIRCLE) f.ring:SetSize(56, 56) f.ring:SetPoint("TOPLEFT", 12, -36)
            f.inner = f:CreateTexture(nil, "ARTWORK")
            f.inner:SetTexture(CIRCLE) f.inner:SetVertexColor(0.08, 0.08, 0.1) f.inner:SetSize(52, 52) f.inner:SetPoint("CENTER", f.ring)
            f.icon = f:CreateTexture(nil, "ARTWORK", nil, 1)
            f.icon:SetSize(30, 30) f.icon:SetPoint("CENTER", f.ring)
            -- 0.6.173: Ornament-Ring als Badge-Rahmen ums Klassensymbol (Gildenmodul); Innenradius ~70 % des Bildes
            if ns.GuildPack then
                f.frame = f:CreateTexture(nil, "OVERLAY", nil, 2)
                f.frame:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\badge_ring")
                -- 0.6.174: kleiner (56), Klassensymbol fuellt die Oeffnung (~70 % = 40)
                f.frame:SetSize(56, 56) f.frame:SetPoint("CENTER", f.ring)
                f.ring:SetAlpha(0)   -- Rahmen kommt aus dem Bild
                f.inner:SetSize(40, 40)
                f.icon:SetSize(36, 36)   -- 0.6.178: ohne Maske (zeigte sonst das ganze Klassenblatt), Ecken liegen unter dem Ring
            end
            f.badge = f:CreateTexture(nil, "OVERLAY")
            f.badge:SetSize(16, 16) f.badge:SetPoint("CENTER", f.ring, "TOPRIGHT", -6, -6)
            f.badge:Hide()
            f.name = K.Title(f, 17, { 1, 0.84, 0.45 })
            f.name:SetPoint("TOPLEFT", f.ring, "TOPRIGHT", 12, -8)
            f.name:SetPoint("RIGHT", f, "RIGHT", -10, 0)
            f.name:SetWordWrap(false)
            f.whyIcon = f:CreateTexture(nil, "ARTWORK")
            f.whyIcon:SetSize(11, 11) f.whyIcon:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -7)
            f.whyIcon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
            f.why = K.Text(f, 10, C.text)
            f.why:SetPoint("LEFT", f.whyIcon, "RIGHT", 5, 0)
            f.why:SetPoint("RIGHT", f, "RIGHT", -10, 0)
            f.why:SetWordWrap(false)
            f:SetAlpha(0)
            return f
        end
        sp.a, sp.b = layer(), layer()
        sp.dots = {}
        for i = 1, 2 do
            local d = sp:CreateTexture(nil, "OVERLAY")
            d:SetTexture(CIRCLE) d:SetSize(5, 5)
            d:SetPoint("BOTTOMRIGHT", -4 - (2 - i) * 9, 2)
            sp.dots[i] = d
        end
        local KINDS = {
            -- art: Bild im Gildenmodul, w/h = Bildteil, th = Texturhoehe (0.6.310: Held vorerst mit online_bg)
            hero = { kick = "Held der Woche", col = { 1, 0.82, 0.42 }, badge = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
                     art = "online_bg", w = 1024, h = 256, th = 256 },
            unl = { kick = "Pechvogel der Woche", col = { 0.55, 0.7, 1 }, badge = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
                    art = "unlucky_bg", w = ART_W, h = ART_H, th = 512 },
        }
        function sp:Fill(f, it)
            local k = KINDS[it.kind]
            local kt = L[k.kick]
            f.kick:SetText(K.Upper and K.Upper(kt) or kt:upper())
            f.headIcon:SetTexture(k.badge)
            f.whyIcon:SetTexture(k.badge)
            f.badge:SetTexture(k.badge)
            -- Bild je Art (nur mit Gildenmodul)
            local art = k.art and ns.GuildPack
            if art then
                f.artW, f.artH, f.artTH = k.w, k.h, k.th
                f.art:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\" .. k.art)
                f:FitArt()
            end
            f.art:SetShown(art and true or false)
            f.shade:SetShown(art and true or false)
            local cls = ns.Radar.ClassOf and ns.Radar.ClassOf(it.name)
            local cr, cg, cb = ns.classColor(cls)
            f.ring:SetVertexColor(cr or 0.8, cg or 0.8, cb or 0.8)
            -- 0.6.173: Ornament-Ring in Klassenfarbe (Bild ist graustufig, Farbe kommt per Vertexfarbe)
            if f.frame then f.frame:SetVertexColor(cr or 0.85, cg or 0.85, cb or 0.85) end
            f.name:SetText(ns.Radar.Colored(it.name))
            f.why:SetText(it.reason or "")
            if not setClassIcon(f.icon, cls) then f.icon:SetTexture(nil) end
        end
        function sp:SetData(list)
            self.list = list
            self.idx = 1
            self.t = 0
            self:SetShown(#list > 0)
            if p.spotBox then p.spotBox:SetShown(#list > 0 and p.online:IsShown()) end
            for i, d in ipairs(self.dots) do d:SetShown(#list > 1) end
            if #list > 0 then
                self:Fill(self.a, list[1])
                self.a:SetAlpha(1) self.b:SetAlpha(0)
                self.front = self.a
            end
            self:Dots()
        end
        function sp:Dots()
            for i, d in ipairs(self.dots) do
                local on = i == self.idx
                d:SetVertexColor(1, 1, 1, on and 0.8 or 0.25)
            end
        end
        sp:SetScript("OnUpdate", function(self, el)
            local l = self.list
            if not l or #l < 2 then return end
            self.t = self.t + el
            if self.fade then
                local q = math.min(1, (self.t) / 0.6)
                self.front:SetAlpha(1 - q)
                self.back:SetAlpha(q)
                if q >= 1 then self.front, self.back, self.fade = self.back, nil, nil self.t = 0 end
                return
            end
            if self.t >= 8 then
                self.idx = self.idx % #l + 1
                self.back = (self.front == self.a) and self.b or self.a
                self:Fill(self.back, l[self.idx])
                self:Dots()
                if ns.db and ns.db.settings.noAnim then
                    self.front:SetAlpha(0) self.back:SetAlpha(1)
                    self.front, self.back = self.back, nil
                    self.t = 0
                else
                    self.fade, self.t = true, 0
                end
            end
        end)
        sp:SetScript("OnClick", function(self)
            local it = self.list and self.list[self.idx]
            if it and ns.Profile and ns.Profile.Show then ns.Profile.Show(it.name) end
        end)
        sp:SetScript("OnEnter", function(self)
            local it = self.list and self.list[self.idx]
            if not it then return end
            local hint = it.kind == "hero" and L["Aktivstes Mitglied der letzten 7 Tage (Level-Ups, Bosse, Beute, Abzeichen)"] or L["Die meisten Tode der letzten 7 Tage"]
            K.ShowTip(self, { L[KINDS[it.kind].kick], ns.Radar.Colored(it.name), it.reason or "", "|cff888888" .. hint .. "|r", "|cff666666" .. L["Klick: Profil"] .. "|r" })
        end)
        sp:SetScript("OnLeave", function() GameTooltip:Hide() end)
        sp:Hide()
        online.spot = sp
        online.empty = emptyState(online, ns.ICONS.radar, C.mint, L["Gerade niemand online."],
            { { "Gildenchat", "chat" }, { "Mitglieder", "radar" } })
        p.online = online

        ----------------------------------------------------------------
        -- Spalte 2: Was gerade passiert (+ Wochenaufgaben)
        ----------------------------------------------------------------
        local feed = box(p, L["Was gerade passiert"], C.violet or C.accent)
        feed.head:Live(true)
        -- 0.6.180: Zeilen wie in der Vorlage - Zeit links, Symbol, Text, Pfeil rechts, feine Trennlinie
        feed.list = K.List(feed, 40, function(l)   -- 0.6.181: 40 statt 34, ruhiger
            local r = K.Row(l)
            if r.stripe then r.stripe:SetAlpha(0) end   -- keine Streifen, nur feine Trennlinien
            r.bar = r:CreateTexture(nil, "ARTWORK")
            r.bar:SetPoint("LEFT", 4, 0)
            r.bar:SetSize(2, 18)
            r.bar:SetAlpha(0.7)
            r.pulse = r:CreateTexture(nil, "BACKGROUND", nil, 1)
            r.pulse:SetAllPoints()
            r.pulse:SetColorTexture(1, 1, 1, 0.06)
            r.pulse:Hide()
            r.cols.when = K.Text(r, 9, C.dim)
            r.cols.when:SetPoint("LEFT", 14, 0)
            r.cols.when:SetWidth(56)
            r.cols.when:SetJustifyH("LEFT")
            r.cols.when:SetWordWrap(false)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(24, 24)
            r.icon:SetPoint("LEFT", 74, 0)
            r.chev = K.Text(r, 12, C.dim, "RIGHT")
            r.chev:SetPoint("RIGHT", -12, 0)
            r.chev:SetAlpha(0.6)
            r.chev:SetText(">")
            r.cols.text = K.Text(r, 12, C.text)
            r.cols.text:SetPoint("LEFT", 110, 0)
            r.cols.text:SetPoint("RIGHT", r.chev, "LEFT", -12, 0)
            r.cols.text:SetWordWrap(false)
            r.sep = r:CreateTexture(nil, "BORDER")
            r.sep:SetHeight(1)
            r.sep:SetPoint("BOTTOMLEFT", 14, 0) r.sep:SetPoint("BOTTOMRIGHT", -14, 0)
            r.sep:SetColorTexture(1, 1, 1, 0.045)
            r:SetScript("OnClick", function() ns.ShowPage("chronicle") end)
            r:SetScript("OnEnter", function(self) if self.full then K.ShowTip(self, { self.full, self.cols.when:GetText() or "" }) end end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, e, idx)
            local c = KIND_COLOR[e.kind] or C.muted
            r.bar:SetColorTexture(c[1], c[2], c[3], 1)
            local item = ns.Chronicle and ns.Chronicle.Item(e)
            local itemID = item and ns.itemID(item)
            local iconTex = itemID and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
            local lvlBadge = e.kind == "level" and not e.rank and ns.LevelBadges and ns.LevelBadges.Exact(tonumber(e.lvl or e.a1), true)
            if iconTex then
                r.icon:SetTexture(iconTex)
                r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                r.icon:SetVertexColor(1, 1, 1)
            elseif lvlBadge then
                -- 0.5.571: Stufe 10/20/.../60 -> Stufen-Abzeichen
                r.icon:SetTexture(lvlBadge)
                r.icon:SetTexCoord(0, 1, 0, 1)
                r.icon:SetVertexColor(1, 1, 1)
            else
                r.icon:SetTexture(ns.ICONS[KIND_ICON[e.kind] or "chronicle"])
                r.icon:SetTexCoord(0, 1, 0, 1)
                r.icon:SetVertexColor(c[1], c[2], c[3])
            end
            local txt = ns.Radar.Label(e.who) .. " " .. (e.mergedText or (ns.Chronicle and ns.Chronicle.Text(e)) or "") .. ((not e.mergedText and item) and (" " .. item) or "")
            r.full = txt
            r.cols.text:SetText(txt)
            local ago = ns.ago(e.ts) or ""
            r.cols.when:SetText((ago:gsub("^%l", string.upper)))
            -- Neuestes (letzte Stunde) leuchtet sanft
            r.pulse:SetShown(idx == 1 and (ns.now() - (e.ts or 0)) < 3600)
            p.pulseTex = idx == 1 and r.pulse or p.pulseTex
            if p.fresh and animOn() then K.FadeIn(r, 0.5 + (idx or 1) * 0.06) end
        end)
        feed.list.empty:SetText("")
        feed.empty = emptyState(feed, ns.ICONS.chronicle or ns.ICONS.home, C.violet or C.accent, L["Noch nichts passiert - zieht los und schreibt Geschichte!"],
            { { "Gruppe suchen", "groups" }, { "Gildenchat", "chat" } })

        ----------------------------------------------------------------
        -- Gilden-Highlight (unten links): Wochenaufgaben der Gilde
        ----------------------------------------------------------------
        local hl = box(p, L["Gilden-Highlight"], C.amber)
        p.hl = hl
        hl.glow = hl:CreateTexture(nil, "BORDER")
        hl.glow:SetAllPoints()
        if not K.Gradient(hl.glow, "HORIZONTAL", { C.amber[1], C.amber[2], C.amber[3], 0.07 }, { C.amber[1], C.amber[2], C.amber[3], 0 }) then hl.glow:Hide() end
        hl.glow:Hide()   -- ruhig: kein farbiger Schleier ueber der Karte
        hl.week = K.Text(hl, 10, C.muted, "RIGHT")
        hl.week:SetPoint("TOPRIGHT", -12, -15)
        hl.week:SetWordWrap(false)
        hl.empty = emptyState(hl, ns.ICONS.rank or ns.ICONS.badges, C.amber, L["Diese Woche ist noch alles offen - wer macht den Anfang?"],
            { { "Termin anlegen", "raid" }, { "Gruppe suchen", "groups" } })
        local wk = CreateFrame("Button", nil, hl)
        wk:SetPoint("TOPLEFT", 12, -34)
        wk:SetPoint("BOTTOMRIGHT", -12, 8)
        wk:SetScript("OnClick", function() ns.ShowPage("rank") end)
        wk:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
        wk:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Kopf/Restzeit stehen im Kartenkopf (hl.week); die drei Aufgaben nebeneinander als Spalten
        wk.head = K.Text(wk, 10, C.amber)
        wk.head:Hide()
        wk.left = K.Text(wk, 9, C.dim, "RIGHT")
        wk.left:Hide()
        wk.rows = {}
        -- je Aufgabe eine Zeile in voller Breite: Haken-Punkt | Text | kleine Leiste | Stand
        for i = 1, 3 do
            local r = CreateFrame("Frame", nil, wk)
            r:SetHeight(20)
            r.dot = r:CreateTexture(nil, "ARTWORK")
            r.dot:SetTexture(CIRCLE)
            r.dot:SetSize(7, 7)
            r.dot:SetPoint("LEFT", 2, 0)
            r.n = K.Text(r, 10, C.muted, "RIGHT")
            r.n:SetPoint("RIGHT", 0, 0)
            r.n:SetWidth(52)
            r.track = r:CreateTexture(nil, "ARTWORK")
            r.track:SetColorTexture(1, 1, 1, 0.08)
            r.track:SetSize(80, 3)
            r.track:SetPoint("RIGHT", r.n, "LEFT", -8, 0)
            r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.fill:SetHeight(3)
            r.fill:SetPoint("LEFT", r.track, "LEFT")
            r.t = K.Text(r, 11, C.text)
            r.t:SetPoint("LEFT", 16, 0)
            r.t:SetPoint("RIGHT", r.track, "LEFT", -12, 0)
            r.t:SetWordWrap(false)
            -- vollstaendiger Text als Tooltip, falls er doch gekuerzt wird
            r:EnableMouse(true)
            r:SetScript("OnEnter", function(self) if self.full then K.ShowTip(self, { self.full, self.state }) end end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnMouseUp", function() ns.ShowPage("rank") end)
            wk.rows[i] = r
        end
        hl.wk = wk
        feed.wk = wk
        feed.list:SetPoint("TOPLEFT", 8, -46)
        feed.list:SetPoint("BOTTOMRIGHT", -8, 10)
        p.feed = feed

        -- Reiter-Chips rechts im Kartenkopf: defs = { { key, "Text" }, ... }
        local function tabChips(bx, defs, onPick)
            bx.chips = {}
            local prev
            for i = #defs, 1, -1 do
                local d = defs[i]
                local b = CreateFrame("Button", nil, bx)
                b:SetHeight(16)
                b.key = d[1]
                b.bg = b:CreateTexture(nil, "BACKGROUND")
                b.bg:SetAllPoints()
                b.bg:SetColorTexture(1, 1, 1, 0.05)
                b.t = K.Text(b, 9, C.muted, "CENTER")
                b.t:SetPoint("CENTER")
                b.t:SetText(K.Upper(L[d[2]]))
                local w = tonumber(b.t:GetStringWidth()) or 0
                if w <= 0 then w = #d[2] * 6 end
                b:SetWidth(math.floor(w + 14))
                -- Glas/Modern: schlichte Textreiter, aktiver mit feiner Unterstreichung (keine Kaesten)
                local sk = K.Skin and K.Skin("button")
                if sk and sk.fill == "round_fill" then
                    b.plain = true
                    b.bg:Hide()
                    b.t:SetText(L[d[2]])
                    w = tonumber(b.t:GetStringWidth()) or 0
                    if w <= 0 then w = #d[2] * 6 end
                    b:SetSize(math.floor(w + 4), 18)
                    b.line = b:CreateTexture(nil, "ARTWORK")
                    b.line:SetHeight(2)
                    b.line:SetPoint("BOTTOMLEFT", 0, 0)
                    b.line:SetPoint("BOTTOMRIGHT", 0, 0)
                    b.line:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                    b.line:Hide()
                end
                if prev then b:SetPoint("RIGHT", prev, "LEFT", b.plain and -12 or -3, 0) else b:SetPoint("TOPRIGHT", bx, "TOPRIGHT", b.plain and -14 or -10, b.plain and -11 or -13) end
                b:SetScript("OnClick", function() onPick(d[1], true) end)
                b:SetScript("OnEnter", function(self)
                    if self.plain then self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) return end
                    self.bg:SetColorTexture(1, 1, 1, 0.14)
                end)
                b:SetScript("OnLeave", function() bx:MarkChips(bx.tab) end)
                bx.chips[#bx.chips + 1] = b
                prev = b
            end
            -- Ueberschrift der Karte nie unter die Reiter laufen lassen (gekuerzt), Zaehler/Live-Punkt weg
            if bx.head and bx.head.text and prev then
                bx.head.text:SetWordWrap(false)
                bx.head.text:SetPoint("RIGHT", prev, "LEFT", -8, 0)
                if bx.head.count then bx.head.count:Hide() end
                bx.head.SetCount = function() end
                if bx.head.dot then bx.head.dot:Hide() end
                bx.head.Live = function() end
            end
            function bx:MarkChips(key)
                for _, b in ipairs(self.chips) do
                    local on = b.key == key
                    if b.plain then b.line:SetShown(on) else b.bg:SetColorTexture(1, 1, 1, on and 0.16 or 0.05) end
                    local c = on and C.text or C.muted
                    b.t:SetTextColor(c[1], c[2], c[3])
                end
            end
        end
        tabChips(feed, { { "feed", "Live" }, { "map", "Karte" }, { "pulse", "Puls" } }, function(k) p:SetFeedTab(k) end)

        -- Gildenkarte (Kontinent mit den meisten Mitgliedern, Punkte in Klassenfarbe)
        local mapF = CreateFrame("Frame", nil, feed)
        mapF:SetPoint("TOPLEFT", 8, -38)
        mapF:SetPoint("BOTTOMRIGHT", -8, 8)
        mapF:SetClipsChildren(true)
        mapF.bg = mapF:CreateTexture(nil, "BACKGROUND")
        mapF.bg:SetAllPoints()
        mapF.bg:SetColorTexture(0.03, 0.04, 0.06, 0.85)
        mapF.art = CreateFrame("Frame", nil, mapF)
        mapF.art:SetClipsChildren(true)
        mapF.art.bg = mapF.art:CreateTexture(nil, "BACKGROUND")
        mapF.art.bg:SetAllPoints()
        if not K.Gradient(mapF.art.bg, "VERTICAL", { 0.10, 0.12, 0.15, 1 }, { 0.16, 0.18, 0.22, 1 }) then mapF.art.bg:SetColorTexture(0.12, 0.14, 0.17, 1) end
        mapF.art.big = K.Title(mapF.art, 16, { 1, 1, 1, 0.14 }, "CENTER")
        mapF.art.big:SetPoint("CENTER")
        mapF.tiles = {}
        mapF.dots = {}
        mapF.label = K.Text(mapF, 9, C.muted)
        mapF.label:SetPoint("BOTTOMLEFT", 6, 4)
        mapF.label:SetPoint("RIGHT", -6, 0)
        mapF.label:SetWordWrap(false)
        if mapF.label.SetShadowColor then mapF.label:SetShadowColor(0, 0, 0, 1) mapF.label:SetShadowOffset(1, -1) end
        mapF.none = K.Text(mapF, 11, C.muted, "CENTER")
        mapF.none:SetPoint("LEFT", 14, 0) mapF.none:SetPoint("RIGHT", -14, 0)
        mapF.none:SetWordWrap(true)
        mapF.none:SetText(L["Noch keine Positionen - die Karte fuellt sich, sobald Mitglieder mit Oasis unterwegs sind."])
        mapF:Hide()
        feed.mapF = mapF

        -- Gilden-Puls: heute (hell) gegen typischen Tag (Schatten)
        local pulseF = CreateFrame("Frame", nil, feed)
        pulseF:SetPoint("TOPLEFT", 8, -38)
        pulseF:SetPoint("BOTTOMRIGHT", -8, 8)
        pulseF.peak = K.Text(pulseF, 11, C.text)
        pulseF.peak:SetPoint("TOPLEFT", 2, -1)
        pulseF.peak:SetPoint("RIGHT", -2, 0)
        pulseF.peak:SetWordWrap(false)
        pulseF.sub = K.Text(pulseF, 9, C.muted)
        pulseF.sub:SetPoint("TOPLEFT", 2, -16)
        pulseF.sub:SetPoint("RIGHT", -2, 0)
        pulseF.sub:SetWordWrap(false)
        pulseF.chart = CreateFrame("Frame", nil, pulseF)
        pulseF.chart:SetPoint("TOPLEFT", 2, -32)
        pulseF.chart:SetPoint("BOTTOMRIGHT", -2, 12)
        pulseF.base = pulseF.chart:CreateTexture(nil, "BORDER")
        pulseF.base:SetPoint("BOTTOMLEFT") pulseF.base:SetPoint("BOTTOMRIGHT") pulseF.base:SetHeight(1)
        pulseF.base:SetColorTexture(1, 1, 1, 0.12)
        pulseF.bars = {}
        for k = 0, 47 do
            local t1 = pulseF.chart:CreateTexture(nil, "ARTWORK", nil, 0)
            t1:SetColorTexture(1, 1, 1, 0.09)
            local t2 = pulseF.chart:CreateTexture(nil, "ARTWORK", nil, 1)
            pulseF.bars[k] = { typ = t1, day = t2 }
        end
        pulseF.nowLine = pulseF.chart:CreateTexture(nil, "OVERLAY")
        pulseF.nowLine:SetWidth(1)
        pulseF.nowLine:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
        pulseF.nowGlow = pulseF.chart:CreateTexture(nil, "OVERLAY", nil, 1)
        pulseF.nowGlow:SetTexture(EMBER) pulseF.nowGlow:SetBlendMode("ADD")
        pulseF.nowGlow:SetSize(16, 16)
        pulseF.nowGlow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        pulseF.axis = {}
        for i, h in ipairs({ 0, 6, 12, 18 }) do
            local a = K.Text(pulseF, 8, C.dim)
            a:SetText(h .. ":00")
            pulseF.axis[i] = { fs = a, slot = h * 2 }
        end
        pulseF:EnableMouse(true)
        pulseF:SetScript("OnEnter", function(self)
            local d = self.data
            if not d then return end
            K.ShowTip(self, { L["Gilden-Puls"], d.peak and (L["Stosszeit %s Uhr"]):format(d.peak) or "",
                (L["Heute bis zu %d gleichzeitig online"]):format(d.dayMax or 0),
                "|cff888888" .. L["Hell: heute  ·  Schatten: typischer Tag (Spielzeit-Statistik)"] .. "|r" })
        end)
        pulseF:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pulseF:Hide()
        feed.pulseF = pulseF

        ----------------------------------------------------------------
        -- Untere Karte mit Reitern (wechselt von selbst): Countdown, Wochenaufgaben, Tagesziel, Rekorde
        ----------------------------------------------------------------
        hl.week:Hide()
        -- Gildennachricht immer zuerst; Tagesziel + Rekorde sind ins Profil gewandert
        hl.order = { "motd", "count", "tasks" }
        hl.heads = {}
        hl.avail = { tasks = true }
        tabChips(hl, { { "motd", "Nachricht" }, { "count", "Countdown" }, { "tasks", "Aufgaben" } },
            function(k) hl.rotT = -45 p:SetHlTab(k) end)
        -- Ueberschrift darf nicht unter die Reiter laufen: Breite bis vor den linken Reiter, sonst gekuerzt;
        -- Zaehler rechts neben dem Titel entfaellt hier (steht in der Karte selbst)
        local function page()
            local f = CreateFrame("Button", nil, hl)
            f:SetPoint("TOPLEFT", 12, -34)
            f:SetPoint("BOTTOMRIGHT", -12, 8)
            f:Hide()
            return f
        end
        -- Gildennachricht: Symbolkachel (pulsiert bei neuer Nachricht), Kopfzeile + Nachricht, Knoepfe rechts
        local mo = page()
        local RED = C.red or { 0.9, 0.25, 0.28 }
        mo.box = CreateFrame("Frame", nil, mo)
        mo.box:SetAllPoints()
        mo.box:SetSize(300, 50)
        mo.box.bg = mo.box:CreateTexture(nil, "BACKGROUND")
        mo.box.bg:SetAllPoints()
        if K.ApplySkin and K.ApplySkin(mo.box, "panel", { 0.10, 0.04, 0.05, 0.85 }, { RED[1], RED[2], RED[3], 0.45 }) then
            mo.box.bg:Hide()
        else
            mo.box.bg:SetColorTexture(0.10, 0.04, 0.05, 0.85)
            K.Border(mo.box, { RED[1], RED[2], RED[3], 0.45 })
        end
        -- roter Verlauf von links (hinter der Kachel kraeftig, nach rechts auslaufend)
        mo.box.tint = mo.box:CreateTexture(nil, "BORDER")
        mo.box.tint:SetPoint("TOPLEFT", 2, -2) mo.box.tint:SetPoint("BOTTOMLEFT", 2, 2)
        mo.box.tint:SetWidth(260)
        if not K.Gradient(mo.box.tint, "HORIZONTAL", { RED[1], RED[2], RED[3], 0.22 }, { RED[1], RED[2], RED[3], 0 }) then mo.box.tint:SetColorTexture(RED[1], RED[2], RED[3], 0.08) end
        if K.RoundMask then K.RoundMask(mo.box.tint, mo.box, 12) end
        -- Symbolkachel
        mo.tile = CreateFrame("Frame", nil, mo.box)
        mo.tile:SetSize(36, 36)
        mo.tile:SetPoint("LEFT", 10, 0)
        mo.tile.bg = mo.tile:CreateTexture(nil, "BACKGROUND")
        mo.tile.bg:SetAllPoints()
        mo.tile.bg:SetColorTexture(RED[1], RED[2], RED[3], 1)
        if K.ApplySkin and K.ApplySkin(mo.tile, "button", RED, { 1, 1, 1, 0.18 }) then mo.tile.bg:Hide() end
        mo.icon = K.Glyph(mo.tile, 20, ns.MEDIA .. "icons\\announce", { 1, 1, 1 })
        mo.icon:SetPoint("CENTER")
        mo.ping = mo.tile:CreateTexture(nil, "BACKGROUND", nil, -1)
        mo.ping:SetTexture(ns.MEDIA .. "softglow")
        mo.ping:SetBlendMode("ADD")
        mo.ping:SetPoint("CENTER")
        mo.ping:SetSize(70, 70)
        mo.ping:SetVertexColor(RED[1], RED[2], RED[3])
        mo.ping:SetAlpha(0)
        -- Texte
        mo.kicker = K.Text(mo.box, 10, { RED[1] * 0.9 + 0.1, RED[2] * 0.6 + 0.3, RED[3] * 0.6 + 0.3 })
        mo.kicker:SetPoint("TOPLEFT", mo.tile, "TOPRIGHT", 12, 1)
        mo.kicker:SetText(L["Nachricht der Gildenleitung"])
        mo.new = K.Text(mo.box, 9, { 1, 1, 1 })
        mo.new:SetPoint("LEFT", mo.kicker, "RIGHT", 8, 0)
        mo.new.bg = mo.box:CreateTexture(nil, "ARTWORK")
        mo.new.bg:SetPoint("TOPLEFT", mo.new, "TOPLEFT", -4, 2) mo.new.bg:SetPoint("BOTTOMRIGHT", mo.new, "BOTTOMRIGHT", 4, -2)
        mo.new.bg:SetColorTexture(RED[1], RED[2], RED[3], 0.9)
        mo.new:SetText(L["NEU"])
        mo.text = K.Text(mo.box, 13, C.text)
        mo.text:SetPoint("TOPLEFT", mo.kicker, "BOTTOMLEFT", 0, -3)
        mo.text:SetJustifyH("LEFT")
        mo.text:SetWordWrap(true)
        if mo.text.SetMaxLines then mo.text:SetMaxLines(2) end
        -- Knoepfe rechts
        -- nur wer die Gildennachricht aendern darf, sieht "Bearbeiten" (Klick auf die Box = Gildenchat)
        mo.edit = K.Button(mo.box, L["Bearbeiten"], 92, 22, "ghost", function() Info.EditMOTD() end)
        mo.edit:SetPoint("RIGHT", -12, 0)
        mo.text:SetPoint("RIGHT", mo.edit, "LEFT", -12, 0)
        function mo:Layout()
            local canEdit = (CanEditMOTD and ns.safe(CanEditMOTD())) and true or false
            self.edit:SetShown(canEdit)
            self.text:ClearAllPoints()
            self.text:SetPoint("TOPLEFT", self.kicker, "BOTTOMLEFT", 0, -3)
            if canEdit then self.text:SetPoint("RIGHT", self.edit, "LEFT", -12, 0) else self.text:SetPoint("RIGHT", self.box, "RIGHT", -14, 0) end
        end
        -- neue Nachricht: Kachel pulsiert dreimal, "NEU" bis zum naechsten Oeffnen
        function mo:SetMessage(txt)
            self.full = txt
            self.text:SetText(txt or "")
            local seen = ns.db.motdSeen
            -- "NEU" bleibt in dieser Sitzung stehen (die Seite wird mehrmals aufgefrischt)
            local isNew = txt ~= nil and txt ~= "" and (seen ~= txt or self.newFor == txt)
            if isNew and seen ~= txt then self.newFor = txt end
            self.new:SetShown(isNew)
            self.new.bg:SetShown(isNew)
            if isNew and seen ~= txt then
                self.pulseT = 0
                ns.db.motdSeen = txt
            end
            self:Layout()
        end
        mo:SetScript("OnUpdate", function(self, el)
            if not self.pulseT then return end
            if ns.db and ns.db.settings.noAnim then self.pulseT = nil self.ping:SetAlpha(0) return end
            self.pulseT = self.pulseT + el
            local q = self.pulseT / 0.9
            if q >= 3 then self.pulseT = nil self.ping:SetAlpha(0) return end
            local f = q % 1
            self.ping:SetAlpha(0.7 * (1 - f))
            self.ping:SetSize(44 + 40 * f, 44 + 40 * f)
        end)
        mo:SetScript("OnClick", function() ns.ShowPage("chat") end)
        mo:SetScript("OnEnter", function(self)
            K.SkinLine(self.box, { RED[1], RED[2], RED[3], 0.9 })
            if self.full then K.ShowTip(self, { L["Gildennachricht"], self.full, "|cff888888" .. L["Klick: Gildenchat"] .. "|r" }) end
        end)
        mo:SetScript("OnLeave", function(self)
            K.SkinLine(self.box, { RED[1], RED[2], RED[3], 0.45 })
            GameTooltip:Hide()
        end)
        hl.mo = mo

        -- Countdown: Tage : Std : Min : Sek als Klappziffern, rechts Gilden-Bereitschaft
        local cd = page()
        cd:SetScript("OnClick", function() ns.ShowPage("raid") end)
        cd.groups = {}
        do local sk = K.Skin and K.Skin("panel") cd.round = sk and sk.fill == "round_fill" or false end
        local LBL = { "Tage", "Std", "Min", "Sek" }
        local gx = 0
        for i = 1, 4 do
            local g = CreateFrame("Frame", nil, cd)
            local gw = i == 1 and 50 or 42
            g:SetSize(gw, 32)
            g:SetPoint("TOPLEFT", gx, 0)
            g.bx = gx
            gx = gx + gw + 14
            g.bg = g:CreateTexture(nil, "BACKGROUND")
            g.bg:SetAllPoints()
            if not K.Gradient(g.bg, "VERTICAL", { 0.06, 0.06, 0.08, 0.95 }, { 0.16, 0.16, 0.20, 0.95 }) then g.bg:SetColorTexture(0.1, 0.1, 0.12, 0.95) end
            -- Glas/Modern: runde Glasflaeche statt Klappkarte (keine Naht, keine harte Akzentkante)
            g.round = cd.round
            if g.round then
                K.ApplySkin(g, "panel", { 1, 1, 1, 0.045 })
            else
                g.seam = g:CreateTexture(nil, "ARTWORK", nil, 2)
                g.seam:SetPoint("LEFT", 0, 0) g.seam:SetPoint("RIGHT", 0, 0) g.seam:SetHeight(1)
                g.seam:SetColorTexture(0, 0, 0, 0.55)
                g.top = g:CreateTexture(nil, "ARTWORK")
                g.top:SetPoint("TOPLEFT") g.top:SetPoint("TOPRIGHT") g.top:SetHeight(1)
                g.top:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.6)
            end
            g.glow = g:CreateTexture(nil, "BORDER")
            g.glow:SetTexture(EMBER) g.glow:SetBlendMode("ADD")
            g.glow:SetSize(gw + 30, 56) g.glow:SetPoint("CENTER")
            g.glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
            g.glow:SetAlpha(0)
            g.t = K.Title(g, g.round and 21 or 19, C.text, "CENTER")
            g.t:SetPoint("CENTER", 0, 0)
            g.t:SetText("--")
            g.ty = 0
            g.l = K.Text(cd, g.round and 10 or 8, C.muted, g.round and "LEFT" or "CENTER")
            g.l:SetPoint("TOP", g, "BOTTOM", 0, -3)
            g.l:SetText(g.round and L[LBL[i]] or K.Upper(L[LBL[i]]))
            g.flip = 1
            -- Glas: ruhig - kein Schein beim Umspringen
            if g.round then g.glow:Hide() end
            if i > 1 then
                local col = K.Title(cd, 16, C.dim, "CENTER")
                col:SetPoint("RIGHT", g, "LEFT", -3, 1)
                col:SetText(":")
                g.col = col
            end
            cd.groups[i] = g
        end
        cd.digitsW = gx - 14
        -- Vor dem Release: nur der Countdown, mittig, darunter Startzeit in Ortszeit
        cd.when = K.Text(cd, 10, C.muted, "CENTER")
        cd.when:Hide()
        function cd:Center(on)
            local w, h = self:GetWidth() or 0, self:GetHeight() or 0
            if self.round then return self:CenterRound(on, w, h) end
            local off = (on and w > self.digitsW) and math.floor((w - self.digitsW) / 2) or 0
            -- senkrecht mittig: Ziffern (32) + Beschriftung (14) + Abstand + Startzeile (14) = ~70
            local block = on and 72 or 46
            local dy = (on and h > block) and math.floor((h - block) / 2) or 0
            -- Release-Countdown: die vier Felder fuellen die ganze Breite der Karte
            local gap = 14
            local gw = on and math.floor((w - gap * 3) / 4) or nil
            for i, g in ipairs(self.groups) do
                g.ow = g.ow or g:GetWidth()
                g:ClearAllPoints()
                if gw and gw > g.ow then
                    g:SetSize(gw, 36)
                    g:SetPoint("TOPLEFT", (i - 1) * (gw + gap), -dy)
                    if g.glow then g.glow:SetSize(gw + 30, 60) end
                else
                    g:SetSize(g.ow, 32)
                    g:SetPoint("TOPLEFT", (g.bx or 0) + off, -dy)
                end
            end
            self.when:ClearAllPoints()
            self.when:SetPoint("TOP", self, "TOP", 0, -dy - 58)
            self.when:SetShown(on and self.whenText ~= nil)
            if self.whenText then self.when:SetText(self.whenText) end
        end
        -- Glas/Modern: Release = vier ruhige Felder ueber die volle Breite, Zahl + Einheit nebeneinander
        -- ("28 Tage"), Startzeit steht im Kopf; Raid-Countdown (mit Bereitschaft) = kompakte Felder, Einheit darunter
        function cd:CenterRound(on, w, h)
            local gap = on and 10 or 14
            local th = on and math.max(30, math.min(44, h - 6)) or 32
            local inside = on
            local block = on and th or 46
            local dy = (h > block) and math.floor((h - block) / 2) or 0
            local gw = on and math.floor((w - gap * 3) / 4) or nil
            for i, g in ipairs(self.groups) do
                g.ow = g.ow or g:GetWidth()
                local tw = (gw and gw > g.ow) and gw or g.ow
                g:ClearAllPoints()
                g:SetSize(tw, th)
                if gw and gw > g.ow then
                    g:SetPoint("TOPLEFT", (i - 1) * (gw + gap), -dy)
                else
                    g:SetPoint("TOPLEFT", g.bx or 0, -dy)
                end
                -- Zahl + Einheit als Gruppe mittig im Feld; die Einheit sitzt auf der Grundlinie der Zahl
                g.l:SetParent(inside and g or self)
                g.l:ClearAllPoints()
                if inside then
                    local lw = tonumber(g.l:GetStringWidth()) or 0
                    g.tx, g.ty = -math.floor((lw + 5) / 2), 0
                    g.l:SetPoint("BOTTOMLEFT", g.t, "BOTTOMRIGHT", 5, 2)
                else
                    g.tx, g.ty = 0, 0
                    g.l:SetPoint("TOP", g, "BOTTOM", 0, -3)
                end
                g.t:ClearAllPoints()
                g.t:SetPoint("CENTER", g.tx, g.ty)
                if g.col then g.col:SetShown(not on) end
            end
            -- Startzeit nicht mehr als eigene Zeile (machte die Karte eng) - steht im Kopf + Tooltip
            self.when:Hide()
        end
        cd:SetScript("OnEnter", function(self)
            if self.whenText then K.ShowTip(self, { self.title or L["Raid-Countdown"], self.whenText }) end
        end)
        cd:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cd.done = K.Text(cd, 12, C.amber)
        cd.done:SetPoint("TOPLEFT", 0, -6)
        cd.done:Hide()
        cd.bars = CreateFrame("Frame", nil, cd)
        cd.bars:SetPoint("TOPLEFT", cd.digitsW + 22, 2)
        cd.bars:SetPoint("BOTTOMRIGHT", 0, 0)
        cd.rows = {}
        for i = 1, 3 do
            local r = CreateFrame("Frame", nil, cd.bars)
            r:SetHeight(18)
            r:SetPoint("TOPLEFT", 0, -(i - 1) * 19)
            r:SetPoint("RIGHT", 0, 0)
            r.t = K.Text(r, 9, C.muted)
            r.t:SetPoint("TOPLEFT", 0, 0)
            r.t:SetWordWrap(false)
            r.v = K.Text(r, 9, C.text, "RIGHT")
            r.v:SetPoint("TOPRIGHT", 0, 0)
            r.track = r:CreateTexture(nil, "ARTWORK")
            r.track:SetPoint("BOTTOMLEFT", 0, 2) r.track:SetPoint("BOTTOMRIGHT", 0, 2)
            r.track:SetHeight(3)
            r.track:SetColorTexture(1, 1, 1, 0.07)
            r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.fill:SetPoint("LEFT", r.track, "LEFT")
            r.fill:SetHeight(3)
            r.fill:SetWidth(1)
            r.ratio = 0
            cd.rows[i] = r
        end
        hl.cd = cd

        -- Tagesziel: drei Ringe aus Lichtpunkten (Schritte, XP, Wochenaufgaben), voll = Feuerwerk
        local goal = page()
        -- Smartwatch-Ringe (Bewegen / Trainieren / Stehen): Schritte, XP, Wochenaufgaben
        local RCOL = { { 1, 0.20, 0.36 }, { 0.62, 1, 0.12 }, { 0.10, 0.85, 1 } }
        goal.rcol = RCOL
        goal.ringF = K.ActivityRings(goal, 66, RCOL)
        goal.ringF:SetPoint("LEFT", 2, 0)
        goal.rings = {}
        goal.halo = goal.ringF:CreateTexture(nil, "BACKGROUND")
        goal.halo:SetTexture(EMBER) goal.halo:SetBlendMode("ADD")
        goal.halo:SetSize(110, 110) goal.halo:SetPoint("CENTER")
        goal.halo:SetVertexColor(C.mint[1], C.mint[2], C.mint[3])
        goal.halo:SetAlpha(0)
        goal.halo:Hide()
        -- je Ring eine Zeile: Bezeichnung | Leiste in Ringfarbe | Wert (rechtsbuendig)
        goal.lines, goal.vals, goal.bars = {}, {}, {}
        for i = 1, 3 do
            local y = -(i - 1) * 16
            local fs = K.Text(goal, 11, C.muted)
            fs:SetPoint("TOPLEFT", 84, y)
            fs:SetWidth(104)
            fs:SetWordWrap(false)
            goal.lines[i] = fs
            local v = K.Text(goal, 11, C.text, "RIGHT")
            v:SetPoint("TOPRIGHT", goal, "TOPRIGHT", 0, y)
            v:SetWidth(96)
            v:SetWordWrap(false)
            goal.vals[i] = v
            local tr = goal:CreateTexture(nil, "ARTWORK")
            tr:SetHeight(4)
            tr:SetPoint("LEFT", fs, "RIGHT", 4, 0)
            tr:SetPoint("RIGHT", v, "LEFT", -10, 0)
            tr:SetColorTexture(RCOL[i][1], RCOL[i][2], RCOL[i][3], 0.16)
            local fl = goal:CreateTexture(nil, "ARTWORK", nil, 1)
            fl:SetHeight(4)
            fl:SetPoint("LEFT", tr, "LEFT")
            fl:SetWidth(1)
            fl:SetColorTexture(RCOL[i][1], RCOL[i][2], RCOL[i][3], 1)
            goal.bars[i] = { track = tr, fill = fl, ratio = 0 }
        end
        goal.msg = K.Text(goal, 9, C.dim)
        goal.msg:SetPoint("TOPLEFT", 84, -52)
        goal.msg:SetPoint("RIGHT", 0, 0)
        goal.msg:SetWordWrap(false)
        goal:SetScript("OnClick", function() if goal.data and goal.data.full then p:Fireworks() end end)
        goal:SetScript("OnEnter", function(self)
            K.ShowTip(self, { L["Dein Tagesziel"], L["Aussen: 10.000 Schritte  ·  Mitte: halbe Stufe XP  ·  Innen: Wochenaufgaben"],
                self.data and self.data.full and ("|cff66db9e" .. L["Klick: nochmal Feuerwerk"] .. "|r") or nil })
        end)
        goal:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Feuerwerk ueber der ganzen Karte
        local fw = CreateFrame("Frame", nil, hl)
        fw:SetAllPoints()
        fw:SetClipsChildren(true)
        fw:SetFrameLevel(hl:GetFrameLevel() + 20)
        fw:EnableMouse(false)
        fw.parts = {}
        for i = 1, 48 do
            local t = fw:CreateTexture(nil, "OVERLAY")
            t:SetTexture(i % 3 == 0 and (ns.MEDIA .. "dot") or EMBER)
            t:SetBlendMode("ADD")
            t:Hide()
            fw.parts[i] = { t = t }
        end
        fw:Hide()
        hl.fw = fw
        hl.goal = goal

        -- Rekorde: 2 x 2 Felder
        local rec = page()
        rec.cells = {}
        for i = 1, 4 do
            local c = CreateFrame("Button", nil, rec)
            c:SetHeight(26)
            c.bg = c:CreateTexture(nil, "BACKGROUND")
            c.bg:SetAllPoints()
            c.bg:SetColorTexture(1, 1, 1, 0.035)
            c:SetSize(160, 30)
            if K.ApplySkin(c, "panel", { 1, 1, 1, 0.035 }) then c.bg:Hide() end
            c.icon = K.Glyph(c, 20, nil)
            c.icon:SetPoint("LEFT", 12, 0)
            c.t = K.Text(c, 10, C.muted)
            c.t:SetPoint("BOTTOMLEFT", c, "LEFT", 42, 2)
            c.t:SetPoint("RIGHT", -10, 0)
            c.t:SetWordWrap(false)
            c.v = K.Text(c, 12, C.text)
            c.v:SetPoint("TOPLEFT", c, "LEFT", 42, -2)
            c.v:SetPoint("RIGHT", -10, 0)
            c.v:SetWordWrap(false)
            c:SetScript("OnClick", function(self) if self.page then ns.ShowPage(self.page) end end)
            c:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
            c:SetScript("OnLeave", function() GameTooltip:Hide() end)
            rec.cells[i] = c
        end
        rec.pg, rec.pages = 1, 2
        local function arrow(dir)
            local a = CreateFrame("Button", nil, rec)
            a:SetSize(16, 30)
            a.t = K.Text(a, 16, C.muted, "CENTER")
            a.t:SetPoint("CENTER", 0, 1)
            a.t:SetText(dir < 0 and "<" or ">")
            a:SetScript("OnClick", function() p:RecPage(dir) end)
            a:SetScript("OnEnter", function(self) self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
            a:SetScript("OnLeave", function(self) self.t:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
            return a
        end
        rec.prev, rec.next = arrow(-1), arrow(1)
        rec:EnableMouseWheel(true)
        rec:SetScript("OnMouseWheel", function(_, d) p:RecPage(d > 0 and -1 or 1) end)
        -- Seitenpunkte unten mittig
        rec.dots = {}
        for i = 1, 2 do
            local d = rec:CreateTexture(nil, "ARTWORK")
            d:SetTexture(CIRCLE)
            d:SetSize(5, 5)
            rec.dots[i] = d
        end
        hl.rec = rec

        ----------------------------------------------------------------
        -- Spalte 3: Als Naechstes (Durchsagen, Termine, Fuer dich)
        ----------------------------------------------------------------
        local nextBox = box(p, L["Als Naechstes"], C.amber)
        -- 0.6.180: jeder Eintrag als Karte - dunkle Flaeche, goldene Kante links, gerahmtes Symbol, Pfeil rechts,
        -- bei "(x/y)" im Text ein Fortschrittsbalken mit Prozent
        nextBox.list = K.List(nextBox, 60, function(l)   -- 0.6.181: hoehere Karten mit Abstand
            local r = K.Row(l)
            if r.stripe then r.stripe:SetAlpha(0) end
            if r.hl then r.hl:ClearAllPoints() r.hl:SetPoint("TOPLEFT", 6, -5) r.hl:SetPoint("BOTTOMRIGHT", -6, 5) r.hl:SetColorTexture(1, 1, 1, 0.05) end
            r.card = r:CreateTexture(nil, "BACKGROUND", nil, 1)
            r.card:SetPoint("TOPLEFT", 6, -5) r.card:SetPoint("BOTTOMRIGHT", -6, 5)
            if not K.Gradient(r.card, "HORIZONTAL", { 1, 1, 1, 0.06 }, { 1, 1, 1, 0.015 }) then r.card:SetColorTexture(1, 1, 1, 0.04) end
            r.cardLine = r:CreateTexture(nil, "BACKGROUND", nil, 2)
            r.cardLine:SetHeight(1)
            r.cardLine:SetPoint("TOPLEFT", r.card, "TOPLEFT", 2, 0) r.cardLine:SetPoint("TOPRIGHT", r.card, "TOPRIGHT")
            if not K.Gradient(r.cardLine, "HORIZONTAL", { 1, 1, 1, 0.10 }, { 1, 1, 1, 0 }) then r.cardLine:SetColorTexture(1, 1, 1, 0.05) end
            r.edge = r:CreateTexture(nil, "ARTWORK")
            r.edge:SetPoint("TOPLEFT", r.card, "TOPLEFT") r.edge:SetPoint("BOTTOMLEFT", r.card, "BOTTOMLEFT")
            r.edge:SetWidth(2)
            r.chev = K.Text(r, 12, C.dim, "RIGHT")
            r.chev:SetPoint("RIGHT", -18, 0)
            r.chev:SetText(">")
            r.chev:SetAlpha(0.6)
            r.track = r:CreateTexture(nil, "ARTWORK")
            r.track:SetHeight(3)
            r.track:SetColorTexture(1, 1, 1, 0.08)
            r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.fill:SetHeight(3)
            r.fill:SetPoint("LEFT", r.track, "LEFT")
            r.pct = K.Text(r, 9, C.muted, "RIGHT")
            r.pct:SetPoint("RIGHT", r.chev, "LEFT", -12, -9)
            r.track:SetPoint("LEFT", 66, -9)
            r.track:SetPoint("RIGHT", r.pct, "LEFT", -8, 0)
            r.track:Hide() r.fill:Hide() r.pct:Hide()
            r.date = CreateFrame("Frame", nil, r)
            r.date:SetSize(36, 36)
            r.date:SetPoint("LEFT", 18, 0)
            K.Border(r.date, { C.amber[1], C.amber[2], C.amber[3], 0.45 })
            r.date.bg = K.Fill(r.date, C.raised)
            r.date.top = r.date:CreateTexture(nil, "ARTWORK")
            r.date.top:SetPoint("TOPLEFT") r.date.top:SetPoint("TOPRIGHT")
            r.date.top:SetHeight(2)
            r.date.a = K.Title(r.date, 9, C.amber, "CENTER")
            r.date.a:SetPoint("TOP", 0, -4)
            r.date.b = K.Text(r.date, 10, C.text, "CENTER")
            r.date.b:SetPoint("BOTTOM", 0, 2)
            r.icon = K.Glyph(r.date, 18, nil)
            r.icon:SetPoint("CENTER")
            r.cols.text = K.Text(r, 12, C.text)
            r.cols.text:SetPoint("LEFT", 66, 0)
            r.cols.text:SetPoint("RIGHT", r.chev, "LEFT", -12, 0)
            r.cols.text:SetWordWrap(true)
            if r.cols.text.SetMaxLines then r.cols.text:SetMaxLines(2) end
            r.b1 = K.Button(r, "", 50, 20, "ghost")
            r.b1:SetPoint("RIGHT", r.chev, "LEFT", -6, 0)
            r.b2 = K.Button(r, "", 50, 20, "ghost")
            r.b2:SetPoint("RIGHT", r.b1, "LEFT", -3, 0)
            r:SetScript("OnClick", function(self)
                local a = self.item
                if not a then return end
                if a.fn then a.fn() elseif a.page then ns.ShowPage(a.page) end
            end)
            r:SetScript("OnEnter", function(self)
                local a = self.item
                if a then K.ShowTip(self, a.tip or { a.text }) end
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, a, idx)
            r.b1:Hide() r.b2:Hide()
            r.cols.text:SetPoint("RIGHT", r.chev, "LEFT", -12, 0)
            if a.ev and ns.Raid then
                local mine = ns.Raid.MySignup(a.ev.id)
                local st = mine and mine.status
                r.b2:SetLabel(st == "yes" and ("|cff66db9e" .. L["Dabei"] .. "|r") or L["Zusagen"])
                r.b1:SetLabel(st == "no" and ("|cffe64040" .. L["Abgesagt"] .. "|r") or L["Absagen"])
                r.b2:SetScript("OnClick", function() ns.Raid.SignUp(a.ev, nil, "yes") ns.RefreshPage("home") end)
                r.b1:SetScript("OnClick", function() ns.Raid.SignUp(a.ev, nil, "no") ns.RefreshPage("home") end)
                r.b1:SetWidth(50)
                r.b1:Show() r.b2:Show()
                r.cols.text:SetPoint("RIGHT", r.b2, "LEFT", -4, 0)
            elseif a.lfg and ns.Groups and not ns.isMe(a.lfg.who) then
                local g = a.lfg
                local asked = ns.Groups.joined and ns.Groups.joined[g.id]
                r.b1:SetLabel(asked and ("|cff888888" .. L["Gefragt"] .. "|r") or L["Beitreten"])
                r.b1:SetScript("OnClick", function(self)
                    if asked then return end
                    local free = ns.Groups.FreeRoles(g)
                    local roles = ns.Groups.MyRoles()
                    local items = {}
                    for _, rk in ipairs({ "tank", "heal", "dps" }) do
                        if free[rk] and roles[rk] then
                            items[#items + 1] = { text = L[rk == "tank" and "Tank" or rk == "heal" and "Heiler" or "Schaden"], fn = function() ns.Groups.Join(g, rk) ns.RefreshPage("home") end }
                        end
                    end
                    if #items == 0 then ns.ShowPage("groups") return end
                    if #items == 1 then items[1].fn() return end
                    K.ShowMenu(self, items, L["Als ..."], 120)
                end)
                r.b1:SetWidth(64)
                r.b1:Show()
                r.cols.text:SetPoint("RIGHT", r.b1, "LEFT", -4, 0)
            end
            local c = a.color or C.amber
            r.date.top:SetColorTexture(c[1], c[2], c[3], 1)
            r.edge:SetColorTexture(c[1], c[2], c[3], 0.9)
            -- Fortschritt aus "(x/y)" im Text
            local x, y = tostring(a.text or ""):match("%((%d+)%s*/%s*(%d+)%)")
            x, y = tonumber(x), tonumber(y)
            if x and y and y > 0 then
                local q = math.max(0, math.min(1, x / y))
                r.fill:SetColorTexture(c[1], c[2], c[3], 1)
                r.track:Show() r.fill:Show() r.pct:Show()
                r.fill:SetWidth(math.max(1, (r.track:GetWidth() or 100) * q))
                r.fillQ = q
                r.pct:SetText(("%d%%"):format(q * 100 + 0.5))
                r.cols.text:ClearAllPoints()
                r.cols.text:SetPoint("LEFT", 66, 7)
                r.cols.text:SetPoint("RIGHT", r.chev, "LEFT", -12, 7)
            else
                r.track:Hide() r.fill:Hide() r.pct:Hide()
                r.fillQ = nil
                r.cols.text:ClearAllPoints()
                r.cols.text:SetPoint("LEFT", 66, 0)
                r.cols.text:SetPoint("RIGHT", r.chev, "LEFT", -12, 0)
            end
            if a.ts then
                r.date.a:SetText(K.Upper(ns.weekday(a.ts, true)))
                r.date.a:SetTextColor(c[1], c[2], c[3])
                r.date.b:SetText(date("%H:%M", a.ts))
                r.date.a:Show() r.date.b:Show() r.icon:Hide()
            else
                r.date.a:Hide() r.date.b:Hide()
                r.icon:SetTexture(a.icon or ns.ICONS.home)
                r.icon:SetVertexColor(c[1], c[2], c[3])
                r.icon:Show()
            end
            r.cols.text:SetText(a.text)
            if p.fresh and animOn() then K.FadeIn(r, 0.6 + (idx or 1) * 0.06) end
        end)
        nextBox.list:SetPoint("TOPLEFT", 6, -44)
        nextBox.list:SetPoint("BOTTOMRIGHT", -6, 8)
        nextBox.list.empty:SetText("")
        nextBox.empty = emptyState(nextBox, ns.ICONS.raid, C.amber, L["Nichts geplant - wie waer's mit einem Termin?"],
            { { "Termin anlegen", "raid" }, { "Gruppe suchen", "groups" } })
        p.nextBox = nextBox
        -- 0.6.182: Hintergrundbilder mit eigenem Zierrahmen (Gildenmodul): links dunkle Oase, rechts Lager mit Fackeln.
        -- Dann keine Oasis-Kante/Flaeche und kein Zierrahmen (sonst doppelt); ohne Gildenmodul wie bisher (0.6.180)
        local function boxArt(bx, file)
            bx.art = bx:CreateTexture(nil, "BACKGROUND", nil, 2)
            if K.BgImg then K.BgImg(bx.art) end   -- 0.6.227: Helligkeit einstellbar
            bx.art:SetAllPoints()
            bx.art:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\" .. file)
            if bx.bg then bx.bg:SetAlpha(0) end
            if bx.borders then for _, b in ipairs(bx.borders) do b:SetAlpha(0) end end
            if bx.skinLine then for _, b in ipairs(bx.skinLine) do b:SetAlpha(0) end end
        end
        if ns.GuildPack then
            boxArt(feed, "feed_bg")
            boxArt(nextBox, "next_bg")
        elseif K.FrameLines then
            feed.frameLines = K.FrameLines(feed, 8)
            nextBox.frameLines = K.FrameLines(nextBox, 8)
        end

        -- Werbebanner "Midas" (AH-Addon von Rebo) unten in Spalte 3, Hoehe = Breite / 3
        local ad = CreateFrame("Button", nil, p)
        ad:SetClipsChildren(true)
        ad.img = ad:CreateTexture(nil, "ARTWORK")
        ad.img:SetAllPoints()
        ad.img:SetTexture(ns.MEDIA .. "midas_ad")
        local AV = 342 / 512
        -- Ausschnitt passend zum Rahmen (Bild 3:1; breiterer Rahmen -> oben/unten etwas abschneiden), z = Zoom
        local function adZoom(z)
            local w, h = ad:GetWidth() or 300, ad:GetHeight() or 100
            local u0, u1, v0, v1 = 0, 1, 0, AV
            if w > 1 and h > 1 then
                local r = (w / h) / 3
                if r > 1 then local c = AV * (1 - 1 / r) / 2 v0, v1 = c, AV - c
                elseif r < 1 then local c = (1 - r) / 2 u0, u1 = c, 1 - c end
            end
            local du, dv = (u1 - u0) * (1 - 1 / z) / 2, (v1 - v0) * (1 - 1 / z) / 2
            ad.img:SetTexCoord(u0 + du, u1 - du, v0 + dv, v1 - dv)
        end
        ad:SetScript("OnSizeChanged", function() adZoom(1) end)
        adZoom(1)
        ad.hl = ad:CreateTexture(nil, "OVERLAY")
        ad.hl:SetAllPoints()
        ad.hl:SetColorTexture(1, 1, 1, 0.10)
        ad.hl:SetBlendMode("ADD")
        ad.hl:Hide()
        K.Border(ad, { 1, 1, 1, 0.10 })
        -- Hover: nur aufhellen, nie zoomen (Bild bleibt immer ganz zu sehen)
        ad:SetScript("OnEnter", function(self)
            self.hl:Show()
            adZoom(1)
            K.ShowTip(self, { L["Midas - AH-Marktanalyse von Rebo"], "|cff888888" .. L["Klick: Midas oeffnen"] .. "|r" })
        end)
        ad:SetScript("OnLeave", function(self)
            self.hl:Hide()
            adZoom(1)
            GameTooltip:Hide()
        end)
        ad:SetScript("OnClick", function()
            local cmd = SlashCmdList and SlashCmdList.MIDAS
            local api = rawget(_G, "MidasAPI")
            local ok = false
            if type(api) == "table" then
                for _, fn in ipairs({ "Toggle", "Show", "Open" }) do
                    if type(api[fn]) == "function" then ok = pcall(api[fn], api) if ok then break end end
                end
            end
            if not ok and type(cmd) == "function" then ok = pcall(cmd, "") end
            if not ok then
                if K.Toast then
                    K.Toast(L["Midas"], L["Midas ist nicht installiert - im Gilden-Discord oder auf CurseForge herunterladen."], C.amber)
                else
                    ns.print(L["Midas ist nicht installiert - im Gilden-Discord oder auf CurseForge herunterladen."])
                end
            end
        end)
        p.ad = ad
        -- ohne Gilde: statt der Gildenkarten die eigenen Inhalte (Profil, Was tun?, Dungeons, Gilde finden, Oasis-Kontakte)
        if ns.NoGuild and ns.NoGuild.BuildArea then
            p.ngArea = ns.NoGuild.BuildArea(p)
            p.ngArea:Hide()
        end

        ----------------------------------------------------------------
        -- Anordnung (alles relativ zur Seitengroesse)
        ----------------------------------------------------------------
        local GAP = 10
        function p:PlaceTile(t)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", t.bx or 0, (t.by or 0) - (t.dy or 0) + (t.lift or 0))
        end
        function p:LayoutGrid()
            local o = self.online
            local w, h = o:GetWidth() or 230, o:GetHeight() or 260
            if w < 60 then w = 230 end
            if h < 80 then h = 260 end
            local gw, gh = w - 16, h - 44
            -- rechts sitzt Held/Pechvogel: Kreise nur bis davor
            -- 0.6.174: Held/Pechvogel hat eine eigene Box - die Online-Box ist schon schmaler, nichts mehr abziehen
            local list = self.onlineList or computeOnline()
            self.onlineList = list
            local n = #list
            -- Kreisgroesse: wenige gross, sonst die groesste Stufe, in die alle passen
            local MODES = { { 44, 50, 60 }, { 34, 42, 50 }, { 26, 32, 32 } }
            local pick = MODES[3]
            for mi, md in ipairs(MODES) do
                local cap = math.max(1, math.floor(gw / md[2])) * math.max(1, math.floor(gh / md[3]))
                if (mi == 1 and n <= 6 and cap >= n) or (mi > 1 and cap >= n) then pick = md break end
            end
            local mode, cellW, cellH = pick[1], pick[2], pick[3]
            local cols = math.max(1, math.floor(gw / cellW))
            local rows = math.max(1, math.floor(gh / cellH))
            local cap = cols * rows
            local show = n > cap and (cap - 1) or n
            local cw = gw / cols
            local modeChanged = self.gridMode ~= nil and self.gridMode ~= mode
            self.gridMode = mode
            local cwCell = (mode == 44 and 48) or (mode == 34 and 40) or 30
            for i = 1, math.max(#self.cells, show + 1) do
                local c = self.cells[i]
                if i <= show or (i == show + 1 and n > cap) then
                    if not c then c = memberCell(o.grid) self.cells[i] = c end
                    c:SetMode(mode)
                    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", math.floor(col * cw + (cw - cwCell) / 2), -row * cellH)
                    if modeChanged and animOn() then K.FadeIn(c, 0.02 * i) end
                    if i <= show then c:SetMember(list[i]) else c:SetMore(n - show) end
                elseif c then
                    c:Hide()
                    c.member, c.more = nil, nil
                end
            end
            -- Leertext nur, wenn wirklich niemand in der Liste ist (nie unter Kreisen)
            o.grid:SetShown(n > 0)
            o.empty:SetShown(n == 0)
        end
        -- Dashboard ohne Gilde: Banner bleibt, darunter Karten-Reihe + Kontakte, Midas rechts daneben
        function p:LayoutNoGuild(ty, W, H)
            for _, t in ipairs(self.tiles) do t:Hide() end
            self.online:Hide() if self.spotBox then self.spotBox:Hide() end self.feed:Hide() self.nextBox:Hide() self.hl:Hide()
            local a = self.ngArea
            a:Show()
            a:ClearAllPoints()
            a:SetPoint("TOPLEFT", 0, ty)
            a:SetSize(W, math.max(100, H + ty))
            local showAd = adWanted()
            local aw = showAd and math.floor(math.min(330, W * 0.36)) or 0
            local off = a:LayoutDash(W, showAd and (aw + GAP) or 0, H + ty - 34) or 0   -- 34 = Rang-Leiste unten
            a:FillContacts()
            showAd = showAd and a.adFits ~= false   -- Midas bleibt, solange es irgendwie passt
            self.ad:SetShown(showAd)
            if showAd then
                self.ad:ClearAllPoints()
                self.ad:SetPoint("TOPRIGHT", 0, ty - off - (a.cardH or 150) - GAP)
                local adH = math.floor(aw / 3)
                local room = (H + ty - 34) - (off + (a.cardH or 150) + GAP)
                if room < adH then adH = math.max(60, room) aw = adH * 3 end
                self.ad:SetSize(aw, adH)
            end
        end
        function p:Layout()
            local W, H = self:GetWidth() or 760, self:GetHeight() or 560
            if W < 100 then W = 760 end
            if H < 100 then H = 560 end
            local banH = H >= 520 and 178 or 150
            self.ban:SetHeight(banH)
            -- Modell rechts, Glas-Kaertchen unten rechts, Schrift links bekommt den Rest
            local sw = math.floor(math.min(240, W * 0.30))
            self.ban.stage:SetWidth(sw)
            self.ban.motd:SetWidth(math.floor(math.min(260, W * 0.34)))
            local textW = math.max(140, W - sw - 70)
            self.ban.line2:SetWidth(textW)
            self.ban.greet:SetWidth(textW)
            self.ban.welcome:SetWidth(textW)
            -- Ticker unten im Banner: Schrift, Kaertchen und Buehne ruecken darueber
            local tkOn = S().dashTicker ~= false
            local b = self.ban
            b.line2:ClearAllPoints()
            b.line2:SetPoint("BOTTOMLEFT", 20, tkOn and 34 or 18)
            b.welcome:ClearAllPoints()
            b.welcome:SetPoint("BOTTOMLEFT", 20, tkOn and 34 or 18)
            b.motd:ClearAllPoints()
            b.motd:SetPoint("BOTTOMRIGHT", -14, tkOn and 34 or 14)
            b.stage:ClearAllPoints()
            b.stage:SetPoint("TOPRIGHT", 34, 0)
            b.stage:SetPoint("BOTTOMRIGHT", 34, tkOn and 22 or 0)
            b.heroPlate.maxW = math.min(240, sw)
            b.heroPlate:SetWidth(math.min(b.heroPlate.maxW, b.heroPlate.fitW or 200))
            self.ban.dimLeft:SetWidth(math.floor(math.min(420, W * 0.5)))
            -- Schlichte Startseite (Einstieg fuer Neue): keine Kachelreihe, keine untere Zeile - nur drei klare Spalten
            -- Kacheln entfallen: an ihrer Stelle "Wer ist online" in voller Breite
            local simple = false
            for _, t in ipairs(self.tiles) do t:Hide() end
            -- Kacheln
            local ty = -(banH + GAP)
            if self.ngArea and ns.GuildView and not ns.GuildView() then
                self:LayoutNoGuild(ty, W, H)
                return
            end
            if self.ngArea and self.ngArea:IsShown() then
                self.ngArea:Hide()
                self.online:Show() self.feed:Show() self.nextBox:Show()
            end
            -- Spalten: Gildennachricht zaehlt doppelt (5 Spalten bei 4 Kacheln)
            local cols = 0
            for _, t in ipairs(self.tiles) do cols = cols + (t.span or 1) end
            local tw = math.floor((W - GAP * (cols - 1)) / cols)
            local tx = 0
            for _, t in ipairs(self.tiles) do
                local w = tw * (t.span or 1) + GAP * ((t.span or 1) - 1)
                t:SetSize(w, 66)
                t.bx, t.by = tx, ty
                tx = tx + w + GAP
                self:PlaceTile(t)
            end
            -- Inhalt: oben drei Spalten gleich hoch, unten eine Zeile "Gilden-Highlight" + Midas (3:1)
            local OH = 118   -- Hoehe der Online-Box (volle Breite)
            self.online:ClearAllPoints()
            self.online:SetPoint("TOPLEFT", 0, ty)
            -- 0.6.171: Held/Pechvogel als eigene Box rechts daneben (nur wenn es einen gibt)
            local spOn = self.online.spot and self.online.spot.list and #self.online.spot.list > 0
            -- 0.6.175: gleiche Spaltenbreiten wie die Boxen darunter (Was gerade passiert 55 % / Als Naechstes)
            local SPW = spOn and ((W - GAP) - math.floor((W - GAP) * 0.55)) or 0
            self.online:SetSize(spOn and (W - SPW - GAP) or W, OH)
            if self.spotBox then
                self.spotBox:ClearAllPoints()
                self.spotBox:SetPoint("TOPLEFT", self.online, "TOPRIGHT", GAP, 0)   -- 0.6.173: direkt an "Wer ist online" (0.6.172 lag ausserhalb des Fensters)
                self.spotBox:SetSize(math.max(1, SPW), OH)
                self.spotBox:SetShown(spOn and self.online:IsShown() and true or false)
            end
            local top = ty - OH - GAP
            local ch = math.max(120, H + top - 10)   -- 10 px Luft zum unteren Rand
            local inner = W - GAP
            local w2 = math.floor(inner * 0.55)
            local w3 = inner - w2
            local bh = (not simple and ch >= 250) and math.max(92, math.min(118, math.floor(ch * 0.38))) or 0
            local showAd = bh > 0 and adWanted()
            -- Midas so breit wie die Box darueber ("Als Naechstes"), volle Zeilenhoehe; Countdown-Karte = Breite der linken Box
            local adH = showAd and bh or 0
            local aw = showAd and w3 or 0
            local ch2 = bh > 0 and (ch - bh - GAP) or ch
            -- 0.5.916: zu wenig Hoehe fuer die untere Zeile (kleines Fenster) -> Midas trotzdem zeigen: unten in der rechten
            -- Spalte, die Box "Als Naechstes" wird dafuer niedriger
            local adInCol = false
            -- 0.6.183: aus - Midas in der rechten Spalte machte "Als Naechstes" kuerzer als "Was gerade passiert"
            -- (ungleich hohe Boxen); Midas kommt nur noch in der eigenen Zeile darunter (grosses Fenster)
            if false and bh == 0 and not simple and adWanted() then
                local h = math.min(110, math.floor(w3 / 3))
                if ch2 - h - GAP >= 64 then adInCol, showAd, adH, aw = true, true, h, w3 end
            end
            -- 0.6.184: "Als Naechstes" haengt oben UND unten an "Was gerade passiert" - immer exakt gleich hoch
            self.feed:ClearAllPoints()
            self.feed:SetPoint("TOPLEFT", 0, top)
            self.feed:SetSize(w2, ch2)
            self.nextBox:ClearAllPoints()
            self.nextBox:SetPoint("TOPLEFT", self.feed, "TOPRIGHT", GAP, 0)
            self.nextBox:SetPoint("BOTTOMLEFT", self.feed, "BOTTOMRIGHT", GAP, 0)
            self.nextBox:SetWidth(w3)
            local rowY = top - ch2 - GAP
            self.hl:SetShown(bh > 0)
            if bh > 0 then
                local hw = showAd and (W - aw - GAP) or W
                self.hl:ClearAllPoints()
                self.hl:SetPoint("TOPLEFT", 0, rowY)
                self.hl:SetSize(hw, bh)
                -- Aufgaben untereinander, volle Breite, senkrecht mittig
                local rh = math.max(16, math.min(22, math.floor((bh - 44) / 3)))
                local ry = math.max(0, math.floor((bh - 42 - rh * 3) / 2))
                for i, r in ipairs(self.hl.wk.rows) do
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", 0, -ry - (i - 1) * rh)
                    r:SetPoint("RIGHT", self.hl.wk, "RIGHT", 0, 0)
                    r:SetHeight(rh)
                end
                self.hl.empty:ClearAllPoints()
                self.hl.empty:SetPoint("TOPLEFT", 14, -36)
                self.hl.empty:SetPoint("RIGHT", -14, 0)
                -- Countdown: Bereitschaft nur, wenn rechts neben den Ziffern Platz ist
                local inner2 = hw - 24
                local relOnly = self.hl.cd.ev == nil   -- Release-Countdown: ohne Bereitschafts-Balken
                self.hl.cd.bars:SetShown(not relOnly and inner2 - self.hl.cd.digitsW - 22 >= 130)
                self.hl.cd:Center(relOnly)
                -- Rekorde: zwei grosse Felder nebeneinander, Pfeile links/rechts, Punkte darunter
                local rec = self.hl.rec
                local AW = 18
                local rw = math.floor((inner2 - 2 * AW - 8) / 2)
                local rh = math.max(30, math.min(44, bh - 44 - 12))
                local ry = -math.max(0, math.floor((bh - 44 - 10 - rh) / 2))
                rec.prev:ClearAllPoints() rec.prev:SetPoint("LEFT", rec, "TOPLEFT", 0, ry - rh / 2)
                rec.next:ClearAllPoints() rec.next:SetPoint("RIGHT", rec, "TOPRIGHT", 0, ry - rh / 2)
                for i, c in ipairs(rec.cells) do
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", AW + ((i - 1) % 2) * (rw + 8), ry)
                    c:SetSize(rw, rh)
                end
                for i, d in ipairs(rec.dots) do
                    d:ClearAllPoints()
                    d:SetPoint("TOP", rec, "TOPLEFT", inner2 / 2 + (i - 1.5) * 10, ry - rh - 5)
                end
                self:RecPage(0)
                -- schmale Karte: Kopf zeigt nur den Reiter-Titel ohne Zusatz (sonst stoesst er an die Chips)
                self.hl.narrow = hw < 400
            end
            self.ad:SetShown(showAd)
            if showAd then
                -- immer ganzes Bild (3:1), rechts unten, senkrecht mittig in der Zeile
                self.ad:ClearAllPoints()
                self.ad:SetPoint("TOPRIGHT", 0, adInCol and (top - ch2 + adH) or rowY)
                self.ad:SetSize(aw, adH)
            end
            self.feed.list:ClearAllPoints()
            self.feed.list:SetPoint("TOPLEFT", 4, -38)
            self.feed.list:SetPoint("BOTTOMRIGHT", -4, 6)
            self.nextBox.list:ClearAllPoints()
            self.nextBox.list:SetPoint("TOPLEFT", 4, -38)
            self.nextBox.list:SetPoint("BOTTOMRIGHT", -4, 6)
            self:LayoutGrid()
        end
        p:SetScript("OnSizeChanged", function(self)
            self:Layout()
            if self.feed.list.Refresh then self.feed.list:Refresh() end
            if self.nextBox.list.Refresh then self.nextBox.list:Refresh() end
        end)

        ----------------------------------------------------------------
        -- Bewegung: Ken-Burns, Partikel, Glanz, Uhr, Countdown (nur solange sichtbar)
        ----------------------------------------------------------------
        local function applyCoords(b, zoom, px, py)
            local W, H = b:GetWidth() or 760, b:GetHeight() or 190
            if W < 50 then W = 760 end
            if H < 50 then H = 190 end
            local asp = b.asp or (16 / 9)
            local us, vs = 1, (H / W) * asp
            if vs > 1 then us, vs = 1 / vs, 1 end
            us, vs = us / zoom, vs / zoom
            local cu = 0.5 + (1 - us) / 2 * px
            local cv = (b.vc or 0.45) + (1 - vs) / 2 * py
            cv = math.max(vs / 2, math.min(1 - vs / 2, cv))
            local vm = b.vmax or 1
            b.img:SetTexCoord(cu - us / 2, cu + us / 2, (cv - vs / 2) * vm, (cv + vs / 2) * vm)
        end
        ban.applyCoords = applyCoords
        local acc, slow = 0, 0
        local function tick(self, el)
            acc = acc + el
            if acc < 0.033 then return end
            local dt = acc
            acc = 0
            self.t = (self.t or 0) + dt
            self.since = (self.since or 0) + dt
            local mov = moving()
            -- Bild: langsames Zoomen/Schwenken (36 s), beim Oeffnen kurzer Zoom von nah
            if self.bgKey then
                local ph = self.t / 36 * math.pi * 2
                local intro = animOn() and math.max(0, 1 - self.since / 1.6) or 0
                local z, px, py = 1.06, 0, 0
                if mov then
                    z = 1.09 + 0.07 * math.sin(ph)
                    px = 0.65 * math.cos(ph * 0.5)
                    py = 0.3 * math.sin(ph)
                end
                applyCoords(self, z + 0.22 * ease(intro) * intro, px, py)
            end
            local W, H = self:GetWidth() or 760, self:GetHeight() or 190
            -- Partikel
            -- ruhiges Banner: keine Glut-Partikel
            self.pf:SetShown(false)
            if false then
                for _, d in ipairs(self.dots) do
                    d.y = d.y + d.vy * dt
                    d.x = d.x + d.vx * dt
                    d.phase = d.phase + dt * d.freq
                    d.flick = d.flick + dt * (6 + math.random() * 6)
                    local rise = d.y / (H * d.life)
                    if rise >= 1 or d.x < -10 or d.x > W + 10 then resetDot(d) rise = 0 end
                    local fadeIn = math.min(1, (d.y + 30) / 50)
                    d.t:SetAlpha(math.max(0, d.a * (1 - rise) ^ 1.3 * fadeIn * (0.75 + 0.25 * math.sin(d.flick))))
                    d.t:ClearAllPoints()
                    d.t:SetPoint("CENTER", self, "BOTTOMLEFT", d.x + math.sin(d.phase) * d.sway, d.y)
                end
            end
            -- Glanz/Lichtpunkt/Namensglanz/Umlaeufer: abgeschaltet (ruhiges Banner); nur das Bild bewegt sich leicht
            if false then
                local c9 = self.t % 9
                if self.sheen.ok and c9 < 2.2 then
                    local q = c9 / 2.2
                    q = q < 0.5 and 2 * q * q or 1 - (-2 * q + 2) ^ 2 / 2
                    self.sheen:ClearAllPoints()
                    self.sheen:SetPoint("TOP") self.sheen:SetPoint("BOTTOM")
                    self.sheen:SetPoint("LEFT", self, "LEFT", -240 + (W + 260) * q, 0)
                    self.sheen:Show()
                else
                    self.sheen:Hide()
                end
                local q = (self.t % 5) / 5
                self.spark:ClearAllPoints()
                self.spark:SetPoint("CENTER", self.line, "LEFT", W * q, 0)
                self.spark:SetAlpha(math.sin(q * math.pi))
                self.spark:Show()
                local anchor = self.logo or self.logoText
                local c4 = (self.t + 1.5) % 4.5
                if anchor and c4 < 1.3 then
                    local q2 = c4 / 1.3
                    local lw = (anchor.GetWidth and anchor:GetWidth()) or 300
                    self.nameShine:ClearAllPoints()
                    self.nameShine:SetPoint("CENTER", anchor, "LEFT", lw * q2, 0)
                    self.nameShine:SetAlpha(0.55 * math.sin(q2 * math.pi))
                else
                    self.nameShine:SetAlpha(0)
                end
                if p.pulseTex then p.pulseTex:SetAlpha(0.5 + 0.5 * math.sin(self.t * 2.4)) end
                -- Lichtrand: zwei Lichtpunkte laufen gegenlaeufig um das Banner (eine Runde ~14 s)
                local per = 2 * (W + H)
                for i, r in ipairs(self.runners) do
                    local s = ((self.t / 14 + (i - 1) * 0.5) % 1) * per
                    local x, y, horiz
                    if s < W then x, y, horiz = s, 0, true
                    elseif s < W + H then x, y = W, -(s - W)
                    elseif s < 2 * W + H then x, y, horiz = W - (s - W - H), -H, true
                    else x, y = 0, -H + (s - 2 * W - H) end
                    if horiz then r:SetSize(110, 5) else r:SetSize(5, 70) end
                    r:ClearAllPoints()
                    r:SetPoint("CENTER", self, "TOPLEFT", x, y)
                    r:SetAlpha(0.75)
                    r:Show()
                end
                -- Buehne und Name atmen ganz leicht
                if self.stage and self.stage:IsShown() then
                    self.stage.halo:SetAlpha(0.18 + 0.07 * math.sin(self.t * 1.1))
                    self.stage.ring:SetAlpha(0.28 + 0.12 * math.sin(self.t * 1.7))
                end
                self.logoGlow:SetAlpha(0.22 + 0.08 * math.sin(self.t * 0.9))
            else
                self.sheen:Hide()
                self.spark:Hide()
                self.nameShine:SetAlpha(0)
                for _, r in ipairs(self.runners) do r:Hide() end
                if self.stage and self.stage.halo then self.stage.halo:SetAlpha(0) self.stage.ring:SetAlpha(0) end
            end
            if p.WowTick then p:WowTick(dt) end
            -- jede Sekunde: Uhr + Countdown-Kachel
            slow = slow + dt
            if slow >= 1 then
                slow = 0
                p:UpdateClock()
            end
        end
        function p:UpdateClock()
            local b = self.ban
            b.clock:SetText(ns.weekday(ns.now()) .. ", " .. date(L["%d.%m. %H:%M"], ns.now()))
            local t3 = self.tiles[3]
            if t3 and t3.ev then t3.value:SetText(countdown((t3.ev.ts or 0) - ns.now())) end
            self:UpdateCountdown()
            -- Tagesziel live (Schritte zaehlen jede Sekunde mit), nur wenn sichtbar
            if self.hl.goal:IsVisible() then self:UpdateGoal(false) end
            -- Karte alle 4 s frisch
            self.mapAcc = (self.mapAcc or 0) + 1
            if self.mapAcc >= 4 and self.feed.tab == "map" then self.mapAcc = 0 self:UpdateMap() end
        end

        ----------------------------------------------------------------
        -- WOW-Teile: Laufzeit (nur ueber tick, also nur bei sichtbarer Seite)
        ----------------------------------------------------------------
        -- Mischung eigener Charakter (0) <-> Held der Woche (1)
        function p:SetHeroMix(mix)
            local b = self.ban
            local ownOk = b.model ~= nil and not b.model.failed
            if not b.heroData then mix = 0 elseif not ownOk then mix = 1 end
            b.mix = mix
            local port = b.heroMode == "portrait"
            local function vis(f, on, alpha)
                if not f then return end
                local was = f:IsShown()
                f:SetShown(on)
                if on then
                    f:SetAlpha(alpha)
                    -- Modelle nach dem Verstecken neu laden (sonst bleiben sie im Client oft leer)
                    if not was and f.Apply and not f.failed then f:Apply() end
                end
            end
            vis(b.model, ownOk and mix < 0.98, 1 - mix)
            vis(b.hero, b.heroData ~= nil and not port and mix > 0.02, mix)
            vis(b.heroPort, b.heroData ~= nil and port and mix > 0.02, mix)
            vis(b.heroPlate, b.heroData ~= nil and mix > 0.02, mix)
            vis(b.crown, b.heroData ~= nil and mix > 0.02, mix)
            -- Krone: beim Portraet direkt auf dem Ring, beim Modell ueber dem Kopf
            if port ~= b.crownPort then
                b.crownPort = port
                b.crown:ClearAllPoints()
                if port then b.crown:SetPoint("CENTER", b.heroPort, "TOP", 0, 1) else b.crown:SetPoint("TOP", b.stage, "TOP", -17, -18) end
            end
            -- Durchsage-Kaertchen weicht dem Helden
            if b.motd.has then vis(b.motd, mix < 0.98, 1 - mix) end
        end
        local function easeIO(q) return q < 0.5 and 2 * q * q or 1 - (-2 * q + 2) ^ 2 / 2 end
        function p:WowTick(dt)
            local b = self.ban
            local anim = animOn()
            -- Held im Wechsel: 12 s ich, 10 s Held, je 1 s Ueberblendung
            if b.heroData then
                b.heroT = (b.heroT or 0) + dt
                local c = b.heroT % 24
                local mix
                if c < 12 then mix = 0 elseif c < 13 then mix = c - 12 elseif c < 23 then mix = 1 else mix = 24 - c end
                if not anim then mix = mix >= 0.5 and 1 or 0 else mix = easeIO(mix) end
                if math.abs((b.mix or -1) - mix) > 0.001 then self:SetHeroMix(mix) end
            end
            -- Ticker
            local tk = b.ticker
            if not tk.place then tk.place = function(el) self:PlaceTicker(el) end end
            -- Willkommen: Schreibmaschine, stehen lassen, ausblenden
            local wl = b.wel
            if wl and wl.active then
                wl.t = wl.t + dt
                local nC = #wl.chars
                local typeDur = anim and math.min(3.2, nC * 0.035) or 0
                local n = typeDur > 0 and math.floor(nC * math.min(1, wl.t / typeDur)) or nC
                if n ~= wl.shown then
                    wl.shown = n
                    b.welcome:SetText(wl.text:sub(1, wl.chars[n] or 0) .. (n < nC and "|cffffd24a_|r" or ""))
                end
                local endT = typeDur + 10
                if wl.t > endT then
                    local q = math.min(1, (wl.t - endT) / 0.8)
                    b.welcome:SetAlpha(1 - q)
                    if q >= 1 then self:EndWelcome() end
                end
            end
            -- Countdown-Ziffern klappen
            local cd = self.hl.cd
            if cd:IsShown() then
                for i, g in ipairs(cd.groups) do
                    if g.flip < 1 then
                        g.flip = math.min(1, g.flip + dt / 0.3)
                        local e = ease(g.flip)
                        g.t:ClearAllPoints()
                        g.t:SetPoint("CENTER", g.tx or 0, (g.ty or 0) + 8 * (1 - e))
                        g.t:SetAlpha(0.2 + 0.8 * e)
                        g.glow:SetAlpha(0.55 * (1 - e))
                    elseif i == 4 and anim then
                        g.glow:SetAlpha(0.08 + 0.08 * math.sin((b.t or 0) * 6.28))
                    end
                end
            end
            -- Tagesziel-Schein, Feuerwerk
            local goal = self.hl.goal
            if goal:IsShown() and goal.data and goal.data.full and anim then
                goal.halo:SetAlpha(0.25 + 0.15 * math.sin((b.t or 0) * 2))
            end
            local fw = self.hl.fw
            if fw.on then
                fw.t = fw.t + dt
                local alive = false
                for _, q in ipairs(fw.parts) do
                    if q.start and fw.t >= q.start then
                        local a = fw.t - q.start
                        if a < q.life then
                            alive = true
                            q.x = q.x + q.vx * dt
                            q.y = q.y + q.vy * dt
                            q.vy = q.vy - 70 * dt
                            q.t:ClearAllPoints()
                            q.t:SetPoint("CENTER", fw, "BOTTOMLEFT", q.x, q.y)
                            q.t:SetAlpha(math.max(0, 1 - a / q.life))
                            q.t:Show()
                        else
                            q.t:Hide()
                        end
                    elseif q.start then
                        alive = true
                    end
                end
                if not alive then fw.on = false fw:Hide() end
            end
            -- Karte: Punkte pulsieren
            local mapF = self.feed.mapF
            if mapF:IsShown() and anim then
                local t = b.t or 0
                for i, d in ipairs(mapF.dots) do
                    if d:IsShown() then d.glow:SetAlpha(0.35 + 0.35 * math.sin(t * 3 + i * 0.7)) end
                end
            end
            -- untere Karte wechselt alle 14 s (nicht unter der Maus, nicht ohne Animation)
            local hl = self.hl
            if hl:IsShown() and anim then
                local over = false
                if hl.IsMouseOver then local ok, r = pcall(hl.IsMouseOver, hl) over = ok and r end
                if not over then
                    hl.rotT = (hl.rotT or 0) + dt
                    if hl.rotT >= 14 then hl.rotT = 0 self:NextHlTab() end
                end
            end
        end

        -- Ticker
        function p:SetTicker(list)
            local tk = self.ban.ticker
            local key = table.concat(list, "\1")
            if key ~= tk.key then
                tk.key = key
                for i, txt in ipairs(list) do
                    local it = tk.items[i]
                    if not it then
                        it = { fs = K.Text(tk.clip, 10, { 0.9, 0.9, 0.92 }), dot = tk.clip:CreateTexture(nil, "ARTWORK") }
                        it.dot:SetTexture(ns.MEDIA .. "dot")
                        it.dot:SetSize(5, 5)
                        it.dot:SetVertexColor(1, 0.82, 0.42)
                        it.fs:SetWordWrap(false)
                        tk.items[i] = it
                    end
                    it.fs:SetText(txt)
                    it.fs:Show() it.dot:Show()
                    local w = tonumber(it.fs:GetStringWidth()) or 0
                    if w <= 0 then w = #(txt:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h", ""):gsub("|h", "")) * 5.5 end
                    it.w = math.floor(math.min(w, 700) + 40)
                end
                for i = #list + 1, #tk.items do tk.items[i].fs:Hide() tk.items[i].dot:Hide() end
                tk.n = #list
            end
            tk:SetShown(tk.n > 0 and S().dashTicker ~= false)
            self:PlaceTicker(0)
        end
        function p:PlaceTicker(dt)
            local tk = self.ban.ticker
            if (tk.n or 0) == 0 then return end
            local cw = tk.clip:GetWidth() or 600
            if cw < 50 then cw = 600 end
            local sum, maxW = 0, 0
            for i = 1, tk.n do sum = sum + tk.items[i].w maxW = math.max(maxW, tk.items[i].w) end
            local total = math.max(sum, cw + maxW + 40)
            if not animOn() then tk.off = 0
            elseif not tk.paused then tk.off = (tk.off + 32 * dt) % total end
            local cum = 0
            for i = 1, tk.n do
                local it = tk.items[i]
                -- ohne Runden und ohne Pixelraster: weiches Gleiten statt ruckelnder 1-Pixel-Spruenge
                local x = ((cum - tk.off + maxW) % total) - maxW
                if not it.smooth then
                    it.smooth = true
                    for _, o in ipairs({ it.dot, it.fs }) do
                        if o.SetSnapToPixelGrid then o:SetSnapToPixelGrid(false) end
                        if o.SetTexelSnappingBias then o:SetTexelSnappingBias(0) end
                    end
                    it.dot:ClearAllPoints()
                    it.fs:ClearAllPoints()
                end
                it.dot:SetPoint("LEFT", tk.clip, "LEFT", x, 0)
                it.fs:SetPoint("LEFT", tk.clip, "LEFT", x + 11, 0)
                cum = cum + it.w
            end
        end

        -- Willkommen zurueck
        function p:PlayWelcome(text)
            local b = self.ban
            local chars = {}
            for pos, ch in text:gmatch("()([%z\1-\127\194-\244][\128-\191]*)") do chars[#chars + 1] = pos + #ch - 1 end
            b.wel = { active = true, t = 0, text = text, chars = chars, shown = -1 }
            b.welcome:SetText("")
            b.welcome:SetAlpha(1)
            b.welcome:Show()
            b.line2:Hide()
            b.greet:ClearAllPoints()
            b.greet:SetPoint("BOTTOMLEFT", b.welcome, "TOPLEFT", 0, 4)
        end
        function p:EndWelcome()
            local b = self.ban
            if b.wel then b.wel.active = false end
            b.welcome:Hide()
            b.greet:ClearAllPoints()
            b.greet:SetPoint("BOTTOMLEFT", b.line2, "TOPLEFT", 0, 6)
            b.greet:SetText(b.greetNormal or "")
            b.line2:Show()
            if animOn() then K.FadeIn(b.line2, 0) K.FadeIn(b.greet, 0) end
        end

        -- Held laden (nur wenn sich Person oder Einheit aendert)
        function p:LoadHero(h)
            local b = self.ban
            if not h then
                b.heroData, b.heroKey, b.heroMode = nil, nil, nil
                self:SetHeroMix(0)
                return
            end
            local unit = unitFor(h.name)
            local key = h.name .. "#" .. tostring(unit)
            b.heroData = h
            local plate = b.heroPlate
            plate.name:SetText(ns.Radar.Colored(h.name))
            plate.why:SetText(h.reason or "")
            -- Schild so breit wie der laengste Text (+ Rand), nie breiter als die Buehne
            local tw = math.max(tonumber(plate.name:GetStringWidth()) or 0, tonumber(plate.why:GetStringWidth()) or 0, tonumber(plate.kick:GetStringWidth()) or 0)
            plate.fitW = math.max(150, math.floor(tw + 32))
            plate:SetWidth(math.min(plate.maxW or 220, plate.fitW))
            local cls = ns.Radar.ClassOf and ns.Radar.ClassOf(h.name)
            local cr, cg, cb = ns.classColor(cls)
            cr, cg, cb = cr or 0.8, cg or 0.8, cb or 0.8
            local hp = b.heroPort
            hp.who, hp.why = h.name, h.reason
            hp.ring:SetVertexColor(cr, cg, cb)
            hp.glow:SetVertexColor(cr, cg, cb)
            if setClassIcon(hp.icon, cls) then hp.icon:Show() hp.letter:Hide()
            else
                hp.icon:Hide()
                hp.letter:SetText(K.Upper((ns.displayName(h.name) or "?"):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"))
                hp.letter:SetTextColor(cr, cg, cb)
                hp.letter:Show()
            end
            if b.hero then b.hero.who, b.hero.why = h.name, h.reason end
            if key == b.heroKey then return end
            b.heroKey = key
            local m, method = b.hero, "portrait"
            if m then
                local pr = ns.db.members and ns.db.members[h.name]
                if unit then m.unit, m.look, method = unit, nil, "unit"
                elseif type(pr) == "table" and tonumber(pr.rc) and tonumber(pr.rc) > 0 and m.SetCustomRace then
                    m.unit, m.look, method = nil, { race = tonumber(pr.rc), sex = tonumber(pr.sx) or 0 }, "race"
                end
                if method ~= "portrait" then
                    m:Apply()
                    if m.failed then method = "portrait" end
                end
            end
            b.heroMode = method
            Info.heroMethod = method
            b.mix = -1
            -- kommt kein Modell an (Forever kann Volksmodelle verweigern): Portraet
            if method ~= "portrait" and m and m.GetModelFileID then
                ns.After(0.8, function()
                    if b.heroKey ~= key then return end
                    local ok, id = pcall(m.GetModelFileID, m)
                    if ok and not (id and id ~= 0) and m:IsShown() then
                        b.heroMode = "portrait"
                        Info.heroMethod = "portrait (kein Modell)"
                        b.mix = -1
                    end
                end)
            end
        end

        -- Reiter der Feed-Karte
        function p:SetFeedTab(key)
            local f = self.feed
            local changed = f.tab ~= key
            f.tab = key
            f:MarkChips(key)
            f.list:SetShown(key == "feed")
            f.empty:SetShown(key == "feed" and f.isEmpty == true)
            f.mapF:SetShown(key == "map")
            f.pulseF:SetShown(key == "pulse")
            f.head.text:SetText(K.Upper(L[key == "map" and "Gildenkarte" or key == "pulse" and "Gilden-Puls" or "Was gerade passiert"]))
            if key == "map" then self:UpdateMap() elseif key == "pulse" then self:UpdatePulse(changed) end
            if changed and animOn() and key ~= "feed" then K.FadeIn(key == "map" and f.mapF or f.pulseF, 0) end
        end

        -- Gildenkarte
        function p:UpdateMap()
            -- beide Kontinente nebeneinander; Klick auf eine Karte oeffnet die Weltkarte dort
            local mapF = self.feed.mapF
            local pts, _, count = Info.MapPoints()
            mapF.art:Hide()
            mapF.label:Hide()
            mapF.none:Hide()
            for _, t in ipairs(mapF.tiles) do t:Hide() end
            for _, d in ipairs(mapF.dots) do d:Hide() end
            mapF.panels = mapF.panels or {}
            local mw, mh = mapF:GetWidth() or 250, mapF:GetHeight() or 130
            if mw < 20 then mw = 250 end
            if mh < 20 then mh = 130 end
            local GAP, LBL = 10, 16
            local pw, ph = math.floor((mw - GAP) / 2), mh - LBL
            for idx, cont in ipairs({ 1414, 1415 }) do
                local pn = mapF.panels[cont]
                if not pn then
                    pn = CreateFrame("Button", nil, mapF)
                    pn.cont = cont
                    pn.art = CreateFrame("Frame", nil, pn)
                    pn.art:SetClipsChildren(true)
                    pn.art.bg = pn.art:CreateTexture(nil, "BACKGROUND")
                    pn.art.bg:SetAllPoints()
                    pn.art.bg:SetColorTexture(0.12, 0.13, 0.15, 1)
                    pn.art.big = K.Text(pn.art, 11, C.dim, "CENTER")
                    pn.art.big:SetPoint("CENTER")
                    pn.art.big:SetText(L[CONT[cont]])
                    K.Border(pn.art, { 1, 1, 1, 0.10 })
                    pn.tiles, pn.dots = {}, {}
                    pn.label = K.Text(pn, 10, C.muted)
                    pn.label:SetWordWrap(false)
                    pn.count = K.Text(pn, 10, C.text, "RIGHT")
                    local okL, layers = pcall(function() return C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(cont) end)
                    local okT, texs = pcall(function() return C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(cont, 1) end)
                    local L1 = okL and type(layers) == "table" and layers[1]
                    if L1 and okT and type(texs) == "table" and #texs > 0 and (L1.layerWidth or 0) > 0 and (L1.tileWidth or 0) > 0 then
                        pn.layer = { w = L1.layerWidth, h = L1.layerHeight, tw = L1.tileWidth, th = L1.tileHeight,
                            cols = math.ceil(L1.layerWidth / L1.tileWidth) }
                        for i, tex in ipairs(texs) do
                            local t = pn.art:CreateTexture(nil, "BORDER")
                            t:SetTexture(tex)
                            t:SetVertexColor(0.78, 0.78, 0.82)
                            pn.tiles[i] = t
                        end
                    end
                    pn.art.big:SetShown(pn.layer == nil)
                    pn:SetScript("OnClick", function(self)
                        if ns.Map and ns.Map.ShowOnWorldMap then ns.Map.ShowOnWorldMap(self.cont)
                        elseif ToggleWorldMap then pcall(ToggleWorldMap) end
                    end)
                    pn:SetScript("OnEnter", function(self)
                        for _, t in ipairs(self.tiles) do t:SetVertexColor(0.95, 0.95, 1) end
                        K.ShowTip(self, { L[CONT[self.cont]], (L["%d hier"]):format(self.n or 0), "|cff888888" .. L["Auf der Weltkarte zeigen"] .. "|r" })
                    end)
                    pn:SetScript("OnLeave", function(self)
                        for _, t in ipairs(self.tiles) do t:SetVertexColor(0.78, 0.78, 0.82) end
                        GameTooltip:Hide()
                    end)
                    mapF.panels[cont] = pn
                end
                pn:ClearAllPoints()
                pn:SetPoint("TOPLEFT", (idx - 1) * (pw + GAP), 0)
                pn:SetSize(pw, mh)
                -- Bild einpassen (Seitenverhaeltnis halten), senkrecht mittig ueber der Beschriftung
                local asp = pn.layer and (pn.layer.w / pn.layer.h) or 1.5
                local w, h = pw, pw / asp
                if h > ph then h, w = ph, ph * asp end
                pn.art:ClearAllPoints()
                pn.art:SetPoint("TOP", pn, "TOP", 0, -math.floor((ph - h) / 2))
                pn.art:SetSize(w, h)
                if pn.layer then
                    local ly = pn.layer
                    local sc = w / ly.w
                    for i, t in ipairs(pn.tiles) do
                        local col, row = (i - 1) % ly.cols, math.floor((i - 1) / ly.cols)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", pn.art, "TOPLEFT", col * ly.tw * sc, -row * ly.th * sc)
                        t:SetSize(ly.tw * sc, ly.th * sc)
                    end
                end
                -- Beschriftung unter der Karte, buendig mit dem Bild
                pn.label:ClearAllPoints()
                pn.label:SetPoint("TOPLEFT", pn.art, "BOTTOMLEFT", 0, -4)
                pn.label:SetPoint("RIGHT", pn.art, "RIGHT", -20, 0)
                pn.label:SetText(L[CONT[cont]])
                pn.count:ClearAllPoints()
                pn.count:SetPoint("TOPRIGHT", pn.art, "BOTTOMRIGHT", 0, -4)
                local n = 0
                for _, pt in ipairs(pts) do
                    if pt.cont == cont then
                        n = n + 1
                        local d = pn.dots[n]
                        if not d then
                            d = CreateFrame("Button", nil, pn.art)
                            d:SetSize(12, 12)
                            d.edge = d:CreateTexture(nil, "BORDER")
                            d.edge:SetTexture(CIRCLE)
                            d.edge:SetVertexColor(0, 0, 0, 0.9)
                            d.edge:SetPoint("CENTER")
                            d.dot = d:CreateTexture(nil, "ARTWORK")
                            d.dot:SetTexture(CIRCLE)
                            d.dot:SetPoint("CENTER")
                            d:SetScript("OnEnter", function(self)
                                local m = ns.Radar.byName and ns.Radar.byName[self.who]
                                K.ShowTip(self, { ns.Radar.Colored(self.who), m and (m.zone or "") or "", "|cff888888" .. L["Klick: auf der Weltkarte zeigen"] .. "|r" })
                            end)
                            d:SetScript("OnLeave", function() GameTooltip:Hide() end)
                            d:SetScript("OnClick", function(self)
                                local m = ns.Radar.byName and ns.Radar.byName[self.who]
                                if ns.Map and ns.Map.ShowMember then ns.Map.ShowMember(self.who, m and m.zone, m and m.aname) end
                            end)
                            pn.dots[n] = d
                        end
                        d.who = pt.name
                        local cr, cg, cb = ns.classColor(ns.Radar.ClassOf and ns.Radar.ClassOf(pt.name))
                        d.dot:SetVertexColor(cr or 0.9, cg or 0.9, cb or 0.9)
                        local sz = pt.me and 9 or 7
                        d.dot:SetSize(sz, sz)
                        d.edge:SetSize(sz + 2, sz + 2)
                        d:SetFrameLevel(pn.art:GetFrameLevel() + 2)
                        d:ClearAllPoints()
                        d:SetPoint("CENTER", pn.art, "TOPLEFT", pt.x * w, -pt.y * h)
                        d:Show()
                    end
                end
                for i = n + 1, #pn.dots do pn.dots[i]:Hide() end
                pn.n = n
                pn.count:SetText(n > 0 and tostring(n) or "")
                pn:Show()
            end
        end

        -- Gilden-Puls
        function p:UpdatePulse(anim)
            local pf = self.feed.pulseF
            local d = Info.Pulse()
            pf.data = d
            pf.peak:SetText(d.peak and ("|cffffd24a" .. (L["Stosszeit %s Uhr"]):format(d.peak) .. "|r") or L["Noch zu wenig Daten fuer eine Stosszeit"])
            pf.sub:SetText((L["Heute bis zu %d gleichzeitig online  ·  jetzt %d"]):format(d.dayMax, d.now))
            local cw, ch = pf.chart:GetWidth() or 250, pf.chart:GetHeight() or 80
            if cw < 40 then cw = 250 end
            if ch < 20 then ch = 80 end
            local bw = cw / 48
            local mint = C.mint
            local heights = {}
            for k = 0, 47 do
                local bar = pf.bars[k]
                -- gemeinsame Skala fuer heute + typischen Tag (vorher je eigenes Maximum -> alles "voll"),
                -- Obergrenze = groesster Wert + Luft, mindestens 5 Spieler
                local top = math.max(5, math.ceil(math.max(d.typMax or 0, d.dayMax or 0) * 1.25))
                local th = ((d.typ[k] or 0) / top) * ch
                local dh = ((d.today[k] or 0) / top) * ch
                bar.typ:ClearAllPoints()
                bar.typ:SetPoint("BOTTOMLEFT", pf.chart, "BOTTOMLEFT", k * bw, 0)
                bar.typ:SetSize(math.max(1, bw - 1), math.max(1, th))
                bar.typ:SetShown(th > 0)
                bar.day:ClearAllPoints()
                bar.day:SetPoint("BOTTOMLEFT", pf.chart, "BOTTOMLEFT", k * bw + bw * 0.2, 0)
                bar.day:SetWidth(math.max(1, bw * 0.6))
                local cur = k == d.cur
                local c = cur and C.accent or mint
                bar.day:SetColorTexture(c[1], c[2], c[3], cur and 1 or 0.8)
                bar.day:SetShown(dh > 0)
                bar.day:SetHeight(math.max(1, dh))
                heights[k] = math.max(1, dh)
            end
            if anim and animOn() then
                K.Tween(pf, 0.8, function(q)
                    local e = ease(q)
                    for k = 0, 47 do pf.bars[k].day:SetHeight(math.max(1, heights[k] * e)) end
                end)
            end
            local nx = (d.cur + 0.5) * bw
            pf.nowLine:ClearAllPoints()
            pf.nowLine:SetPoint("BOTTOM", pf.chart, "BOTTOMLEFT", nx, 0)
            pf.nowLine:SetHeight(ch)
            pf.nowGlow:ClearAllPoints()
            pf.nowGlow:SetPoint("CENTER", pf.chart, "BOTTOMLEFT", nx, heights[d.cur] or 1)
            for _, a in ipairs(pf.axis) do
                a.fs:ClearAllPoints()
                a.fs:SetPoint("TOPLEFT", pf.chart, "BOTTOMLEFT", a.slot * bw, -2)
            end
        end

        -- untere Karte
        function p:SetHlTab(key)
            local hl = self.hl
            hl.avail = hl.avail or {}
            if not hl.avail[key] then
                key = nil
                for _, k in ipairs(hl.order) do if hl.avail[k] then key = k break end end
                key = key or "tasks"
            end
            local changed = hl.tab ~= key
            hl.tab = key
            hl:MarkChips(key)
            for _, b in ipairs(hl.chips) do b:SetShown(hl.avail[b.key] == true) end
            hl.wk:SetShown(key == "tasks" and hl.hasTasks == true)
            hl.empty:SetShown(key == "tasks" and not hl.hasTasks)
            hl.cd:SetShown(key == "count")
            hl.mo:SetShown(key == "motd")
            hl.goal:SetShown(key == "goal")
            hl.rec:SetShown(key == "rec")
            if key == "rec" then self:RecPage(0) end
            local hd = hl.heads[key] or {}
            hl.head.text:SetText(K.Upper(hd[1] or L["Gilden-Highlight"]) .. (hd[3] or ""))
            hl.head:SetCount((not hl.narrow) and hd[2] or nil)
            if changed then
                if key == "count" then self:AnimReadiness() end
                if key == "goal" then self:UpdateGoal(true) end
                local pg = (key == "motd" and hl.mo) or (key == "count" and hl.cd) or (key == "goal" and hl.goal) or (key == "rec" and hl.rec) or hl.wk
                if animOn() and pg:IsShown() then K.FadeIn(pg, 0) end
            end
        end
        function p:NextHlTab()
            local hl = self.hl
            local o, cur = hl.order, 1
            for i, k in ipairs(o) do if k == hl.tab then cur = i end end
            for s = 1, #o do
                local k = o[(cur - 1 + s) % #o + 1]
                if hl.avail and hl.avail[k] then self:SetHlTab(k) return end
            end
        end

        -- Countdown jede Sekunde
        function p:UpdateCountdown()
            local cd = self.hl.cd
            local hl = self.hl
            local now = ns.now()
            if not cd.target or now >= cd.target or now - (cd.checked or 0) > 30 then
                cd.checked = now
                cd.target, cd.title, cd.ev = Info.CountdownTarget()
                cd.whenText = (cd.target and not cd.ev) and (L["Start"] .. ": " .. date("%d.%m.%Y, %H:%M", cd.target) .. " " .. L["Uhr (deine Ortszeit)"]) or nil
                cd.bars:SetShown(cd.ev ~= nil and cd.bars:IsShown())
                cd:Center(cd.ev == nil)
                local on = cd.target ~= nil and S().dashCountdown ~= false
                if (hl.avail.count == true) ~= on then
                    hl.avail.count = on
                    if not on and hl.tab == "count" then self:SetHlTab("tasks") else self:SetHlTab(hl.tab or "count") end
                end
                hl.heads.count = { cd.title or L["Raid-Countdown"], cd.target and date("%d.%m.%Y %H:%M", cd.target) or nil,
                    -- Glas: Startzeit dezent hinter dem Titel (statt eigener Zeile in der Karte)
                    (cd.round and cd.target) and ("   |cff8c8c94" .. date("%d.%m. %H:%M", cd.target) .. "|r") or nil }   -- Ortszeit des Spielers
                if hl.tab == "count" then
                    hl.head.text:SetText(K.Upper(hl.heads.count[1]) .. (hl.heads.count[3] or ""))
                    hl.head:SetCount((not hl.narrow) and hl.heads.count[2] or nil)
                end
            end
            if not cd.target then return end
            local left = math.max(0, cd.target - now)
            local vals = { math.floor(left / 86400), math.floor(left % 86400 / 3600), math.floor(left % 3600 / 60), math.floor(left % 60) }
            local anim = animOn() and cd:IsShown()
            for i, g in ipairs(cd.groups) do
                local s = ("%02d"):format(vals[i])
                if g.val ~= s then
                    g.val = s
                    g.t:SetText(s)
                    if anim and g.inited then g.flip = 0 else g.flip = 1 g.t:ClearAllPoints() g.t:SetPoint("CENTER", g.tx or 0, g.ty or 0) g.t:SetAlpha(1) end
                    g.inited = true
                end
            end
        end
        -- Bereitschaft (Werte) + Balken
        function p:SetReadiness(r)
            local rows = self.hl.cd.rows
            local defs = {
                { L["Stufe 60"], r.lvl60, math.max(1, r.total), C.amber, true },
                { L["Onyxia freigeschaltet"], r.unlocked, math.max(1, r.lvl60), C.violet or C.accent, r.unlocked ~= nil },
                { L["Raid-Vorbereitung gruen"], r.prepG, math.max(1, r.prepN or 1), C.mint, r.prepG ~= nil },
            }
            local i = 0
            for _, d in ipairs(defs) do
                if d[5] then
                    i = i + 1
                    local row = rows[i]
                    row.t:SetText(d[1])
                    row.v:SetText((d[2] or 0) .. " / " .. (d == defs[1] and r.total or d[3]))
                    row.fill:SetColorTexture(d[4][1], d[4][2], d[4][3], 0.95)
                    row.ratio = math.min(1, (d[2] or 0) / d[3])
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -(i - 1) * 19)
                    row:SetPoint("RIGHT", 0, 0)
                    row:Show()
                    local w = row.track:GetWidth() or 120
                    if w < 10 then w = 120 end
                    row.fill:SetWidth(math.max(1, w * row.ratio))
                end
            end
            for j = i + 1, #rows do rows[j]:Hide() end
        end
        function p:AnimReadiness()
            if not animOn() then return end
            for k, row in ipairs(self.hl.cd.rows) do
                if row:IsShown() then
                    local w = row.track:GetWidth() or 120
                    if w < 10 then w = 120 end
                    local target = math.max(1, w * (row.ratio or 0))
                    row.fill:SetWidth(1)
                    K.Tween(row.fill, 1.1, function(q) row.fill:SetWidth(math.max(1, target * ease(q))) end, nil, 0.15 + k * 0.12)
                end
            end
        end

        -- Tagesziel
        function p:UpdateGoal(anim)
            local goal = self.hl.goal
            local g = Info.DailyGoal()
            goal.data = g
            local sig = ("%.3f:%.3f:%.3f"):format(g.r1, g.r2, g.r3)
            if anim or goal.sig ~= sig then
                goal.sig = sig
                goal.ringF:Set({ g.r1, g.r2, g.r3 }, anim and animOn())
            end
            for i, r in ipairs({ g.r1, g.r2, g.r3 }) do
                local b = goal.bars[i]
                b.ratio = r
                local w = b.track:GetWidth() or 0
                if w > 2 then b.fill:SetWidth(math.max(1, w * math.min(1, r))) end
            end
            local function col(c, s) return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, s) end
            local R = goal.rcol
            goal.lines[1]:SetText(L["Schritte"])
            goal.vals[1]:SetText(fmtNum(g.steps) .. " |cff6b6b70/ " .. fmtNum(g.stepGoal) .. "|r")
            -- zu Pferd/Flug zaehlt nicht: Hinweis, statt still bei 0 zu bleiben
            local mounted = (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player"))
            goal.lines[2]:SetText(L["XP heute"])
            goal.vals[2]:SetText(g.xpGoal > 0 and (fmtNum(g.xp) .. " |cff6b6b70/ " .. fmtNum(g.xpGoal) .. "|r") or ("|cff888888" .. L["Hoechststufe"] .. "|r"))
            goal.lines[3]:SetText(L["Wochenaufgaben"])
            goal.vals[3]:SetText(g.tasks .. " |cff6b6b70/ " .. g.taskN .. "|r")
            goal.msg:SetText(g.full and ("|cff66db9e" .. L["Tagesziel geschafft - stark!"] .. "|r")
                or (mounted and ("|cffe8b44a" .. L["Schritte laufen nur zu Fuss (kein Reittier, kein Flug)."] .. "|r"))
                or L["Schritte laufen nur zu Fuss (kein Reittier, kein Flug)."])
            self.hl.heads.goal = { L["Dein Tagesziel"], (math.floor((g.r1 + g.r2 + g.r3) / 3 * 100)) .. " %" }
            -- Feuerwerk: einmal am Tag (Demo: einmal je Sitzung), sobald alle drei Ringe voll sind
            if g.full and goal:IsShown() then
                local c = ns.char or ns.db
                local day = date("%Y-%m-%d")
                if demoOn() then
                    if not Info.demoFw then Info.demoFw = true self:Fireworks(1.3) end
                elseif c and c.dashFw ~= day then
                    c.dashFw = day
                    self:Fireworks(1.3)
                end
            end
        end
        function p:Fireworks(delay)
            if not animOn() then return end
            local fw = self.hl.fw
            local w, h = self.hl:GetWidth() or 400, self.hl:GetHeight() or 100
            if w < 50 then w = 400 end
            if h < 30 then h = 100 end
            local cols = { C.mint, C.amber, C.pink or C.accent, C.accent, { 1, 1, 1 } }
            local per = math.floor(#fw.parts / 3)
            for i, q in ipairs(fw.parts) do
                local burst = math.min(2, math.floor((i - 1) / per))
                local bx = w * (0.2 + 0.3 * burst) + (burst == 1 and -20 or 0)
                local by = h * (0.45 + 0.15 * (burst % 2))
                local a = math.random() * 2 * math.pi
                local sp = 40 + math.random() * 70
                q.x, q.y = bx, by
                q.vx, q.vy = math.cos(a) * sp, math.sin(a) * sp + 15
                q.life = 0.9 + math.random() * 0.6
                q.start = (delay or 0) + burst * 0.35
                local c = cols[(i + burst) % #cols + 1]
                q.t:SetVertexColor(c[1], c[2], c[3])
                local sz = 4 + math.random() * 7
                q.t:SetSize(sz, sz)
                q.t:Hide()
            end
            fw.t, fw.on = 0, true
            fw:Show()
        end

        -- Rekorde
        -- Rekorde blaettern (dir -1/+1, 0 = nur anzeigen)
        function p:RecPage(dir)
            local rec = self.hl.rec
            rec.pg = ((rec.pg or 1) - 1 + (dir or 0)) % rec.pages + 1
            for i, c in ipairs(rec.cells) do c:SetShown(math.ceil(i / 2) == rec.pg) end
            for i, d in ipairs(rec.dots) do
                local cc = i == rec.pg and C.text or C.dim
                d:SetVertexColor(cc[1], cc[2], cc[3], i == rec.pg and 0.9 or 0.5)
            end
            if dir ~= 0 and animOn() then
                for i, c in ipairs(rec.cells) do if c:IsShown() then K.FadeIn(c, 0) end end
            end
        end
        function p:UpdateRecords()
            local cells = self.hl.rec.cells
            for i, r in ipairs(Info.Records()) do
                local c = cells[i]
                if c then
                    c.icon:SetTexture(r.icon or ns.ICONS.badges)
                    c.icon:SetVertexColor(r.color[1], r.color[2], r.color[3])
                    c.t:SetText(r.title)
                    c.v:SetText(r.who and (ns.Radar.Colored(r.who) .. "  |cffd8d8dc" .. (r.value or "") .. "|r") or ("|cff666666" .. L["noch kein Rekord"] .. "|r"))
                    c.page = r.page
                    c.tip = { r.title, r.who and (ns.displayName(r.who) .. "  -  " .. (r.value or "")) or L["noch kein Rekord"] }
                end
            end
        end
        -- Fehler im Bild-Takt nur EINMAL melden und den Takt abschalten (sonst feuert er jedes Bild)
        local function safeTick(self, el)
            local ok, e = pcall(tick, self, el)
            if not ok then
                self:SetScript("OnUpdate", nil)
                p.motionBroken = true
                if ns.err then ns.err("Dashboard", e) end
            end
        end
        function p:StartMotion()
            self.ban.since = 0
            if self.motionBroken then return end
            self.ban:SetScript("OnUpdate", safeTick)
        end
        p:HookScript("OnShow", function(self)
            self.fresh = true
            self:StartMotion()
            -- Modell nach dem Verstecken neu laden (sonst bleibt es im Client oft leer)
            if self.ban.model and not self.ban.model.failed then self.ban.model:Apply() end
            if self.ban.hero and self.ban.heroData and self.ban.heroMode ~= "portrait" and not self.ban.hero.failed then self.ban.hero:Apply() end
        end)
        if ban.model then ban.model:Apply() end
        p:HookScript("OnHide", function(self) self.ban:SetScript("OnUpdate", nil) end)
        p:StartMotion()

        -- Hintergrund waehlen (auch nach Einstellungsaenderung)
        function p:ApplyBackground()
            local k = pickBackground(self.ban.img)
            self.ban.bgKey = k
            if k then
                self.ban.asp, self.ban.vc, self.ban.vmax = BG[k][2], BG[k][3], BG[k][4]
                self.ban.img:Show()
                applyCoords(self.ban, 1.08, 0, 0)
            else
                self.ban.img:Hide()
            end
        end
        p:ApplyBackground()
        p:Layout()
    end,

    refresh = function(p)
        local fresh = p.fresh
        local doAnim = fresh and animOn()
        local R = ns.Radar
        local ban = p.ban

        ----------------------------------------------------------------
        -- Banner
        ----------------------------------------------------------------
        local guild = (ns.Admin and ns.Admin.GuildName and ns.Admin.GuildName()) or (GetGuildInfo and GetGuildInfo("player"))
        ban.kicker:SetText(K.Upper(L["Oasis"] .. "  ·  " .. L["Dashboard"]))
        if ban.logo and ban.logo.Apply then pcall(ban.logo.Apply, ban.logo) end
        if ban.logoText then ban.logoText:SetText(K.Upper(guild or "Oasis")) end
        local _, classFile = UnitClass("player")
        local cr, cg, cb = ns.classColor(ns.safe(classFile))
        local myCol = ("|cff%02x%02x%02x"):format((cr or 1) * 255, (cg or 1) * 255, (cb or 1) * 255) .. ns.displayName(ns.me()) .. "|r"
        ban.greetNormal = greeting() .. ", " .. myCol
        -- Willkommen zurueck: einmal je Sitzung, mit dem, was seit dem letzten Besuch passiert ist
        -- nur wenn die Seite wirklich zu sehen ist (Hintergrund-Refresh zaehlt nicht als Besuch)
        local seen = true
        if p.IsVisible then local okV, v = pcall(p.IsVisible, p) seen = not okV or v and true or false end
        if seen and Info.lastVisit == nil then Info.lastVisit = tonumber(ns.db.dashSeen) or false end
        if seen and not Info.welcomeDone and S().dashWelcome ~= false then
            Info.welcomeDone = true
            local last = Info.lastVisit
            if demoOn() and (not last or ns.now() - last < 2 * 86400) then last = ns.now() - 2 * 86400 - 3 * 3600 end
            if last and ns.now() - last >= 1800 then
                local ok, txt = pcall(Info.WelcomeText, last)
                if ok and txt then p:PlayWelcome(txt) end
            end
        end
        if seen then ns.db.dashSeen = ns.now() end
        if ban.wel and ban.wel.active then
            ban.greet:SetText(L["Willkommen zurueck"] .. ", " .. myCol)
        else
            ban.greet:SetText(ban.greetNormal)
        end
        local on = computeOnline()
        p.onlineList = on
        local nOn = #on
        local ev, isRaid = nextRaid()
        local parts = { (L["%d online"]):format(nOn) }
        if ev then
            local left = (ev.ts or 0) - ns.now()
            local fmt = isRaid and L["naechster Raid in %s"] or L["naechster Termin in %s"]
            parts[#parts + 1] = left > 0 and fmt:format(countdown(left)) or ((ev.title or "?") .. " " .. L["laeuft"])
        else
            parts[#parts + 1] = L["kein Termin geplant"]
        end
        local unread = chatUnread()
        if unread > 0 then parts[#parts + 1] = (L["%d neue im Gildenchat"]):format(unread) end
        ban.line2:SetText(table.concat(parts, "  |cff888888·|r  "))

        -- Durchsage (3 Tage) vor Nachricht des Tages -> stehen jetzt in der Kachel "Gildennachricht",
        -- das Glas-Kaertchen im Banner bleibt deshalb aus (sonst doppelt)
        local note = ns.Admin and ns.Admin.LatestNotice and ns.Admin.LatestNotice()
        local motdText = Info.MOTD()
        ban.motd.has = false
        ban.motd.tip = nil
        ban.motd:Hide()
        ban.info:SetShown(Info.Text() ~= "" and (not ns.GuildView or ns.GuildView()))
        if ns.GuildView and not ns.GuildView() then
            local lv = ns.safe(UnitLevel("player")) or 0
            local zn = ns.safe(GetRealZoneText()) or ""
            ban.line2:SetText((L["Level %d"]):format(lv) .. (zn ~= "" and ("  |cff888888·|r  " .. zn) or "") .. "  |cff888888·|r  " .. L["ohne Gilde unterwegs"])
        end

        -- Held der Woche
        local hero = nil
        if S().dashHero ~= false then
            local okH, h = pcall(Info.Hero)
            hero = okH and h or nil
        end
        -- Held steht nicht mehr im Banner (ueberlappte), sondern rechts in "Wer ist online" im Wechsel mit dem Pechvogel
        p:LoadHero(nil)
        if ban.stage then ban.stage:SetShown(ban.model ~= nil and not ban.model.failed) end
        p:SetHeroMix(0)
        do
            local list = {}
            if hero then list[#list + 1] = { kind = "hero", name = hero.name, reason = hero.reason } end
            local okU, u = pcall(Info.Unlucky)
            if okU and u and (not hero or u.name ~= hero.name) then list[#list + 1] = { kind = "unl", name = u.name, reason = u.reason } end
            local sp = p.online.spot
            local key = ""
            for _, it in ipairs(list) do key = key .. it.kind .. it.name .. (it.reason or "") end
            if sp.key ~= key then sp.key = key sp:SetData(list) if p.Layout then pcall(p.Layout, p) elseif p.LayoutGrid then p:LayoutGrid() end end   -- 0.6.174: ganzes Layout (Breite der Online-Box + eigene Box)
            p.online.grid:SetPoint("BOTTOMRIGHT", -8, 6)
        end

        -- Live-Ticker: Held + letzte Ereignisse der Chronik
        local tlist = {}
        if hero then
            tlist[#tlist + 1] = "|cffffd24a" .. L["Held der Woche:"] .. "|r " .. ns.Radar.Colored(hero.name) .. "  |cffa3a3a8" .. (hero.reason or "") .. "|r"
        end
        do
            local chr = ns.Store.List("chronicle")
            table.sort(chr, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
            for _, e in ipairs(chr) do
                if #tlist >= 14 then break end
                if e.kind ~= "news" or e.item then
                    local okT, txt = pcall(function()
                        local item = ns.Chronicle and ns.Chronicle.Item(e)
                        local c = KIND_COLOR[e.kind] or C.muted
                        local tag = ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
                        return ns.Radar.Label(e.who) .. " " .. tag .. ((ns.Chronicle and ns.Chronicle.Text(e)) or "") .. "|r" .. (item and (" " .. item) or "")
                            .. "  |cff777777" .. ns.ago(e.ts) .. "|r"
                    end)
                    if okT and txt then tlist[#tlist + 1] = txt end
                end
            end
        end
        if ns.GuildView and not ns.GuildView() then
            tlist = {}
            local life = ns.char and ns.char.life
            for _, e in ipairs((life and life.events) or {}) do
                if #tlist >= 10 then break end
                if type(e.x) == "string" and e.x ~= "" then
                    tlist[#tlist + 1] = e.x .. "  |cff777777" .. (ns.ago and ns.ago(e.t or 0) or "") .. "|r"
                end
            end
        end
        p:SetTicker(tlist)

        ----------------------------------------------------------------
        -- Kacheln: Online | Mitglieder | Naechster Termin | Gildennachricht (doppelt breit)
        ----------------------------------------------------------------
        local t = p.tiles
        local total = math.max(R.total or 0, nOn)
        t[1]:Set(nOn, "/ " .. total, total > 0 and nOn / total or 0, doAnim)
        t[1].tip = { L["Online jetzt"], L["Klick: Mitgliederliste"] }
        local ina = #Info.Inactive()
        t[2]:Set(R.total or 0, nil, nil, doAnim)
        t[2].tip = { L["Mitglieder"], (L["%d seit %d+ Tagen inaktiv"]):format(ina, ns.db.settings.inactiveDays or 30) }
        local t3 = t[3]
        if ev then
            t3.ev = ev
            t3.page = "raid"
            t3:Set(countdown((ev.ts or 0) - ns.now()), ev.title or "?", nil, false)
            t3.tip = { ev.title or "?", ns.fmtWhen and ns.fmtWhen(ev.ts) or "", "|cff888888" .. L["Klick: Termine"] .. "|r" }
        else
            t3.ev = nil
            local lfg = ns.Groups and #ns.Groups.Active() or 0
            t3.page = lfg > 0 and "groups" or "raid"
            t3:Set(lfg > 0 and lfg or "–", lfg > 0 and (lfg == 1 and L["Gruppe sucht"] or L["Gruppen suchen"]) or L["nichts geplant"], nil, doAnim and lfg > 0)
            t3.tip = { L["Naechster Termin"], L["Nichts geplant - wie waer's mit einem Termin?"] }
        end
        local t4 = t[4]
        t4:Set("", nil, nil, false)
        t4.value:Hide()
        if note then
            local tt = (note.title or "") ~= "" and note.title or ""
            local body = (tt ~= "" and (tt .. ((note.text or "") ~= "" and "  |cffa3a3a8" or "")) or "") .. (note.text or "") .. (tt ~= "" and "|r" or "")
            t4.msg:SetText(body)
            t4.msg:SetTextColor(C.text[1], C.text[2], C.text[3])
            t4.label:SetText(K.Upper((L["Durchsage von %s  ·  %s"]):format(ns.displayName(note.by), ns.ago(note.ts))))
            t4.tip = { tt ~= "" and tt or L["Durchsage"], note.text or "", "|cff888888" .. ns.displayName(note.by) .. ", " .. ns.ago(note.ts) .. "|r" }
            t4.page = "radar"
        elseif motdText ~= "" then
            t4.msg:SetText(motdText)
            t4.msg:SetTextColor(C.text[1], C.text[2], C.text[3])
            t4.label:SetText(K.Upper(L["Gildennachricht"]))
            t4.tip = { L["Gildennachricht"], motdText, "|cff888888" .. L["Klick: Mitglieder-Uebersicht"] .. "|r" }
            t4.page = "radar"
        else
            t4.msg:SetText(L["Keine Gildennachricht"])
            t4.msg:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
            t4.label:SetText(K.Upper(L["Gildennachricht"]))
            t4.tip = { L["Gildennachricht"], L["Keine Gildennachricht"] }
            t4.page = "radar"
        end
        for _, tile in ipairs(t) do tile.track:SetShown(tile.bar:IsShown()) end

        ----------------------------------------------------------------
        -- Wer ist online
        ----------------------------------------------------------------
        p.onlineList = on
        p:LayoutGrid()
        p.online.head:SetCount(#on)

        ----------------------------------------------------------------
        -- Was gerade passiert
        ----------------------------------------------------------------
        local feed = ns.Store.List("chronicle")
        table.sort(feed, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
        local top, rankOf = {}, {}
        for _, e in ipairs(feed) do
            if e.kind == "badge" or (e.kind == "level" and e.rank) then
                -- 0.5.545/547: Abzeichen und Oasis-Rang nicht im Dashboard (zu viele, stehen in der Chronik)
            elseif e.kind == "level" and e.rank then
                local k = e.who or "?"
                local first = rankOf[k]
                if first then
                    first.merged = (first.merged or 1) + 1
                else
                    local c = {}
                    for kk, vv in pairs(e) do c[kk] = vv end
                    rankOf[k] = c
                    top[#top + 1] = c
                end
            else
                top[#top + 1] = e
            end
            if #top >= 20 then break end
        end
        for _, c in pairs(rankOf) do
            if (c.merged or 1) > 1 then
                c.mergedText = (L["ist %d Oasis-Raenge aufgestiegen (jetzt Rang %s)"]):format(c.merged, tostring(c.a1 or "?"))
            end
        end
        p.pulseTex = nil
        p.feed.list:SetData(top)
        p.feed.isEmpty = #top == 0
        -- Gilde diese Woche: kurz im Kopf
        local wkAgo = ns.now() - 7 * 86400
        local bosses, levels, loot = 0, 0, 0
        for _, e in ipairs(feed) do
            if (e.ts or 0) > wkAgo then
                if e.kind == "boss" then bosses = bosses + 1
                elseif e.kind == "level" and not e.rank then levels = levels + 1
                elseif e.kind == "loot" then loot = loot + 1 end
            end
        end
        p.feed.head:SetCount(nil)
        p:SetFeedTab(p.feed.tab or "feed")

        -- Wochenaufgaben
        local wk = p.hl.wk
        local hasTasks = false
        if ns.Rewards and ns.Rewards.Tasks then
            local ok, tasks = pcall(ns.Rewards.Tasks)
            tasks = (ok and type(tasks) == "table") and tasks or {}
            hasTasks = #tasks > 0
            local doneN = 0
            for i, r in ipairs(wk.rows) do
                local tk = tasks[i]
                if tk then
                    local done = tk.done or (tk.have or 0) >= (tk.need or 1)
                    if done then doneN = doneN + 1 end
                    r.t:SetText(done and ("|cff8a8a90" .. tk.text .. "|r") or tk.text)
                    r.n:SetText(done and ("|cff66db9e" .. L["geschafft"] .. "|r") or ((tk.have or 0) .. " / " .. (tk.need or 0)))
                    r.full, r.state = tk.text, r.n:GetText()
                    local c = done and C.mint or C.amber
                    r.dot:SetVertexColor(c[1], c[2], c[3])
                    r.fill:SetColorTexture(c[1], c[2], c[3], 0.9)
                    local w = r.track:GetWidth() or 80
                    if w < 10 then w = 80 end
                    local target = math.max(1, w * math.min(1, (tk.have or 0) / math.max(1, tk.need or 1)))
                    if doAnim then
                        r.fill:SetWidth(1)
                        K.Tween(r.fill, 0.9, function(q) r.fill:SetWidth(math.max(1, target * ease(q))) end, nil, 0.7 + i * 0.1)
                    else
                        r.fill:SetWidth(target)
                    end
                    r:Show()
                else
                    r:Hide()
                end
            end
            local left = ns.Rewards.WeekLeft and ns.Rewards.WeekLeft() or 0
            wk.head:SetText(K.Upper(L["Wochenaufgaben der Gilde"]) .. "  |cff888888" .. doneN .. "/" .. math.max(3, #tasks) .. "|r")
            wk.left:SetText((L["noch %d Tg %d Std"]):format(math.floor(left / 86400), math.floor(left % 86400 / 3600)))
            p.hl.heads.tasks = { L["Wochenaufgaben"], doneN .. "/" .. math.max(3, #tasks) .. "  |cff888888· " .. (wk.left:GetText() or "") .. "|r" }
            local week = date("%Y-%W")
            local all, some = 0, 0
            for name, pr in pairs(ns.db.members or {}) do
                if type(pr) == "table" and not ns.isMe(name) and pr.wk then
                    local w, n = tostring(pr.wk):match("^(.-):(%d+)$")
                    if w == week then
                        n = tonumber(n) or 0
                        if n >= 3 then all = all + 1 elseif n > 0 then some = some + 1 end
                    end
                end
            end
            if doneN >= 3 then all = all + 1 elseif doneN > 0 then some = some + 1 end
            local weekParts = {}
            if bosses > 0 then weekParts[#weekParts + 1] = (L["%d Bosse"]):format(bosses) end
            if levels > 0 then weekParts[#weekParts + 1] = (L["%d Level-Ups"]):format(levels) end
            if loot > 0 then weekParts[#weekParts + 1] = (L["%d Beute"]):format(loot) end
            wk.tip = { L["Wochenaufgaben der Gilde"], (L["Gilde: %d haben alle geschafft, %d sind dabei"]):format(all, some),
                #weekParts > 0 and (L["Diese Woche:"] .. " " .. table.concat(weekParts, " · ")) or nil,
                "|cff666666" .. L["Klick: Rang & Belohnungen"] .. "|r" }
        end
        p.hl.hasTasks = hasTasks
        if not hasTasks then p.hl.heads.tasks = { L["Gilden-Highlight"], nil } end

        -- Raid-Countdown (Bereitschaft), Tagesziel, Rekorde, Puls
        if ns.db.settings.dashCountdown ~= false then
            local okR, r = pcall(Info.Readiness)
            if okR and r then p:SetReadiness(r) end
        end
        p.hl.cd.checked = 0
        p:UpdateCountdown()
        p:UpdateGoal(false)
        p:UpdateRecords()
        p.hl.heads.rec = { L["Gilden-Rekorde"], nil }
        pcall(Info.SamplePulse)
        if p.feed.tab == "pulse" then p:UpdatePulse(false) end
        -- Gildennachricht in die Karte; beim Oeffnen des Dashboards immer zuerst zeigen
        do
            local hl = p.hl
            local has = (motdText or "") ~= ""
            hl.avail.motd = has
            hl.mo:SetMessage(has and motdText or nil)
            hl.heads.motd = { L["Gildennachricht"], nil }
            if fresh and has then hl.tab = nil hl.rotT = -10 end
        end
        p:SetHlTab(p.hl.tab or (p.hl.avail.motd and "motd") or "count")
        if doAnim and p.hl.tab == "count" then p:AnimReadiness() end

        ----------------------------------------------------------------
        -- Als Naechstes: Durchsagen, MOTD (falls oben eine Durchsage steht), Termine, Fuer dich
        ----------------------------------------------------------------
        local items = {}
        if note and motdText ~= "" then
            items[#items + 1] = { icon = ns.MEDIA .. "icons\\announce", color = C.accent, text = L["Nachricht des Tages:"] .. " |cffd8d8dc" .. motdText .. "|r",
                tip = { L["Nachricht des Tages"], motdText } }
        end
        if ns.Admin and ns.Admin.Notices then
            local ok, list = pcall(ns.Admin.Notices)
            if ok and type(list) == "table" then
                local shown = 0
                for _, n in ipairs(list) do
                    if n ~= note and ns.now() - (n.ts or 0) < 7 * 86400 and shown < 2 then
                        shown = shown + 1
                        local tt = (n.title or "") ~= "" and n.title or (n.text or "")
                        items[#items + 1] = { icon = ns.MEDIA .. "icons\\announce", color = n.imp and C.red or C.accent,
                            text = tt .. "  |cff888888· " .. ns.displayName(n.by) .. ", " .. ns.ago(n.ts) .. "|r",
                            tip = { tt, n.text or "", "|cff888888" .. ns.displayName(n.by) .. "|r" } }
                    end
                end
            end
        end
        for _, a in ipairs(upcoming()) do items[#items + 1] = a end
        for _, a in ipairs(suggestions()) do items[#items + 1] = a end
        p.nextBox.list:SetData(items)
        p.nextBox.empty:SetShown(#items == 0)
        p.nextBox.head:SetCount(#items > 0 and #items or nil)

        ----------------------------------------------------------------
        -- Auftritt beim Oeffnen
        ----------------------------------------------------------------
        if doAnim then
            ban:SetAlpha(0)
            K.Tween(ban, 0.6, function(q) ban:SetAlpha(q) end, function() ban:SetAlpha(1) end)
            ns.After(1.2, function() if (ban:GetAlpha() or 1) < 1 then ban:SetAlpha(1) end end)
            local anchor = ban.logo or ban.logoText
            if anchor then K.FadeIn(anchor, 0.25) end
            K.FadeIn(ban.greet, 0.4)
            K.FadeIn(ban.line2, 0.5)
            if ban.motd:IsShown() then K.FadeIn(ban.motd, 0.9) end
            if ban.stage and ban.stage:IsShown() then K.FadeIn(ban.stage, 0.45) end
            for i, tile in ipairs(p.tiles) do
                tile:SetAlpha(0)
                tile.dy = -26
                p:PlaceTile(tile)
                K.Tween(tile, 0.5, function(q)
                    local e = ease(q)
                    tile:SetAlpha(q)
                    tile.dy = -26 * (1 - e)
                    p:PlaceTile(tile)
                end, function() tile:SetAlpha(1) tile.dy = 0 p:PlaceTile(tile) end, 0.15 + i * 0.07)
                ns.After(2, function() if tile.dy ~= 0 or (tile:GetAlpha() or 1) < 1 then tile.dy = 0 tile:SetAlpha(1) p:PlaceTile(tile) end end)
                p:SweepTile(tile, 0.75 + i * 0.12)
            end
            K.FadeIn(p.online, 0.35) if p.spotBox and p.spotBox:IsShown() then K.FadeIn(p.spotBox, 0.35) end
            K.FadeIn(p.feed, 0.45)
            K.FadeIn(p.nextBox, 0.55)
            if p.hl:IsShown() then K.FadeIn(p.hl, 0.65) end
            if p.ad:IsShown() then K.FadeIn(p.ad, 0.75) end
            for i, c in ipairs(p.cells) do
                if c:IsShown() then K.FadeIn(c, 0.5 + i * 0.035) end
            end
        else
            for _, tile in ipairs(p.tiles) do
                if tile.dy ~= 0 then tile.dy = 0 p:PlaceTile(tile) end
            end
        end
        p:UpdateClock()
        if p.ngArea and ns.GuildView and not ns.GuildView() then p:Layout() end
        p.fresh = false
    end,
})
-- Gilde betreten/verlassen: Dashboard umschalten
ns.On("PLAYER_GUILD_UPDATE", function()
    local def = ns.PageDef("home")
    if def and def.frame and def.frame.Layout then def.frame:Layout() ns.RefreshPage("home") end
end)

------------------------------------------------------------------------
-- Einstellungen der Startseite
------------------------------------------------------------------------
local function addSettings()
    if not ns.AddPageSettings or Info.settingsAdded then return end
    Info.settingsAdded = true
    ns.AddPageSettings("home", function(det, y)
        local function relayout()
            local def = ns.PageDef("home")
            if def and def.frame and def.frame.Layout then def.frame:Layout() end
            ns.RefreshPage("home")
        end
        for _, d in ipairs({
            { "dashHero", "Held der Woche im Banner", "Aktivstes Mitglied der Woche als zweite Figur neben deinem Charakter" },
            { "dashCountdown", "Raid-Countdown", "Laufende Uhr bis zum Raid-Start mit Gilden-Bereitschaft" },
            { "dashTicker", "Live-Ticker im Banner", "Laufband mit den letzten Ereignissen am unteren Bannerrand" },
            { "dashWelcome", "Begruessung mit Rueckblick", "Einmal je Sitzung: was seit deinem letzten Besuch passiert ist" },
        }) do
            local tg = K.Toggle(det, L[d[2]], function() return S()[d[1]] ~= false end,
                function(v) S()[d[1]] = (not v) and false or nil relayout() end, L[d[3]])
            tg:SetPoint("TOPLEFT", 14, y)
            tg:SetWidth(600)
            if det.t then det.t[#det.t + 1] = tg end
            y = y - 50
        end
        local t = K.Toggle(det, L["Banner ruhig stellen"], function() return S().dashStill == true end,
            function(v) S().dashStill = v and true or nil end,
            L["Kein Zoomen, keine Glut und kein Glanz im Dashboard-Banner"])
        t:SetPoint("TOPLEFT", 14, y)
        t:SetWidth(600)
        if det.t then det.t[#det.t + 1] = t end
        y = y - 50
        local t2 = K.Toggle(det, L["Midas-Werbebanner ausblenden"], function() return not adWanted() end,
            function(v)
                S().hideMidasAd = v and true or false
                local def = ns.PageDef("home")
                if def and def.frame and def.frame.Layout then def.frame:Layout() end
            end,
            L["Banner des AH-Addons Midas unten im Dashboard"])
        t2:SetPoint("TOPLEFT", 14, y)
        t2:SetWidth(600)
        if det.t then det.t[#det.t + 1] = t2 end
        y = y - 50
        local lbl = K.Text(det, 12, C.text)
        lbl:SetPoint("TOPLEFT", 14, y)
        lbl:SetText(L["Banner-Bild"])
        local b = K.Button(det, "", 240, 24, "ghost")
        b:SetPoint("TOPLEFT", 164, y + 5)
        local function label()
            local cur = S().dashBg or "auto"
            for _, e in ipairs(BG_NAMES) do if e[1] == cur then return L[e[2]] end end
            return L["Automatisch (nach Fraktion)"]
        end
        b:SetLabel(label())
        b:SetScript("OnClick", function(self)
            local items = {}
            for _, e in ipairs(BG_NAMES) do
                items[#items + 1] = { text = L[e[2]], checked = (S().dashBg or "auto") == e[1], fn = function()
                    S().dashBg = e[1] ~= "auto" and e[1] or nil
                    self:SetLabel(label())
                    local def = ns.PageDef("home")
                    if def and def.frame and def.frame.ApplyBackground then def.frame:ApplyBackground() end
                end }
            end
            K.ShowMenu(self, items, L["Banner-Bild"], 220)
        end)
        return y - 40
    end)
end

ns.Listen("LOGIN", function()
    addSettings()
    ns.After(10, function()
        if QueryGuildNews then pcall(QueryGuildNews) end
        if C_Calendar and C_Calendar.OpenCalendar then pcall(C_Calendar.OpenCalendar) end
    end)
    ns.Every(600, function() if QueryGuildNews then pcall(QueryGuildNews) end end)
end)
ns.Listen("MAIN_SHOWN", function() if QueryGuildNews then pcall(QueryGuildNews) end end)

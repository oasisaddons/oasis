-- Oasis Modul 6: Gilden-Chronik (Level, epische Beute, Legacy, Bosse, neue Mitglieder)
local ADDON, ns = ...
ns.ModuleFile("Oasis_Chronik", function()   -- Modul Chronik (abschaltbar, siehe ModuleLoader.lua)
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

local Chronicle = {}
ns.Chronicle = Chronicle

local KINDS = {
    level = { "Level", C.blue },
    loot = { "Beute", C.pink },
    legacy = { "Legacy", C.violet },
    boss = { "Boss", C.amber },
    guild = { "Gilde", C.mint },
    duel = { "Wuerfeln", C.red },
    badge = { "Abzeichen", C.accent },
    news = { "Gilden-News", { 0.55, 0.68, 0.85 } },
}
ns.Relabel(function()
    KINDS.level[1], KINDS.loot[1], KINDS.legacy[1], KINDS.boss[1] = L["Level"], L["Beute"], L["Legacy"], L["Boss"]
    KINDS.guild[1], KINDS.duel[1], KINDS.badge[1], KINDS.news[1] = L["Gilde"], L["Wuerfeln"], L["Abzeichen"], L["Gilden-News"]
end)

-- Eintraege speichern eine Textvorlage (tk) + Werte (a1..a3), damit jeder Client
-- sie in seiner eigenen Sprache anzeigt
function Chronicle.Add(kind, id, tk, args, extra)
    if Store.Get("chronicle", id) then return end
    local rec = { id = id, kind = kind, who = ns.me(), tk = tk, ts = ns.now() }
    for i, v in ipairs(args or {}) do rec["a" .. i] = tostring(v) end
    if extra then for k, v in pairs(extra) do rec[k] = v end end
    Store.Put("chronicle", rec)
end
function Chronicle.Text(e)
    if not e.tk then return e.text or "" end
    if e.kind == "badge" and ns.Badges then
        return L[e.tk] .. " " .. ns.Badges.Label(e.a1, e.a2)
    end
    local a1 = e.kind == "boss" and L[e.a1 or ""] or (e.a1 or "")
    local ok, s = pcall(string.format, L[e.tk], a1, e.a2 or "", e.a3 or "")
    return ok and s or L[e.tk]
end
function Chronicle.Item(e)
    if e.kind == "legacy" and e.a1 and ns.Legacy then
        local x = ns.Legacy and ns.Legacy.byId[tonumber(e.a1)]
        if x then return x.name end
    end
    if e.item and e.item:find("|H") then
        local _, link = C_Item.GetItemInfo(e.item)
        return link or e.item
    end
    return e.item
end

-- Gilden-Optionen (Gildenleitung): was in die Chronik kommt und ob im Gildenchat gepostet werden darf
ns.GuildOption({ page = "chronicle", key = "chLvStep", default = 5, min = 1, max = 10, step = 1,
    label = "Level-Eintrag alle", desc = "Ein Level-Meilenstein wird alle so viele Level eingetragen (Level 60 immer).",
    fmt = function(v) return v .. " Level" end })
ns.GuildOption({ page = "chronicle", key = "chLoot", default = "4",
    choices = { { key = "3", text = "Selten" }, { key = "4", text = "Episch" }, { key = "5", text = "Legendaer" } },
    label = "Beute ab Qualitaet", desc = "Ab dieser Qualitaet wird erbeutete Beute in die Chronik eingetragen." })
ns.GuildOption({ page = "chronicle", key = "chJoin", default = true,
    label = "Beitritte und Austritte eintragen", desc = "Neue Mitglieder und Austritte erscheinen in der Chronik." })
ns.GuildOption({ page = "chronicle", key = "chPost", default = true,
    label = "Meilensteine im Gildenchat erlauben", desc = "Mitglieder duerfen Level- und Legacy-Meilensteine automatisch im Gildenchat posten (wenn sie es persoenlich eingeschaltet haben)." })

local function announce(text)
    if ns.db.settings.announceMilestones and IsInGuild() and ns.GuildOpt("chPost") ~= false then
        ns.OfferChat(L["Im Gildenchat zeigen?"], L["[Oasis] "] .. text, "GUILD")
    end
end

------------------------------------------------------------------------
-- Quellen
------------------------------------------------------------------------
ns.Listen("LEVEL_UP", function(level)
    local step = math.max(1, math.floor(tonumber(ns.GuildOpt("chLvStep")) or 5))
    if level % step == 0 or level == 60 then
        Chronicle.Add("level", ("lvl-%s-%d"):format(ns.short(ns.me()), level), "hat Level %s erreicht", { level }, { lvl = level })
        announce(L["Level %d erreicht!"]:format(level))
    end
end)

ns.Listen("STORE", function(coll, rec, old)
    if coll == "loot" and not old and not rec.del and ns.isMe(rec.who) and (rec.quality or 0) >= (tonumber(ns.GuildOpt("chLoot")) or 4) then
        Chronicle.Add("loot", "chr-" .. rec.id, "hat erbeutet:", nil, { item = rec.item, zone = rec.zone, mapID = rec.mapID })
    end
    local age = ns.now() - (tonumber(rec.ts) or 0)
    if coll == "chronicle" and not old and not rec.del and not ns.isMe(rec.who) and age >= -5 and age <= 30 then
        if rec.kind == "level" and ns.db.settings.chrToastLevels == false then
            -- persoenlich: Level-Hinweise anderer aus
        elseif (rec.kind == "level" or rec.kind == "boss" or rec.kind == "legacy" or rec.kind == "duel" or rec.kind == "badge")
            -- nur eigene Meldungen (Ersteller = betroffene Person), je Person gedrosselt, Texte entschaerft
            and SEC.Name(rec.who) and (not rec.by or Comm.whoKey(rec.by) == Comm.whoKey(rec.who))
            and SEC.Rate("chrtoast:" .. rec.who, 20) then
            K.Toast(ns.displayName(rec.who) .. " " .. SEC.Text(Chronicle.Text(rec), 120), SEC.Text(Chronicle.Item(rec) or ns.zoneName(rec.mapID, rec.zone), 120, true), (KINDS[rec.kind] or KINDS.guild)[2],
                function() ns.ShowPage("chronicle") end, "chronicle", (tonumber(rec.ts) or 0) + 30)
        end
    end
    if coll == "chronicle" then
        if Chronicle.RefreshSoon then Chronicle.RefreshSoon() else ns.RefreshPage("chronicle") end
    end
end)

ns.Listen("LEGACY_DONE", function(e)
    Chronicle.Add("legacy", ("leg-%s-%s"):format(ns.short(ns.me()), tostring(e.id)), "hat eine Legacy-Challenge geschafft:", { e.id }, { item = e.name })
    if ns.db.settings.chrPostLegacy ~= false then announce(L["Legacy-Challenge geschafft: "] .. e.name) end
end)

-- Bosskills: der Gruppenanfuehrer traegt ein
ns.On("ENCOUNTER_END", function(encounterID, encounterName, difficultyID, groupSize, success)
    encounterID, encounterName, success = ns.safe(encounterID), ns.safe(encounterName), ns.safe(success)
    if success ~= 1 or not encounterName then return end
    if IsInGroup() and not UnitIsGroupLeader("player") then return end
    local guildies = {}
    local n = GetNumGroupMembers()
    for i = 1, n do
        local unit = IsInRaid() and ("raid" .. i) or (i == n and "player" or ("party" .. i))
        local name = ns.safe(ns.UnitName(unit))
        if name and ns.Radar.byName[ns.fullName(name)] then guildies[#guildies + 1] = ns.short(name) end
    end
    if #guildies < 2 and IsInGroup() then return end
    ns.After(3, function()
        local fight = ns.Scan and ns.Scan.FightInfo() or nil
        local id = ("boss-%s-%s-%s"):format(tostring(encounterID), ns.short(ns.me()), date("%y%m%d"))
        local extra = { zone = table.concat(guildies, ", ") }
        if fight and fight.top then extra.top = fight.top end
        if fight and fight.dur then
            Chronicle.Add("boss", id, "und Gruppe besiegen %s (%s)", { encounterName, ("%d:%02d"):format(fight.dur / 60, fight.dur % 60) }, extra)
        else
            Chronicle.Add("boss", id, "und Gruppe besiegen %s", { encounterName }, extra)
        end
    end)
end)

-- Beitritt / Austritt (jeder Client sieht die Systemmeldung, gleiche ID verhindert Doppelte)
local function toPattern(fmt)
    if not fmt then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. p:gsub("%%%%s", "(.+)") .. "$"
end
local joinPats = { toPattern(ERR_GUILD_JOIN_S), toPattern("%s has joined the guild."), toPattern("%s ist der Gilde beigetreten.") }
local leavePats = { toPattern(ERR_GUILD_LEAVE_S), toPattern("%s has left the guild."), toPattern("%s hat die Gilde verlassen.") }
local function matchAny(text, pats)
    for _, p in ipairs(pats) do
        local m = p and text:match(p)
        if m then return m end
    end
end
ns.On("CHAT_MSG_SYSTEM", function(text)
    text = ns.safe(text)
    if not text then return end
    local who = matchAny(text, joinPats)
    local kind = "tritt der Gilde bei - willkommen!"
    if not who then
        who = matchAny(text, leavePats)
        kind = "hat die Gilde verlassen"
    end
    local tag = (kind:sub(1, 4) == "trit") and "join" or "left"
    if not who then return end
    if ns.GuildOpt("chJoin") == false then return end
    who = who:gsub("|H.-|h%[?(.-)%]?|h", "%1")
    local id = ("guild-%s-%s-%s"):format(tag, who, date("%y%m%d"))
    ns.After(math.random(0, 80) / 10, function()
        if Store.Get("chronicle", id) then return end
        Store.Put("chronicle", { id = id, kind = "guild", who = ns.fullName(who), tk = kind, ts = ns.now() })
    end)
end)

------------------------------------------------------------------------
-- Seite: Reiterleiste, Wochen-Kacheln, Zeitleiste (Tageskapitel, Karten, Buendel), rechte Spalte
------------------------------------------------------------------------
local filter, whoFilter, search = "all", nil, ""
local onlyMine, onlyOnline = false, false
local expanded = {}          -- aufgeklappte Buendel (id des neuesten Eintrags)
local firstKill = {}         -- Boss-Name -> id des ersten Kills (fuer "Erstkill")
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local EMBER = ns.MEDIA .. "ember"
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local DAYNAMES = { "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag" }
local TAB_KEYS = { "all", "level", "loot", "legacy", "boss", "guild", "duel", "badge", "news" }
local GLYPH = { all = "chronicle", level = "stats", loot = "wants", legacy = "legacy", boss = "raid", guild = "social",
    duel = "deathroll", badge = "badges", news = "announce" }
local TILE_KINDS = { "level", "loot", "boss", "badge", "guild" }
local TILE_LABEL = { level = "Level-Meilensteine", loot = "Beute", boss = "Bosse besiegt", badge = "Abzeichen", guild = "Neue Mitglieder" }
local WEEK_KINDS = { "level", "loot", "boss", "legacy", "badge", "guild", "duel" }
local WEEK_LABEL = { level = "Level-Meilensteine", loot = "Epische Beute", boss = "Bosse besiegt", legacy = "Legacy-Challenges",
    badge = "Abzeichen", guild = "Neue Mitglieder", duel = "Wuerfelspiele" }
local BUNDLE_TEXT = { badge = "hat %d Abzeichen erhalten", loot = "hat %d Beutestuecke erbeutet", boss = "und Gruppe besiegen %d Bosse",
    duel = "hat %d Wuerfelspiele gespielt", news = "%d Gilden-News", legacy = "hat %d Legacy-Challenges geschafft" }
local BUNDLE_GAP = 3 * 3600  -- gleiche Ereignisse einer Person innerhalb von 3 Std. = eine Karte
local QHEX = { ["9d9d9d"] = 0, ffffff = 1, ["1eff00"] = 2, ["0070dd"] = 3, a335ee = 4, ff8000 = 5, e6cc80 = 6 }
local QCOL = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 0.9, 0.9, 0.9 }, [2] = { 0.12, 1, 0 }, [3] = { 0.1, 0.5, 0.95 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 } }
local MEDAL = { { 1, 0.80, 0.28 }, { 0.80, 0.82, 0.88 }, { 0.82, 0.52, 0.30 } }
local H_DAY, H_CARD, H_BIG, H_KID, GAP = 32, 52, 66, 26, 6
local LINE_X, CARD_X = 16, 34

local function S() return ns.db and ns.db.settings or {} end
local function animOn() return not S().noAnim end
local function kindOf(k) return KINDS[k] or KINDS.guild end
local function dayKey(ts) return date("%Y%m%d", ts or 0) end
local function dayLabel(ts)
    local now = ns.now()
    local k = dayKey(ts)
    if k == dayKey(now) then return L["Heute"] end
    if k == dayKey(now - 86400) then return L["Gestern"] end
    local w = tonumber(date("%w", ts)) + 1
    return L[DAYNAMES[w]] .. ", " .. date("%d.%m.", ts)
end
local function plain(s)
    s = tostring(s or "")
    s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
    return s
end
local function isJoin(e) return e.kind == "guild" and (e.tk or ""):find("^trit") ~= nil end
local function itemQuality(e)
    local it = e and e.item
    if type(it) ~= "string" then return nil end
    local hex = it:match("|c%x%x(%x%x%x%x%x%x)")
    local q = hex and QHEX[hex:lower()]
    if q then return q end
    local id = ns.itemID(it)
    if id and C_Item and C_Item.GetItemQualityByID then
        local ok, v = pcall(C_Item.GetItemQualityByID, id)
        if ok and type(v) == "number" then return v end
    end
end
local function itemLink(e)
    local it = Chronicle.Item(e)
    if type(it) == "string" and it:find("|H") then return it end
end
local function lineText(e)
    local item = Chronicle.Item(e)
    return Chronicle.Text(e) .. (item and (" " .. item) or "")
end
local function levelOf(e) return (not e.rank) and tonumber(e.lvl or e.a1) or nil end
-- Highlight: epische Beute, Level 60, Boss-Erstkill, neues Mitglied (+ Gewicht fuer "Highlight der Woche")
local function highlight(e)
    if e.kind == "loot" then
        local q = itemQuality(e) or 0
        if q >= 5 then return 100, L["Legendaer"] end
        if q >= 4 then return 70, L["Episch"] end
        return 12
    elseif e.kind == "level" then
        local lv = levelOf(e)
        if lv == 60 then return 90, L["Level 60"] end
        return (lv or 0) / 4
    elseif e.kind == "boss" then
        if e.a1 and firstKill[e.a1] == e.id then return 80, L["Erstkill"] end
        return 30
    elseif isJoin(e) then return 45, L["Neu"]
    elseif e.kind == "legacy" then return 50
    elseif e.kind == "badge" then return 8 + (tonumber(e.a2) or 0) * 4
    end
    return 1
end
local function plainLine(e) return ns.displayName(e.who or "") .. " " .. plain(lineText(e)) end
-- Suchtreffer im Klartext gelb hervorheben (nur Texte ohne Farbcodes/Links)
local function mark(text)
    if search == "" or text:find("|", 1, true) then return text end
    local lo = text:lower()
    local out, pos = {}, 1
    while true do
        local a, b = lo:find(search, pos, true)
        if not a then break end
        out[#out + 1] = text:sub(pos, a - 1)
        out[#out + 1] = "|cffffd84a" .. text:sub(a, b) .. "|r"
        pos = b + 1
    end
    if pos == 1 then return text end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

-- Klassensymbol (Atlas oder Symbolblatt) wie im Dashboard
local function setClassIcon(tex, class)
    if ns.GuildInfo and ns.GuildInfo.SetClassIcon then
        local ok, r = pcall(ns.GuildInfo.SetClassIcon, tex, class)
        if ok then return r end
    end
    local tc = type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not tc then return false end
    tex:SetTexture(CLASS_SHEET)
    tex:SetTexCoord(tc[1] + 0.015, tc[2] - 0.015, tc[3] + 0.015, tc[4] - 0.015)
    return true
end
local function circleMask(owner, tex)
    if not owner.CreateMaskTexture then return end
    local ok, m = pcall(owner.CreateMaskTexture, owner)
    if not ok or not m then return end
    pcall(function()
        m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(tex)
        tex:AddMaskTexture(m)
    end)
end

-- 2026: Glas-Optik wie Mitglieder/Legacy/Abzeichen (Helfer aus ns.Insta; fehlen sie, bleibt das alte Aussehen)
local function hasGlass() return ns.Insta and ns.Insta.Glass and true or false end
local function glass(f, fill, line, r) if hasGlass() then ns.Insta.Glass(f, fill, line, r) end end
local function round(t, box, r) if K.RoundMask and t then K.RoundMask(t, box or t, r) end end
-- Klasse einer Person, notfalls ueber einen ihrer Charaktere (Main/Twinks); je Refresh gecacht
local classCache = {}
local function classFor(who)
    if not who then return nil end
    local c = classCache[who]
    if c ~= nil then return c or nil end
    c = ns.Radar.ClassOf(who)
    if not c and ns.Alts and ns.Alts.Main and ns.Alts.CharsOf then
        local ok, chars = pcall(ns.Alts.CharsOf, ns.Alts.Main(who))
        if ok and chars then for _, n in ipairs(chars) do c = ns.Radar.ClassOf(n) if c then break end end end
    end
    classCache[who] = c or false
    return c
end
local function calmBtn(b, primary)
    if not (b and hasGlass()) then return b end
    local ac = C.accent
    local fill = primary and { ac[1], ac[2], ac[3], 0.16 } or { 1, 1, 1, 0.05 }
    local line = primary and { ac[1], ac[2], ac[3], 0.45 } or { 1, 1, 1, 0.10 }
    if b.sheen then b.sheen:Hide() end
    glass(b, fill, line, 8)
    b:SetScript("OnEnter", function(self) glass(self, { fill[1], fill[2], fill[3], fill[4] + 0.05 }, { line[1], line[2], line[3], line[4] + 0.12 }) end)
    b:SetScript("OnLeave", function(self) glass(self, fill, line) end)
    return b
end

-- Rundes Bild: Klassenkreis (Person) bzw. Item-/Abzeichen-Symbol, Ring in Klassen-/Qualitaets-/Artfarbe,
-- kleine Art-Marke unten rechts
local function makeAvatar(parent)
    local a = CreateFrame("Frame", nil, parent)
    a.glow = a:CreateTexture(nil, "BACKGROUND", nil, 2)
    a.glow:SetTexture(EMBER)
    a.glow:SetBlendMode("ADD")
    a.glow:SetPoint("CENTER")
    a.glow:Hide()
    a.ring = a:CreateTexture(nil, "BORDER")
    a.ring:SetTexture(CIRCLE)
    a.ring:SetAllPoints()
    a.inner = a:CreateTexture(nil, "ARTWORK", nil, -1)
    a.inner:SetTexture(CIRCLE)
    a.inner:SetVertexColor(0.06, 0.06, 0.07)
    a.inner:SetPoint("CENTER")
    a.iconM = a:CreateTexture(nil, "ARTWORK", nil, 1)
    a.iconM:SetPoint("CENTER")
    circleMask(a, a.iconM)
    a.iconC = a:CreateTexture(nil, "ARTWORK", nil, 1)
    a.iconC:SetPoint("CENTER")
    a.letter = K.Title(a, 13, C.text, "CENTER")
    a.letter:SetPoint("CENTER")
    a.mini = a:CreateTexture(nil, "OVERLAY", nil, 1)
    a.mini:SetTexture(CIRCLE)
    a.mini:SetSize(15, 15)
    a.mini:SetPoint("CENTER", a, "BOTTOMRIGHT", -3, 3)
    a.miniIco = a:CreateTexture(nil, "OVERLAY", nil, 2)
    a.miniIco:SetSize(9, 9)
    a.miniIco:SetPoint("CENTER", a.mini)
    if hasGlass() then a.glow:SetTexture(nil) a.glow:SetAlpha(0) end
    function a:SetSz(s)
        self:SetSize(s, s)
        self.inner:SetSize(hasGlass() and s - 3 or s - 4, hasGlass() and s - 3 or s - 4)
        self.iconM:SetSize(s - 6, s - 6)
        self.iconC:SetSize(math.floor(s * 0.6), math.floor(s * 0.6))
        self.glow:SetSize(s * 2.1, s * 2.1)
    end
    a:SetSz(34)
    return a
end
local function setAvatar(a, e)
    local kd = kindOf(e.kind)
    local kc = kd[2]
    a.iconM:Hide() a.iconC:Hide() a.letter:Hide()
    a.iconM:SetVertexColor(1, 1, 1)
    local ring, mini = kc, true
    local itemID = e.item and ns.itemID(e.item)
    local tex = itemID and C_Item and C_Item.GetItemIconByID and select(2, pcall(C_Item.GetItemIconByID, itemID))
    if (e.kind == "loot" or e.kind == "news") and tex then
        a.iconM:SetTexture(tex)
        a.iconM:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        a.iconM:Show()
        local q = itemQuality(e)
        ring = (q and QCOL[q]) or kc
        mini = e.kind == "news"
    elseif e.kind == "badge" and ns.Badges and ns.Badges.byId and ns.Badges.byId[e.a1] and ns.Badges.byId[e.a1].icon then
        a.iconM:SetTexture(ns.Badges.byId[e.a1].icon)
        a.iconM:SetTexCoord(0, 1, 0, 1)
        a.iconM:Show()
        mini = false
    elseif e.kind == "level" and ns.LevelBadges and ns.LevelBadges.Exact(levelOf(e), true) then
        -- 0.5.571: Stufe 10/20/.../60 -> Stufen-Abzeichen
        a.iconM:SetTexture(ns.LevelBadges.Exact(levelOf(e), true))
        a.iconM:SetTexCoord(0, 1, 0, 1)
        a.iconM:Show()
        mini = false
    else
        local cls = classFor(e.who)
        if cls and setClassIcon(a.iconC, cls) then
            a.iconC:Show()
            ring = { ns.classColor(cls) }
        elseif e.kind == "news" or not e.who then
            a.iconM:SetTexture(ns.MEDIA .. "icons\\" .. (GLYPH[e.kind] or "chronicle"))
            a.iconM:SetTexCoord(-0.15, 1.15, -0.15, 1.15)
            a.iconM:SetVertexColor(kc[1], kc[2], kc[3])
            a.iconM:Show()
            mini = false
        else
            a.letter:SetText(((ns.displayName(e.who) or "?"):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"):upper())
            a.letter:SetTextColor(kc[1], kc[2], kc[3])
            a.letter:Show()
            if cls then local cr, cg, cb = ns.classColor(cls) ring = { cr, cg, cb } end
        end
    end
    a.ring:SetVertexColor(ring[1], ring[2], ring[3], hasGlass() and 0.7 or 1)
    a.glow:SetVertexColor(ring[1], ring[2], ring[3])
    a.mini:SetShown(mini)
    a.miniIco:SetShown(mini)
    if mini then
        a.mini:SetVertexColor(kc[1] * 0.55, kc[2] * 0.55, kc[3] * 0.55)
        a.miniIco:SetTexture(ns.MEDIA .. "icons\\" .. (GLYPH[e.kind] or "chronicle"))
        a.miniIco:SetVertexColor(1, 1, 1)
    end
    return ring
end

------------------------------------------------------------------------
-- Aktionen (Klick, Rechtsklick, Tooltip)
------------------------------------------------------------------------
local refreshSoon
local function showProfile(who)
    if who and ns.Profile and ns.Profile.Show then ns.Profile.Show(who) end
end
local function setWho(who)
    if whoFilter == who then whoFilter = nil else whoFilter = who end
    refreshSoon(true)
end
local function gzText(e)
    local n = ns.displayName(e.who or "")
    if e.kind == "level" then
        local lv = levelOf(e)
        if lv == 60 then return (L["GZ zu Level 60, %s! Willkommen im Endgame!"]):format(n) end
        if lv then return (L["GZ zu Level %d, %s!"]):format(lv, n) end
    elseif e.kind == "loot" and Chronicle.Item(e) then
        return (L["GZ zu %s, %s!"]):format(Chronicle.Item(e), n)
    elseif e.kind == "boss" then
        return (L["Stark gemacht, %s - GZ zu %s!"]):format(n, L[e.a1 or ""])
    elseif e.kind == "legacy" then
        return (L["GZ zur Legacy-Challenge, %s!"]):format(n)
    elseif e.kind == "badge" then
        return (L["GZ zum neuen Abzeichen, %s!"]):format(n)
    elseif isJoin(e) then
        return (L["Willkommen in der Gilde, %s!"]):format(n)
    end
    return (L["GZ %s!"]):format(n, "")
end
local function congratulate(e)
    local text = gzText(e)
    local function send(t)
        if (t or "") == "" then return end
        if ns.SendChat(t, "GUILD") then
            if ns.Badges and ns.Badges.Add then pcall(ns.Badges.Add, "gz", 1) end
            if ns.Rewards and ns.Rewards.Credit then pcall(ns.Rewards.Credit, "gz", e.who) end
        end
    end
    local WL = ns.WhisperLog
    if WL and WL.Prompt then
        WL.Prompt(L["Gratulieren"], L["Text fuer den Gildenchat:"], text, send, L["Senden"])
    else
        ns.OpenChat("/g " .. text)
    end
end
local function copyEntry(e, kids)
    local lines = { date("%d.%m. %H:%M", e.ts or 0) .. "  " .. plainLine(e) }
    for i, k in ipairs(kids or {}) do
        if i > 1 then lines[#lines + 1] = date("%d.%m. %H:%M", k.ts or 0) .. "  " .. plainLine(k) end
    end
    local text = table.concat(lines, "\n")
    if ns.WhisperLog and ns.WhisperLog.Copy then ns.WhisperLog.Copy(L["Eintrag kopieren"], text)
    else ns.OpenChat(text) end
end
local function linkItem(e)
    local link = itemLink(e)
    if link and ChatEdit_InsertLink then pcall(ChatEdit_InsertLink, link) return true end
end
local function entryMenu(owner, e, kids)
    if not e then return end
    local items = {}
    local me = e.who and ns.isMe(e.who)
    if e.who and not me then items[#items + 1] = { text = L["Fluestern"], fn = function() ns.Whisper(e.who) end } end
    if e.who and ns.Profile and ns.Profile.Show then items[#items + 1] = { text = L["Profil ansehen"], fn = function() showProfile(e.who) end } end
    if e.who and not me and e.kind ~= "news" then
        items[#items + 1] = { text = L["Gratulieren im Gildenchat ..."], disabled = not IsInGuild(), fn = function() congratulate(e) end }
    end
    if itemLink(e) then items[#items + 1] = { text = L["Gegenstand im Chat verlinken"], fn = function() linkItem(e) end } end
    if e.who then
        items[#items + 1] = { text = whoFilter == e.who and L["Personenfilter aufheben"] or L["Nur Eintraege dieser Person"], fn = function() setWho(e.who) end }
    end
    if not e.noCopy then items[#items + 1] = { text = L["Eintrag kopieren"], fn = function() copyEntry(e, kids) end } end
    K.ShowMenu(owner, items, e.who and ns.displayName(e.who) or L["Chronik"], 190)
end
local function entryTip(owner, e, kids)
    local link = itemLink(e)
    local hint = "|cff777777" .. L["Klick auf Name: Profil  ·  Rechtsklick: Aktionen"] .. (link and ("  ·  " .. L["Shift-Klick: verlinken"]) or "") .. "|r"
    if link and (not kids or #kids < 2) then
        GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
        if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ns.Radar.Colored(e.who) .. "  |cff888888" .. ns.fmtDate(e.ts) .. "|r", 1, 1, 1)
            local zn = ns.zoneName(e.mapID, e.zone)
            if zn ~= "" then GameTooltip:AddLine(zn, 0.7, 0.7, 0.75) end
            GameTooltip:AddLine(hint, 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
    end
    local lines = { ns.Radar.Colored(e.who) }
    if kids and #kids > 1 then
        for i, k in ipairs(kids) do
            if i > 8 then lines[#lines + 1] = "|cff888888" .. (L["... und %d weitere"]):format(#kids - 8) .. "|r" break end
            lines[#lines + 1] = "|cff888888" .. date("%H:%M", k.ts or 0) .. "|r  " .. lineText(k)
        end
    else
        lines[#lines + 1] = lineText(e)
        lines[#lines + 1] = "|cff888888" .. ns.fmtDate(e.ts) .. "  ·  " .. ns.ago(e.ts) .. "|r"
    end
    local zn = ns.zoneName(e.mapID, e.zone)
    if zn ~= "" then lines[#lines + 1] = (e.kind == "boss" and L["Dabei: "] or "") .. zn end
    if e.top then lines[#lines + 1] = L["Top-Schaden: "] .. e.top end
    local _, tag = highlight(e)
    if tag then lines[#lines + 1] = K.hex(C.amber) .. "* " .. tag .. "|r" end
    lines[#lines + 1] = " "
    lines[#lines + 1] = hint
    K.ShowTip(owner, lines)
end

------------------------------------------------------------------------
-- Daten aufbereiten: filtern, buendeln, Tageskapitel
------------------------------------------------------------------------
local function passBase(e)
    if whoFilter and e.who ~= whoFilter then return false end
    if onlyMine and not (e.who and ns.isMe(e.who)) then return false end
    if onlyOnline and not (e.who and ns.Radar.IsOnline(e.who)) then return false end
    if search ~= "" then
        local hit = (ns.displayName(e.who or "")):lower():find(search, 1, true) or plain(lineText(e)):lower():find(search, 1, true)
        if not hit then return false end
    end
    return true
end
-- neueste zuerst; Level einer Person am selben Tag und gleiche Ereignisse kurz hintereinander -> eine Karte
local function bundle(rows)
    local out, open = {}, {}
    for _, e in ipairs(rows) do
        local key
        if e.kind == "level" and not e.rank then key = "L" .. (e.who or "") .. dayKey(e.ts)
        elseif BUNDLE_TEXT[e.kind] and e.who then key = e.kind .. (e.who or "") .. dayKey(e.ts) end
        local g = key and open[key]
        if g and e.kind ~= "level" and ((g.kids[#g.kids].ts or 0) - (e.ts or 0)) > BUNDLE_GAP then g = nil end
        if g then
            g.kids[#g.kids + 1] = e
            if e.kind == "level" then g.fromLvl = tonumber(e.a1) or g.fromLvl end
        else
            g = { e = e, kids = { e }, fromLvl = tonumber(e.a1) }
            if key then open[key] = g end
            out[#out + 1] = g
        end
    end
    for _, g in ipairs(out) do
        local best, tag = 0, nil
        for _, k in ipairs(g.kids) do
            local s, t = highlight(k)
            if s > best or (t and not tag) then best = math.max(best, s) tag = t or tag end
        end
        g.tag = tag
        g.big = tag ~= nil
    end
    return out
end
local function groupText(g)
    local e, n = g.e, #g.kids
    if n > 1 then
        if e.kind == "level" and g.fromLvl then
            return (L["hat Level %d bis %d erreicht"]):format(g.fromLvl, tonumber(e.a1) or 0)
        end
        if BUNDLE_TEXT[e.kind] then return (L[BUNDLE_TEXT[e.kind]]):format(n) end
    end
    return lineText(e)
end
local function kidLabel(k)
    if k.kind == "badge" and ns.Badges then return ns.Badges.Label(k.a1, k.a2) end
    if k.kind == "loot" then return Chronicle.Item(k) and plain(Chronicle.Item(k)) or "" end
    if k.kind == "boss" then return L[k.a1 or ""] end
    if k.kind == "level" then return "Lv " .. (k.a1 or "?") end
    return plain(Chronicle.Text(k))
end

------------------------------------------------------------------------
-- Bausteine
------------------------------------------------------------------------
local function gradient(tex, dir, c, a1, a2, fallbackA)
    if not K.Gradient(tex, dir, { c[1], c[2], c[3], a1 }, { c[1], c[2], c[3], a2 }) then
        tex:SetColorTexture(c[1], c[2], c[3], fallbackA or (a1 + a2) / 2)
    end
end
local function emptyState(parent, color, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(320, 110)
    f.halo = f:CreateTexture(nil, "BACKGROUND")
    f.halo:SetTexture(EMBER)
    f.halo:SetBlendMode("ADD")
    f.halo:SetSize(90, 90)
    f.halo:SetPoint("TOP", 0, 18)
    f.halo:SetVertexColor(color[1], color[2], color[3])
    f.halo:SetAlpha(hasGlass() and 0 or 0.3)
    f.disc = f:CreateTexture(nil, "BORDER")
    f.disc:SetTexture(CIRCLE)
    f.disc:SetSize(44, 44)
    f.disc:SetPoint("TOP", 0, -5)
    f.disc:SetVertexColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25)
    f.icon = K.Glyph(f, 22, ns.MEDIA .. "icons\\chronicle", color)
    f.icon:SetPoint("CENTER", f.disc)
    f.text = K.Text(f, 13, C.muted, "CENTER")
    f.text:SetPoint("TOP", f.disc, "BOTTOM", 0, -10)
    f.text:SetWidth(300)
    f.text:SetWordWrap(true)
    f.text:SetText(text or "")
    f.btn = K.Button(f, "", 150, 22, "primary")
    f.btn:SetPoint("TOP", f.text, "BOTTOM", 0, -10)
    f.btn2 = K.Button(f, "", 110, 22, "ghost")
    calmBtn(f.btn, true) calmBtn(f.btn2)
    function f:Set(msg, b1, fn1, b2, fn2)
        self.text:SetText(msg)
        self.btn:SetShown(b1 ~= nil)
        self.btn2:SetShown(b2 ~= nil)
        self.btn:ClearAllPoints()
        if b1 then
            self.btn:SetLabel(b1)
            self.btn:SetWidth(math.max(110, (self.btn.label:GetStringWidth() or 0) + 26))
            self.btn:SetScript("OnClick", fn1)
        end
        if b2 then
            self.btn2:SetLabel(b2)
            self.btn2:SetWidth(math.max(90, (self.btn2.label:GetStringWidth() or 0) + 26))
            self.btn2:SetScript("OnClick", fn2)
            self.btn:SetPoint("TOPRIGHT", self.text, "BOTTOM", -4, -10)
            self.btn2:ClearAllPoints()
            self.btn2:SetPoint("TOPLEFT", self.text, "BOTTOM", 4, -10)
        else
            self.btn:SetPoint("TOP", self.text, "BOTTOM", 0, -10)
        end
    end
    f:Hide()
    return f
end

-- Reiterleiste: Symbol + Text + Zaehler, gleitender Balken in der Farbe der Art
local function buildTabs(p, onPick)
    local f = CreateFrame("Frame", nil, p)
    f:SetHeight(34)
    f.base = f:CreateTexture(nil, "BACKGROUND")
    f.base:SetPoint("BOTTOMLEFT") f.base:SetPoint("BOTTOMRIGHT")
    f.base:SetHeight(1)
    f.base:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    if hasGlass() then f.base:Hide() glass(f, nil, nil, 10) end
    f.buttons = {}
    for i, k in ipairs(TAB_KEYS) do
        local b = CreateFrame("Button", nil, f)
        b.key = k
        b.color = k == "all" and C.accent or kindOf(k)[2]
        b.hov = b:CreateTexture(nil, "BACKGROUND")
        b.hov:SetAllPoints()
        gradient(b.hov, "VERTICAL", b.color, 0.10, 0, 0.05)
        b.hov:SetAlpha(0)
        if hasGlass() then b.hov:SetColorTexture(1, 1, 1, 0.035) end
        b.ico = K.Glyph(b, 14, ns.MEDIA .. "icons\\" .. GLYPH[k], C.muted)
        b.label = K.Text(b, 13, C.muted)
        b.label:SetText(k == "all" and L["Alle"] or kindOf(k)[1])
        b.count = K.Text(b, 10, C.dim)
        b:SetScript("OnClick", function() onPick(k) end)
        b:SetScript("OnEnter", function(self)
            self.hov:SetAlpha(1)
            if f.value ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end
        end)
        b:SetScript("OnLeave", function(self)
            self.hov:SetAlpha(f.value == self.key and 0.6 or 0)
            if f.value ~= self.key then self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
        end)
        f.buttons[i] = b
    end
    f.ind = f:CreateTexture(nil, "OVERLAY")
    f.ind:SetHeight(2)
    f.indGlow = f:CreateTexture(nil, "ARTWORK")
    f.indGlow:SetHeight(12)
    f.indGlow:SetPoint("BOTTOMLEFT", f.ind, "TOPLEFT")
    f.indGlow:SetPoint("BOTTOMRIGHT", f.ind, "TOPRIGHT")
    function f:Layout()
        local W = self:GetWidth() or 0
        if W < 50 then return end
        local n, gap = #self.buttons, 2
        local nat, sum = {}, 0
        local withIcon = true
        for pass = 1, 2 do
            sum = 0
            for i, b in ipairs(self.buttons) do
                local cw = (b.count:GetText() or "") ~= "" and ((b.count:GetStringWidth() or 0) + 5) or 0
                nat[i] = (withIcon and 19 or 0) + (b.label:GetStringWidth() or 0) + cw + 18
                sum = sum + nat[i]
            end
            if pass == 1 and sum + gap * (n - 1) > W then withIcon = false else break end
        end
        local scale = math.min(1.6, (W - gap * (n - 1)) / math.max(1, sum))
        local x = 0
        for i, b in ipairs(self.buttons) do
            local bw = math.floor(nat[i] * scale)
            if i == n then bw = math.max(20, math.floor(W - x)) end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, 0)
            b:SetSize(bw, 33)
            b.x, b.w = x, bw
            x = x + bw + gap
            -- Gruppe (Symbol, Text, Zahl) mittig; zu eng -> Text gekuerzt (Tooltip kommt automatisch)
            local cw = (b.count:GetText() or "") ~= "" and ((b.count:GetStringWidth() or 0) + 5) or 0
            local iw = withIcon and 19 or 0
            local tw = math.max(10, math.min(b.label:GetStringWidth() or 0, bw - iw - cw - 12))
            local x0 = math.max(4, math.floor((bw - (iw + tw + cw)) / 2))
            b.ico:SetShown(withIcon)
            b.ico:ClearAllPoints()
            b.ico:SetPoint("LEFT", b, "LEFT", x0, 0)
            b.label:ClearAllPoints()
            b.label:SetPoint("LEFT", b, "LEFT", x0 + iw, 0)
            b.label:SetWidth(tw + 1)
            b.count:ClearAllPoints()
            b.count:SetPoint("LEFT", b.label, "RIGHT", 4, 0)
        end
        self:MoveInd(self.value, false)
    end
    f:SetScript("OnSizeChanged", function(self) self:Layout() end)
    function f:SetCounts(t)
        local changed = false
        for _, b in ipairs(self.buttons) do
            local n = t[b.key] or 0
            local s = n > 0 and tostring(n) or ""
            if b.count:GetText() ~= s then b.count:SetText(s) changed = true end
        end
        if changed then self:Layout() end
    end
    function f:MoveInd(key, animate)
        local tb
        for _, b in ipairs(self.buttons) do if b.key == key then tb = b end end
        if not tb or not tb.x then return end
        local c = tb.color
        self.ind:SetColorTexture(c[1], c[2], c[3], 1)
        gradient(self.indGlow, "VERTICAL", c, 0.22, 0, 0.1)
        if hasGlass() then
            -- schlanke Akzentlinie unten im Glas, kein Schein
            self.indGlow:Hide()
            self.ind:SetHeight(2)
            round(self.ind, self.ind, 1)
        end
        local x1, w1 = tb.x + 6, math.max(1, tb.w - 12)
        local x0, w0 = self.indX or x1, self.indW or w1
        self.indX, self.indW = x1, w1
        local function put(x, w)
            self.ind:ClearAllPoints()
            self.ind:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, hasGlass() and 3 or 0)
            self.ind:SetWidth(math.max(1, w))
        end
        if not animate or not animOn() then put(x1, w1) return end
        K.Tween(self.ind, 0.24, function(q) put(x0 + (x1 - x0) * q, w0 + (w1 - w0) * q) end, function() put(x1, w1) end)
    end
    function f:Select(key, animate)
        local changed = self.value ~= key
        self.value = key
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            local c = on and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3])
            local ic = on and b.color or C.muted
            b.ico:SetVertexColor(ic[1], ic[2], ic[3])
            b.hov:SetAlpha(on and 0.6 or 0)
            local cc = hasGlass() and (on and C.muted or C.dim) or (on and b.color or C.dim)
            b.count:SetTextColor(cc[1], cc[2], cc[3])
        end
        if changed or not self.indX then self:MoveInd(key, animate) end
    end
    return f
end

-- Wochen-Kachel (Verlauf, Glow, Hover-Lift, hochzaehlend), Klick = Filter
local function buildTile(parent, kind, onClick)
    local c = kindOf(kind)[2]
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(54)
    t.kind, t.lift = kind, 0
    t.bg = K.Fill(t, C.raised)
    t.grad = t:CreateTexture(nil, "BORDER", nil, 1)
    t.grad:SetAllPoints()
    gradient(t.grad, "HORIZONTAL", c, 0.16, 0.02)
    t.hov = t:CreateTexture(nil, "BORDER", nil, 2)
    t.hov:SetAllPoints()
    gradient(t.hov, "VERTICAL", c, 0, 0.20, 0.08)
    t.hov:SetAlpha(0)
    K.Border(t, C.line)
    t.top = t:CreateTexture(nil, "ARTWORK")
    t.top:SetPoint("TOPLEFT") t.top:SetPoint("TOPRIGHT")
    t.top:SetHeight(2)
    t.top:SetColorTexture(c[1], c[2], c[3], 0.85)
    t.gloss = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t.gloss:SetPoint("TOPLEFT", 1, -2) t.gloss:SetPoint("TOPRIGHT", -1, -2)
    t.gloss:SetHeight(16)
    if not K.Gradient(t.gloss, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.05 }) then t.gloss:Hide() end
    t.iconGlow = t:CreateTexture(nil, "BORDER", nil, 3)
    t.iconGlow:SetTexture(EMBER)
    t.iconGlow:SetBlendMode("ADD")
    t.iconGlow:SetSize(52, 52)
    t.iconGlow:SetVertexColor(c[1], c[2], c[3])
    t.iconGlow:SetAlpha(0.3)
    t.icon = K.Glyph(t, 22, ns.MEDIA .. "icons\\" .. GLYPH[kind], c)
    t.icon:SetPoint("RIGHT", -12, 0)
    t.iconGlow:SetPoint("CENTER", t.icon)
    t.value = K.Title(t, 20, C.text)
    t.value:SetPoint("TOPLEFT", 12, -8)
    t.sub = K.Text(t, 10, c)
    t.sub:SetPoint("BOTTOMLEFT", t.value, "BOTTOMRIGHT", 6, 2)
    t.sub:SetPoint("RIGHT", t.icon, "LEFT", -4, 0)
    t.label = K.Text(t, 10, C.muted)
    t.label:SetPoint("BOTTOMLEFT", 12, 8)
    t.label:SetPoint("RIGHT", t.icon, "LEFT", -4, 0)
    t.label:SetText(K.Upper and K.Upper(L[TILE_LABEL[kind]]) or L[TILE_LABEL[kind]]:upper())
    if hasGlass() then
        -- Glaskachel: grosse Zahl, kleine Farbmarke, "+3 heute" als Pille, ruhiges Symbol
        t.grad:Hide() t.top:Hide() t.gloss:Hide()
        t.iconGlow:SetTexture(nil) t.iconGlow:SetAlpha(0)
        t.hov:SetColorTexture(1, 1, 1, 0.035)
        round(t.hov, t, 11)
        glass(t, nil, nil, 11)
        t.icon:SetAlpha(0.75)
        t.label:SetText(L[TILE_LABEL[kind]])
        K.SetFontSafe(t.label, K.FONT, 11, "", K.FONT)
        t.label:ClearAllPoints()
        t.label:SetPoint("BOTTOMLEFT", 22, 8)
        t.label:SetPoint("RIGHT", t.icon, "LEFT", -4, 0)
        t.label:SetWordWrap(false)
        t.mark = t:CreateTexture(nil, "ARTWORK")
        t.mark:SetColorTexture(c[1], c[2], c[3], 0.9)
        t.mark:SetSize(3, 10)
        t.mark:SetPoint("RIGHT", t.label, "LEFT", -6, 0)
        round(t.mark, t.mark, 1)
        t.subPill = CreateFrame("Frame", nil, t)
        t.subPill:SetHeight(16)
        t.subPill:SetPoint("LEFT", t.value, "RIGHT", 8, 0)
        glass(t.subPill, { c[1], c[2], c[3], 0.12 }, { c[1], c[2], c[3], 0.40 }, 8)
        t.sub:SetParent(t.subPill)
        t.sub:ClearAllPoints()
        t.sub:SetPoint("CENTER", 0, 0)
        t.subPill:Hide()
    end
    function t:Place()
        if not self.bx then return end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", self:GetParent(), "TOPLEFT", self.bx, self.by + self.lift)
        self:SetWidth(self.bw)
    end
    local function hover(on)
        local from, to = t.lift, on and 2 or 0
        local h0, h1 = t.hov:GetAlpha() or 0, (on or (t.sel and not hasGlass())) and 1 or 0
        if animOn() then
            K.Tween(t.hov, 0.16, function(q)
                t.lift = from + (to - from) * q
                t.hov:SetAlpha(h0 + (h1 - h0) * q)
                if not hasGlass() then t.iconGlow:SetAlpha(0.3 + 0.4 * (t.hov:GetAlpha() or 0)) end
                t:Place()
            end)
        else
            t.lift = to
            t.hov:SetAlpha(h1)
            t.iconGlow:SetAlpha(on and 0.7 or 0.3)
            t:Place()
        end
    end
    t:SetScript("OnEnter", function(self)
        hover(true)
        K.ShowTip(self, { L[WEEK_LABEL[kind]] .. " - " .. L["letzte 7 Tage"], "|cff888888" .. (self.sel and L["Klick: Filter aufheben"] or L["Klick: nur diese Art zeigen"]) .. "|r" })
    end)
    t:SetScript("OnLeave", function() hover(false) GameTooltip:Hide() end)
    t:SetScript("OnClick", function() onClick(kind) end)
    function t:SetSel(on)
        self.sel = on
        if hasGlass() then
            glass(self, on and { c[1], c[2], c[3], 0.08 } or nil, on and { c[1], c[2], c[3], 0.55 } or nil)
            if not self:IsMouseOver() then self.hov:SetAlpha(0) end
            return
        end
        K.SetBorderColor(self, on and c or C.line, on and 0.9 or 1)
        self.top:SetHeight(on and 3 or 2)
        if not self:IsMouseOver() then self.hov:SetAlpha(on and 1 or 0) end
    end
    return t
end

-- Schalter-Chip ("Nur meine", "Nur online")
local function buildChip(parent, text, get, set)
    local b = K.Button(parent, text, 80, 22, "ghost")
    b.label:SetFont(K.FONT, 11, "")
    b:SetWidth(math.max(70, (b.label:GetStringWidth() or 0) + 26))
    function b:Update()
        local on = get()
        local c = on and C.accent or C.muted
        self.label:SetTextColor(c[1], c[2], c[3])
        K.SetBorderColor(self, on and C.accent2 or C.line)
        if hasGlass() then
            local a = C.accent
            if on then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end
            glass(self, on and { a[1], a[2], a[3], 0.15 } or { 1, 1, 1, 0.045 }, on and { a[1], a[2], a[3], 0.45 } or { 1, 1, 1, 0.10 }, 9)
        end
    end
    b:SetScript("OnClick", function(self) set(not get()) self:Update() refreshSoon(true) end)
    b:HookScript("OnLeave", function(self) self:Update() end)
    b:Update()
    return b
end

------------------------------------------------------------------------
-- Zeitleiste: eigene Liste mit unterschiedlichen Zeilenhoehen, weichem Scrollen, Tageskapitel oben angeheftet
------------------------------------------------------------------------
local function buildTimeline(p)
    local TL = CreateFrame("Frame", nil, p)
    TL:SetClipsChildren(true)
    TL:EnableMouseWheel(true)
    TL.items, TL.total, TL.off, TL.target = {}, 0, 0, 0
    TL.used, TL.pools = {}, { day = {}, card = {}, kid = {} }

    TL.line = TL:CreateTexture(nil, "BACKGROUND", nil, 1)
    TL.line:SetWidth(hasGlass() and 1 or 2)
    TL.line:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    if hasGlass() then TL.line:SetColorTexture(1, 1, 1, 0.10) end
    TL.thumb = TL:CreateTexture(nil, "OVERLAY")
    TL.thumb:SetWidth(3)
    TL.thumb:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)

    -- Zeilen ----------------------------------------------------------
    local function newDay()
        local r = CreateFrame("Frame", nil, TL)
        r.knot = r:CreateTexture(nil, "ARTWORK")
        r.knot:SetTexture(CIRCLE)
        r.knot:SetSize(14, 14)
        r.knot:SetPoint("CENTER", r, "LEFT", LINE_X - CARD_X + 1, -2)
        r.knot:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
        r.knotIn = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.knotIn:SetTexture(CIRCLE)
        r.knotIn:SetSize(8, 8)
        r.knotIn:SetPoint("CENTER", r.knot)
        r.knotIn:SetVertexColor(C.bg[1], C.bg[2], C.bg[3])
        r.text = K.Title(r, 12, C.text)
        r.text:SetPoint("LEFT", 0, -2)
        r.info = K.Text(r, 11, C.dim)
        r.info:SetPoint("LEFT", r.text, "RIGHT", 8, 0)
        r.rule = r:CreateTexture(nil, "ARTWORK")
        r.rule:SetHeight(1)
        r.rule:SetPoint("LEFT", r.info, "RIGHT", 10, 0)
        r.rule:SetPoint("RIGHT", r, "RIGHT", 0, -2)
        gradient(r.rule, "HORIZONTAL", C.line, 1, 0, 0.6)
        if hasGlass() then
            r.knot:SetSize(9, 9)
            r.knotIn:SetSize(5, 5)
            r.pillF = CreateFrame("Frame", nil, r)
            r.pillF:SetHeight(20)
            r.pillF:SetPoint("LEFT", r, "LEFT", -6, -2)
            r.pillF:SetFrameLevel(math.max(0, r:GetFrameLevel() - 1))
            glass(r.pillF, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.12 }, 10)
            r.text:ClearAllPoints()
            r.text:SetPoint("LEFT", 4, -2)
            r.rule:SetAlpha(0.5)
        end
        r.type = "day"
        return r
    end
    local function fillDay(r, it)
        if r.pillF then
            r.text:SetText(it.label)
            r.info:SetText(it.n)
            r.pillF:SetWidth((r.text:GetStringWidth() or 60) + (r.info:GetStringWidth() or 10) + 30)
            return
        end
        r.text:SetText(K.Upper and K.Upper(it.label) or it.label:upper())
        r.info:SetText((L["%d Eintraege"]):format(it.n))
    end

    local function newCard()
        local r = CreateFrame("Button", nil, TL)
        r:RegisterForClicks("AnyUp")
        r.bg = K.Fill(r, C.panel)
        r.tint = r:CreateTexture(nil, "BORDER", nil, 1)
        r.tint:SetAllPoints()
        r.hov = r:CreateTexture(nil, "BORDER", nil, 2)
        r.hov:SetAllPoints()
        r.hov:SetColorTexture(1, 1, 1, 0.045)
        r.hov:Hide()
        K.Border(r, C.line)
        r.edge = r:CreateTexture(nil, "ARTWORK")
        r.edge:SetPoint("TOPLEFT") r.edge:SetPoint("BOTTOMLEFT")
        r.edge:SetWidth(2)
        -- Knoten auf der Zeitleiste + Verbinder
        r.conn = r:CreateTexture(nil, "BACKGROUND")
        r.conn:SetHeight(1)
        r.conn:SetPoint("LEFT", r, "LEFT", LINE_X - CARD_X + 1, 0)
        r.conn:SetPoint("RIGHT", r, "LEFT", 0, 0)
        r.kglow = r:CreateTexture(nil, "BACKGROUND", nil, 2)
        r.kglow:SetTexture(EMBER)
        r.kglow:SetBlendMode("ADD")
        r.kglow:SetSize(34, 34)
        r.kglow:SetPoint("CENTER", r, "LEFT", LINE_X - CARD_X + 1, 0)
        r.knot = r:CreateTexture(nil, "ARTWORK")
        r.knot:SetTexture(CIRCLE)
        r.knot:SetPoint("CENTER", r, "LEFT", LINE_X - CARD_X + 1, 0)
        r.knotIn = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.knotIn:SetTexture(CIRCLE)
        r.knotIn:SetSize(5, 5)
        r.knotIn:SetPoint("CENTER", r.knot)
        r.knotIn:SetVertexColor(C.bg[1], C.bg[2], C.bg[3])
        r.av = makeAvatar(r)
        r.av:SetPoint("LEFT", 9, 0)
        if hasGlass() then
            glass(r, nil, nil, 12)
            r.tint:Hide() r.edge:Hide()
            r.kglow:SetTexture(nil) r.kglow:SetAlpha(0)
            r.hov:SetColorTexture(1, 1, 1, 0.035)
            round(r.hov, r, 12)
            r.knotIn:SetSize(4, 4)
        end
        r.name = K.Text(r, 13, C.text)
        r.text = K.Text(r, 13, C.text)
        r.sub = K.Text(r, 11, C.muted)
        r.pill = K.Badge(r)
        r.pill:SetPoint("TOPRIGHT", -8, -8)
        if hasGlass() then r.pill:SetHeight(16) K.SetFontSafe(r.pill.text, K.FONT, 10, "", K.FONT) end
        r.chev = K.Text(r, 14, C.muted, "CENTER")
        r.chev:SetPoint("BOTTOMRIGHT", -12, 7)
        r.chev:SetSize(14, 14)
        -- Name klickbar (Profil)
        r.nameBtn = CreateFrame("Button", nil, r)
        r.nameBtn:SetPoint("TOPLEFT", r.name, "TOPLEFT", -2, 3)
        r.nameBtn:SetPoint("BOTTOMRIGHT", r.name, "BOTTOMRIGHT", 2, -3)
        r.nameBtn:RegisterForClicks("AnyUp")
        r.nameBtn:SetScript("OnClick", function(self, btn)
            local g = r.item and r.item.g
            if not g then return end
            if btn == "RightButton" then entryMenu(self, g.e, g.kids) return end
            showProfile(g.e.who)
        end)
        r.nameBtn:SetScript("OnEnter", function(self)
            local g = r.item and r.item.g
            r.hov:Show()
            r.name:SetAlpha(0.8)
            if g and g.e.who then K.ShowTip(self, { ns.Radar.Colored(g.e.who), "|cff888888" .. L["Klick: Profil ansehen"] .. "|r" }) end
        end)
        r.nameBtn:SetScript("OnLeave", function() r.name:SetAlpha(1) r.hov:Hide() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self, btn)
            local g = self.item and self.item.g
            if not g then return end
            if btn == "RightButton" then entryMenu(self, g.e, g.kids) return end
            if IsModifiedClick and IsModifiedClick("CHATLINK") and linkItem(g.e) then return end
            if #g.kids > 1 then
                expanded[g.e.id] = not expanded[g.e.id] or nil
                refreshSoon(true)
            elseif g.e.who then
                setWho(g.e.who)
            end
        end)
        r:SetScript("OnEnter", function(self)
            local g = self.item and self.item.g
            if not g then return end
            self.hov:Show()
            K.SetBorderColor(self, self.kc, 0.75)
            if hasGlass() then glass(self, nil, { self.kc[1], self.kc[2], self.kc[3], 0.35 }) end
            entryTip(self, g.e, g.kids)
        end)
        r:SetScript("OnLeave", function(self)
            self.hov:Hide()
            K.SetBorderColor(self, self.big and self.kc or C.line, self.big and 0.55 or 1)
            if hasGlass() then glass(self, nil, self.big and { self.kc[1], self.kc[2], self.kc[3], 0.28 } or nil) end
            GameTooltip:Hide()
        end)
        r.type = "card"
        return r
    end
    local function fillCard(r, it)
        local g = it.g
        local e = g.e
        local kd = kindOf(e.kind)
        local kc = kd[2]
        local big = g.big
        r.kc, r.big = kc, big
        r.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 1)
        gradient(r.tint, "HORIZONTAL", kc, big and 0.20 or 0.09, 0, big and 0.1 or 0.04)
        r.edge:SetColorTexture(kc[1], kc[2], kc[3], big and 1 or 0.8)
        K.SetBorderColor(r, big and kc or C.line, big and 0.55 or 1)
        r.conn:SetColorTexture(kc[1], kc[2], kc[3], 0.35)
        r.knot:SetSize(big and 12 or 10, big and 12 or 10)
        r.knot:SetVertexColor(kc[1], kc[2], kc[3])
        r.knotIn:SetShown(not big)
        r.kglow:SetVertexColor(kc[1], kc[2], kc[3])
        r.kglow:SetShown(big and not hasGlass())
        r.kglow:SetAlpha(0.6)
        if hasGlass() then
            glass(r, big and { kc[1], kc[2], kc[3], 0.05 } or nil, big and { kc[1], kc[2], kc[3], 0.28 } or nil)
            r.knot:SetSize(big and 9 or 7, big and 9 or 7)
            r.conn:SetColorTexture(1, 1, 1, 0.08)
        end
        r.av:SetSz(big and 42 or 34)
        local ring = setAvatar(r.av, e)
        r.av.glow:SetShown(big and not hasGlass())
        r.av.glow:SetAlpha(0.45)
        local ax = big and 62 or 54
        -- Name + Text in Zeile 1, Zeit/Ort in Zeile 2
        K.SetFontSafe(r.name, K.FONT, big and 14 or 13, "", K.FONT)
        K.SetFontSafe(r.text, K.FONT, big and 14 or 13, "", K.FONT)
        local nm = e.who and ns.displayName(e.who) or ""
        local nameStr
        if search ~= "" and nm:lower():find(search, 1, true) then nameStr = "|cffffd84a" .. nm .. "|r"
        else nameStr = e.who and ns.Radar.Colored(e.who) or "" end
        r.name:SetText(nameStr)
        local W = r:GetWidth() or 300
        local nw = math.min((r.name:GetStringWidth() or 0) + 1, math.floor(W * 0.42))
        r.name:SetWidth(math.max(1, nw))
        r.name:ClearAllPoints()
        r.name:SetPoint("TOPLEFT", ax, big and -12 or -9)
        r.nameBtn:SetShown(e.who ~= nil)
        local txt = groupText(g)
        r.text:SetText(mark(txt))
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", r.name, "RIGHT", nm ~= "" and 5 or 0, 0)
        r.text:SetPoint("RIGHT", r.pill, "LEFT", -8, 0)
        -- Zeile 2
        local sub = { date("%H:%M", e.ts or 0), ns.ago(e.ts) }
        if #g.kids > 1 then
            local names, seen = {}, {}
            for _, k in ipairs(g.kids) do
                local s = kidLabel(k)
                if s ~= "" and not seen[s] then seen[s] = true names[#names + 1] = s end
            end
            sub[#sub + 1] = table.concat(names, ", ")
        else
            local zn = ns.zoneName(e.mapID, e.zone)
            if zn ~= "" then sub[#sub + 1] = (e.kind == "boss" and (L["mit "] .. zn) or zn) end
            if e.top then sub[#sub + 1] = L["Top-Schaden: "] .. e.top end
        end
        r.sub:SetText(table.concat(sub, "  ·  "))
        r.sub:ClearAllPoints()
        r.sub:SetPoint("BOTTOMLEFT", ax, big and 12 or 9)
        r.sub:SetPoint("RIGHT", r, "RIGHT", #g.kids > 1 and -30 or -10, 0)
        -- Marke rechts: Highlight-Stichwort oder Art
        if hasGlass() then
            -- Kategorie als kleine farbige Pille (Highlight-Stichwort normal geschrieben)
            local pc = g.tag and (ring or kc) or kc
            r.pill:Set(g.tag or kd[1], pc)
            glass(r.pill, { pc[1], pc[2], pc[3], 0.12 }, { pc[1], pc[2], pc[3], 0.40 }, 8)
        elseif g.tag then r.pill:Set(K.Upper and K.Upper(g.tag) or g.tag:upper(), ring or kc)
        else r.pill:Set(kd[1], kc) end
        r.chev:SetShown(#g.kids > 1)
        r.chev:SetText(expanded[e.id] and "-" or "+")
        if hasGlass() then r.chev:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
        if r:IsMouseOver() then r.hov:Show() else r.hov:Hide() end
    end

    local function newKid()
        local r = CreateFrame("Button", nil, TL)
        r:RegisterForClicks("AnyUp")
        r.guide = r:CreateTexture(nil, "BACKGROUND")
        r.guide:SetWidth(1)
        r.guide:SetPoint("TOPLEFT", 26, 0)
        r.guide:SetPoint("BOTTOMLEFT", 26, 0)
        r.dot = r:CreateTexture(nil, "ARTWORK")
        r.dot:SetTexture(CIRCLE)
        r.dot:SetSize(5, 5)
        r.dot:SetPoint("CENTER", r, "LEFT", 26, 0)
        r.hov = r:CreateTexture(nil, "HIGHLIGHT")
        r.hov:SetPoint("TOPLEFT", 36, 0) r.hov:SetPoint("BOTTOMRIGHT")
        r.hov:SetColorTexture(1, 1, 1, 0.05)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(18, 18)
        r.icon:SetPoint("LEFT", 40, 0)
        r.text = K.Text(r, 12, C.text)
        r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
        r.text:SetPoint("RIGHT", -62, 0)
        r.when = K.Text(r, 11, C.dim, "RIGHT")
        r.when:SetPoint("RIGHT", -10, 0)
        r:SetScript("OnClick", function(self, btn)
            local e = self.item and self.item.e
            if not e then return end
            if btn == "RightButton" then entryMenu(self, e) return end
            if IsModifiedClick and IsModifiedClick("CHATLINK") then linkItem(e) end
        end)
        r:SetScript("OnEnter", function(self) if self.item then entryTip(self, self.item.e) end end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r.type = "kid"
        return r
    end
    local function fillKid(r, it)
        local e = it.e
        local kc = kindOf(e.kind)[2]
        r.guide:SetColorTexture(kc[1], kc[2], kc[3], hasGlass() and 0.18 or 0.35)
        r.dot:SetVertexColor(kc[1], kc[2], kc[3])
        local itemID = e.item and ns.itemID(e.item)
        local tex = itemID and C_Item and C_Item.GetItemIconByID and select(2, pcall(C_Item.GetItemIconByID, itemID))
        r.icon:SetVertexColor(1, 1, 1)
        if tex then
            r.icon:SetTexture(tex) r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        elseif e.kind == "badge" and ns.Badges and ns.Badges.byId and ns.Badges.byId[e.a1] and ns.Badges.byId[e.a1].icon then
            r.icon:SetTexture(ns.Badges.byId[e.a1].icon) r.icon:SetTexCoord(0, 1, 0, 1)
        elseif e.kind == "level" and not e.rank and ns.LevelBadges and ns.LevelBadges.Exact(tonumber(e.lvl or e.a1), true) then
            r.icon:SetTexture(ns.LevelBadges.Exact(tonumber(e.lvl or e.a1), true)) r.icon:SetTexCoord(0, 1, 0, 1)
        else
            r.icon:SetTexture(ns.MEDIA .. "icons\\" .. (GLYPH[e.kind] or "chronicle")) r.icon:SetTexCoord(0, 1, 0, 1)
            r.icon:SetVertexColor(kc[1], kc[2], kc[3])
        end
        r.text:SetText(mark(lineText(e)))
        r.when:SetText(date("%H:%M", e.ts or 0))
    end

    local MAKE = { day = newDay, card = newCard, kid = newKid }
    local FILL = { day = fillDay, card = fillCard, kid = fillKid }
    local XOFF = { day = CARD_X, card = CARD_X, kid = CARD_X }

    -- angeheftetes Tageskapitel
    TL.sticky = CreateFrame("Frame", nil, TL)
    TL.sticky:SetHeight(H_DAY - 4)
    TL.sticky:SetFrameLevel((TL:GetFrameLevel() or 1) + 20)
    TL.sticky.bg = TL.sticky:CreateTexture(nil, "BACKGROUND")
    TL.sticky.bg:SetAllPoints()
    TL.sticky.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.97)
    TL.sticky.fade = TL.sticky:CreateTexture(nil, "BACKGROUND")
    TL.sticky.fade:SetPoint("TOPLEFT", TL.sticky, "BOTTOMLEFT")
    TL.sticky.fade:SetPoint("TOPRIGHT", TL.sticky, "BOTTOMRIGHT")
    TL.sticky.fade:SetHeight(8)
    gradient(TL.sticky.fade, "VERTICAL", C.bg, 0, 0.9, 0)
    TL.sticky.row = newDay()
    TL.sticky.row:SetParent(TL.sticky)
    TL.sticky.row:SetPoint("TOPLEFT", CARD_X, 0)
    TL.sticky.row:SetPoint("BOTTOMRIGHT", -10, 0)
    TL.sticky:Hide()

    function TL:MaxOff() return math.max(0, self.total - (self:GetHeight() or 0) + 8) end
    function TL:Release(r)
        r:Hide()
        r.item = nil
        local pool = self.pools[r.type]
        pool[#pool + 1] = r
    end
    function TL:Layout(force)
        local H = self:GetHeight() or 0
        local off = math.floor(self.off + 0.5)
        local keep = {}
        for it, r in pairs(self.used) do
            if force or not (it.y + it.h > off and it.y < off + H) or r.gen ~= self.gen then self:Release(r) else keep[it] = r end
        end
        self.used = keep
        local firstDay, nextDay
        for _, it in ipairs(self.items) do
            if it.t == "day" then
                if it.y <= off then firstDay = it elseif not nextDay and firstDay then nextDay = it end
            end
            if it.y + it.h > off and it.y < off + H then
                local r = self.used[it]
                if not r then
                    local pool = self.pools[it.t]
                    r = table.remove(pool) or MAKE[it.t]()
                    r.item, r.gen = it, self.gen
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", self, "TOPLEFT", XOFF[it.t] + (it.indent or 0), -(it.y - off))
                    r:SetPoint("RIGHT", self, "RIGHT", -10, 0)
                    r:SetHeight(it.h - (it.t == "card" and GAP or 0))
                    r:Show()
                    local ok, err = pcall(FILL[it.t], r, it)
                    if not ok then ns.err(L["Chronik"], err) end
                    self.used[it] = r
                else
                    r:SetPoint("TOPLEFT", self, "TOPLEFT", XOFF[it.t] + (it.indent or 0), -(it.y - off))
                end
            elseif it.y >= off + H and firstDay then
                if it.t == "day" and not nextDay then nextDay = it end
                break
            end
        end
        -- Tageskapitel oben anheften, vom naechsten Kapitel sanft hinausschieben
        if firstDay and off > 0 then
            local push = 0
            if nextDay then push = math.min(0, (nextDay.y - off) - (H_DAY - 4)) end
            self.sticky:ClearAllPoints()
            self.sticky:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -push)
            self.sticky:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            if self.sticky.cur ~= firstDay then self.sticky.cur = firstDay fillDay(self.sticky.row, firstDay) end
            self.sticky:Show()
        else
            self.sticky:Hide()
        end
        -- Linie nur so lang wie der Inhalt
        self.line:ClearAllPoints()
        self.line:SetPoint("TOPLEFT", self, "TOPLEFT", LINE_X, off > 0 and 0 or -(H_DAY / 2))
        self.line:SetHeight(math.max(1, math.min(H, self.total - off - 10) - (off > 0 and 0 or H_DAY / 2)))
        self.line:SetShown(#self.items > 0)
        -- Rollbalken
        local maxOff = self:MaxOff()
        if maxOff > 0 and H > 0 then
            local th = math.max(24, H * H / math.max(H, self.total))
            self.thumb:SetHeight(th)
            self.thumb:ClearAllPoints()
            self.thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -((H - th) * off / maxOff))
            self.thumb:Show()
        else
            self.thumb:Hide()
        end
    end
    function TL:ScrollTo(v, animate)
        self.target = math.max(0, math.min(self:MaxOff(), v))
        if not animate or not animOn() then
            self.off = self.target
            self:SetScript("OnUpdate", nil)
            self:Layout()
            return
        end
        -- OnUpdate nur waehrend der Bewegung (und nur solange sichtbar)
        self:SetScript("OnUpdate", function(s, el)
            local d = s.target - s.off
            if math.abs(d) < 0.6 then
                s.off = s.target
                s:SetScript("OnUpdate", nil)
            else
                s.off = s.off + d * math.min(1, el * 14)
            end
            s:Layout()
        end)
    end
    TL:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self.target - delta * 72, true) end)
    TL:SetScript("OnSizeChanged", function(self) self:Layout(true) end)
    TL:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) self.off = self.target end)

    -- Daten setzen; keepAnchor = Leseposition halten, wenn oben Neues dazukommt (kein Springen beim Nachladen)
    function TL:SetItems(items, keepAnchor)
        local anchorKey, anchorDy
        if keepAnchor and self.off > 0 then
            for _, it in ipairs(self.items) do
                if it.y + it.h > self.off then anchorKey, anchorDy = it.key, it.y - self.off break end
            end
        end
        local y = 0
        for _, it in ipairs(items) do it.y = y y = y + it.h end
        self.items, self.total = items, y
        self.gen = (self.gen or 0) + 1
        self.sticky.cur = nil
        if anchorKey then
            for _, it in ipairs(items) do
                if it.key == anchorKey then self.off = it.y - anchorDy self.target = self.off break end
            end
        elseif not keepAnchor then
            self.off, self.target = 0, 0
        end
        self.off = math.max(0, math.min(self:MaxOff(), self.off))
        self.target = math.max(0, math.min(self:MaxOff(), self.target))
        self:Layout(true)
    end
    -- sichtbare Karten gestaffelt einblenden (nur beim Oeffnen/Filterwechsel)
    function TL:Stagger()
        if not animOn() then return end
        local list = {}
        for it, r in pairs(self.used) do list[#list + 1] = { it.y, r } end
        table.sort(list, function(a, b) return a[1] < b[1] end)
        for i, x in ipairs(list) do
            local r = x[2]
            r:SetAlpha(0)
            K.Tween(r, 0.28, function(q) r:SetAlpha(q) end, function() r:SetAlpha(1) end, math.min(0.5, (i - 1) * 0.035))
        end
        ns.After(1.2, function() for _, r in pairs(self.used) do r:SetAlpha(1) end end)
    end
    -- Glow der Highlights atmet leise (OnUpdate nur solange die Seite sichtbar ist)
    local pulse = CreateFrame("Frame", nil, TL)
    pulse.t = 0
    pulse:SetScript("OnUpdate", function(s, el)
        if not animOn() then return end
        s.t = s.t + el
        if s.t < 0.05 then return end
        s.ph = ((s.ph or 0) + s.t) % 2.4
        s.t = 0
        local a = 0.42 + 0.22 * math.sin(s.ph / 2.4 * math.pi * 2)
        for _, r in pairs(TL.used) do
            if r.big and r.kglow and not hasGlass() then r.kglow:SetAlpha(a + 0.15) r.av.glow:SetAlpha(a) end
        end
    end)
    return TL
end

------------------------------------------------------------------------
-- Rechte Spalte
------------------------------------------------------------------------
local function sideBox(parent, title, color)
    local f = K.Panel(parent, C.panel)
    f.head = K.GameHead(f, title, color)
    if hasGlass() then
        glass(f, nil, nil, 12)
        f.head.text:SetText(title)
        if f.head.mark then f.head.mark:SetSize(3, 12) end
        f.head.Live = function() end
    end
    f.head:SetPoint("TOPLEFT", 10, -9)
    f.head:SetPoint("RIGHT", -10, 0)
    return f
end

local function buildHighlight(p)
    local f = sideBox(p, L["Highlight der Woche"], C.amber)
    f:SetHeight(86)
    f.glow = f:CreateTexture(nil, "BORDER")
    f.glow:SetAllPoints()
    gradient(f.glow, "HORIZONTAL", C.amber, 0.10, 0)
    if hasGlass() then f.glow:Hide() end
    f.btn = CreateFrame("Button", nil, f)
    f.btn:SetPoint("TOPLEFT", 4, -28)
    f.btn:SetPoint("BOTTOMRIGHT", -4, 4)
    f.btn:RegisterForClicks("AnyUp")
    f.btn.hl = f.btn:CreateTexture(nil, "HIGHLIGHT")
    f.btn.hl:SetAllPoints()
    f.btn.hl:SetColorTexture(1, 1, 1, 0.04)
    f.av = makeAvatar(f.btn)
    f.av:SetSz(38)
    f.av:SetPoint("LEFT", 8, 0)
    f.av.glow:SetShown(not hasGlass())
    f.av.glow:SetAlpha(0.5)
    if hasGlass() then f.btn.hl:SetColorTexture(1, 1, 1, 0.035) round(f.btn.hl, f.btn, 10) end
    f.name = K.Text(f.btn, 13, C.text)
    f.name:SetPoint("TOPLEFT", 56, -5)
    f.name:SetPoint("RIGHT", -6, 0)
    f.text = K.Text(f.btn, 11, C.muted)
    f.text:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
    f.text:SetPoint("RIGHT", -6, 0)
    f.when = K.Text(f.btn, 10, C.dim)
    f.when:SetPoint("TOPLEFT", f.text, "BOTTOMLEFT", 0, -3)
    f.when:SetPoint("RIGHT", -6, 0)
    f.none = K.Text(f, 11, C.dim)
    f.none:SetPoint("LEFT", 14, -10)
    f.none:SetPoint("RIGHT", -10, -10)
    f.none:SetWordWrap(true)
    f.none:SetText(L["Noch kein Highlight - die Woche ist jung."])
    f.btn:SetScript("OnClick", function(self, btn)
        local e = f.e
        if not e then return end
        if btn == "RightButton" then entryMenu(self, e) return end
        if IsModifiedClick and IsModifiedClick("CHATLINK") and linkItem(e) then return end
        showProfile(e.who)
    end)
    f.btn:SetScript("OnEnter", function(self) if f.e then entryTip(self, f.e) end end)
    f.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function f:Set(e, tag)
        self.e = e
        self.btn:SetShown(e ~= nil)
        self.none:SetShown(e == nil)
        if not e then return end
        setAvatar(self.av, e)
        self.name:SetText((e.who and ns.Radar.Colored(e.who) or "") .. (tag and ("  " .. K.hex(C.amber) .. ((K.Upper and not hasGlass()) and K.Upper(tag) or tag) .. "|r") or ""))
        self.text:SetText(lineText(e))
        self.when:SetText(dayLabel(e.ts) .. ", " .. date("%H:%M", e.ts or 0))
    end
    return f
end

local function buildWeek(p, onPick)
    local f = sideBox(p, L["Diese Woche"], C.accent)
    f:SetHeight(32 + #WEEK_KINDS * 19 + 6)
    f.rows = {}
    for i, k in ipairs(WEEK_KINDS) do
        local c = kindOf(k)[2]
        local r = CreateFrame("Button", nil, f)
        r:SetHeight(18)
        r:SetPoint("TOPLEFT", 8, -30 - (i - 1) * 19)
        r:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(c[1], c[2], c[3], 0.08)
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints()
        gradient(r.sel, "HORIZONTAL", c, 0.16, 0)
        r.sel:Hide()
        if hasGlass() then
            r.sel:SetColorTexture(c[1], c[2], c[3], 0.10)
            round(r.sel, r, 6)
            r.hl:SetColorTexture(1, 1, 1, 0.035)
            round(r.hl, r, 6)
        end
        r.label = K.Text(r, 11, C.muted)
        r.label:SetPoint("LEFT", 4, 0)
        r.label:SetWidth(96)
        r.label:SetText(L[WEEK_LABEL[k]])
        r.value = K.Title(r, 12, C.text, "RIGHT")
        r.value:SetPoint("RIGHT", -4, 0)
        r.value:SetWidth(30)
        r.track = r:CreateTexture(nil, "ARTWORK")
        r.track:SetHeight(5)
        r.track:SetPoint("LEFT", 104, 0)
        r.track:SetPoint("RIGHT", -38, 0)
        r.track:SetColorTexture(1, 1, 1, 0.05)
        r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.fill:SetHeight(5)
        r.fill:SetPoint("LEFT", r.track, "LEFT")
        gradient(r.fill, "HORIZONTAL", c, 0.55, 1, 0.9)
        if hasGlass() then
            r.fill:SetColorTexture(c[1], c[2], c[3], 0.85)
            round(r.track, r.track, 2)
            round(r.fill, r.fill, 2)
        end
        r.fill:SetWidth(1)
        r:SetScript("OnClick", function() onPick(k) end)
        r:SetScript("OnEnter", function(self)
            K.ShowTip(self, { L[WEEK_LABEL[k]], (L["%d Eintraege"]):format(self.n or 0) .. " - " .. L["letzte 7 Tage"], "|cff888888" .. L["Klick: nur diese Art zeigen"] .. "|r" })
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.rows[k] = r
    end
    function f:Set(counts, sel, animate)
        local max = 1
        for _, k in ipairs(WEEK_KINDS) do max = math.max(max, counts[k] or 0) end
        for i, k in ipairs(WEEK_KINDS) do
            local r = self.rows[k]
            local n = counts[k] or 0
            r.n = n
            r.value:SetText(n)
            local vc = n > 0 and C.text or C.dim
            r.value:SetTextColor(vc[1], vc[2], vc[3])
            r.sel:SetShown(sel == k)
            local tw = (r.track:GetWidth() or 60)
            local w = math.max(1, tw * n / max)
            r.fill:SetShown(n > 0)
            if animate and animOn() and n > 0 then
                r.fill:SetWidth(1)
                K.Tween(r.fill, 0.7, function(q) r.fill:SetWidth(math.max(1, w * q)) end, nil, (i - 1) * 0.05)
            else
                r.fill:SetWidth(w)
            end
        end
    end
    return f
end

local function buildTop(p)
    local f = sideBox(p, L["Am aktivsten (7 Tage)"], C.mint)
    f.list = K.List(f, 28, function(l)
        local r = K.Row(l)
        r.stripe:Hide()
        r.medal = r:CreateTexture(nil, "ARTWORK")
        r.medal:SetTexture(CIRCLE)
        r.medal:SetSize(18, 18)
        r.medal:SetPoint("LEFT", 4, 0)
        r.rank = r:CreateFontString(nil, "OVERLAY")
        K.SetFontSafe(r.rank, K.FONT_HEAD or K.FONT, 10, "", K.FONT)
        r.rank:SetSize(18, 18)
        K.CenterNum(r.rank, r.medal, "CENTER", 0, 0)
        r.ring = r:CreateTexture(nil, "ARTWORK")
        r.ring:SetTexture(CIRCLE)
        r.ring:SetSize(20, 20)
        r.ring:SetPoint("LEFT", 28, 0)
        r.inner = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.inner:SetTexture(CIRCLE)
        r.inner:SetSize(17, 17)
        r.inner:SetPoint("CENTER", r.ring)
        r.inner:SetVertexColor(0.06, 0.06, 0.07)
        r.cls = r:CreateTexture(nil, "ARTWORK", nil, 2)
        r.cls:SetSize(12, 12)
        r.cls:SetPoint("CENTER", r.ring)
        r.ini = K.Text(r, 10, C.text, "CENTER")
        r.ini:SetPoint("CENTER", r.ring, "CENTER", 0, 0)
        r.ini:SetWidth(20)
        if hasGlass() then
            r.cls:SetSize(16, 16)
            r.inner:SetSize(18, 18)
            round(r.track, r.track, 1)
            round(r.bar, r.bar, 1)
            r.hl:SetColorTexture(1, 1, 1, 0.035)
            round(r.hl, r, 6)
        end
        r.who = K.Text(r, 12, C.text)
        r.who:SetPoint("TOPLEFT", 54, -3)
        r.who:SetPoint("RIGHT", -44, 0)
        r.track = r:CreateTexture(nil, "ARTWORK")
        r.track:SetHeight(3)
        r.track:SetPoint("BOTTOMLEFT", 54, 5)
        r.track:SetPoint("RIGHT", -44, 0)
        r.track:SetColorTexture(1, 1, 1, 0.05)
        r.bar = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.bar:SetHeight(3)
        r.bar:SetPoint("LEFT", r.track, "LEFT")
        r.n = K.Title(r, 12, C.text, "RIGHT")
        r.n:SetPoint("RIGHT", -8, 0)
        r.n:SetWidth(34)
        r:SetScript("OnClick", function(self, btn)
            if not self.item then return end
            if btn == "RightButton" then entryMenu(self, { who = self.item.who, kind = "guild", noCopy = true }) return end
            setWho(self.item.who)
        end)
        r:RegisterForClicks("AnyUp")
        r:SetScript("OnEnter", function(self)
            if not self.item then return end
            K.ShowTip(self, { ns.Radar.Colored(self.item.who), (L["%d Eintraege"]):format(self.item.n) .. " - " .. L["letzte 7 Tage"],
                "|cff888888" .. (whoFilter == self.item.who and L["Klick: Personenfilter aufheben"] or L["Klick: nur Eintraege dieser Person"]) .. "|r" })
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return r
    end, function(r, x)
        local m = MEDAL[x.rank]
        r.medal:SetShown(m ~= nil)
        if m then
            r.medal:SetVertexColor(m[1], m[2], m[3])
            r.rank:SetTextColor(0.1, 0.08, 0.05)
        else
            r.rank:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        end
        r.rank:SetText(x.rank)
        local cls = classFor(x.who)
        local cr, cg, cb = ns.classColor(cls)
        r.ring:SetVertexColor(cr, cg, cb, hasGlass() and 0.7 or 1)
        local ok = cls ~= nil and setClassIcon(r.cls, cls) or false
        r.cls:SetShown(ok)
        r.ini:SetShown(not ok)
        if not ok then r.ini:SetText(((ns.displayName(x.who) or "?"):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"):upper()) end
        r.who:SetText(ns.Radar.Colored(x.who))
        r.n:SetText(x.n)
        local tw = r.track:GetWidth() or 100
        r.bar:SetWidth(math.max(1, tw * x.n / math.max(1, x.max)))
        r.bar:SetColorTexture(cr, cg, cb, 0.85)
        r.sel:SetShown(whoFilter == x.who)
    end)
    f.list:SetPoint("TOPLEFT", 4, -30)
    f.list:SetPoint("BOTTOMRIGHT", -4, 6)
    f.list.empty:SetText(L["Diese Woche noch ruhig."])
    return f
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local page
local pending, pendingKeep = false, true
-- gebuendeltes Neuzeichnen: viele Datensaetze beim Abgleich -> ein Durchlauf
refreshSoon = function(now)
    if now then
        pendingKeep = false
        ns.RefreshPage("chronicle")
        pendingKeep = true
        return
    end
    if pending then return end
    pending = true
    ns.After(0.25, function()
        pending = false
        ns.RefreshPage("chronicle")
    end)
end
Chronicle.RefreshSoon = refreshSoon

local function setFilter(k, toggle)
    if toggle and filter == k then k = "all" end
    filter = k
    if page and page.tl then
        page.tl.switch = true
        if animOn() then
            local tl = page.tl
            tl:SetAlpha(0.15)
            K.Tween(tl, 0.22, function(q) tl:SetAlpha(0.15 + 0.85 * q) end, function() tl:SetAlpha(1) end)
        end
    end
    refreshSoon(true)
end

local SIDE = 228

ns.RegisterPage({
    key = "chronicle", title = "Chronik", order = 6,
    sub = "Was in der Gilde passiert: Level-Meilensteine, epische Beute, Legacy, Bosse, neue Gesichter",
    build = function(p)
        page = p
        p.fresh = true
        p:HookScript("OnShow", function(self) self.fresh = true end)

        p.tabs = buildTabs(p, setFilter)
        p.tabs:SetPoint("TOPLEFT", 0, 0)
        p.tabs:SetPoint("TOPRIGHT", 0, 0)

        -- Kennzahl-Kacheln dieser Woche
        p.tileRow = CreateFrame("Frame", nil, p)
        p.tileRow:SetPoint("TOPLEFT", 0, -42)
        p.tileRow:SetPoint("TOPRIGHT", 0, -42)
        p.tileRow:SetHeight(56)
        p.tiles = {}
        for i, k in ipairs(TILE_KINDS) do p.tiles[i] = buildTile(p.tileRow, k, function(x) setFilter(x, true) end) end
        local function layoutTiles(w)
            local n, gap = #p.tiles, 8
            local tw = math.floor(((w or 700) - gap * (n - 1)) / n)
            for i, t in ipairs(p.tiles) do
                t.bx, t.by, t.bw = (i - 1) * (tw + gap), 0, tw
                t:Place()
            end
        end
        p.tileRow:SetScript("OnSizeChanged", function(_, w) layoutTiles(w) end)
        layoutTiles(p.tileRow:GetWidth())

        -- Werkzeugleiste: Suche, Schalter, Personenfilter, Anzahl
        local TOOL_Y = -108
        p.search = K.Input(p, 170, L["Suchen ..."], function(t)
            search = (t or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            refreshSoon(true)
        end)
        p.search:SetPoint("TOPLEFT", 0, TOOL_Y)
        p.mine = buildChip(p, L["Nur meine"], function() return onlyMine end, function(v) onlyMine = v end)
        p.mine:SetPoint("LEFT", p.search, "RIGHT", 8, 0)
        p.online = buildChip(p, L["Nur online"], function() return onlyOnline end, function(v) onlyOnline = v end)
        p.online:SetPoint("LEFT", p.mine, "RIGHT", 6, 0)
        p.chip = K.Button(p, "", 140, 22, "ghost", function() whoFilter = nil refreshSoon(true) end)
        calmBtn(p.chip)
        glass(p.search, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.10 }, 8)
        p.chip:SetPoint("LEFT", p.online, "RIGHT", 6, 0)
        p.chip.label:SetFont(K.FONT, 11, "")
        p.count = K.Text(p, 11, C.dim, "RIGHT")

        -- Zeitleiste
        p.tl = buildTimeline(p)
        p.empty = emptyState(p.tl, C.accent, "")
        p.empty:SetPoint("TOP", 0, -50)

        -- rechte Spalte
        p.hl = buildHighlight(p)
        p.week = buildWeek(p, function(x) setFilter(x, true) end)
        p.top = buildTop(p)

        local function layout()
            local W = p:GetWidth() or 700
            local side = W >= 620
            p.hl:SetShown(side) p.week:SetShown(side) p.top:SetShown(side)
            local right = side and (SIDE + 12) or 0
            p.count:ClearAllPoints()
            p.count:SetPoint("TOPRIGHT", p, "TOPRIGHT", -(right + 10), TOOL_Y - 6)
            p.tl:ClearAllPoints()
            p.tl:SetPoint("TOPLEFT", 0, TOOL_Y - 32)
            p.tl:SetPoint("BOTTOMRIGHT", -right, 0)
            if side then
                p.hl:ClearAllPoints()
                p.hl:SetPoint("TOPRIGHT", 0, TOOL_Y)
                p.hl:SetWidth(SIDE)
                p.week:ClearAllPoints()
                p.week:SetPoint("TOPRIGHT", p.hl, "BOTTOMRIGHT", 0, -8)
                p.week:SetWidth(SIDE)
                p.top:ClearAllPoints()
                p.top:SetPoint("TOPRIGHT", p.week, "BOTTOMRIGHT", 0, -8)
                p.top:SetPoint("BOTTOM", p, "BOTTOM", 0, 0)
                p.top:SetWidth(SIDE)
                -- wenig Hoehe: Highlight weglassen, damit "Am aktivsten" Platz behaelt
                local H = p:GetHeight() or 500
                local small = H < 470
                p.hl:SetShown(not small)
                if small then p.week:ClearAllPoints() p.week:SetPoint("TOPRIGHT", 0, TOOL_Y) end
            end
            -- Chips nur, wenn Platz ist (sonst ueberlappt die Anzahl)
            local avail = W - right
            p.online:SetShown(avail >= 430)
            p.count:SetShown(avail >= 470)
        end
        p:HookScript("OnSizeChanged", layout)
        layout()
    end,

    refresh = function(p)
        local keep = pendingKeep and not p.tl.switch
        local fresh = p.fresh
        local all = Store.List("chronicle")
        wipe(classCache)
        local now = ns.now()
        local since, today = now - 7 * 86400, dayKey(now)

        -- Erstkills (fruehester Kill je Boss) + Wochenzahlen
        wipe(firstKill)
        local fkTs = {}
        local week, todayN, per = {}, {}, {}
        local best, bestScore, bestTag
        for _, e in ipairs(all) do
            if e.kind == "boss" and e.a1 and (not fkTs[e.a1] or (e.ts or 0) < fkTs[e.a1]) then fkTs[e.a1] = e.ts or 0 firstKill[e.a1] = e.id end
        end
        for _, e in ipairs(all) do
            if (e.ts or 0) >= since then
                local k = e.kind
                if k == "level" and e.rank then k = nil end
                if k == "guild" and not isJoin(e) then k = nil end
                if k then
                    week[k] = (week[k] or 0) + 1
                    if dayKey(e.ts) == today then todayN[k] = (todayN[k] or 0) + 1 end
                end
                if e.who and e.kind ~= "news" and e.kind ~= "guild" then
                    local mw = ns.Alts and ns.Alts.Main and ns.Alts.Main(e.who) or e.who
                    per[mw] = (per[mw] or 0) + 1
                end
                local s, tag = highlight(e)
                if e.kind ~= "news" and (not best or s > bestScore or (s == bestScore and (e.ts or 0) > (best.ts or 0))) then
                    best, bestScore, bestTag = e, s, tag
                end
            end
        end

        -- Filter + Zaehler je Reiter
        local base, counts = {}, { all = 0 }
        for _, e in ipairs(all) do
            if passBase(e) then
                base[#base + 1] = e
                counts.all = counts.all + 1
                counts[e.kind] = (counts[e.kind] or 0) + 1
            end
        end
        local rows = {}
        for _, e in ipairs(base) do if filter == "all" or e.kind == filter then rows[#rows + 1] = e end end
        table.sort(rows, function(a, b)
            if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
            return (a.id or "") > (b.id or "")
        end)
        local groups = bundle(rows)

        -- Zeitleiste: Tageskapitel + Karten (+ aufgeklappte Einzeleintraege)
        local items, curDay, head = {}, nil, nil
        for _, g in ipairs(groups) do
            local k = dayKey(g.e.ts)
            if k ~= curDay then
                curDay = k
                head = { t = "day", h = H_DAY, label = dayLabel(g.e.ts), n = 0, key = "d" .. k }
                items[#items + 1] = head
            end
            head.n = head.n + #g.kids
            items[#items + 1] = { t = "card", g = g, h = (g.big and H_BIG or H_CARD) + GAP, key = "c" .. (g.e.id or "") }
            if #g.kids > 1 and expanded[g.e.id] then
                for i, kid in ipairs(g.kids) do
                    items[#items + 1] = { t = "kid", e = kid, h = H_KID, key = "k" .. (kid.id or i), last = i == #g.kids }
                end
                items[#items].h = H_KID + GAP
            end
        end
        p.tl:SetItems(items, keep)
        if fresh or p.tl.switch then p.tl:Stagger() end
        p.tl.switch = nil

        -- Leerzustand mit passender Aktion
        local filtered = filter ~= "all" or whoFilter or search ~= "" or onlyMine or onlyOnline
        p.empty:SetShown(#items == 0)
        if #items == 0 then
            if filtered then
                p.empty:Set(L["Nichts gefunden - andere Filter probieren?"], L["Filter zuruecksetzen"], function()
                    filter, whoFilter, search, onlyMine, onlyOnline = "all", nil, "", false, false
                    p.search:SetText("")
                    p.mine:Update() p.online:Update()
                    refreshSoon(true)
                end)
            else
                p.empty:Set(L["Noch nichts passiert - zieht los und schreibt Geschichte!"], L["Gruppe suchen"], function() ns.ShowPage("groups") end,
                    L["Gildenchat"], function() ns.ShowPage("chat") end)
            end
        end

        -- Kopf
        p.tabs:SetCounts(counts)
        p.tabs:Select(filter, not fresh)
        for _, t in ipairs(p.tiles) do
            local n = week[t.kind] or 0
            t:SetSel(filter == t.kind)
            local tn = todayN[t.kind] or 0
            t.sub:SetText(tn > 0 and ((L["+%d heute"]):format(tn)) or "")
            if t.subPill then
                t.subPill:SetShown(tn > 0)
                if tn > 0 then t.subPill:SetWidth((t.sub:GetStringWidth() or 40) + 14) end
            end
            local vc = n > 0 and C.text or C.dim
            t.value:SetTextColor(vc[1], vc[2], vc[3])
            if fresh and animOn() then
                K.CountUp(t.value, n, 0.9)
            elseif t.shown ~= n then
                t.value:SetText(n)
            end
            t.shown = n
        end
        if fresh and animOn() then
            for i, t in ipairs(p.tiles) do K.FadeIn(t, (i - 1) * 0.05) end
        end

        p.mine:Update() p.online:Update()
        p.chip:SetShown(whoFilter ~= nil)
        if whoFilter then
            p.chip:SetLabel(L["nur "] .. ns.displayName(whoFilter) .. "  |cff888888x|r")
            p.chip:SetWidth(math.min(170, (p.chip.label:GetStringWidth() or 0) + 24))
        end
        p.count:SetText((L["%d Eintraege"]):format(#rows))

        -- rechte Spalte
        p.hl:Set(best, bestTag)
        p.week:Set(week, filter, fresh)
        local top, max = {}, 1
        for who, n in pairs(per) do top[#top + 1] = { who = who, n = n } max = math.max(max, n) end
        table.sort(top, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.who < b.who end)
        for i, x in ipairs(top) do x.rank, x.max = i, max end
        p.top.list:SetData(top)
        p.fresh = false
    end,
})
end)

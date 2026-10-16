-- Oasis: Begegnungen ausserhalb der Gilde (0.5.512)
--  * Ausruestung betrachten: beim Betrachten (eigenes oder Blizzards) werden Ausruestung + Gegenstandsstufe gemerkt;
--    fremde Mitspieler in der Gruppe betrachtet Oasis ausser Kampf selbst (gedrosselt) - Talente gleich mit
--  * Realm-Blick: Klasse, Level und Gilde von Spielern, denen man begegnet (Ziel, Maus, Gruppe) -> Statistik
--  * Anwerben: gute, aktive Spieler ohne Gilde aus Gruppen; "Vorschlagen" teilt sie mit der Gilde (Store "scout")
-- Daten ueber Fremde bleiben in der Gilde (nur Vorschlaege werden geteilt), nie im Oasis-Netz.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Begegnungen", function()   -- Modul Begegnungen (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local S = {}
ns.Scout = S
local COLL = "scout"
local SEEN_MAX, GEAR_MAX = 4000, 300

local function sdb() ns.db.seen = ns.db.seen or {} return ns.db.seen end
local function gdb() ns.db.gear = ns.db.gear or {} return ns.db.gear end
local function fullOf(unit)
    local n, realm = ns.UnitFullName(unit)
    n, realm = ns.safe(n), ns.safe(realm)
    if not n or not ns.validName(n) then return nil end
    return ns.fullName((realm and realm ~= "") and (n .. "-" .. realm) or n)
end
local function isGuildie(full) return ns.Radar and ns.Radar.byName and ns.Radar.byName[full] ~= nil end

------------------------------------------------------------------------
-- Begegnungen erfassen (nur ausser Kampf, je Name hoechstens alle 5 Minuten)
------------------------------------------------------------------------
local lastSeen = {}
function S.See(unit)
    if not unit or ns.inCombat() or not ns.db then return end
    if not ns.safe(UnitIsPlayer(unit)) or ns.safe(UnitIsUnit(unit, "player")) then return end
    local full = fullOf(unit)
    if not full or isGuildie(full) then return end
    local now = GetTime()
    if lastSeen[full] and now - lastSeen[full] < 300 then return end
    lastSeen[full] = now
    local _, cls = UnitClass(unit)
    local e = sdb()[full] or { f = ns.now() }
    e.c = ns.safe(cls) or e.c
    e.l = ns.safe(UnitLevel(unit)) or e.l
    local g = ns.safe(GetGuildInfo(unit))
    if g ~= nil then e.g = g end
    if g == nil and UnitIsVisible and ns.safe(UnitIsVisible(unit)) then e.g = e.g or "" end   -- sichtbar, ohne Gilde
    local fac = UnitFactionGroup and ns.safe(UnitFactionGroup(unit))
    if fac then e.fa = fac:sub(1, 1) end
    e.t = ns.now()
    e.z = ns.safe(GetRealZoneText()) or e.z
    sdb()[full] = e
    -- Spielerbuch-Eintrag (Gruppe) bekommt die Gilde mit
    local a = ns.db.allies and ns.db.allies[full]
    if a and e.g ~= nil then a.guild = e.g end
end
ns.On("PLAYER_TARGET_CHANGED", function() if ns.db and ns.db.settings.scoutSeen ~= false then S.See("target") end end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() if ns.db and ns.db.settings.scoutSeen ~= false then S.See("mouseover") end end)
ns.On("GROUP_ROSTER_UPDATE", function()
    if not ns.db or ns.inCombat() then return end
    local raid = IsInRaid()
    for i = 1, (GetNumGroupMembers() or 0) do
        local u = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(u) then S.See(u) end
    end
end)
-- aufraeumen: aelter als 90 Tage, hoechstens SEEN_MAX Eintraege
ns.Listen("LOGIN", function()
    ns.After(40, function()
        local db, list = sdb(), {}
        for k, v in pairs(db) do
            if ns.now() - (v.t or 0) > 90 * 86400 then db[k] = nil else list[#list + 1] = { k, v.t or 0 } end
        end
        if #list > SEEN_MAX then
            table.sort(list, function(a, b) return a[2] < b[2] end)
            for i = 1, #list - SEEN_MAX do db[list[i][1]] = nil end
        end
    end)
end)

------------------------------------------------------------------------
-- Ausruestung beim Betrachten merken
------------------------------------------------------------------------
local SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
local SLOT_NAME = { [1] = "Kopf", [2] = "Hals", [3] = "Schultern", [15] = "Ruecken", [5] = "Brust", [9] = "Handgelenke",
    [10] = "Haende", [6] = "Taille", [7] = "Beine", [8] = "Fuesse", [11] = "Ring", [12] = "Ring", [13] = "Schmuck",
    [14] = "Schmuck", [16] = "Waffenhand", [17] = "Nebenhand", [18] = "Distanz" }
S.SLOTS, S.SLOT_NAME = SLOTS, SLOT_NAME
local function ilvlOf(link)
    if not link then return nil end
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local ok, v = pcall(C_Item.GetDetailedItemLevelInfo, link)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    if GetDetailedItemLevelInfo then
        local ok, v = pcall(GetDetailedItemLevelInfo, link)
        if ok and type(v) == "number" and v > 0 then return v end
    end
end
S.IlvlOf = ilvlOf
local function unitByGuid(guid)
    guid = ns.safe(guid)
    if not guid then return nil end
    local list = { "target", "mouseover", "focus" }
    if IsInRaid() then for i = 1, 40 do list[#list + 1] = "raid" .. i end
    else for i = 1, 4 do list[#list + 1] = "party" .. i end end
    for _, u in ipairs(list) do
        if UnitExists(u) and ns.safe(UnitGUID(u)) == guid then return u end
    end
end
function S.ReadGear(unit)
    local full = fullOf(unit)
    if not full or ns.safe(UnitIsUnit(unit, "player")) then return end
    local items, sum, n, missing = {}, 0, 0, 0
    for _, slot in ipairs(SLOTS) do
        local link = ns.safe(GetInventoryItemLink(unit, slot))
        if link then
            items[slot] = link
            local il = ilvlOf(link)
            if il then sum = sum + il n = n + 1 else missing = missing + 1 end
        end
    end
    if not next(items) then return end
    local _, cls = UnitClass(unit)
    local e = { t = ns.now(), i = items, il = n > 0 and math.floor(sum / n + 0.5) or nil, c = ns.safe(cls), l = ns.safe(UnitLevel(unit)) }
    local db = gdb()
    db[full] = e
    -- begrenzen
    local cnt, oldest, ok = 0, nil, nil
    for k, v in pairs(db) do cnt = cnt + 1 if not oldest or (v.t or 0) < oldest then oldest, ok = v.t or 0, k end end
    if cnt > GEAR_MAX and ok then db[ok] = nil end
    if missing > 0 and not S.retry then
        -- Gegenstandsdaten noch nicht da: einmal kurz spaeter erneut lesen
        S.retry = true
        ns.After(1.5, function() S.retry = nil if UnitExists(unit) and fullOf(unit) == full then S.ReadGear(unit) end end)
    end
    if S.win and S.win:IsShown() and S.win.who == full then S.ShowGear(full) end
    ns.RefreshPage("scout")
    return e
end
ns.On("INSPECT_READY", function(guid)
    local u = unitByGuid(guid)
    if u then pcall(S.ReadGear, u) end
end)

-- fremde Mitspieler in der Gruppe ausser Kampf selbst betrachten (je Person hoechstens alle 20 Min, alle 4 s einer)
local autoT = 0
local function autoInspect()
    if not ns.db or ns.db.settings.scoutAutoInspect == false or ns.inCombat() or not IsInGroup() then return end
    if InspectFrame and InspectFrame:IsShown() then return end
    if GetTime() - autoT < 4 then return end
    local raid = IsInRaid()
    for i = 1, (GetNumGroupMembers() or 0) do
        local u = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(u) and not ns.safe(UnitIsUnit(u, "player")) then
            local full = fullOf(u)
            local g = full and gdb()[full]
            if full and not isGuildie(full) and (not g or ns.now() - (g.t or 0) > 1200)
                and ns.safe(CanInspect(u)) and ns.safe(CheckInteractDistance and CheckInteractDistance(u, 1) or true) then
                autoT = GetTime()
                if ns.Talents and ns.Talents.Inspect then ns.Talents.Inspect(u, false) else pcall(NotifyInspect, u) end
                return
            end
        end
    end
end
ns.Listen("LOGIN", function() ns.Every(5, autoInspect) end)

------------------------------------------------------------------------
-- Ausruestungs-Fenster
------------------------------------------------------------------------
local function buildGear()
    local f = CreateFrame("Frame", "OasisGearView", UIParent)
    f:SetSize(460, 420)
    f:SetPoint("CENTER", 120, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    K.Fill(f, C.bg)
    K.Border(f, C.line)
    if K.ApplySkin then pcall(K.ApplySkin, f, "panel", C.bg) end
    f.head = f:CreateTexture(nil, "BORDER")
    f.head:SetPoint("TOPLEFT", 1, -1) f.head:SetPoint("TOPRIGHT", -1, -1) f.head:SetHeight(58)
    f.title = K.Title(f, 15, C.text)
    f.title:SetPoint("TOPLEFT", 18, -14)
    f.sub = K.Text(f, 11, C.muted)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
    f.il = K.Title(f, 20, C.amber, "RIGHT")
    f.il:SetPoint("TOPRIGHT", -44, -14)
    f.ilLbl = K.Text(f, 9, C.dim, "RIGHT")
    f.ilLbl:SetPoint("TOPRIGHT", f.il, "BOTTOMRIGHT", 0, -2)
    f.ilLbl:SetText(K.Upper(L["Gegenstandsstufe"]))
    local x = K.CloseButton(f, function() f:Hide() end)
    x:SetPoint("TOPRIGHT", -10, -10)
    f.rows = {}
    for i, slot in ipairs(SLOTS) do
        local col = (i <= 9) and 0 or 1
        local row = (i <= 9) and (i - 1) or (i - 10)
        local r = CreateFrame("Button", nil, f)
        r:SetSize(212, 34)
        r:SetPoint("TOPLEFT", 16 + col * 220, -70 - row * 37)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(30, 30)
        r.icon:SetPoint("LEFT", 0, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = K.Text(r, 11, C.text)
        r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 7, -2)
        r.name:SetPoint("RIGHT", -2, 0)
        r.name:SetWordWrap(false)
        r.meta = K.Text(r, 10, C.dim)
        r.meta:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 7, 2)
        r.slot = slot
        r:SetScript("OnEnter", function(self)
            if not self.link then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self)
            if self.link and IsModifiedClick and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self.link) end
        end)
        f.rows[i] = r
    end
    f.foot = K.Text(f, 10, C.dim)
    f.foot:SetPoint("BOTTOMLEFT", 18, 14)
    f.foot:SetPoint("RIGHT", -18, 0)
    f.foot:SetJustifyH("LEFT")
    ns.EscClose("OasisGearView")
    S.win = f
    return f
end
function S.ShowGear(full)
    local f = S.win or buildGear()
    f.who = full
    local e = gdb()[full]
    local a = ns.db.allies and ns.db.allies[full]
    local s = sdb()[full]
    local cls = (e and e.c) or (a and a.class) or (s and s.c)
    local cr, cg, cb = ns.classColor(cls)
    if not K.Gradient(f.head, "HORIZONTAL", { cr, cg, cb, 0.25 }, { cr, cg, cb, 0.02 }) then f.head:SetColorTexture(cr, cg, cb, 0.1) end
    f.title:SetText(ns.colorName(full, cls))
    local lvl = (e and e.l) or (a and a.lvl) or (s and s.l)
    local cn = cls and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls] or ""
    local g = (s and s.g) or (a and a.guild)
    f.sub:SetText((L["Level "] .. (lvl or "?") .. " " .. cn) .. ((g and g ~= "") and ("  ·  <" .. g .. ">") or ""))
    f.il:SetText(e and e.il and tostring(e.il) or "-")
    for _, r in ipairs(f.rows) do
        local link = e and e.i and e.i[r.slot]
        r.link = link
        if link then
            local name, _, q, _, _, _, _, _, _, icon = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(link)
            if not name and GetItemInfo then name, _, q, _, _, _, _, _, _, icon = GetItemInfo(link) end
            local qc = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            r.icon:SetTexture(icon or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(link)) or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.icon:SetDesaturated(false)
            r.name:SetText(name or link)
            if qc then r.name:SetTextColor(qc.r, qc.g, qc.b) else r.name:SetTextColor(C.text[1], C.text[2], C.text[3]) end
            local il = ilvlOf(link)
            r.meta:SetText(L[SLOT_NAME[r.slot]] .. (il and ("  ·  " .. il) or ""))
        else
            r.icon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
            r.icon:SetDesaturated(true)
            r.name:SetText("|cff555555" .. L["leer"] .. "|r")
            r.meta:SetText(L[SLOT_NAME[r.slot]])
        end
    end
    f.foot:SetText(e and ((L["Betrachtet %s"]):format(ns.ago(e.t)) .. "  ·  " .. L["Shift-Klick: Gegenstand in den Chat"])
        or L["Noch keine Ausruestung bekannt - Spieler in der Naehe anvisieren und betrachten (Oasis betrachtet Mitspieler in der Gruppe automatisch)."])
    f:Show()
    f:Raise()
end
function S.HasGear(full) return gdb()[full] ~= nil end
-- Ausruestung jetzt holen (Ziel) und anzeigen
function S.InspectAndShow(unit)
    local full = unit and fullOf(unit)
    if not full then return end
    if ns.Talents and ns.Talents.Inspect then ns.Talents.Inspect(unit, false) else pcall(NotifyInspect, unit) end
    S.ShowGear(full)
end
ns.slash.ausruestung = function(arg)
    arg = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" then
        if ns.safe(UnitExists("target")) and ns.safe(UnitIsPlayer("target")) then S.InspectAndShow("target") return end
        ns.print(L["Spieler anvisieren oder /oa ausruestung Name"])
        return
    end
    for k in pairs(gdb()) do if ns.short(k):lower() == arg:lower() then S.ShowGear(k) return end end
    S.ShowGear(ns.fullName(arg))
end
ns.slash.gear = ns.slash.ausruestung

------------------------------------------------------------------------
-- Anwerben: Kandidaten (eigene Begegnungen) + Vorschlaege der Gilde (Store "scout")
------------------------------------------------------------------------
function S.Suggest(name, note)
    local a = ns.db.allies and ns.db.allies[name] or {}
    local s = sdb()[name] or {}
    Store.Put(COLL, { id = "sc:" .. name, target = name, by = ns.me(), class = a.class or s.c, lvl = a.lvl or s.l,
        cnt = a.count, note = note and tostring(note):sub(1, 120) or nil, t = ns.now() })
    K.Toast(L["Vorgeschlagen"], (L["%s steht jetzt auf der Anwerbe-Liste der Gilde."]):format(ns.displayName(name)), C.mint)
end
function S.Suggested(name) local r = Store.Get(COLL, "sc:" .. name) return r and not r.del and r or nil end
function S.Candidates()
    local out, have = {}, {}
    local function guildOf(name)
        local s = sdb()[name]
        local a = ns.db.allies and ns.db.allies[name]
        if s and s.g ~= nil then return s.g end
        return a and a.guild
    end
    -- Vorschlaege aus der Gilde
    for _, r in ipairs(Store.List(COLL)) do
        if r.target and not isGuildie(r.target) then
            local g = guildOf(r.target)
            local up, down = 0, 0
            if ns.Social and ns.Social.GuildRep then up, down = ns.Social.GuildRep(r.target) end
            out[#out + 1] = { name = r.target, class = r.class, lvl = r.lvl, cnt = r.cnt or 0, by = r.by, note = r.note,
                t = r.t or r.u or 0, sug = true, guild = g, up = up, down = down, score = 100 + up * 5 - down * 10 }
            have[r.target] = true
        end
    end
    -- eigene Mitspieler ohne Gilde: aktiv (30 Tage), nicht schlecht bewertet
    for name, a in pairs(ns.db.allies or {}) do
        if not have[name] and not isGuildie(name) and not a.bad and not a.ninja and ns.now() - (a.last or 0) < 30 * 86400 then
            local g = guildOf(name)
            if g == "" then
                local up, down = 0, 0
                if ns.Social and ns.Social.GuildRep then up, down = ns.Social.GuildRep(name) end
                if down <= up then
                    out[#out + 1] = { name = name, class = a.class, lvl = a.lvl, cnt = a.count or 1, t = a.last or 0, guild = g,
                        fav = a.fav, up = up, down = down, score = (a.count or 1) * 3 + (a.fav and 15 or 0) + up * 5 + math.min(10, (a.lvl or 0) / 6) }
                end
            end
        end
    end
    table.sort(out, function(x, y) if x.score ~= y.score then return x.score > y.score end return (x.t or 0) > (y.t or 0) end)
    return out
end

-- Rechte beim Empfang: Vorschlag nur vom Vorschlagenden; loeschen auch Offiziere
local function installAuth()
    local A = ns.Admin
    if not (A and A.AUTH) then return end
    A.AUTH[COLL] = function(rec, actor, old)
        if A.InGuildList and not A.InGuildList(actor) then return false end
        local owner = (old and old.by) or rec.by
        if owner and A.SameName(owner, actor) then return true end
        local role = A.RoleOf and A.RoleOf(actor)
        return rec.del and (role == "lead" or role == "officer") or false
    end
end
installAuth()
ns.Listen("LOGIN", installAuth)
-- Gildenleitung: neuer Vorschlag -> Hinweis
ns.Listen("STORE", function(coll, rec, old)
    if coll ~= COLL then return end
    if rec and not old and not rec.del and not ns.isMe(rec.by) and ns.isOfficer and ns.isOfficer() and ns.db.settings.scoutHint ~= false then
        K.Toast(L["Anwerbe-Vorschlag"], (L["%s schlaegt %s vor"]):format(ns.displayName(rec.by or "?"), ns.displayName(rec.target or "?")), C.accent,
            function() S.view = "recruit" ns.ShowPage("scout") end)
    end
    ns.RefreshPage("scout")
end)

------------------------------------------------------------------------
-- Realm-Statistik (letzte 30 Tage)
------------------------------------------------------------------------
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
function S.Stats(days)
    local since = ns.now() - (days or 30) * 86400
    local byClass, byLvl, guilds, total, noGuild, max60 = {}, {}, {}, 0, 0, 0
    for _, b in ipairs({ 10, 20, 30, 40, 50, 59, 60 }) do byLvl[b] = 0 end
    local function bucket(l)
        if l >= 60 then return 60 elseif l >= 50 then return 59 end
        return math.floor(l / 10) * 10 + 10
    end
    for _, e in pairs(sdb()) do
        if (e.t or 0) >= since and e.c then
            total = total + 1
            byClass[e.c] = (byClass[e.c] or 0) + 1
            local l = tonumber(e.l) or 0
            if l > 0 then local b = bucket(l) byLvl[b] = (byLvl[b] or 0) + 1 end
            if l >= 60 then max60 = max60 + 1 end
            if e.g and e.g ~= "" then guilds[e.g] = (guilds[e.g] or 0) + 1 elseif e.g == "" then noGuild = noGuild + 1 end
        end
    end
    local gl = {}
    for g, n in pairs(guilds) do gl[#gl + 1] = { g = g, n = n } end
    table.sort(gl, function(a, b) return a.n > b.n end)
    return { total = total, byClass = byClass, byLvl = byLvl, guilds = gl, noGuild = noGuild, max60 = max60 }
end

------------------------------------------------------------------------
-- Seite "Anwerben & Realm"
------------------------------------------------------------------------
S.view = "recruit"
local function bars(parent, n)
    local t = {}
    for i = 1, n do
        local r = CreateFrame("Frame", nil, parent)
        r:SetHeight(22)
        r.lbl = K.Text(r, 11, C.text)
        r.lbl:SetPoint("LEFT", 0, 0)
        r.lbl:SetWidth(110)
        r.lbl:SetWordWrap(false)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetPoint("LEFT", 116, 0) r.bg:SetPoint("RIGHT", -54, 0) r.bg:SetHeight(8)
        r.bg:SetColorTexture(1, 1, 1, 0.04)
        r.fill = r:CreateTexture(nil, "ARTWORK")
        r.fill:SetPoint("LEFT", r.bg, "LEFT") r.fill:SetHeight(8)
        r.val = K.Text(r, 11, C.muted, "RIGHT")
        r.val:SetPoint("RIGHT", 0, 0)
        r.val:SetWidth(50)
        t[i] = r
    end
    return t
end
local function setBar(r, label, n, max, col, suffix)
    r.lbl:SetText(label)
    local w = (r.bg:GetWidth() or 200)
    if w < 10 then w = 200 end
    r.fill:SetWidth(math.max(1, w * (max > 0 and n / max or 0)))
    r.fill:SetColorTexture(col[1], col[2], col[3], 0.85)
    r.fill:SetShown(n > 0)
    r.val:SetText(n .. (suffix or ""))
    r:Show()
end

if ns.ICONS then ns.ICONS.scout = ns.ICONS.allies or ns.ICONS.social or ns.ICONS.groups end
ns.RegisterPage({
    key = "scout", title = "Anwerben & Realm", order = 2.86,
    sub = "Spieler ohne Gilde aus deinen Gruppen, Vorschlaege der Gilde und wer auf dem Realm unterwegs ist",
    build = function(p)
        p.seg = K.Segments(p, { { key = "recruit", text = L["Anwerben"] }, { key = "stats", text = L["Realm-Statistik"] } },
            function(k) S.view = k ns.RefreshPage("scout") end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        -- Anwerben
        p.rec = CreateFrame("Frame", nil, p)
        p.rec:SetPoint("TOPLEFT", 0, -34) p.rec:SetPoint("BOTTOMRIGHT")
        p.rec.info = K.Text(p.rec, 11, C.muted)
        p.rec.info:SetPoint("TOPLEFT", 0, 0) p.rec.info:SetPoint("RIGHT", 0, 0)
        p.rec.info:SetJustifyH("LEFT")
        p.rec.info:SetWordWrap(true)
        p.rec.info:SetText(L["Gut bewertete, aktive Spieler ohne Gilde aus deinen Gruppen (Spielerbuch) und Vorschlaege aus der Gilde. 'Vorschlagen' setzt jemanden auf die gemeinsame Liste fuer die Gildenleitung."])
        p.list = K.List(p.rec, 40, function(l)
            local r = K.Row(l)
            r.cls = r:CreateTexture(nil, "ARTWORK")
            r.cls:SetSize(22, 22)
            r.cls:SetPoint("LEFT", 8, 0)
            r.name = K.Text(r, 13, C.text)
            r.name:SetPoint("TOPLEFT", 40, -5)
            r.name:SetWidth(220)
            r.name:SetWordWrap(false)
            r.meta = K.Text(r, 10, C.muted)
            r.meta:SetPoint("BOTTOMLEFT", 40, 6)
            r.meta:SetWidth(380)
            r.meta:SetWordWrap(false)
            r.tag = K.Text(r, 10, C.amber)
            r.tag:SetPoint("LEFT", 270, 6)
            r.tag:SetWidth(200)
            r.tag:SetWordWrap(false)
            r.inv = K.Button(r, L["Gilde"], 56, 22, "primary")
            r.inv:SetPoint("RIGHT", -10, 0)
            r.wsp = K.Button(r, L["Fluestern"], 70, 22, "ghost")
            r.wsp:SetPoint("RIGHT", r.inv, "LEFT", -6, 0)
            r.sug = K.Button(r, L["Vorschlagen"], 92, 22, "ghost")
            r.sug:SetPoint("RIGHT", r.wsp, "LEFT", -6, 0)
            r.gear = K.Button(r, L["Ausruestung"], 88, 22, "ghost")
            r.gear:SetPoint("RIGHT", r.sug, "LEFT", -6, 0)
            r:RegisterForClicks("AnyUp")
            r:SetScript("OnClick", function(self, btn)
                local it = self.item
                if not it then return end
                if btn == "RightButton" then
                    local mine = it.sug and (ns.isMe(it.by) or (ns.isOfficer and ns.isOfficer()))
                    K.ShowMenu(self, {
                        { text = L["Anfluestern"], fn = function() ns.Whisper(it.name) end },
                        { text = L["In die Gruppe einladen"], fn = function() ns.InviteName(it.name) end },
                        { text = L["Ausruestung ansehen"], fn = function() S.ShowGear(it.name) end },
                        { text = L["Talente ansehen"], fn = function() if ns.Talents then ns.Talents.Show(it.name) end end },
                        { text = L["Vorschlag entfernen"], disabled = not mine, fn = function() Store.Delete(COLL, "sc:" .. it.name) end },
                    }, ns.colorName(it.name, it.class))
                end
            end)
            return r
        end, function(r, it)
            local tc = it.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[it.class]
            if tc then r.cls:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes") r.cls:SetTexCoord(unpack(tc)) r.cls:Show() else r.cls:Hide() end
            r.name:SetText(ns.colorName(it.name, it.class) .. "  |cff8a8a90" .. (it.lvl or "?") .. "|r")
            local m = {}
            m[#m + 1] = (L["%dx zusammen gespielt"]):format(it.cnt or 0)
            if (it.t or 0) > 0 then m[#m + 1] = ns.ago(it.t) end
            local g = gdb()[it.name]
            if g and g.il then m[#m + 1] = (L["Stufe %d"]):format(g.il) end
            if (it.up or 0) + (it.down or 0) > 0 then m[#m + 1] = ("|cff66db9e+%d|r / |cffff5a5a-%d|r"):format(it.up or 0, it.down or 0) end
            if it.guild == nil then m[#m + 1] = "|cff8a8a90" .. L["Gilde unbekannt"] .. "|r" end
            r.meta:SetText(table.concat(m, "  ·  "))
            r.tag:SetText(it.sug and ((L["vorgeschlagen von %s"]):format(ns.displayName(it.by or "?")) .. ((it.note and it.note ~= "") and (": " .. it.note) or ""))
                or (it.fav and L["dein Favorit"] or ""))
            local canGuild = CanGuildInvite and CanGuildInvite()
            r.inv:SetShown(canGuild and true or false)
            r.inv:SetScript("OnClick", function() if ns.Social and ns.Social.InviteGuild then ns.Social.InviteGuild(it.name) elseif C_GuildInfo and C_GuildInfo.Invite then pcall(C_GuildInfo.Invite, it.name) end end)
            r.wsp:ClearAllPoints()
            if canGuild then r.wsp:SetPoint("RIGHT", r.inv, "LEFT", -6, 0) else r.wsp:SetPoint("RIGHT", -10, 0) end
            r.wsp:SetScript("OnClick", function() ns.Whisper(it.name) end)
            r.sug:SetShown(not it.sug)
            r.sug:SetScript("OnClick", function() S.Suggest(it.name) end)
            r.gear:ClearAllPoints()
            r.gear:SetPoint("RIGHT", it.sug and r.wsp or r.sug, "LEFT", -6, 0)
            r.gear:SetShown(g ~= nil)
            r.gear:SetScript("OnClick", function() S.ShowGear(it.name) end)
        end)
        p.list:SetPoint("TOPLEFT", p.rec, "TOPLEFT", 0, -40)
        p.list:SetPoint("BOTTOMRIGHT")
        p.list.empty:SetText(L["Noch keine Kandidaten. Spiel mit Leuten ausserhalb der Gilde - wer ohne Gilde ist und gut bewertet wird, landet hier."])
        -- Statistik
        p.st = CreateFrame("Frame", nil, p)
        p.st:SetPoint("TOPLEFT", 0, -34) p.st:SetPoint("BOTTOMRIGHT")
        p.st.sum = K.Text(p.st, 12, C.muted)
        p.st.sum:SetPoint("TOPLEFT", 0, 0)
        p.st.sum:SetPoint("RIGHT", 0, 0)
        p.st.sum:SetJustifyH("LEFT")
        local function head(txt, x, y)
            local h = K.Text(p.st, 10, C.accent)
            h:SetPoint("TOPLEFT", x, y)
            h:SetText(K.Upper(txt))
            return h
        end
        head(L["Klassen"], 0, -34)
        head(L["Levelstufen"], 0, -284)
        p.st.gh = head(L["Haeufigste Gilden"], 440, -34)
        p.st.cls = bars(p.st, #CLASSES)
        for i, r in ipairs(p.st.cls) do r:SetPoint("TOPLEFT", 0, -52 - (i - 1) * 24) r:SetWidth(400) end
        p.st.lvl = bars(p.st, 7)
        for i, r in ipairs(p.st.lvl) do r:SetPoint("TOPLEFT", 0, -302 - (i - 1) * 24) r:SetWidth(400) end
        p.st.gl = bars(p.st, 10)
        for i, r in ipairs(p.st.gl) do r:SetPoint("TOPLEFT", 440, -52 - (i - 1) * 24) r:SetPoint("RIGHT", 0, 0) end
        p.st.note = K.Text(p.st, 10, C.dim)
        p.st.note:SetPoint("TOPLEFT", 440, -302)
        p.st.note:SetPoint("RIGHT", 0, 0)
        p.st.note:SetJustifyH("LEFT")
        p.st.note:SetWordWrap(true)
        p.st.note:SetText(L["Gezaehlt werden Spieler, die du in den letzten 30 Tagen anvisiert, mit der Maus beruehrt oder in der Gruppe hattest (ohne Gildenmitglieder). Jeder Spieler zaehlt einmal. Mehr Oasis-Nutzer unterwegs = genauere Zahlen fuer die eigene Sicht."])
    end,
    refresh = function(p)
        p.seg:Select(S.view)
        p.rec:SetShown(S.view == "recruit")
        p.st:SetShown(S.view == "stats")
        if S.view == "recruit" then
            p.list:SetData(S.Candidates())
            return
        end
        local st = S.Stats(30)
        p.st.sum:SetText((L["%d Spieler in 30 Tagen gesehen  ·  %d auf Level 60  ·  %d ohne Gilde"]):format(st.total, st.max60, st.noGuild))
        local maxC = 0
        for _, c in ipairs(CLASSES) do maxC = math.max(maxC, st.byClass[c] or 0) end
        for i, c in ipairs(CLASSES) do
            local n = st.byClass[c] or 0
            local cr, cg, cb = ns.classColor(c)
            local pct = st.total > 0 and math.floor(n * 100 / st.total + 0.5) or 0
            setBar(p.st.cls[i], ns.colorName((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[c]) or c, c), n, maxC, { cr, cg, cb }, "  |cff6a6a70" .. pct .. "%|r")
        end
        local LV = { { 10, "1-9" }, { 20, "10-19" }, { 30, "20-29" }, { 40, "30-39" }, { 50, "40-49" }, { 59, "50-59" }, { 60, "60" } }
        local maxL = 0
        for _, b in ipairs(LV) do maxL = math.max(maxL, st.byLvl[b[1]] or 0) end
        for i, b in ipairs(LV) do setBar(p.st.lvl[i], L["Level "] .. b[2], st.byLvl[b[1]] or 0, maxL, C.accent) end
        local maxG = st.guilds[1] and st.guilds[1].n or 0
        for i, r in ipairs(p.st.gl) do
            local g = st.guilds[i]
            if g then setBar(r, "<" .. g.g .. ">", g.n, maxG, C.blue or C.accent) else r:Hide() end
        end
        p.st.gh:SetShown(#st.guilds > 0)
    end,
})
ns.slash.anwerben = function() S.view = "recruit" ns.ShowPage("scout") end
ns.slash.realm = function() S.view = "stats" ns.ShowPage("scout") end
end)

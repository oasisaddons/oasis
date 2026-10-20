-- Oasis: Ruf-Planer
--  * liest den eigenen Ruf (C_Reputation bzw. Classic GetFactionInfo, alles per pcall)
--  * teilt je Charakter einen kompakten Stand mit der Gilde (nur bei Aenderung, hoechstens alle 5 Min)
--  * Seite: je Fraktion wer wie weit ist, "kurz vor Respektvoll/Ehrfuerchtig", "gemeinsam farmen" (online + Einladen),
--    Fortschritt diese Woche; Raid-/Classic-Fraktionen (Hydraxianer, Argentumdaemmerung, Holzschlund ...) hervorgehoben
-- Datensatz "repfac": { id = "rf-<char>", c = char, cls, wk = Woche, f = "id:stufe:wert:max:woche:name;..." }
-- Teilen ueber ns.PlannerSync (RaidTime.lua, steht in der toc davor).
local ADDON, ns = ...
ns.ModuleFile("Oasis_Reputation", function()   -- Modul Ruf-Planer (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local RP = {}
ns.RepPlanner = RP
local COLL = "repfac"
local KEEP = 120 * 86400
local MIN_GAP = 300

if ns.ICONS then ns.ICONS.repplan = ns.MEDIA .. "icons\\badges" end
do
    for _, g in ipairs(ns.NAV_GROUPS or {}) do
        if g.key == "play" then
            local has = false
            for _, k in ipairs(g.pages) do if k == "repplan" then has = true end end
            if not has then g.pages[#g.pages + 1] = "repplan" end
        end
    end
end

local function S() return ns.db.settings end
local function weekKey(ts) return date("%Y-%W", ts or ns.now()) end

-- wichtige Fraktionen (Classic/Forever-Raids): ID -> Name (Ersatz, falls der Client ihn nicht liefert) + Hinweis
local KEY_FACTIONS = {
    [749] = { "Hydraxian Waterlords", "Molten Core: Aqual Quintessence douses the runes" },
    [529] = { "Argent Dawn", "Scholomance, Stratholme, Naxxramas attunement" },
    [576] = { "Timbermaw Hold", "Recipes, passage to Winterspring" },
    [59] = { "Thorium Brotherhood", "Fire resistance recipes for Molten Core" },
    [609] = { "Cenarion Circle", "Ahn'Qiraj, nature resistance" },
    [270] = { "Zandalar Tribe", "Zul'Gurub rewards" },
    [910] = { "Brood of Nozdormu", "Temple of Ahn'Qiraj" },
    [990] = { "The Scale of the Sands", "Hyjal" },
    [809] = { "Shen'dralar", "Dire Maul, librams" },
    [909] = { "Darkmoon Faire", "Cards and prizes" },
}
RP.KEY_FACTIONS = KEY_FACTIONS
local STANDING = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local ST_COLOR = {
    { 0.8, 0.13, 0.13 }, { 1, 0, 0 }, { 0.93, 0.4, 0.13 }, { 1, 1, 0 }, { 0, 0.7, 0.1 }, { 0, 0.8, 0.4 }, { 0.2, 0.6, 1 }, { 0.75, 0.45, 1 },
}
function RP.StandingText(st)
    st = tonumber(st) or 4
    local g = _G["FACTION_STANDING_LABEL" .. st]
    if type(g) == "string" and g ~= "" then return g end
    return L[STANDING[st] or "Neutral"]
end
function RP.StandingColor(st) return ST_COLOR[tonumber(st) or 4] or ST_COLOR[4] end

------------------------------------------------------------------------
-- Ruf lesen (per pcall; fehlt die API -> nil)
------------------------------------------------------------------------
local function clean(s) return (tostring(s or ""):gsub("[:;]", " ")) end
function RP.ReadOwn()
    local out = {}
    if ns.inCombat() then return nil, "combat" end
    local CR = C_Reputation
    if CR and CR.GetNumFactions and CR.GetFactionDataByIndex then
        local okN, n = pcall(CR.GetNumFactions)
        n = okN and ns.safe(n) or 0
        if CR.ExpandAllFactionHeaders then pcall(CR.ExpandAllFactionHeaders) local ok2, n2 = pcall(CR.GetNumFactions) if ok2 and ns.safe(n2) then n = n2 end end
        for i = 1, n do
            local ok, f = pcall(CR.GetFactionDataByIndex, i)
            if ok and type(f) == "table" and ns.safe(f.name) and (not f.isHeader or f.isHeaderWithRep) then
                local lo, hi, v = ns.safe(f.currentReactionThreshold) or 0, ns.safe(f.nextReactionThreshold) or 0, ns.safe(f.currentStanding) or 0
                out[#out + 1] = { id = ns.safe(f.factionID) or 0, name = f.name, st = ns.safe(f.reaction) or 4,
                    cur = v - lo, max = math.max(0, hi - lo), total = v }
            end
        end
        if #out > 0 then return out, "C_Reputation" end
    end
    if GetNumFactions and GetFactionInfo then
        local okN, n = pcall(GetNumFactions)
        n = okN and ns.safe(n) or 0
        if ExpandAllFactionHeaders then pcall(ExpandAllFactionHeaders) local ok2, n2 = pcall(GetNumFactions) if ok2 and ns.safe(n2) then n = n2 end end
        for i = 1, n do
            local ok, name, _, standing, bMin, bMax, val, _, _, isHeader, _, hasRep, _, _, fid = pcall(GetFactionInfo, i)
            name, standing, bMin, bMax, val = ns.safe(name), ns.safe(standing), ns.safe(bMin), ns.safe(bMax), ns.safe(val)
            if ok and name and (not isHeader or hasRep) and standing and bMin and bMax and val then
                out[#out + 1] = { id = ns.safe(fid) or 0, name = name, st = standing, cur = val - bMin, max = math.max(0, bMax - bMin), total = val }
            end
        end
        return out, "GetFactionInfo"
    end
    return nil, "none"
end

-- Fraktionsschluessel: ID, sonst Name
local function fkey(e) return (e.id and e.id ~= 0) and ("i" .. e.id) or ("n" .. e.name) end
RP.FKey = fkey

-- eigener Stand + Wochen-Basis -> Kodierung
local function encodeOwn(list)
    local c = ns.char
    local wk = weekKey()
    c.repWeek = c.repWeek or {}
    local rw = c.repWeek
    if rw.wk ~= wk then rw.wk, rw.base = wk, {} end
    rw.base = rw.base or {}
    local parts = {}
    table.sort(list, function(a, b) return fkey(a) < fkey(b) end)
    for _, e in ipairs(list) do
        local k = fkey(e)
        if rw.base[k] == nil then rw.base[k] = e.total end
        local gain = math.max(0, (e.total or 0) - rw.base[k])
        parts[#parts + 1] = ("%d:%d:%d:%d:%d:%s"):format(e.id or 0, e.st or 4, e.cur or 0, e.max or 0, gain, clean(e.name))
    end
    return table.concat(parts, ";"), wk
end
function RP.Decode(s)
    local out = {}
    for part in (s or ""):gmatch("[^;]+") do
        local id, st, cur, mx, gain, name = part:match("^(%-?%d+):(%d+):(%-?%d+):(%d+):(%d+):(.*)$")
        if id then
            id = tonumber(id)
            out[#out + 1] = { id = id, st = tonumber(st), cur = tonumber(cur), max = tonumber(mx), gain = tonumber(gain), name = name }
        end
    end
    return out
end

------------------------------------------------------------------------
-- Teilen: nur bei Aenderung, hoechstens alle 5 Minuten
------------------------------------------------------------------------
local lastSent, lastHash, scheduled = 0, nil, false
function RP.Share(force)
    if not ns.me() or not ns.char then return end
    local list = RP.ReadOwn()
    if not list or #list == 0 then return end
    local f, wk = encodeOwn(list)
    local h = ns.hash(f)
    local _, cls = UnitClass("player")
    local rec = { id = "rf-" .. ns.me(), c = ns.me(), cls = ns.safe(cls) or "", wk = wk, f = f }
    if S().repShare == false then
        -- nur lokal fuehren
        Store.merge(COLL, { id = rec.id, c = rec.c, cls = rec.cls, wk = wk, f = f, u = ns.now(), by = ns.me(), demo = nil })
        ns.RefreshPage("repplan")
        return
    end
    if h == lastHash and not force then return end
    local wait = MIN_GAP - (GetTime() - lastSent)
    if wait > 0 and not force then
        if not scheduled then
            scheduled = true
            ns.After(wait + 1, function() scheduled = false RP.Share() end)
        end
        -- lokal schon mal aktuell
        local old = Store.Get(COLL, rec.id)
        Store.merge(COLL, { id = rec.id, c = rec.c, cls = rec.cls, wk = wk, f = f, u = old and old.u or ns.now(), by = ns.me() })
        ns.RefreshPage("repplan")
        return
    end
    lastSent, lastHash = GetTime(), h
    if ns.PlannerSync and ns.PlannerSync.Put then
        ns.PlannerSync.Put(COLL, rec)
    else
        Store.merge(COLL, rec)
    end
    ns.RefreshPage("repplan")
end
local debounce = false
local function onRepChange()
    if debounce then return end
    debounce = true
    ns.After(20, function() debounce = false pcall(RP.Share) end)
end
ns.On("UPDATE_FACTION", onRepChange)
ns.On("PLAYER_REGEN_ENABLED", function() if lastHash == nil and ns.loggedIn then onRepChange() end end)

------------------------------------------------------------------------
-- Auswertung
------------------------------------------------------------------------
local function isOnline(name)
    local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[name]
    if ns.isMe(name) then return true end
    return m and m.online and true or false
end
RP.IsOnline = isOnline
-- alle Fraktionen: { key, id, name, key = true/false, chars = { { name, cls, st, cur, max, gain, online } } }
function RP.Factions()
    local by, order = {}, {}
    local wk = weekKey()
    for _, r in ipairs(Store.List(COLL)) do
        local inGuild = not (ns.Radar and ns.Radar.roster and #ns.Radar.roster > 0) or ns.isMe(r.c) or (ns.Radar.byName[r.c] ~= nil)
        if r.c and inGuild then
            for _, e in ipairs(RP.Decode(r.f)) do
                local k = fkey(e)
                local fa = by[k]
                if not fa then
                    local kf = KEY_FACTIONS[e.id]
                    fa = { key = k, id = e.id, name = (e.name ~= "" and e.name) or (kf and L[kf[1]]) or "?", important = kf ~= nil,
                        note = kf and L[kf[2]] or nil, chars = {} }
                    by[k] = fa
                    order[#order + 1] = fa
                end
                fa.chars[#fa.chars + 1] = { name = r.c, cls = r.cls, st = e.st, cur = e.cur, max = e.max,
                    gain = (r.wk == wk) and e.gain or 0, online = isOnline(r.c), demo = r.demo }
            end
        end
    end
    local function prog(c) return c.st + ((c.max or 0) > 0 and c.cur / c.max or 1) end
    for _, fa in ipairs(order) do
        table.sort(fa.chars, function(a, b) return prog(a) > prog(b) end)
        fa.weekGain = 0
        for _, c in ipairs(fa.chars) do fa.weekGain = fa.weekGain + (c.gain or 0) end
    end
    table.sort(order, function(a, b)
        if a.important ~= b.important then return a.important end
        if #a.chars ~= #b.chars then return #a.chars > #b.chars end
        return a.name < b.name
    end)
    return order
end
-- "kurz davor": Wohlwollend -> Respektvoll bzw. Respektvoll -> Ehrfuerchtig, ab 75 %
function RP.NearList(minP)
    minP = minP or 0.75
    local out = {}
    for _, fa in ipairs(RP.Factions()) do
        for _, c in ipairs(fa.chars) do
            if (c.st == 6 or c.st == 7) and (c.max or 0) > 0 and c.cur / c.max >= minP then
                out[#out + 1] = { fa = fa, c = c, p = c.cur / c.max, target = c.st + 1 }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.target ~= b.target then return a.target > b.target end
        return a.p > b.p
    end)
    return out
end
-- gemeinsam farmen: Mitglieder, die eine Fraktion mit mir teilen, bei der ich noch nicht Ehrfuerchtig bin
function RP.FarmList()
    local out = {}
    for _, fa in ipairs(RP.Factions()) do
        local mine
        for _, c in ipairs(fa.chars) do if ns.isMe(c.name) then mine = c end end
        if mine and mine.st < 8 then
            for _, c in ipairs(fa.chars) do
                if not ns.isMe(c.name) and c.st < 8 then
                    out[#out + 1] = { fa = fa, c = c, mine = mine }
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.c.online ~= b.c.online then return a.c.online end
        if a.fa.important ~= b.fa.important then return a.fa.important end
        return a.fa.name < b.fa.name
    end)
    return out
end

------------------------------------------------------------------------
-- Demo-Daten (nur lokal)
------------------------------------------------------------------------
local DEMO = {
    { "Grukthar", "WARRIOR", { [749] = { 6, 9800, 12000 }, [529] = { 5, 3100, 6000 }, [59] = { 5, 5200, 6000 }, [576] = { 4, 1200, 3000 } }, { [749] = 1800 } },
    { "Zul'mira", "PRIEST", { [749] = { 7, 18200, 21000 }, [529] = { 6, 2500, 12000 }, [609] = { 5, 400, 6000 } }, { [749] = 2400, [529] = 900 } },
    { "Tavira", "MAGE", { [749] = { 5, 5600, 6000 }, [576] = { 6, 10100, 12000 }, [909] = { 5, 2000, 6000 } }, { [576] = 1500 } },
    { "Hoknar", "SHAMAN", { [529] = { 7, 16800, 21000 }, [59] = { 4, 2400, 3000 } }, {} },
    { "Drogbar", "WARRIOR", { [749] = { 6, 3000, 12000 }, [59] = { 6, 10500, 12000 }, [270] = { 5, 1000, 6000 } }, { [59] = 600 } },
    { "Nakira", "PRIEST", { [529] = { 8, 999, 1000 }, [609] = { 6, 9600, 12000 }, [576] = { 7, 19000, 21000 } }, { [576] = 3000 } },
    { "Vex'ra", "ROGUE", { [749] = { 4, 800, 3000 }, [349] = { 6, 4000, 12000 } }, {} },
    { "Yenzi", "MAGE", { [749] = { 7, 9000, 21000 }, [910] = { 4, 500, 3000 } }, { [749] = 3500 } },
}
function RP.SeedDemo()
    local wk = weekKey()
    for i, d in ipairs(DEMO) do
        local parts = {}
        for id, v in pairs(d[3]) do
            local kf = KEY_FACTIONS[id]
            parts[#parts + 1] = ("%d:%d:%d:%d:%d:%s"):format(id, v[1], v[2], v[3], d[4][id] or 0, kf and L[kf[1]] or (id == 349 and L["Ravenholdt"] or "?"))
        end
        Store.merge(COLL, { id = "demo-rf-" .. i, demo = true, u = ns.now(), by = ns.fullName(d[1]), c = ns.fullName(d[1]), cls = d[2], wk = wk, f = table.concat(parts, ";") })
    end
    ns.RefreshPage("repplan")
end
function RP.RemoveDemo()
    local c = Store.coll(COLL)
    for id, r in pairs(c) do if r.demo then c[id] = nil end end
    ns.RefreshPage("repplan")
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local view, selKey = "factions", nil
local STAR = "|TInterface\\COMMON\\ReputationStar:12:12:0:0:32:32:0:16:0:16|t "
local function stText(st)
    local c = RP.StandingColor(st)
    return ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, RP.StandingText(st))
end
local animNext
local function charRow(l)
    local r = K.Row(l)
    r.av = r:CreateTexture(nil, "ARTWORK")
    r.av:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    r.av:SetSize(22, 22)
    r.av:SetPoint("LEFT", 10, 0)
    r.onl = r:CreateTexture(nil, "OVERLAY")
    r.onl:SetTexture(ns.MEDIA .. "dot")
    r.onl:SetSize(7, 7)
    r.onl:SetPoint("BOTTOMRIGHT", r.av, "BOTTOMRIGHT", 2, -2)
    r:Col("name", 40, 150, 13)
    r:Col("st", 195, 100, 11)
    r.bar = K.Bar(r, 130, 6)
    r.bar:SetPoint("LEFT", 300, 0)
    r:Col("val", 440, 90, 11, C.muted)
    r:Col("gain", 532, 80, 11, C.mint)
    r:Col("extra", 614, 110, 11, C.muted)
    r.inv = K.Button(r, L["Invite"], 76, 20, "ghost", function(self)
        local it = self:GetParent().item
        local c = it and (it.c or it)
        if not c then return end
        if c.demo then ns.print(L["(Demo) Invite sent to "] .. ns.displayName(c.name)) return end
        ns.InviteName(c.name)
    end)
    r.inv:SetPoint("RIGHT", -6, 0)
    r.inv.label:SetFont(K.FONT, 11, "")
    r:SetScript("OnMouseUp", function(self, btn)
        local it = self.item
        local c = it and (it.c or it)
        if btn == "RightButton" and c and not ns.isMe(c.name) then ns.Whisper(c.name) end
    end)
    return r
end
local function fillChar(r, c, extra)
    local tc = c.cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.cls]
    if tc then r.av:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) r.av:SetVertexColor(1, 1, 1, c.online and 1 or 0.55)
    else r.av:SetTexCoord(0, 0.01, 0, 0.01) r.av:SetVertexColor(1, 1, 1, 0) end
    if c.online then r.onl:SetVertexColor(0.4, 0.86, 0.62, 1) else r.onl:SetVertexColor(0.3, 0.3, 0.3, 1) end
    r.cols.name:SetText(ns.colorName(c.name, c.cls))
    r.cols.st:SetText(stText(c.st))
    -- 0.6.451: passt Wert und Maximum nicht zusammen (z. B. "1050 / 30"), Stand aus den Klassik-Schwellen der Stufe rechnen
    if (c.max or 0) <= 0 or (c.cur or 0) > (c.max or 0) then
        local TH = { [1] = { -42000, -6000 }, [2] = { -6000, -3000 }, [3] = { -3000, 0 }, [4] = { 0, 3000 },
            [5] = { 3000, 9000 }, [6] = { 9000, 21000 }, [7] = { 21000, 42000 }, [8] = { 42000, 42999 } }
        local th = TH[tonumber(c.st) or 0]
        local tot = tonumber(c.total) or ((tonumber(c.cur) or 0) + (th and th[1] or 0))
        if th and tot >= th[1] and tot <= th[2] then c.cur, c.max = tot - th[1], th[2] - th[1]
        elseif th then c.cur, c.max = math.min(c.cur or 0, th[2] - th[1]), th[2] - th[1] end
    end
    local p = (c.max or 0) > 0 and math.min(1, c.cur / c.max) or 1
    local sc = RP.StandingColor(c.st)
    r.bar.fill:SetColorTexture(sc[1], sc[2], sc[3], 0.9)
    if animNext and not (ns.db and ns.db.settings.noAnim) then
        -- Ansicht gewechselt: Zeile blendet ein, Balken waechst
        local d = math.min(r.index or 1, 14) * 0.03
        r.bar:Set(0)
        r:SetAlpha(0)
        K.Tween(r, 0.25, function(q) r:SetAlpha(q) end, function() r:SetAlpha(1) end, d)
        K.Tween(r.bar, 0.5, function(q) r.bar:Set(p * (1 - (1 - q) ^ 3)) end, function() r.bar:Set(p) end, d)
    else
        r:SetAlpha(1)
        r.bar:Set(p)
    end
    r.cols.val:SetText((c.max or 0) > 0 and (c.cur .. " / " .. c.max) or "")
    r.cols.gain:SetText((c.gain or 0) > 0 and ((L["+%d week"]):format(c.gain)) or "")
    r.cols.extra:SetText(extra or "")
    r.inv:SetShown(c.online and not ns.isMe(c.name))
end

ns.RegisterPage({
    key = "repplan", title = "Reputation Planner", order = 4.2,
    sub = "Who stands where with which faction? Close to the goal, farm together, progress this week",
    build = function(p)
        p.seg = K.Segments(p, { { key = "factions", text = L["Factions"] }, { key = "near", text = L["Almost there"] }, { key = "farm", text = L["Farm together"] } }, function(k)
            view = k animNext = true ns.RefreshPage("repplan")
        end, 120)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.hint = K.Text(p, 11, C.muted)
        p.hint:SetPoint("LEFT", p.seg, "RIGHT", 14, 0)
        p.hint:SetPoint("RIGHT", p, "RIGHT", -10, 0)
        ------------------------------------------------------------ Fraktionen: links Liste, rechts Detail
        local fv = CreateFrame("Frame", nil, p)
        fv:SetPoint("TOPLEFT", 0, -34) fv:SetPoint("BOTTOMRIGHT")
        p.fv = fv
        fv.list = K.List(fv, 42, function(l)
            local r = K.Row(l)
            if r.stripe then r.stripe:SetAlpha(0) end
            r.selBg = r:CreateTexture(nil, "BACKGROUND", nil, 1)
            r.selBg:SetPoint("TOPLEFT", 0, -1)
            r.selBg:SetPoint("BOTTOMRIGHT", 0, 1)
            r.selBg:SetColorTexture(1, 1, 1, 0.07)
            r.selBg:Hide()
            r:Col("name", 12, 170, 13)
            r.cols.name:ClearAllPoints() r.cols.name:SetPoint("TOPLEFT", 12, -7)
            r.cols.name:SetWordWrap(false)
            r.sub = K.Text(r, 10, C.dim)
            r.sub:SetPoint("BOTTOMLEFT", 12, 8)
            r.sub:SetWidth(150)
            r.gain = K.Title(r, 12, C.mint, "RIGHT")
            r.gain:SetPoint("TOPRIGHT", -10, -8)
            r.gainL = K.Text(r, 9, C.dim, "RIGHT")
            r.gainL:SetPoint("BOTTOMRIGHT", -10, 9)
            r.gainL:SetText(L["this week"])
            r.cols.name:SetPoint("RIGHT", r.gain, "LEFT", -6, 0)
            r:SetScript("OnClick", function(self) selKey = self.item and self.item.key animNext = true ns.RefreshPage("repplan") end)
            return r
        end, function(r, fa)
            local on = selKey == fa.key
            r.cols.name:SetText((fa.important and STAR or "") .. fa.name)
            r.cols.name:SetTextColor(on and 1 or C.text[1], on and 1 or C.text[2], on and 1 or C.text[3])
            r.sub:SetText((L["%d characters"]):format(#fa.chars))
            r.gain:SetText(fa.weekGain > 0 and ("+" .. fa.weekGain) or "")
            r.gainL:SetShown(fa.weekGain > 0)
            r.sel:SetShown(on)
            r.selBg:SetShown(on)
        end)
        fv.list:SetPoint("TOPLEFT", 0, 0)
        fv.list:SetPoint("BOTTOMLEFT", 0, 0)
        fv.list:SetWidth(250)
        fv.list.empty:SetText(L["No reputation data yet. It arrives automatically once members with Oasis are online."])
        fv.card = K.Panel(fv, C.panel)
        fv.card:SetPoint("TOPLEFT", 262, 0)
        fv.card:SetPoint("BOTTOMRIGHT")
        fv.head = K.GameHead(fv.card, "", C.accent)
        fv.head:SetPoint("TOPLEFT", 12, -12)
        fv.head:SetPoint("RIGHT", fv.card, "RIGHT", -12, 0)
        fv.note = K.Text(fv.card, 11, C.amber)
        fv.note:SetPoint("TOPLEFT", 12, -34)
        fv.note:SetPoint("RIGHT", fv.card, "RIGHT", -12, 0)
        fv.chars = K.List(fv.card, 32, charRow, function(r, c) fillChar(r, c) end)
        fv.chars:SetPoint("TOPLEFT", 4, -56)
        fv.chars:SetPoint("BOTTOMRIGHT", -4, 4)
        ------------------------------------------------------------ Kurz davor
        local nv = CreateFrame("Frame", nil, p)
        nv:SetPoint("TOPLEFT", 0, -34) nv:SetPoint("BOTTOMRIGHT")
        p.nv = nv
        nv.list = K.List(nv, 32, charRow, function(r, e)
            fillChar(r, e.c, (e.fa.important and STAR or "") .. e.fa.name)
            r.cols.extra:SetWidth(200)
            r.cols.st:SetText(stText(e.c.st) .. " |cff888888>|r " .. stText(e.target))
        end)
        nv.list:SetPoint("TOPLEFT") nv.list:SetPoint("BOTTOMRIGHT")
        nv.list.empty:SetText(L["Nobody is close to Revered or Exalted (from 75 %)."])
        ------------------------------------------------------------ Gemeinsam farmen
        local gv = CreateFrame("Frame", nil, p)
        gv:SetPoint("TOPLEFT", 0, -34) gv:SetPoint("BOTTOMRIGHT")
        p.gv = gv
        gv.list = K.List(gv, 32, charRow, function(r, e)
            fillChar(r, e.c, (e.fa.important and STAR or "") .. e.fa.name)
            r.cols.extra:SetWidth(200)
        end)
        gv.list:SetPoint("TOPLEFT") gv.list:SetPoint("BOTTOMRIGHT")
        gv.list.empty:SetText(L["No members with the same faction found. Oasis knows your reputation only after the first read (out of combat)."])
        p:HookScript("OnShow", function() animNext = true end)
        p:HookScript("OnShow", function() ns.After(0.2, function() pcall(RP.Share) end) end)
    end,
    refresh = function(p)
        p.seg:Select(view)
        p.fv:SetShown(view == "factions")
        p.nv:SetShown(view == "near")
        p.gv:SetShown(view == "farm")
        local facs = RP.Factions()
        local near = RP.NearList()
        local farm = RP.FarmList()
        local onlineFarm, weekSum = 0, 0
        for _, e in ipairs(farm) do if e.c.online then onlineFarm = onlineFarm + 1 end end
        for _, fa in ipairs(facs) do weekSum = weekSum + fa.weekGain end
        -- Zaehler an den Reitern (frueher eigene Kacheln): Kurz davor / Gemeinsam farmen (davon online)
        for _, b in ipairs(p.seg.buttons or {}) do
            local base = (b.key == "factions" and L["Factions"]) or (b.key == "near" and L["Almost there"]) or L["Farm together"]
            local n = (b.key == "factions" and #facs) or (b.key == "near" and #near) or onlineFarm
            if b.label then b.label:SetText(base .. ((n or 0) > 0 and ("  |cff888888" .. n .. "|r") or "")) end
        end
        local apiOk = (C_Reputation and C_Reputation.GetFactionDataByIndex) or GetFactionInfo
        p.hint:SetText(apiOk and ((weekSum > 0 and ("|cff66db9e" .. (L["Guild this week: +%d rep"]):format(weekSum) .. "|r  ·  ") or "") .. L["Right-click: whisper  ·  star = important for raids"]) or ("|cffff8a3d" .. L["This client provides no reputation data - you only see the standings of others."] .. "|r"))
        if view == "factions" then
            p.fv.list:SetData(facs)
            local sel
            for _, fa in ipairs(facs) do if fa.key == selKey then sel = fa end end
            if not sel then sel = facs[1] selKey = sel and sel.key end
            p.fv.card:SetShown(sel ~= nil)
            if sel then
                p.fv.head.text:SetText(K.Upper and K.Upper(sel.name) or sel.name)
                p.fv.head:SetCount(#sel.chars)
                p.fv.note:SetText(sel.note and (STAR .. sel.note) or "")
                p.fv.chars:SetData(sel.chars)
            end
        elseif view == "near" then
            p.nv.list:SetData(near)
        else
            p.gv.list:SetData(farm)
        end
        animNext = nil
    end,
})

------------------------------------------------------------------------
-- Einstellungen
------------------------------------------------------------------------
-- Settings.lua laedt erst nach diesem Modul -> Anmeldung nachholen, sobald alles geladen ist
local function addSettings(build)
    if ns.AddPageSettings then ns.AddPageSettings("repplan", build)
    else ns.Listen("DB_READY", function() if ns.AddPageSettings then ns.AddPageSettings("repplan", build) end end) end
end
addSettings(function(det, y)
    det.t = det.t or {}
    if S().repShare == nil then S().repShare = true end
    local t = K.Toggle(det, L["Share reputation with the guild"], function() return S().repShare ~= false end, function(v) S().repShare = v end,
        L["Shares your standings (only on change, at most every 5 minutes) so others can farm together with you"])
    t:SetPoint("TOPLEFT", 14, y)
    det.t[#det.t + 1] = t
    return y - 54
end)

------------------------------------------------------------------------
-- /oa probe ruf
------------------------------------------------------------------------
local function probeRep()
    ns.print(("Ruf-API: C_Reputation=%s GetNumFactions(neu)=%s GetFactionDataByIndex=%s | alt: GetNumFactions=%s GetFactionInfo=%s FACTION_STANDING_LABEL7=%s"):format(
        tostring(C_Reputation ~= nil), tostring(C_Reputation and C_Reputation.GetNumFactions ~= nil), tostring(C_Reputation and C_Reputation.GetFactionDataByIndex ~= nil),
        tostring(GetNumFactions ~= nil), tostring(GetFactionInfo ~= nil), tostring(_G.FACTION_STANDING_LABEL7)))
    local list, src = RP.ReadOwn()
    if not list then ns.print("  nichts gelesen (" .. tostring(src) .. ")") return end
    ns.print(("  Quelle %s: %d Fraktionen"):format(src, #list))
    for i, e in ipairs(list) do
        if i > 12 then ns.print("  ...") break end
        ns.print(("  [%s] %s  Stufe %s  %s/%s  gesamt %s"):format(tostring(e.id), tostring(e.name), tostring(e.st), tostring(e.cur), tostring(e.max), tostring(e.total)))
    end
    ns.print(("  geteilte Datensaetze: %d, Sync: %s"):format(#Store.List(COLL), tostring(ns.PlannerSync ~= nil)))
end
RP.Probe = probeRep
do
    local prev = ns.slash.probe
    ns.slash.probe = function(arg)
        local what = ((arg or ""):match("^(%S+)") or ""):lower()
        if what == "ruf" or what == "rep" then probeRep() return end
        if prev then return prev(arg) end
        ns.print(L["Probe: /oa probe raidzeit | /oa probe ruf"])
    end
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
if ns.PlannerSync and ns.PlannerSync.Register then
    ns.PlannerSync.Register(COLL, KEEP, function() ns.RefreshPage("repplan") end)
end
ns.Listen("LOGIN", function()
    if ns.PlannerSync then
        ns.PlannerSync.Prune(COLL)
        ns.After(32, function() ns.PlannerSync.Request(COLL) end)
    end
    ns.After(40, function() pcall(RP.Share) end)
    local D = ns.Demo
    if D and not D.rpHooked then
        D.rpHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) RP.SeedDemo() end
        D.Remove = function(...) remove(...) RP.RemoveDemo() end
        if D.IsActive() then ns.After(3, RP.SeedDemo) end
    end
end)
end)

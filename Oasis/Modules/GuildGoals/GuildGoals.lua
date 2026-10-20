-- Oasis: Gildenziele - gemeinsame Vorhaben (z. B. Thunderfury: Bindungen, 100 Arkanitbarren)
-- Store "ggoals"   : ein Ziel je Datensatz (flach): title, desc, icon (itemID), s1..s6 Schritte, k1..k6 erledigt,
--                    m1..m6 "itemID:Menge" Material, fin = abgeschlossen. Anlegen: jedes Mitglied; aendern/loeschen:
--                    Ersteller oder Offiziere.
-- Store "ggcontrib": Beitrag je Mitglied und Material (id = ziel|nr|name, n = Menge) - Summe = Stand.
-- Beide Sammlungen sind geteilt und werden abgeglichen (RETENTION in Comm.lua).
local ADDON, ns = ...
ns.ModuleFile("Oasis_Gildenziele", function()   -- Modul Gildenziele (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local GG = {}
ns.GuildGoals = GG
local MAXS, MAXM = 6, 6
local COLL, CONTRIB = "ggoals", "ggcontrib"

------------------------------------------------------------------------
-- Daten
------------------------------------------------------------------------
function GG.List()
    local out = Store.List(COLL)
    table.sort(out, function(a, b)
        if (a.fin and 1 or 0) ~= (b.fin and 1 or 0) then return not a.fin end
        return (a.created or a.u or 0) > (b.created or b.u or 0)
    end)
    return out
end
function GG.Mats(g)
    local out = {}
    for i = 1, MAXM do
        local id, need = tostring(g["m" .. i] or ""):match("^(%d+):(%d+)$")
        if id then out[#out + 1] = { i = i, id = tonumber(id), need = tonumber(need) } end
    end
    return out
end
function GG.Steps(g)
    local out = {}
    for i = 1, MAXS do
        local t = g["s" .. i]
        if t and t ~= "" then out[#out + 1] = { i = i, text = t, done = g["k" .. i] == 1 } end
    end
    return out
end
-- Beitraege zu einem Material: Summe, meiner, Liste (Name, Menge)
function GG.Contrib(g, i)
    local sum, mine, list = 0, 0, {}
    local prefix = g.id .. "|" .. i .. "|"
    for id, r in pairs(Store.coll(CONTRIB)) do
        if not r.del and id:sub(1, #prefix) == prefix then
            local n = math.max(0, tonumber(r.n) or 0)
            if n > 0 then
                sum = sum + n
                list[#list + 1] = { who = r.who, n = n }
                if ns.isMe(r.who) then mine = n end
            end
        end
    end
    table.sort(list, function(a, b) return a.n > b.n end)
    return sum, mine, list
end
function GG.Progress(g)
    local parts, done = 0, 0
    for _, s in ipairs(GG.Steps(g)) do parts = parts + 1 if s.done then done = done + 1 end end
    for _, m in ipairs(GG.Mats(g)) do
        parts = parts + 1
        local sum = GG.Contrib(g, m.i)
        done = done + math.min(1, sum / math.max(1, m.need))
    end
    if g.fin then return 1 end
    return parts > 0 and done / parts or 0
end
function GG.CanEdit(g)
    return not g or ns.isMe(g.by) or ns.isOfficer()
end
local function copyOf(g)
    local c = {}
    for k, v in pairs(g) do c[k] = v end
    return c
end
function GG.ToggleStep(g, i)
    if not GG.CanEdit(g) then return end
    local c = copyOf(g)
    c["k" .. i] = (c["k" .. i] == 1) and nil or 1
    Store.Put(COLL, c)
end
function GG.SetContrib(g, i, n)
    n = math.max(0, math.min(99999, math.floor(tonumber(n) or 0)))
    local me = ns.me()
    Store.Put(CONTRIB, { id = g.id .. "|" .. i .. "|" .. me, g = g.id, i = i, n = n, who = me })
end
function GG.SetFinished(g, fin)
    if not GG.CanEdit(g) then return end
    local c = copyOf(g)
    c.fin = fin and 1 or nil
    Store.Put(COLL, c)
    if fin then
        K.Toast(L["Gildenziel erreicht!"], tostring(g.title or "?"), C.mint)
        if ns.Chronicle and ns.Chronicle.Add then pcall(ns.Chronicle.Add, "goal", (L["Gildenziel erreicht: %s"]):format(tostring(g.title or "?"))) end
    end
end

-- Rechte beim Empfang (manipulierte Clients): Ziele nur Ersteller/Offiziere aendern; Beitraege nur der eigene
local function installAuth()
    local A = ns.Admin
    if not (A and A.AUTH) then return end
    local function officer(actor)
        local role = A.RoleOf and A.RoleOf(actor)
        return role == "lead" or role == "officer"
    end
    A.AUTH[COLL] = function(rec, actor, old)
        if A.InGuildList and not A.InGuildList(actor) then return false end
        local owner = (old and old.by) or rec.by
        if owner and A.SameName(owner, actor) then return true end
        return officer(actor)
    end
    A.AUTH[CONTRIB] = function(rec, actor)
        return rec.who ~= nil and A.SameName(rec.who, actor) and tostring(rec.id or ""):sub(-#tostring(rec.who)) == tostring(rec.who)
    end
end
installAuth()
ns.Listen("LOGIN", installAuth)

------------------------------------------------------------------------
-- Hinweise
------------------------------------------------------------------------
ns.Listen("STORE", function(coll, rec, old)
    if coll ~= COLL and coll ~= CONTRIB then return end
    if coll == COLL and rec and not old and not rec.del and not ns.isMe(rec.by) and ns.db.settings.ggHint ~= false then
        if ns.Sound and ns.Sound.Next then ns.Sound.Next("notice") end
        K.Toast(L["Neues Gildenziel"], ns.displayName(rec.by) .. ": " .. tostring(rec.title or "?"), C.accent, function() ns.ShowPage("goals") end)
    end
    if coll == COLL and rec and old and rec.fin == 1 and not old.fin and not ns.isMe(rec.mb) then
        K.Toast(L["Gildenziel erreicht!"], tostring(rec.title or "?"), C.mint, function() ns.ShowPage("goals") end)
    end
    ns.RefreshPage("goals")
end)

------------------------------------------------------------------------
-- Seite (0.5.597 neu: Glas-Design, Kennzahlen, Meilenstein-Pfad, Material-Karten, Helfer-Rangliste, Konfetti)
------------------------------------------------------------------------
local function iconOf(id)
    if not id or id == 0 then return "Interface\\Icons\\INV_Misc_QuestionMark" end
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function nameOf(id)
    if not id then return "?" end
    local n = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
    if not n and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return n or ("#" .. id)
end
local function pct(p) return math.floor(p * 100 + 0.5) .. "%" end
-- Emoji-Codes als Bilder (wie im Chat; gesperrte nur, wenn der Ersteller den Rang hat)
local function emo(text, who)
    if ns.Emoji and ns.Emoji.Render and type(text) == "string" then
        local ok, r = pcall(ns.Emoji.Render, text, who)
        if ok and type(r) == "string" then return r end
    end
    return text
end
local function animOn() return not (ns.db and ns.db.settings.noAnim) end
local function glass(f, fill, line, r)
    local G = ns.Insta and ns.Insta.Glass
    if G and pcall(G, f, fill or { 1, 1, 1, 0.035 }, line or { 1, 1, 1, 0.09 }, r or 12) then return true end
    if not f.oasisFlat then f.oasisFlat = K.Fill(f, { 1, 1, 1, 0.03 }) K.Border(f, C.line) end
    return false
end
-- Fortschrittsbalken mit Verlauf (rund), Set(p, animiert)
local function gradBar(parent, h)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(h)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 1, 1, 0.06)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT") b.fill:SetPoint("BOTTOMLEFT")
    b.fill:SetWidth(1)
    if K.RoundMask then K.RoundMask(b.bg, b, math.min(8, h)) K.RoundMask(b.fill, b, math.min(8, h)) end
    b.p = 0
    function b:Color(c1, c2)
        if not K.Gradient(self.fill, "HORIZONTAL", { c1[1], c1[2], c1[3], 0.75 }, { c2[1], c2[2], c2[3], 1 }) then
            self.fill:SetColorTexture(c2[1], c2[2], c2[3], 1)
        end
    end
    function b:Set(p, anim)
        p = math.max(0, math.min(1, p or 0))
        local w = math.max(1, (self:GetWidth() > 2 and self:GetWidth() or 200) * p)
        local from = self.lastW or 1
        self.lastW, self.p = w, p
        self.fill:SetShown(p > 0)
        if anim and animOn() and math.abs(from - w) > 1 then
            K.Tween(self.fill, 0.6, function(q) self.fill:SetWidth(math.max(1, from + (w - from) * q)) end, function() self.fill:SetWidth(w) end)
        else
            self.fill:SetWidth(w)
        end
    end
    b:Color(C.accent2 or C.accent, C.accent)
    return b
end
-- Beitraege aller Ziele zusammen: wer hat am meisten beigetragen?
local function helpers(onlyGoal)
    local sum = {}
    for id, r in pairs(Store.coll(CONTRIB)) do
        if not r.del and r.who and (not onlyGoal or id:sub(1, #onlyGoal.id + 1) == onlyGoal.id .. "|") then
            local n = math.max(0, tonumber(r.n) or 0)
            if n > 0 then sum[r.who] = (sum[r.who] or 0) + n end
        end
    end
    local out = {}
    for who, n in pairs(sum) do out[#out + 1] = { who = who, n = n } end
    table.sort(out, function(a, b) if a.n ~= b.n then return a.n > b.n end return tostring(a.who) < tostring(b.who) end)
    return out
end

local editing   -- nil | "new" | Ziel-ID
local LISTW = 288

-- Formular (neu / bearbeiten) --------------------------------------------
local function buildForm(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetPoint("TOPLEFT", LISTW + 12, -42)
    f:SetPoint("BOTTOMRIGHT")
    glass(f, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.09 }, 14)
    f:Hide()
    p.form = f
    f.head = K.Title(f, 16, C.text)
    f.head:SetPoint("TOPLEFT", 18, -16)
    local y = -46
    local ROW = 22   -- 0.5.598: enger, damit Meilensteine + Material ohne Ueberlappung passen (Knoepfe stehen oben)
    local function label(text, x, yy) local t = K.Text(f, 11, C.muted) t:SetPoint("TOPLEFT", x, yy) t:SetText(text) return t end
    label(L["Titel"], 18, y - 5)
    f.title = K.Input(f, 300, L["z. B. Thunderfury fuer unseren Tank"])
    f.title:SetPoint("TOPLEFT", 112, y)
    f.title:SetPoint("RIGHT", -18, 0)
    f.title:SetMaxLetters(60)
    f.title:SetHeight(20)
    y = y - 27
    label(L["Beschreibung"], 18, y - 5)
    f.desc = K.Input(f, 300, L["optional"])
    f.desc:SetPoint("TOPLEFT", 112, y)
    f.desc:SetPoint("RIGHT", -18, 0)
    f.desc:SetMaxLetters(160)
    f.desc:SetHeight(20)
    y = y - 27
    label(L["Symbol (Item)"], 18, y - 5)
    f.icon = K.Input(f, 300, L["Item-Name oder Link, optional"])
    f.icon:SetPoint("TOPLEFT", 112, y)
    f.icon:SetPoint("RIGHT", -18, 0)
    f.icon:SetHeight(20)
    if ns.ItemSearch and ns.ItemSearch.Attach then ns.ItemSearch.Attach(f.icon, function(id) f.icon.pickedID = id end) end
    y = y - 34
    label(L["Meilensteine"], 18, y + 4)
    f.steps = {}
    for i = 1, MAXS do
        local e = K.Input(f, 400, (L["Schritt %d"]):format(i))
        e:SetPoint("TOPLEFT", 18, y - 14 - (i - 1) * ROW)
        e:SetPoint("RIGHT", -18, 0)
        e:SetHeight(20)
        e:SetMaxLetters(80)
        f.steps[i] = e
    end
    y = y - 14 - MAXS * ROW - 10
    label(L["Material (Item + Menge)"], 18, y + 4)
    f.mats = {}
    for i = 1, MAXM do
        local n = K.Input(f, 70, L["Menge"])
        n:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, y - 14 - (i - 1) * ROW)
        n:SetHeight(20)
        n:SetNumeric(true)
        n:SetMaxLetters(5)
        local e = K.Input(f, 300, L["Item"])
        e:SetPoint("TOPLEFT", 18, y - 14 - (i - 1) * ROW)
        e:SetPoint("RIGHT", n, "LEFT", -8, 0)
        e:SetHeight(20)
        if ns.ItemSearch and ns.ItemSearch.Attach then ns.ItemSearch.Attach(e, function(id) e.pickedID = id end) end
        f.mats[i] = { item = e, n = n }
    end
    -- Knoepfe oben rechts neben der Ueberschrift (unten fehlte der Platz)
    f.save = K.Button(f, L["Speichern"], 100, 24, "primary", function() GG.SaveForm(p) end)
    f.save:SetPoint("TOPRIGHT", -18, -12)
    f.cancel = K.Button(f, L["Abbrechen"], 90, 24, "ghost", function() editing = nil ns.RefreshPage("goals") end)
    f.cancel:SetPoint("RIGHT", f.save, "LEFT", -8, 0)
    f.del = K.Button(f, L["Loeschen"], 90, 24, "ghost", function()
        local g = type(editing) == "string" and editing ~= "new" and Store.Get(COLL, editing)
        if g and GG.CanEdit(g) then
            if f.del.armed then Store.Delete(COLL, g.id) editing = nil GG.selected = nil ns.RefreshPage("goals")
            else f.del.armed = true f.del:SetLabel(L["Wirklich loeschen?"]) end
        end
    end)
    f.del:SetPoint("RIGHT", f.cancel, "LEFT", -8, 0)
end
local function itemFrom(e)
    if e.pickedID then return e.pickedID end
    local t = e:GetText() or ""
    if t == "" then return nil end
    local id = ns.itemID(t) or tonumber(t)
    if not id and ns.ItemSearch and ns.ItemSearch.ExactID then id = ns.ItemSearch.ExactID(t) end
    return id
end
function GG.FillForm(p, g)
    local f = p.form
    f.head:SetText(g and L["Ziel bearbeiten"] or L["Neues Gildenziel"])
    f.title:SetText(g and g.title or "")
    f.desc:SetText(g and g.desc or "")
    f.icon.pickedID = g and tonumber(g.icon) or nil
    f.icon:SetText(g and tonumber(g.icon) and nameOf(tonumber(g.icon)) or "")
    for i = 1, MAXS do f.steps[i]:SetText(g and g["s" .. i] or "") end
    for i = 1, MAXM do
        local id, need = tostring(g and g["m" .. i] or ""):match("^(%d+):(%d+)$")
        f.mats[i].item.pickedID = tonumber(id)
        f.mats[i].item:SetText(id and nameOf(tonumber(id)) or "")
        f.mats[i].n:SetText(need or "")
    end
    f.del:SetShown(g ~= nil and GG.CanEdit(g))
    f.del.armed = nil
    f.del:SetLabel(L["Loeschen"])
end
function GG.SaveForm(p)
    local f = p.form
    local title = (f.title:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if title == "" then K.Toast(L["Gildenziele"], L["Bitte einen Titel eingeben."], C.amber) return end
    local old = type(editing) == "string" and editing ~= "new" and Store.Get(COLL, editing) or nil
    if old and not GG.CanEdit(old) then return end
    local g = old and copyOf(old) or { id = ns.newId("gg"), created = ns.now() }
    g.title = title
    g.desc = (f.desc:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    g.icon = itemFrom(f.icon)
    for i = 1, MAXS do
        local t = (f.steps[i]:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t ~= (old and old["s" .. i] or "") then g["k" .. i] = nil end   -- geaenderter Schritt: wieder offen
        g["s" .. i] = t ~= "" and t or nil
    end
    for i = 1, MAXM do
        local id = itemFrom(f.mats[i].item)
        local n = tonumber(f.mats[i].n:GetText())
        g["m" .. i] = (id and n and n > 0) and (id .. ":" .. math.floor(n)) or nil
    end
    Store.Put(COLL, g)
    GG.selected, editing = g.id, nil
    ns.RefreshPage("goals")
end

-- Detail rechts -------------------------------------------------------------
local function buildDetail(p)
    local d = CreateFrame("Frame", nil, p)
    d:SetPoint("TOPLEFT", LISTW + 12, -42)
    d:SetPoint("BOTTOMRIGHT")
    glass(d, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.09 }, 14)
    p.detail = d
    -- Kopf: Verlauf, Symbol, Titel
    d.hero = d:CreateTexture(nil, "BACKGROUND", nil, 2)
    d.hero:SetPoint("TOPLEFT", 3, -3) d.hero:SetPoint("TOPRIGHT", -3, -3) d.hero:SetHeight(110)
    d.iconBox = CreateFrame("Frame", nil, d)
    d.iconBox:SetSize(54, 54)
    d.iconBox:SetPoint("TOPLEFT", 18, -18)
    glass(d.iconBox, { 0, 0, 0, 0.35 }, { 1, 1, 1, 0.16 }, 10)
    d.icon = d.iconBox:CreateTexture(nil, "ARTWORK")
    d.icon:SetPoint("TOPLEFT", 4, -4) d.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    d.title = K.Title(d, 19, C.text)
    d.title:SetPoint("TOPLEFT", d.iconBox, "TOPRIGHT", 14, -4)
    d.title:SetPoint("RIGHT", -130, 0)
    d.title:SetWordWrap(false)
    d.meta = K.Text(d, 11, C.muted)
    d.meta:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -6)
    d.meta:SetPoint("RIGHT", -18, 0)
    d.edit = K.Button(d, L["Bearbeiten"], 104, 24, "ghost", function()
        if GG.selected then editing = GG.selected ns.RefreshPage("goals") end
    end)
    d.edit:SetPoint("TOPRIGHT", -16, -18)
    -- grosser Fortschritt
    d.pct = K.Title(d, 24, C.text, "RIGHT")
    d.pct:SetPoint("TOPRIGHT", -18, -84)
    d.bar = gradBar(d, 10)
    d.bar:SetPoint("TOPLEFT", 18, -94)
    d.bar:SetPoint("RIGHT", d.pct, "LEFT", -12, 0)
    d.sum = K.Text(d, 11, C.dim)
    d.sum:SetPoint("TOPLEFT", d.bar, "BOTTOMLEFT", 0, -6)
    -- Erreicht-Banner (springt auf, wenn ein Ziel geschafft ist)
    d.won = K.Title(d, 13, C.mint)
    d.won:SetPoint("TOPRIGHT", d.pct, "BOTTOMRIGHT", 0, -4)
    -- Reiter
    d.tab = "over"
    d.seg = K.Segments(d, { { key = "over", text = L["Uebersicht"] }, { key = "mats", text = L["Material"] }, { key = "help", text = L["Helfer"] } },
        function(k) d.tab = k if K.TabAnim then K.TabAnim(d.seg, k) end p.animTab = true ns.RefreshPage("goals", true) end)
    d.seg:SetPoint("TOPLEFT", 12, -132)
    d.body = CreateFrame("Frame", nil, d)
    d.body:SetPoint("TOPLEFT", 18, -168)
    d.body:SetPoint("BOTTOMRIGHT", -18, 52)
    -- Uebersicht: Beschreibung + Meilenstein-Pfad
    d.desc = K.Text(d.body, 12, C.text)
    d.desc:SetPoint("TOPLEFT", 0, 0)
    d.desc:SetPoint("RIGHT", 0, 0)
    d.desc:SetWordWrap(true)
    d.desc:SetJustifyH("LEFT")
    d.path = d.body:CreateTexture(nil, "BACKGROUND")
    d.path:SetWidth(2)
    d.path:SetColorTexture(1, 1, 1, 0.08)
    d.steps = {}
    for i = 1, MAXS do
        local b = CreateFrame("Button", nil, d.body)
        b:SetHeight(30)
        b.node = b:CreateTexture(nil, "ARTWORK")
        b.node:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        b.node:SetSize(16, 16)
        b.node:SetPoint("LEFT", 0, 0)
        b.check = b:CreateTexture(nil, "OVERLAY")
        b.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        b.check:SetSize(14, 14)
        b.check:SetPoint("CENTER", b.node, "CENTER")
        b.hl = b:CreateTexture(nil, "BACKGROUND")
        b.hl:SetPoint("TOPLEFT", 24, 0) b.hl:SetPoint("BOTTOMRIGHT")
        b.hl:SetColorTexture(1, 1, 1, 0.04)
        if K.RoundMask then K.RoundMask(b.hl, b.hl, 6) end
        b.hl:Hide()
        b.t = K.Text(b, 13, C.text)
        b.t:SetPoint("LEFT", 32, 0)
        b.t:SetPoint("RIGHT", -8, 0)
        b.t:SetWordWrap(false)
        b:SetScript("OnClick", function(self)
            if not (self.g and GG.CanEdit(self.g)) then return end
            local wasDone = self.done
            GG.ToggleStep(self.g, self.i)
            if not wasDone and animOn() then
                -- Haken ploppt auf
                local c = self.check
                c:Show()
                K.Tween(c, 0.35, function(q) local k = 0.4 + 0.9 * math.sin(q * math.pi * 0.75) c:SetSize(14 * k + 4, 14 * k + 4) end, function() c:SetSize(14, 14) end)
                K.Burst(p, self.node, 10, { C.mint, C.accent })
            end
        end)
        b:SetScript("OnEnter", function(self) self.hl:Show() if self.g and GG.CanEdit(self.g) then K.ShowTip(self, L["Klick: abhaken / wieder oeffnen"]) end end)
        b:SetScript("OnLeave", function(self) self.hl:Hide() GameTooltip:Hide() end)
        d.steps[i] = b
    end
    d.noSteps = K.Text(d.body, 12, C.dim)
    d.noSteps:SetPoint("TOPLEFT", 0, -40)
    -- Material-Karten
    d.mats = {}
    for i = 1, MAXM do
        local r = CreateFrame("Frame", nil, d.body)
        r:SetHeight(46)
        glass(r, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.07 }, 10)
        r:EnableMouse(true)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(30, 30)
        r.icon:SetPoint("LEFT", 8, 0)
        r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("TOPLEFT", 46, -7)
        r.name:SetPoint("RIGHT", -176, 0)
        r.name:SetWordWrap(false)
        r.count = K.Text(r, 11, C.muted, "RIGHT")
        r.count:SetPoint("TOPRIGHT", -176, -7)
        r.bar = gradBar(r, 5)
        r.bar:SetPoint("BOTTOMLEFT", 46, 9)
        r.bar:SetPoint("RIGHT", -176, 0)
        r.mine = K.Title(r, 12, C.mint, "CENTER")
        r.mine:SetWidth(34)
        local function step(delta)
            return function(btn)
                local g = r.g
                if not g then return end
                local _, mine = GG.Contrib(g, r.i)
                local n = math.max(0, mine + delta)
                if n == mine then return end
                GG.SetContrib(g, r.i, n)
                K.FloatText(btn or r.mine, (delta > 0 and "+" or "") .. delta, delta > 0 and C.mint or C.red)
            end
        end
        r.minus = K.Button(r, "-1", 28, 22, "ghost")
        r.minus:SetScript("OnClick", function(self) step(-1)(self) end)
        r.minus:SetPoint("RIGHT", -136, 0)
        r.mine:SetPoint("LEFT", r.minus, "RIGHT", 2, 0)
        r.plus = K.Button(r, "+1", 28, 22, "ghost")
        r.plus:SetScript("OnClick", function(self) step(1)(self) end)
        r.plus:SetPoint("LEFT", r.mine, "RIGHT", 2, 0)
        r.plus5 = K.Button(r, "+5", 28, 22, "ghost")
        r.plus5:SetScript("OnClick", function(self) step(5)(self) end)
        r.plus5:SetPoint("LEFT", r.plus, "RIGHT", 2, 0)
        r.plus20 = K.Button(r, "+20", 32, 22, "ghost")
        r.plus20:SetScript("OnClick", function(self) step(20)(self) end)
        r.plus20:SetPoint("LEFT", r.plus5, "RIGHT", 2, 0)
        r:SetScript("OnEnter", function(self)
            if not self.g then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.id then pcall(GameTooltip.SetItemByID, GameTooltip, self.id) end
            local _, _, list = GG.Contrib(self.g, self.i)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(L["Beigetragen:"], 0.6, 0.6, 0.65)
            for j = 1, math.min(10, #list) do GameTooltip:AddDoubleLine("  " .. ns.displayName(list[j].who), list[j].n, 0.9, 0.9, 0.9, 1, 1, 1) end
            if #list == 0 then GameTooltip:AddLine("  " .. L["noch niemand"], 0.5, 0.5, 0.55) end
            GameTooltip:AddLine(L["+/- zaehlt, was DU beigetragen hast"], 0.5, 0.5, 0.55)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.mats[i] = r
    end
    d.noMats = K.Text(d.body, 12, C.dim)
    d.noMats:SetPoint("TOPLEFT", 0, -6)
    -- Helfer-Rangliste
    d.help = {}
    for i = 1, 8 do
        local r = CreateFrame("Frame", nil, d.body)
        r:SetHeight(26)
        r.pos = K.Title(r, 13, C.dim, "CENTER")
        r.pos:SetPoint("LEFT", 0, 0)
        r.pos:SetWidth(24)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("LEFT", 30, 0)
        r.name:SetWidth(150)
        r.name:SetWordWrap(false)
        r.bar = gradBar(r, 6)
        r.bar:SetPoint("LEFT", 186, 0)
        r.bar:SetPoint("RIGHT", -54, 0)
        r.n = K.Title(r, 12, C.text, "RIGHT")
        r.n:SetPoint("RIGHT", 0, 0)
        r.n:SetWidth(48)
        d.help[i] = r
    end
    d.noHelp = K.Text(d.body, 12, C.dim)
    d.noHelp:SetPoint("TOPLEFT", 0, -6)
    -- Fuss
    d.finish = K.Button(d, L["Als erreicht markieren"], 170, 26, "primary", function(self)
        local g = GG.selected and Store.Get(COLL, GG.selected)
        if not g then return end
        GG.SetFinished(g, not g.fin)
        if not g.fin then K.Burst(p, d.pct, 40) end
    end)
    d.finish:SetPoint("BOTTOMRIGHT", -16, 14)
    d.chat = K.Button(d, L["Im Gildenchat teilen"], 150, 26, "ghost", function()
        local g = GG.selected and Store.Get(COLL, GG.selected)
        if not g then return end
        local parts = { (L["Gildenziel: %s (%s)"]):format(tostring(g.title or "?"), pct(GG.Progress(g))) }
        for _, m in ipairs(GG.Mats(g)) do
            local sum = GG.Contrib(g, m.i)
            if sum < m.need then parts[#parts + 1] = (L["%s %d/%d"]):format(nameOf(m.id), sum, m.need) end
            if #parts >= 4 then break end
        end
        -- Klick = Eingabe -> Senden erlaubt
        if ns.SendChat then ns.SendChat(table.concat(parts, " - "):sub(1, 255), "GUILD") end
    end)
    d.chat:SetPoint("RIGHT", d.finish, "LEFT", -8, 0)
    d.none = K.Text(d, 12, C.dim, "CENTER")
    d.none:SetPoint("CENTER")
    d.none:SetWidth(300)
    d.none:SetWordWrap(true)
end

local function fillDetail(p, g, animate)
    local d = p.detail
    local show = g ~= nil
    for _, w in ipairs({ d.iconBox, d.title, d.meta, d.edit, d.pct, d.bar, d.sum, d.won, d.seg, d.body, d.finish, d.chat, d.hero }) do w:SetShown(show) end
    d.none:SetShown(not show)
    d.none:SetText(L["Links ein Ziel waehlen oder ein neues anlegen."])
    if not g then return end
    local ac = g.fin and C.mint or C.accent
    if not K.Gradient(d.hero, "VERTICAL", { ac[1], ac[2], ac[3], 0 }, { ac[1], ac[2], ac[3], 0.16 }) then d.hero:SetColorTexture(ac[1], ac[2], ac[3], 0.05) end
    d.icon:SetTexture(iconOf(tonumber(g.icon)))
    d.icon:SetDesaturated(false)
    d.title:SetText(emo(tostring(g.title or "?"), g.by))
    d.meta:SetText(ns.displayName(g.by or "?") .. "  ·  " .. ns.ago(g.created or g.u or 0))
    d.edit:SetShown(GG.CanEdit(g))
    local p0 = GG.Progress(g)
    d.bar:Color(g.fin and C.mint or (C.accent2 or C.accent), g.fin and C.mint or C.accent)
    d.bar:Set(p0, animate)
    if animate and animOn() then K.CountUp(d.pct, math.floor(p0 * 100 + 0.5), 0.6, function(v) return math.floor(v + 0.5) .. "%" end)
    else d.pct:SetText(pct(p0)) end
    d.pct:SetTextColor((g.fin and C.mint or C.text)[1], (g.fin and C.mint or C.text)[2], (g.fin and C.mint or C.text)[3])
    local steps, mats = GG.Steps(g), GG.Mats(g)
    local sd, md = 0, 0
    for _, s in ipairs(steps) do if s.done then sd = sd + 1 end end
    for _, m in ipairs(mats) do if GG.Contrib(g, m.i) >= m.need then md = md + 1 end end
    local parts = {}
    if #steps > 0 then parts[#parts + 1] = (L["%d von %d Meilensteinen"]):format(sd, #steps) end
    if #mats > 0 then parts[#parts + 1] = (L["%d von %d Materialien"]):format(md, #mats) end
    d.sum:SetText(table.concat(parts, "  ·  "))
    d.won:SetText(g.fin and L["ZIEL ERREICHT"] or "")
    d.seg:Select(d.tab)
    -- alles im Koerper verstecken, dann den Reiter fuellen
    d.desc:Hide() d.path:Hide() d.noSteps:Hide() d.noMats:Hide() d.noHelp:Hide()
    for _, b in ipairs(d.steps) do b:Hide() end
    for _, r in ipairs(d.mats) do r:Hide() end
    for _, r in ipairs(d.help) do r:Hide() end
    local function appear(f, i)
        if not (p.animTab and animOn()) then f:SetAlpha(1) return end
        f:SetAlpha(0)
        K.Tween(f, 0.25, function(q) f:SetAlpha(q) end, function() f:SetAlpha(1) end, (i - 1) * 0.04)
    end
    if d.tab == "over" then
        local y = 0
        if (g.desc or "") ~= "" then
            d.desc:SetText(emo(g.desc, g.by))
            d.desc:Show()
            y = -(d.desc:GetStringHeight() or 14) - 12
        end
        if #steps == 0 then
            d.noSteps:ClearAllPoints()
            d.noSteps:SetPoint("TOPLEFT", 0, y)
            d.noSteps:SetText(L["Keine Meilensteine - nur Material."])
            d.noSteps:Show()
        else
            -- Pfad: senkrechte Linie durch die Knoten, erledigte Knoten gefuellt
            d.path:ClearAllPoints()
            d.path:SetPoint("TOP", d.body, "TOPLEFT", 8, y - 15)
            d.path:SetHeight(math.max(1, (#steps - 1) * 32))
            d.path:SetShown(#steps > 1)
            for n, s in ipairs(steps) do
                local b = d.steps[n]
                b.g, b.i, b.done = g, s.i, s.done
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", 0, y)
                b:SetPoint("RIGHT", d.body, "RIGHT", 0, 0)
                local nc = s.done and C.mint or { 0.22, 0.22, 0.25 }
                b.node:SetVertexColor(nc[1], nc[2], nc[3], 1)
                b.check:SetShown(s.done)
                b.t:SetText(s.done and ("|cff8a8a8a" .. emo(s.text, g.by) .. "|r") or emo(s.text, g.by))
                b:Show()
                appear(b, n)
                y = y - 32
            end
        end
    elseif d.tab == "mats" then
        if #mats == 0 then
            d.noMats:SetText(L["Fuer dieses Ziel wird kein Material gesammelt."])
            d.noMats:Show()
        end
        local y = 0
        for n, m in ipairs(mats) do
            local r = d.mats[n]
            r.g, r.i, r.id = g, m.i, m.id
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, y)
            r:SetPoint("RIGHT", d.body, "RIGHT", 0, 0)
            local sum, mine = GG.Contrib(g, m.i)
            local full = sum >= m.need
            r.icon:SetTexture(iconOf(m.id))
            r.name:SetText(nameOf(m.id))
            r.count:SetText(("%d / %d"):format(sum, m.need))
            local cc = full and C.mint or C.muted
            r.count:SetTextColor(cc[1], cc[2], cc[3])
            r.bar:Color(full and C.mint or (C.accent2 or C.accent), full and C.mint or C.accent)
            r:Show()
            r.bar:Set(sum / math.max(1, m.need), animate or p.animTab)
            r.mine:SetText(tostring(mine))
            appear(r, n)
            y = y - 52
        end
    else
        local list = helpers(g)
        if #list == 0 then
            d.noHelp:SetText(L["Noch hat niemand Material beigetragen."])
            d.noHelp:Show()
        end
        local top = list[1] and list[1].n or 1
        local MEDAL = { { 1, 0.8, 0.32 }, { 0.8, 0.84, 0.92 }, { 0.86, 0.56, 0.32 } }
        for n = 1, math.min(#list, #d.help) do
            local e, r = list[n], d.help[n]
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -(n - 1) * 28)
            r:SetPoint("RIGHT", d.body, "RIGHT", 0, 0)
            r.pos:SetText(n)
            local mc = MEDAL[n] or C.dim
            r.pos:SetTextColor(mc[1], mc[2], mc[3])
            r.name:SetText(ns.Radar and ns.Radar.Colored and ns.Radar.Colored(e.who) or ns.displayName(e.who))
            r.n:SetText(e.n)
            r:Show()
            r.bar:Set(e.n / top, p.animTab)
            appear(r, n)
        end
    end
    d.finish:SetShown(GG.CanEdit(g))
    d.finish:SetLabel(g.fin and L["Wieder offen"] or L["Als erreicht markieren"])
    p.animTab = nil
end

if ns.ICONS then ns.ICONS.goals = ns.MEDIA .. "icons\\checklist" end
ns.RegisterPage({
    key = "goals", title = "Gildenziele", order = 7.65,
    sub = "Gemeinsame Vorhaben der Gilde - Meilensteine abhaken, Material zusammentragen",
    build = function(p)
        -- Kennzahlen oben
        p.tiles = {}
        local TT = { { "checklist", "Aktive Ziele" }, { "star_on", "Erreicht" }, { "heart", "Dein Beitrag" }, { "social", "Helfer" } }
        for i, t in ipairs(TT) do
            local c = CreateFrame("Frame", nil, p)
            c:SetHeight(52)
            glass(c, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.08 }, 12)
            c.ic = K.Glyph(c, 16, ns.MEDIA .. "icons\\" .. t[1], C.accent)
            c.ic:SetPoint("LEFT", 14, 0)
            c.v = K.Title(c, 18, C.text)
            c.v:SetPoint("TOPLEFT", 40, -8)
            c.l = K.Text(c, 10, C.dim)
            c.l:SetPoint("TOPLEFT", c.v, "BOTTOMLEFT", 0, -2)
            c.l:SetText(L[t[2]])
            p.tiles[i] = c
            c:Hide()   -- Kennzahlen-Kacheln entfallen; Werte stehen in der Liste
        end
        p.newBtn = K.Button(p, L["Neues Ziel"], 120, 30, "primary", function()
            editing = (editing == "new") and nil or "new"
            ns.RefreshPage("goals")
        end)
        p.newBtn:SetPoint("TOPRIGHT", 0, -2)
        local function placeTiles()
            local W = (p:GetWidth() or 700) - 132
            local w = (W - 3 * 10) / 4
            for i, c in ipairs(p.tiles) do
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", (i - 1) * (w + 10), 0)
                c:SetWidth(math.max(60, w))
            end
        end
        p:HookScript("OnSizeChanged", placeTiles)
        placeTiles()
        p:HookScript("OnShow", function() p.animAll = true end)
        -- Liste links: Glas-Karten
        p.list = K.List(p, 70, function(l)
            local r = K.Row(l)
            if r.stripe then r.stripe:SetAlpha(0) end
            if r.sel then r.sel:SetAlpha(0) end
            if r.hl then r.hl:SetAlpha(0) end
            r.card = CreateFrame("Frame", nil, r)
            r.card:SetPoint("TOPLEFT", 0, -3)
            r.card:SetPoint("BOTTOMRIGHT", -6, 3)
            r.card:EnableMouse(false)
            glass(r.card, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.07 }, 10)
            r.icon = r.card:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(34, 34)
            r.icon:SetPoint("LEFT", 10, 2)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.done = r.card:CreateTexture(nil, "OVERLAY")
            r.done:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
            r.done:SetSize(16, 16)
            r.done:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT", 5, -5)
            r.t = K.Text(r.card, 13, C.text)
            r.t:SetPoint("TOPLEFT", 54, -10)
            r.t:SetPoint("RIGHT", -52, 0)
            r.t:SetWordWrap(false)
            r.m = K.Text(r.card, 10, C.dim)
            r.m:SetPoint("TOPLEFT", r.t, "BOTTOMLEFT", 0, -3)
            r.m:SetPoint("RIGHT", -52, 0)
            r.m:SetWordWrap(false)
            r.p = K.Title(r.card, 14, C.text, "RIGHT")
            r.p:SetPoint("TOPRIGHT", -12, -10)
            r.bar = gradBar(r.card, 4)
            r.bar:SetPoint("BOTTOMLEFT", 54, 10)
            r.bar:SetPoint("RIGHT", -12, 0)
            r:SetScript("OnClick", function(self)
                if not self.item then return end
                if GG.selected ~= self.item.id then p.animDetail = true end
                GG.selected, editing = self.item.id, nil
                ns.RefreshPage("goals", true)
            end)
            r:SetScript("OnEnter", function(self) if self.item and GG.selected ~= self.item.id then glass(self.card, { 1, 1, 1, 0.055 }, { 1, 1, 1, 0.12 }) end end)
            r:SetScript("OnLeave", function(self) if self.item then self.paint(self) end end)
            function r.paint(self)
                local sel = self.item and GG.selected == self.item.id and not editing
                glass(self.card, sel and { C.accent[1], C.accent[2], C.accent[3], 0.10 } or { 1, 1, 1, 0.03 },
                    sel and { C.accent[1], C.accent[2], C.accent[3], 0.55 } or { 1, 1, 1, 0.07 })
            end
            return r
        end, function(r, g)
            r.icon:SetTexture(iconOf(tonumber(g.icon)))
            r.icon:SetDesaturated(g.fin and true or false)
            r.done:SetShown(g.fin and true or false)
            r.t:SetText(emo(tostring(g.title or "?"), g.by))
            local pr = GG.Progress(g)
            r.p:SetText(pct(pr))
            local pc = g.fin and C.mint or C.text
            r.p:SetTextColor(pc[1], pc[2], pc[3])
            r.m:SetText(g.fin and ("|cff66db9e" .. L["erreicht"] .. "|r  ·  " .. ns.displayName(g.by or "?")) or (ns.displayName(g.by or "?") .. "  ·  " .. ns.ago(g.created or g.u or 0)))
            r.bar:Color(g.fin and C.mint or (C.accent2 or C.accent), g.fin and C.mint or C.accent)
            r.bar:Set(pr, false)
            r.paint(r)
            r:SetAlpha(g.fin and 0.75 or 1)
        end)
        p.list:SetPoint("TOPLEFT", 0, -42)
        p.list:SetPoint("BOTTOMLEFT", 0, 0)
        p.list:SetWidth(LISTW)
        p.list.empty:SetText(L["Noch keine Gildenziele. Lege das erste an - z. B. eine legendaere Waffe oder Material fuer den Raid."])
        buildDetail(p)
        buildForm(p)
    end,
    refresh = function(p)
        local list = GG.List()
        p.list:SetData(list)
        if not GG.selected and list[1] and not editing then GG.selected = list[1].id end
        local g = GG.selected and Store.Get(COLL, GG.selected)
        if g and g.del then g = nil GG.selected = nil end
        -- Kennzahlen
        local active, done, mine = 0, 0, 0
        for _, x in ipairs(list) do if x.fin then done = done + 1 else active = active + 1 end end
        for _, r in pairs(Store.coll(CONTRIB)) do if not r.del and ns.isMe(r.who) then mine = mine + math.max(0, tonumber(r.n) or 0) end end
        local vals = { active, done, mine, #helpers() }
        for i, c in ipairs(p.tiles) do
            if p.animAll and animOn() then K.CountUp(c.v, vals[i], 0.7, nil, (i - 1) * 0.06) else c.v:SetText(vals[i]) end
        end
        p.newBtn:SetLabel(editing == "new" and L["Abbrechen"] or L["Neues Ziel"])
        if editing then
            local eg = editing ~= "new" and Store.Get(COLL, editing) or nil
            if p.form.forId ~= editing then GG.FillForm(p, eg) p.form.forId = editing if animOn() then K.FadeIn(p.form, 0) end end
            p.detail:Hide()
            p.form:Show()
        else
            p.form.forId = nil
            p.form:Hide()
            p.detail:Show()
            local animate = p.animAll or p.animDetail
            if p.animDetail and animOn() then p.animTab = true end
            fillDetail(p, g, animate)
        end
        -- Ziel gerade erreicht (auch von anderen): Konfetti, einmal je Ziel
        if g and g.fin and not (p.cheered or {})[g.id] then
            p.cheered = p.cheered or {}
            p.cheered[g.id] = true
            if not p.animAll then K.Burst(p, p.detail.pct, 40) end
        end
        p.animAll, p.animDetail = nil, nil
    end,
})
ns.slash.ziele = function() ns.ShowPage("goals") end

------------------------------------------------------------------------
-- 0.6.450: Schwarzes Brett - jedes Gildenmitglied heftet Notizen an (Suche, Biete, Termin, Hinweis, Spass).
-- Loeschen: wer sie geschrieben hat oder die Gildenleitung; Anheften (oben halten) nur die Gildenleitung.
------------------------------------------------------------------------
local BOARD = "board"
if ns.ICONS then ns.ICONS.board = ns.MEDIA .. "icons\\announce" end   -- 0.6.452: Symbol in der Seitenleiste
local BCATS = {
    { key = "info", text = "Brett: Hinweis", col = { 0.55, 0.72, 1 } },
    { key = "search", text = "Brett: Suche", col = { 1, 0.72, 0.3 } },
    { key = "offer", text = "Brett: Biete", col = { 0.4, 0.86, 0.55 } },
    { key = "event", text = "Brett: Termin", col = { 0.85, 0.55, 1 } },
    { key = "fun", text = "Brett: Spass", col = { 1, 0.5, 0.6 } },
}
local BCAT = {}
for _, c in ipairs(BCATS) do BCAT[c.key] = c end
local MAXLEN, SHOWN = 200, 18
function GG.BoardList(filter)
    local out = {}
    for _, r in ipairs(Store.List(BOARD)) do
        if r.t and r.t ~= "" and (not filter or filter == "all" or r.c == filter) then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        if (a.pin and 1 or 0) ~= (b.pin and 1 or 0) then return a.pin and true or false end
        return (a.created or a.u or 0) > (b.created or b.u or 0)
    end)
    return out
end
function GG.CanDelNote(r) return r and (ns.isMe(r.by) or ns.isOfficer()) end
ns.RegisterPage({
    key = "board", title = "Schwarzes Brett", order = 7.64,
    sub = "Notizen fuer die ganze Gilde - Suche, Biete, Termine, Hinweise",
    build = function(p)
        p.cat, p.filter = "info", "all"
        p.input = K.Input(p, 400, L["Notiz an das Brett schreiben ..."], function() end)
        p.input:SetPoint("TOPLEFT", 0, -4)
        p.input:SetPoint("RIGHT", p, "RIGHT", -270, 0)
        if p.input.SetMaxLetters then p.input:SetMaxLetters(MAXLEN) end
        local function post()
            local t = (p.input:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if t == "" then return end
            Store.Put(BOARD, { id = ns.newId("nb"), created = ns.now(), t = t, c = p.cat })
            p.input:SetText("")
            p.input:ClearFocus()
            ns.RefreshPage("board", true)
        end
        p.input:SetScript("OnEnterPressed", post)
        p.catBtn = K.Button(p, "", 120, 28, "ghost", function()
            for i, c in ipairs(BCATS) do if c.key == p.cat then p.cat = BCATS[i % #BCATS + 1].key break end end
            p:ShowCat()
        end)
        p.catBtn:SetPoint("LEFT", p.input, "RIGHT", 8, 0)
        p.catBtn:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Art der Notiz"], L["Klick: naechste Art"] }) end)
        p.catBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
        function p:ShowCat()
            local c = BCAT[self.cat]
            self.catBtn:SetLabel(K.hex(c.col) .. L[c.text] .. "|r")
        end
        p:ShowCat()
        p.postBtn = K.Button(p, L["Ans Brett heften"], 130, 28, "primary", post)
        p.postBtn:SetPoint("LEFT", p.catBtn, "RIGHT", 8, 0)
        local items = { { key = "all", text = L["Alle"] } }
        for _, c in ipairs(BCATS) do items[#items + 1] = { key = c.key, text = L[c.text] } end
        p.seg = K.Segments(p, items, function(k) p.filter = k ns.RefreshPage("board", true) end)
        p.seg:SetPoint("TOPLEFT", 0, -46)
        p.empty = K.Text(p, 12, C.dim, "CENTER")
        p.empty:SetPoint("TOP", 0, -140)
        p.empty:SetText(L["Noch nichts am Brett. Schreib die erste Notiz - z. B. Suche Gruppe fuer ... oder Biete ..."])
        p.cards = {}
        local function card(i)
            local c = CreateFrame("Frame", nil, p)
            glass(c, { 0.055, 0.055, 0.065, 0.85 }, { 1, 1, 1, 0.08 }, 10)
            c.strip = c:CreateTexture(nil, "ARTWORK")
            c.strip:SetPoint("TOPLEFT", 10, -1) c.strip:SetPoint("TOPRIGHT", -10, -1) c.strip:SetHeight(2)
            c.cat = K.Text(c, 10, C.dim)
            c.cat:SetPoint("TOPLEFT", 12, -10)
            c.pin = c:CreateTexture(nil, "OVERLAY")
            c.pin:SetTexture(ns.MEDIA .. "icons\\pin")
            c.pin:SetSize(12, 12)
            c.pin:SetPoint("LEFT", c.cat, "RIGHT", 6, 0)
            c.text = K.Text(c, 12, C.text)
            c.text:SetPoint("TOPLEFT", 12, -28)
            c.text:SetPoint("RIGHT", c, "RIGHT", -12, 0)
            c.text:SetJustifyV("TOP")
            if c.text.SetMaxLines then c.text:SetMaxLines(4) end
            c.text:SetWordWrap(true)
            c.who = K.Text(c, 10, C.dim)
            c.who:SetPoint("BOTTOMLEFT", 12, 10)
            c.who:SetPoint("RIGHT", c, "RIGHT", -60, 0)
            c.who:SetWordWrap(false)
            local function iconBtn(path, tip, fn)
                local b = CreateFrame("Button", nil, c)
                b:SetSize(18, 18)
                b.ic = K.Glyph(b, 12, path, C.muted)
                b.ic:SetPoint("CENTER")
                b:SetScript("OnEnter", function(self) self.ic:SetVertexColor(C.text[1], C.text[2], C.text[3]) K.ShowTip(self, tip) end)
                b:SetScript("OnLeave", function(self) self.ic:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
                b:SetScript("OnClick", fn)
                return b
            end
            c.del = iconBtn(ns.MEDIA .. "icons\\eraser", L["Loeschen (zweimal klicken)"], function(self)
                if not (c.r and GG.CanDelNote(c.r)) then return end
                if self.armed and GetTime() - self.armed < 4 then Store.Delete(BOARD, c.r.id) ns.RefreshPage("board", true)
                else self.armed = GetTime() K.Toast(L["Schwarzes Brett"], L["Nochmal klicken zum Loeschen."], C.amber) end
            end)
            c.del:SetPoint("BOTTOMRIGHT", -8, 7)
            c.pinBtn = iconBtn(ns.MEDIA .. "icons\\pin", L["Oben anheften (Gildenleitung)"], function()
                if not (c.r and ns.isOfficer()) then return end
                local r = {}
                for k, v in pairs(c.r) do r[k] = v end
                r.pin = (not r.pin) or nil
                Store.Put(BOARD, r)
                ns.RefreshPage("board", true)
            end)
            c.pinBtn:SetPoint("RIGHT", c.del, "LEFT", -4, 0)
            p.cards[i] = c
            return c
        end
        for i = 1, SHOWN do card(i) end
        p.more = K.Text(p, 10, C.dim, "CENTER")
    end,
    refresh = function(p)
        local list = GG.BoardList(p.filter)
        local W = p:GetWidth() or 700
        if W < 300 then W = 700 end
        local cols = W > 900 and 3 or 2
        local gap, ch = 12, 116
        local cw = math.floor((W - gap * (cols - 1)) / cols)
        p.empty:SetShown(#list == 0)
        for i, c in ipairs(p.cards) do
            local r = list[i]
            c.r = r
            c:SetShown(r ~= nil)
            if r then
                local col = (i - 1) % cols
                local row = math.floor((i - 1) / cols)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", p, "TOPLEFT", col * (cw + gap), -84 - row * (ch + gap))
                c:SetSize(cw, ch)
                local cat = BCAT[r.c] or BCATS[1]
                c.strip:SetColorTexture(cat.col[1], cat.col[2], cat.col[3], 0.8)
                c.cat:SetText(K.hex(cat.col) .. K.Upper(L[cat.text]) .. "|r")
                c.pin:SetShown(r.pin and true or false)
                c.text:SetText(r.t)
                local who = (ns.Radar and ns.Radar.Colored) and ns.Radar.Colored(r.by or "?") or (r.by or "?")
                c.who:SetText(who .. "  |cff666666" .. (ns.ago and ns.ago(r.created or r.u) or "") .. "|r")
                c.del:SetShown(GG.CanDelNote(r) and true or false)
                c.pinBtn:SetShown(ns.isOfficer() and true or false)
            end
        end
        p.more:SetShown(#list > SHOWN)
        if #list > SHOWN then
            p.more:ClearAllPoints()
            p.more:SetPoint("TOP", p, "TOP", 0, -84 - math.ceil(SHOWN / cols) * (ch + gap))
            p.more:SetText((L["%d aeltere Notizen ausgeblendet"]):format(#list - SHOWN))
        end
    end,
})
ns.slash.brett = function() ns.ShowPage("board") end
end)

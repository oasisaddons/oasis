-- Oasis: Taschen & Twinks (wie Bagnon/Altoholic) - "Wo ist mein Leinenstoff?"
-- Jeder Charakter merkt sich seine Taschen und Bank (nur auf diesem Account, nichts wird gesendet).
-- Suche ueber alle eigenen Chars + Gildenbank, Zeile im Item-Tooltip, Bestand in der Handwerks-Boerse.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local Inv = {}
ns.Inventory = Inv
if ns.ICONS then ns.ICONS.bags = ns.MEDIA .. "icons\\bank" end

local function db() ns.db.inv = ns.db.inv or {} return ns.db.inv end
local function meKey() return ns.me() end
local function S() return ns.db.settings end

------------------------------------------------------------------------
-- Einlesen
------------------------------------------------------------------------
local function readBags(list)
    local out, used, total = {}, 0, 0
    for _, bag in ipairs(list) do
        local n = C_Container and C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, (n or 0) do
            total = total + 1
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                used = used + 1
                out[info.itemID] = (out[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return out, used, total
end
local function bagList() local t = {} for b = 0, (NUM_BAG_SLOTS or 4) do t[#t + 1] = b end return t end
local function bankList()
    local t = { (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or (BANK_CONTAINER or -1) }
    local first = (NUM_BAG_SLOTS or 4) + 1
    for b = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do t[#t + 1] = b end
    return t
end
-- 0.5.783: derselbe Charakter stand zweimal in der Liste, weil sich die Schreibweise des eigenen Namens geaendert hat
-- (Forever: "Vorname-Realm" und "Vorname Nachname-Realm"). Gleicher Vorname + gleicher Realm = derselbe Charakter:
-- alten Eintrag in den aktuellen uebernehmen (Bank bleibt erhalten, falls der neue noch keine kennt) und loeschen.
local merged = false
local function mergeMine()
    if merged then return end
    local me = meKey()
    if not me then return end
    merged = true
    local function ident(k)
        local base, realm = tostring(k):match("^(.-)%-(.+)$")
        base = base or tostring(k)
        return ((base:match("^(%S+)") or base) .. "-" .. (realm or "")):lower()
    end
    local mine = ident(me)
    local d = db()
    for who, e in pairs(d) do
        if who ~= me and ident(who) == mine then
            local cur = d[me]
            if not cur then
                d[me] = e
            else
                if not cur.bank and e.bank then cur.bank, cur.bankTs = e.bank, e.bankTs end
                if not cur.bags and e.bags then cur.bags, cur.used, cur.slots, cur.ts = e.bags, e.used, e.slots, e.ts end
            end
            d[who] = nil
        end
    end
end
local function entry()
    mergeMine()
    local e = db()[meKey()] or {}
    db()[meKey()] = e
    local _, cls = UnitClass("player")
    e.cls, e.lvl, e.gold, e.realm = cls, ns.safe(UnitLevel("player")), GetMoney and GetMoney() or 0, GetRealmName and GetRealmName() or ""
    return e
end
function Inv.ScanBags()
    local e = entry()
    e.bags, e.used, e.slots = readBags(bagList())
    e.ts = ns.now()
end
local bankOpen = false
function Inv.ScanBank()
    if not bankOpen then return end
    local e = entry()
    e.bank = readBags(bankList())
    e.bankTs = ns.now()
end
local pend
local function soon()
    if pend then return end
    pend = true
    C_Timer.After(1, function() pend = nil pcall(Inv.ScanBags) if bankOpen then pcall(Inv.ScanBank) end ns.RefreshPage("bags") end)
end
ns.On("BAG_UPDATE_DELAYED", soon)
ns.On("PLAYER_MONEY", function() local e = db()[meKey()] if e then e.gold = GetMoney() end end)
ns.On("BANKFRAME_OPENED", function() bankOpen = true soon() end)
ns.On("BANKFRAME_CLOSED", function() bankOpen = false end)
ns.On("PLAYERBANKSLOTS_CHANGED", soon)
ns.Listen("LOGIN", function() pcall(mergeMine) ns.After(5, function() pcall(Inv.ScanBags) end) end)

------------------------------------------------------------------------
-- Abfragen
------------------------------------------------------------------------
-- alle Fundstellen eines Items: { {who, bags, bank} ... }, Summe, Gildenbank
function Inv.Where(itemID)
    local out, total = {}, 0
    for who, e in pairs(db()) do
        local b, k = e.bags and e.bags[itemID] or 0, e.bank and e.bank[itemID] or 0
        if b + k > 0 then
            out[#out + 1] = { who = who, bags = b, bank = k, cls = e.cls }
            total = total + b + k
        end
    end
    table.sort(out, function(a, b) return a.bags + a.bank > b.bags + b.bank end)
    local gb = ns.GuildBank and ns.GuildBank.Count and ns.GuildBank.Count(itemID) or 0
    return out, total, gb
end
-- Bestand bei den ANDEREN eigenen Chars (fuer die Handwerks-Boerse)
function Inv.OtherCount(itemID)
    local n = 0
    for who, e in pairs(db()) do
        if not ns.isMe(who) then n = n + (e.bags and e.bags[itemID] or 0) + (e.bank and e.bank[itemID] or 0) end
    end
    local mine = db()[meKey()]
    local bank = mine and mine.bank and mine.bank[itemID] or 0
    return n, bank
end

------------------------------------------------------------------------
-- Tooltip: wer hat es noch?
------------------------------------------------------------------------
-- 0.5.612: eigener Block statt einer Sammelzeile - Kopf mit Gesamtzahl, je Charakter eine Zeile
-- (Klassensymbol + Name links, "Taschen x  Bank y" rechts), Gildenbank extra
local function clsIcon(cls)
    local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
    if not tc then return "" end
    return ("|TInterface\\TargetingFrame\\UI-Classes-Circles:13:13:0:0:256:256:%d:%d:%d:%d|t "):format(tc[1] * 256, tc[2] * 256, tc[3] * 256, tc[4] * 256)
end
local function cnt(label, n)
    if not n or n <= 0 then return nil end
    return "|cff8a8a90" .. label .. "|r |cffffffff" .. n .. "|r"
end
local function line(tt, itemID)
    if S().invTooltipOff or not itemID then return end
    local list, total, gb = Inv.Where(itemID)
    if total == 0 and gb == 0 then return end
    tt:AddLine(" ")
    tt:AddDoubleLine("|cffff1200Oasis|r  |cff8a8a90" .. L["Deine Charaktere"] .. "|r",
        "|cff8a8a90" .. L["gesamt"] .. "|r |cffffffff" .. (total + gb) .. "|r")
    for i, x in ipairs(list) do
        if i > 6 then
            tt:AddLine("|cff6a6a70   + " .. (#list - 6) .. " " .. L["weitere"] .. "|r")
            break
        end
        local right = {}
        right[#right + 1] = cnt(L["Taschen"], x.bags)
        right[#right + 1] = cnt(L["Bank"], x.bank)
        local me = ns.isMe(x.who) and (" |cff6a6a70(" .. L["du"] .. ")|r") or ""
        tt:AddDoubleLine("   " .. clsIcon(x.cls) .. ns.colorName(ns.short(x.who), x.cls) .. me, table.concat(right, "   "))
    end
    if gb > 0 then
        tt:AddDoubleLine("   |cffe8b44a" .. L["Gildenbank"] .. "|r", "|cffffffff" .. gb .. "|r")
    end
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        local id = data and ns.safe(data.id)
        pcall(line, tt, id)
    end)
end

------------------------------------------------------------------------
-- Seite "Taschen & Twinks"
------------------------------------------------------------------------
local selChar            -- Charakter rechts; "*" = alle zusammen
local catFilter = 0      -- 0 = alle Kategorien, sonst Rang aus CAT
local mode = "list"      -- "list" | "grid"
local ALL = "*"
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local function itemName(id)
    local n = C_Item.GetItemNameByID and ns.safe(C_Item.GetItemNameByID(id))
    if not n and ns.db.itemNames then
        local t = ns.db.itemNames[GetLocale()]
        n = t and t[id]
    end
    return n
end
local function glass(f, r, a)
    local IG = ns.Insta
    if IG and IG.Glass then IG.Glass(f, { 1, 1, 1, a or 0.03 }, { 1, 1, 1, 0.10 }, r or 12) end
end
local function qualityOf(id)
    local ok, q = pcall(function() return C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id) end)
    q = ok and ns.safe(q) or nil
    return q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
end
local function coins(c)
    if not c or not GetCoinTextureString then return "" end
    return GetCoinTextureString(c - c % 100)
end
-- Kategorien (Rang, Name, Farbe)
local CAT = {
    [2] = { 1, "Waffen", { 0.95, 0.45, 0.35 } }, [4] = { 2, "Ruestung", { 0.45, 0.65, 1.0 } },
    [0] = { 3, "Verbrauchbares", { 0.45, 0.85, 0.55 } }, [7] = { 4, "Handwerkswaren", { 0.95, 0.75, 0.35 } },
    [5] = { 5, "Reagenzien", { 0.75, 0.55, 1.0 } }, [9] = { 6, "Rezepte", { 0.95, 0.6, 0.85 } },
    [12] = { 7, "Quest-Gegenstaende", { 1.0, 0.85, 0.3 } }, [1] = { 8, "Taschen", { 0.7, 0.6, 0.45 } },
    [6] = { 9, "Munition", { 0.8, 0.8, 0.8 } }, [11] = { 9, "Munition", { 0.8, 0.8, 0.8 } }, [13] = { 10, "Schluessel", { 0.8, 0.8, 0.8 } },
}
local OTHER = { 11, "Sonstiges", { 0.6, 0.6, 0.65 } }
-- Filter-Reiter: die wichtigsten Gruppen, Rest unter Sonstiges
local FILTERS = { { key = 0, text = "Alle" }, { key = 50, text = "Gilde braucht" }, { key = 1, text = "Waffen" }, { key = 2, text = "Ruestung" }, { key = 3, text = "Verbrauch" },
    { key = 4, text = "Handwerk" }, { key = 7, text = "Quest" }, { key = 99, text = "Sonstiges" } }
-- 0.6.524: Was braucht die Gilde von dem, was du hast? Gesucht-Liste, Questitems anderer, offene Handwerks-Auftraege
-- [itemID] = { { who, kind = "want"|"quest"|"order", text }, ... } - einmal je Seitenaufbau berechnet
function Inv.GuildNeeds()
    local out = {}
    local function add(id, e) if id and id > 0 then out[id] = out[id] or {} table.insert(out[id], e) end end
    local Store = ns.Store
    for _, w in ipairs(Store and Store.List("wants") or {}) do
        if w.who and not ns.isMe(w.who) and not w.done then
            add(tonumber(w.itemID), { who = w.who, kind = "want", text = (w.qty and w.qty > 1) and ("x" .. w.qty) or nil })
        end
    end
    if ns.QuestItems and ns.QuestItems.NeedsByItem then
        local ok, m = pcall(ns.QuestItems.NeedsByItem)
        if ok and type(m) == "table" then
            for id, list in pairs(m) do for _, e in ipairs(list) do add(id, { who = e.who, kind = "quest", text = e.title }) end end
        end
    end
    for _, o in ipairs(Store and Store.List("orders") or {}) do
        if o.status == "open" and o.from and not ns.isMe(o.from) then add(tonumber(o.item), { who = o.from, kind = "order", text = o.qty and ("x" .. o.qty) or nil }) end
    end
    return out
end
local NEED_KIND = { want = "Gesucht", quest = "Quest", order = "Auftrag" }
local function needText(list)
    local parts = {}
    for i, e in ipairs(list) do
        if i > 3 then parts[#parts + 1] = "+" .. (#list - 3) break end
        parts[#parts + 1] = L[NEED_KIND[e.kind] or "Gesucht"] .. ": " .. ns.displayName(e.who) .. (e.text and (" |cff888888(" .. e.text .. ")|r") or "")
    end
    return table.concat(parts, "  ·  ")
end
Inv.NeedText = needText
local function inFilter(cat, x)
    if catFilter == 50 then return x ~= nil and x.needs ~= nil end   -- 0.6.524: nur was die Gilde braucht
    if catFilter == 0 then return true end
    if catFilter == 99 then return cat[1] >= 5 and cat[1] ~= 7 end
    return cat[1] == catFilter
end

ns.RegisterPage({
    key = "bags", title = "Taschen & Twinks", order = 5.45,
    sub = "Was liegt wo? Suche ueber alle deine Charaktere, ihre Bank und die Gildenbank",
    build = function(p)
        p.search = K.Input(p, 320, L["Item suchen, z.B. Leinenstoff"], function() p.fresh = true ns.RefreshPage("bags") end)
        p.search:SetPoint("TOPLEFT", 0, 0)
        glass(p.search, 8, 0.04)
        if ns.ItemSearch and ns.ItemSearch.Attach then pcall(ns.ItemSearch.Attach, p.search, function() ns.RefreshPage("bags") end) end
        p.sum = K.Text(p, 11, C.muted, "RIGHT")
        p.sum:SetPoint("TOPRIGHT", 0, -6)

        ----------------------------------------------------------------
        -- links: Charakterkarten
        ----------------------------------------------------------------
        local ch = CreateFrame("Frame", nil, p)
        glass(ch, 14, 0.025)
        ch:SetPoint("TOPLEFT", 0, -38)
        ch:SetPoint("BOTTOMLEFT")
        ch:SetWidth(240)
        local ht = K.Title(ch, 14, C.text)
        ht:SetPoint("TOPLEFT", 16, -14)
        ht:SetText(L["Deine Charaktere"])
        p.chars = K.List(ch, 62, function(l)
            local r = K.Row(l)
            if r.sel then r.sel:SetAlpha(0) end
            r.card = CreateFrame("Frame", nil, r)
            r.card:SetPoint("TOPLEFT", 0, -3) r.card:SetPoint("BOTTOMRIGHT", 0, 3)
            r.card:SetFrameLevel(r:GetFrameLevel())
            glass(r.card, 10, 0.02)
            r.ico = r:CreateTexture(nil, "ARTWORK")
            r.ico:SetSize(30, 30)
            r.ico:SetPoint("TOPLEFT", 10, -10)
            r.name = K.Text(r, 13, C.text)
            r.name:SetPoint("TOPLEFT", 48, -10)
            r.name:SetPoint("RIGHT", -10, 0)
            r.name:SetWordWrap(false)
            r.gold = K.Text(r, 10, C.muted)
            r.gold:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
            -- Taschen-Fuellstand
            r.track = r:CreateTexture(nil, "ARTWORK")
            r.track:SetColorTexture(1, 1, 1, 0.07)
            r.track:SetHeight(3)
            r.track:SetPoint("BOTTOMLEFT", 48, 11)
            r.track:SetPoint("BOTTOMRIGHT", -46, 11)
            r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.fill:SetHeight(3)
            r.fill:SetPoint("LEFT", r.track, "LEFT")
            r.slots = K.Text(r, 10, C.dim, "RIGHT")
            r.slots:SetPoint("RIGHT", -10, 0)
            r.slots:SetPoint("BOTTOM", r.track, "BOTTOM", 0, -4)
            r:SetScript("OnEnter", function(self) if self.item and selChar ~= self.item.who then glass(self.card, 10, 0.05) end end)
            r:SetScript("OnLeave", function(self) if self.item and selChar ~= self.item.who then glass(self.card, 10, 0.02) end end)
            r:SetScript("OnClick", function(self)
                if not self.item then return end
                selChar = self.item.who
                p.search:SetText("")
                p.fresh = true
                ns.RefreshPage("bags")
            end)
            return r
        end, function(r, c)
            local on = selChar == c.who
            glass(r.card, 10, on and 0.08 or 0.02)
            if c.who == ALL then
                r.ico:SetTexture(ns.MEDIA .. "icons\\bank")
                r.ico:SetTexCoord(0, 1, 0, 1)
                r.ico:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
                r.name:SetText(L["Alle zusammen"])
                r.gold:SetText(coins(c.gold))
            else
                r.ico:SetTexture(CLASS_CIRCLES)
                r.ico:SetVertexColor(1, 1, 1)
                local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.cls or ""]
                if tc then r.ico:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) else r.ico:SetTexCoord(0, 1, 0, 1) end
                r.name:SetText(ns.colorName(ns.short(c.who), c.cls) .. "  |cff888888" .. (c.lvl or "?") .. "|r" .. (ns.isMe(c.who) and ("  |cff66db9e" .. L["du"] .. "|r") or ""))
                r.gold:SetText(coins(c.gold))
            end
            local frac = (c.used and c.slots and c.slots > 0) and (c.used / c.slots) or 0
            r.track:SetShown(c.slots ~= nil)
            r.fill:SetShown(c.slots ~= nil and frac > 0)
            -- fast voll = Warnfarbe
            local fc = frac >= 0.9 and C.red or (frac >= 0.75 and C.amber or C.mint)
            r.fill:SetColorTexture(fc[1], fc[2], fc[3], 0.85)
            r.fill:SetWidth(math.max(1, 130 * frac))
            r.slots:SetText(c.slots and (c.used .. "/" .. c.slots) or "")
        end)
        p.chars:SetPoint("TOPLEFT", 8, -40)
        p.chars:SetPoint("BOTTOMRIGHT", -8, 8)
        -- Balkenbreite folgt der Kartenbreite
        ch:SetScript("OnSizeChanged", function() ns.RefreshPage("bags") end)

        ----------------------------------------------------------------
        -- rechts: Inhalt
        ----------------------------------------------------------------
        local rp = CreateFrame("Frame", nil, p)
        glass(rp, 14, 0.025)
        rp:SetPoint("TOPLEFT", 250, -38)
        rp:SetPoint("BOTTOMRIGHT")
        p.rp = rp
        p.rtitle = K.Title(rp, 15, C.text)
        p.rtitle:SetPoint("TOPLEFT", 16, -14)
        p.rinfo = K.Text(rp, 11, C.dim)
        p.rinfo:SetPoint("LEFT", p.rtitle, "RIGHT", 10, -1)
        p.rinfo:SetPoint("RIGHT", rp, "RIGHT", -110, 0)
        p.rinfo:SetWordWrap(false)
        -- Ansicht: Liste / Raster
        p.mode = K.Segments(rp, { { key = "list", text = L["Liste"] }, { key = "grid", text = L["Raster"] } },
            function(k) mode = k p.fresh = true ns.RefreshPage("bags") end, nil, { size = 11, pad = 14 })
        p.mode:SetPoint("TOPRIGHT", -10, -9)
        local fl = {}
        for i, f in ipairs(FILTERS) do fl[i] = { key = f.key, text = L[f.text] } end
        p.cat = K.Segments(rp, fl, function(k) catFilter = k p.fresh = true ns.RefreshPage("bags") end, nil, { size = 11, pad = 14 })
        p.cat:SetPoint("TOPLEFT", 10, -40)

        -- Listenansicht
        p.items = K.List(rp, 36, function(l)
            local r = K.Row(l)
            r.icon = K.Icon(r, 26, nil)
            r.icon:SetPoint("LEFT", 10, 0)
            r.q = r:CreateTexture(nil, "OVERLAY")
            r.q:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMLEFT") r.q:SetPoint("BOTTOMRIGHT", r.icon, "BOTTOMRIGHT") r.q:SetHeight(2)
            r.name = K.Text(r, 12, C.text)
            r.name:SetPoint("LEFT", 46, 0)
            r.name:SetPoint("RIGHT", r, "RIGHT", -270, 0)
            r.name:SetWordWrap(false)
            r.n = K.Title(r, 13, C.amber, "RIGHT")
            r.n:SetPoint("RIGHT", r, "RIGHT", -230, 0)
            r.where = K.Text(r, 11, C.muted)
            r.where:SetPoint("LEFT", r, "RIGHT", -215, 0)
            r.where:SetPoint("RIGHT", -10, 0)
            r.where:SetWordWrap(false)
            r.need = K.Glyph(r, 14, ns.MEDIA .. "icons\\wants", C.accent)
            r.need:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", -8, 4)
            r.needT = K.Text(r, 10, C.accent)
            r.needT:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -1)
            r.needT:SetPoint("RIGHT", r, "RIGHT", -230, 0)
            r.needT:SetWordWrap(false)
            r.hd = K.Text(r, 12, C.text)
            r.hd:SetPoint("BOTTOMLEFT", 10, 6)
            r.hdN = K.Text(r, 10, C.dim, "RIGHT")
            r.hdN:SetPoint("BOTTOMRIGHT", -10, 6)
            r.hdLine = r:CreateTexture(nil, "ARTWORK")
            r.hdLine:SetPoint("BOTTOMLEFT", 10, 2) r.hdLine:SetPoint("BOTTOMRIGHT", -10, 2) r.hdLine:SetHeight(1)
            r:SetScript("OnEnter", function(self)
                if not self.item or self.item.header then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetItemByID, GameTooltip, self.item.id)
                if self.item.needs then GameTooltip:AddLine("|cffff1200Oasis|r  " .. L["Die Gilde braucht das:"] .. " " .. needText(self.item.needs), 0.85, 0.85, 0.85, true) end
                GameTooltip:AddLine("|cff888888" .. L["Shift-Klick: in den Chat einfuegen"] .. "|r")
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self)
                if not self.item or self.item.header or not IsShiftKeyDown() then return end
                local _, link = pcall(function() return select(2, C_Item.GetItemInfo(self.item.id)) end)
                if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
            end)
            return r
        end, function(r, it, i)
            local hd = it.header and true or false
            for _, x in ipairs({ r.icon, r.q, r.name, r.n, r.where }) do x:SetShown(not hd) end
            local nd = not hd and it.needs ~= nil
            r.need:SetShown(nd) r.needT:SetShown(nd)
            r.name:ClearAllPoints()
            r.name:SetPoint("LEFT", 46, nd and 6 or 0)
            r.name:SetPoint("RIGHT", r, "RIGHT", -270, 0)
            if nd then r.needT:SetText(needText(it.needs)) end
            r.hd:SetShown(hd) r.hdN:SetShown(hd) r.hdLine:SetShown(hd)
            if r.hl then r.hl:SetAlpha(hd and 0 or 1) end
            if hd then
                r.hd:SetText("|cff" .. it.hex .. it.text .. "|r")
                r.hdN:SetText(it.count)
                r.hdLine:SetColorTexture(it.col[1], it.col[2], it.col[3], 0.25)
                return
            end
            r.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id) or 134400)
            local qc = qualityOf(it.id)
            r.q:SetColorTexture(qc and qc.r or 0.5, qc and qc.g or 0.5, qc and qc.b or 0.5, 0.9)
            r.name:SetText((qc and qc.hex or "|cffffffff") .. (itemName(it.id) or ("#" .. it.id)) .. "|r")
            r.n:SetText(it.n)
            r.where:SetText(it.where or "")
            if p.fresh and K.FadeIn and (i or 0) <= 18 then r.oasisFadedAt = nil K.FadeIn(r, (i or 1) * 0.02) end
        end)
        p.items:SetPoint("TOPLEFT", 6, -72)
        p.items:SetPoint("BOTTOMRIGHT", -6, 8)
        -- 0.6.524: Hinweis "Die Gilde braucht ..." (Klick = Filter "Gilde braucht")
        p.needBar = CreateFrame("Button", nil, rp)
        p.needBar:SetHeight(22)
        p.needBar:SetPoint("BOTTOMLEFT", 10, 10)
        p.needBar:SetPoint("BOTTOMRIGHT", -10, 10)
        p.needBar:SetFrameLevel(rp:GetFrameLevel() + 20)
        glass(p.needBar, 6, 0.10)
        p.needBar.ic = K.Glyph(p.needBar, 14, ns.MEDIA .. "icons\\wants", C.accent)
        p.needBar.ic:SetPoint("LEFT", 8, 0)
        p.needBar.t = K.Text(p.needBar, 11, C.text)
        p.needBar.t:SetPoint("LEFT", 28, 0)
        p.needBar:SetScript("OnClick", function() catFilter = 50 p.fresh = true ns.RefreshPage("bags") end)
        p.needBar:Hide()

        -- Rasteransicht: Taschen-Look, eine Zeile = mehrere Felder
        local CELL = 40
        p.grid = K.List(rp, CELL + 6, function(l)
            local r = K.Row(l)
            if r.hl then r.hl:SetAlpha(0) end
            r.cells = {}
            for c = 1, 14 do
                local b = CreateFrame("Button", nil, r)
                b:SetSize(CELL, CELL)
                b:SetPoint("LEFT", 10 + (c - 1) * (CELL + 6), 0)
                glass(b, 6, 0.03)
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetPoint("TOPLEFT", 3, -3) b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
                b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.q = b:CreateTexture(nil, "OVERLAY")
                b.q:SetPoint("BOTTOMLEFT", 3, 3) b.q:SetPoint("BOTTOMRIGHT", -3, 3) b.q:SetHeight(2)
                b.need = K.Glyph(b, 14, ns.MEDIA .. "icons\\wants", C.accent)
                b.need:SetPoint("TOPRIGHT", 2, 2)
                b.n = b:CreateFontString(nil, "OVERLAY")
                K.SetFontSafe(b.n, K.FONT_HEAD or K.FONT, 11, "OUTLINE", K.FONT)
                b.n:SetPoint("BOTTOMRIGHT", -3, 4)
                b:SetScript("OnEnter", function(self)
                    if not self.it then return end
                    glass(self, 6, 0.10)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    pcall(GameTooltip.SetItemByID, GameTooltip, self.it.id)
                    if self.it.needs then GameTooltip:AddLine("|cffff1200Oasis|r  " .. L["Die Gilde braucht das:"] .. " " .. needText(self.it.needs), 0.85, 0.85, 0.85, true) end
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function(self) glass(self, 6, 0.03) GameTooltip:Hide() end)
                b:SetScript("OnClick", function(self)
                    if not self.it or not IsShiftKeyDown() then return end
                    local _, link = pcall(function() return select(2, C_Item.GetItemInfo(self.it.id)) end)
                    if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
                end)
                r.cells[c] = b
            end
            return r
        end, function(r, line, i)
            for c, b in ipairs(r.cells) do
                local it = line[c]
                b.it = it
                b:SetShown(it ~= nil and c <= (p.gridCols or 10))
                b.need:SetShown(it ~= nil and it.needs ~= nil)
                if it then
                    b.icon:SetTexture(C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id) or 134400)
                    local qc = qualityOf(it.id)
                    b.q:SetColorTexture(qc and qc.r or 0.5, qc and qc.g or 0.5, qc and qc.b or 0.5, (qc and it.id and 0.9) or 0)
                    b.n:SetText(it.n > 1 and it.n or "")
                end
            end
            if p.fresh and K.FadeIn and (i or 0) <= 10 then r.oasisFadedAt = nil K.FadeIn(r, (i or 1) * 0.04) end
        end)
        p.grid:SetPoint("TOPLEFT", 6, -72)
        p.grid:SetPoint("BOTTOMRIGHT", -6, 8)
        p.gridCell = CELL

        -- leer: Hinweis mit Erklaerung
        local em = CreateFrame("Frame", nil, rp)
        em:SetSize(380, 120)
        em:SetPoint("CENTER", 0, -10)
        em.ico = K.Glyph(em, 30, ns.MEDIA .. "icons\\bank", C.dim)
        em.ico:SetPoint("TOP")
        em.t = K.Title(em, 14, C.text, "CENTER")
        em.t:SetPoint("TOP", em.ico, "BOTTOM", 0, -10)
        em.t:SetWidth(380)
        em.d = K.Text(em, 11, C.muted, "CENTER")
        em.d:SetPoint("TOP", em.t, "BOTTOM", 0, -6)
        em.d:SetWidth(360)
        em.d:SetWordWrap(true)
        p.empty = em
        p.items.empty:SetText("")
        p.grid.empty:SetText("")
        p.fresh = true
    end,
    refresh = function(p)
        local chars = {}
        local gold, used, slots = 0, 0, 0
        for who, e in pairs(db()) do
            chars[#chars + 1] = { who = who, cls = e.cls, lvl = e.lvl, gold = e.gold, used = e.used, slots = e.slots }
            gold = gold + (e.gold or 0)
        end
        table.sort(chars, function(a, b) if ns.isMe(a.who) ~= ns.isMe(b.who) then return ns.isMe(a.who) end return (a.lvl or 0) > (b.lvl or 0) end)
        if #chars > 1 then table.insert(chars, 1, { who = ALL, gold = gold }) end
        selChar = selChar or ns.me()
        if selChar == ALL and #chars < 2 then selChar = ns.me() end
        p.chars:SetData(chars)
        p.sum:SetText((L["%d Charaktere"]):format(#chars - (#chars > 1 and 1 or 0)) .. "  ·  " .. coins(gold - gold % 10000))

        local q = ((p.search:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")):lower()
        local out = {}
        local em = p.empty
        local function whereText(id)
            local list, _, gb = Inv.Where(id)
            local w = {}
            for _, x in ipairs(list) do
                w[#w + 1] = ns.colorName(ns.short(x.who), x.cls) .. " " .. (x.bags > 0 and x.bags or "") .. (x.bank > 0 and ((x.bags > 0 and "+" or "") .. x.bank .. " " .. L["Bank"]) or "")
            end
            if gb > 0 then w[#w + 1] = "|cffe8b44a" .. L["Gildenbank"] .. " " .. gb .. "|r" end
            return table.concat(w, "  ·  ")
        end
        if q ~= "" or selChar == ALL then
            -- Suche bzw. alle Charaktere zusammen (+ Gildenbank bei Suche)
            local ids = {}
            for _, e in pairs(db()) do
                for _, t in ipairs({ e.bags or {}, e.bank or {} }) do for id in pairs(t) do ids[id] = true end end
            end
            if q ~= "" and ns.GuildBank and ns.GuildBank.AllItems then
                local okG, gl = pcall(ns.GuildBank.AllItems)
                if okG and type(gl) == "table" then
                    for k, v in pairs(gl) do
                        local id = type(v) == "table" and tonumber(v.id) or tonumber(k)
                        if id then ids[id] = true end
                    end
                end
            end
            local qid = tonumber(q:match("item:(%d+)") or q)
            for id in pairs(ids) do
                local n = itemName(id)
                if q == "" or (qid and id == qid) or (n and n:lower():find(q, 1, true)) then
                    local _, total, gb = Inv.Where(id)
                    out[#out + 1] = { id = id, n = total + (q ~= "" and gb or 0), where = whereText(id) }
                end
            end
            if q ~= "" then
                local shown = q
                if qid then shown = itemName(qid) or ("#" .. qid) end
                p.rtitle:SetText((L["Treffer fuer \"%s\""]):format(shown))
                em.t:SetText(L["Nichts gefunden"])
                em.d:SetText(L["Bei Twinks einmal einloggen und die Bank einmal oeffnen - dann findet Oasis auch dort alles."])
            else
                p.rtitle:SetText(L["Alle Charaktere"])
                em.t:SetText(L["Noch nichts eingelesen"])
                em.d:SetText(L["Einmal mit jedem Charakter einloggen."])
            end
            p.rinfo:SetText("")
        else
            local e = db()[selChar] or {}
            local by = {}
            for id, n in pairs(e.bags or {}) do by[id] = { id = id, n = n, bag = n, bank = 0 } end
            for id, n in pairs(e.bank or {}) do by[id] = by[id] or { id = id, n = 0, bag = 0, bank = 0 } by[id].n = by[id].n + n by[id].bank = n end
            for _, x in pairs(by) do
                x.where = (x.bag > 0 and ((L["Taschen %d"]):format(x.bag)) or "") .. (x.bank > 0 and ((x.bag > 0 and "  ·  " or "") .. "|cffe8b44a" .. (L["Bank %d"]):format(x.bank) .. "|r") or "")
                out[#out + 1] = x
            end
            p.rtitle:SetText(ns.colorName(ns.short(selChar), e.cls))
            p.rinfo:SetText(e.bankTs and ((L["Bank gesehen %s"]):format(ns.ago(e.bankTs))) or L["Bank noch nicht gesehen - einmal oeffnen"])
            em.t:SetText(L["Noch nichts eingelesen"])
            em.d:SetText(L["Einmal mit diesem Charakter einloggen."])
        end

        -- Kategorien + Filter
        local shown = {}
        local needs, nNeed = Inv.GuildNeeds(), 0
        for _, x in ipairs(out) do
            local ok, _, _, _, _, _, classID = pcall(C_Item.GetItemInfoInstant, x.id)
            x.cat = (ok and CAT[classID or -1]) or OTHER
            x.needs = needs[x.id]
            if inFilter(x.cat, x) then shown[#shown + 1] = x end
            if x.needs then nNeed = nNeed + 1 end
        end
        if #out > 0 and #shown == 0 then
            em.t:SetText(catFilter == 50 and L["Gerade braucht niemand etwas davon"] or L["Nichts in dieser Kategorie"])
            em.d:SetText(catFilter == 50 and L["Hier erscheinen Items aus der Gesucht-Liste, Questitems anderer und offene Handwerks-Auftraege."] or L["Andere Kategorie waehlen."])
        end
        -- Hinweisleiste: wie viele Items die Gilde gerade braucht (Klick = Filter)
        p.needBar:SetShown(nNeed > 0 and catFilter ~= 50)
        local bot = (nNeed > 0 and catFilter ~= 50) and 38 or 8
        p.items:SetPoint("BOTTOMRIGHT", -6, bot)
        p.grid:SetPoint("BOTTOMRIGHT", -6, bot)
        p.needBar.t:SetText((L["%d deiner Items braucht gerade jemand aus der Gilde - anzeigen"]):format(nNeed))
        table.sort(shown, function(a, b)
            if a.cat[1] ~= b.cat[1] then return a.cat[1] < b.cat[1] end
            if (a.needs ~= nil) ~= (b.needs ~= nil) then return a.needs ~= nil end
            local na, nb = itemName(a.id) or "", itemName(b.id) or ""
            if na ~= nb then return na < nb end
            return a.id < b.id
        end)
        p.cat:Select(catFilter)
        p.mode:Select(mode)
        em:SetShown(#shown == 0)
        p.items:SetShown(mode == "list")
        p.grid:SetShown(mode == "grid")
        if mode == "list" then
            local rows, lastCat, hdr = {}, nil, nil
            for _, x in ipairs(shown) do
                if x.cat ~= lastCat then
                    local c = x.cat[3]
                    hdr = { header = true, text = L[x.cat[2]], col = c, count = 0, hex = ("%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) }
                    rows[#rows + 1] = hdr
                    lastCat = x.cat
                end
                hdr.count = hdr.count + 1
                rows[#rows + 1] = x
            end
            p.items:SetData(rows)
        else
            local w = p.grid:GetWidth() or 0
            if w < 100 then w = 480 end
            p.gridCols = math.max(4, math.min(14, math.floor((w - 24) / (p.gridCell + 6))))
            local lines = {}
            for i, x in ipairs(shown) do
                local li = math.floor((i - 1) / p.gridCols) + 1
                lines[li] = lines[li] or {}
                lines[li][#lines[li] + 1] = x
            end
            p.grid:SetData(lines)
        end
        p.fresh = nil
    end,
})

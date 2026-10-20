-- Oasis: Gildenbank (Inhalt, Gold, Protokoll)
-- WoW gibt die Bank nur heraus, solange jemand am Gildentresor steht. Oasis liest dann alle
-- Faecher + Protokoll aus und teilt den Stand mit der Gilde.
local ADDON, ns = ...
ns.ModuleFile("Oasis_GuildBank", function()   -- Modul Gildenbank (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local Bank = {}
ns.GuildBank = Bank

local SLOTS = 98
local function maxTabs() return MAX_GUILDBANK_TABS or 8 end

------------------------------------------------------------------------
-- Auslesen
------------------------------------------------------------------------
Bank.open = false

local function scanTab(tab)
    local name, icon, viewable = GetGuildBankTabInfo(tab)
    if not viewable then return end
    local parts, n = {}, 0
    for slot = 1, (MAX_GUILDBANK_SLOTS_PER_TAB or SLOTS) do
        local link = GetGuildBankItemLink(tab, slot)
        if link then
            local _, count = GetGuildBankItemInfo(tab, slot)
            local id = ns.itemID(link)
            if id then
                parts[#parts + 1] = slot .. ":" .. id .. ":" .. (count or 1)
                n = n + 1
            end
        end
    end
    local items = table.concat(parts, ",")
    local old = Store.Get("bank", "tab-" .. tab)
    if old and old.items == items and old.name == name and (ns.now() - (old.ts or 0)) < 1800 then return end
    Store.Put("bank", { id = "tab-" .. tab, n = tab, name = name or ("Fach " .. tab), icon = icon or 0, items = items, who = ns.me(), ts = ns.now() })
end

local function logTs(y, m, d, h)
    return ns.now() - ((((y or 0) * 365 + (m or 0) * 30 + (d or 0)) * 24) + (h or 0)) * 3600
end

local function scanLog(tab)
    local entries = {}
    if tab == "money" then
        for i = 1, (GetNumGuildBankMoneyTransactions() or 0) do
            local typ, name, amount, y, m, d, h = GetGuildBankMoneyTransaction(i)
            if typ then entries[#entries + 1] = table.concat({ typ, name or "?", 0, amount or 0, math.floor(logTs(y, m, d, h) / 3600) * 3600 }, "/") end
        end
    else
        for i = 1, (GetNumGuildBankTransactions(tab) or 0) do
            local typ, name, link, count, tab1, tab2, y, m, d, h = GetGuildBankTransaction(tab, i)
            if typ then entries[#entries + 1] = table.concat({ typ, name or "?", ns.itemID(link) or 0, count or 1, math.floor(logTs(y, m, d, h) / 3600) * 3600, tab1 or 0, tab2 or 0 }, "/") end
        end
    end
    -- neueste zuerst, maximal 30
    local list = {}
    for i = #entries, math.max(1, #entries - 29), -1 do list[#list + 1] = entries[i] end
    local s = table.concat(list, "#")
    local id = "log-" .. tab
    local old = Store.Get("banklog", id)
    if old and old.e == s then return end
    Store.Put("banklog", { id = id, tab = tostring(tab), e = s, who = ns.me(), ts = ns.now() })
end

local function scanAll()
    if not Bank.open then return end
    for tab = 1, (GetNumGuildBankTabs() or 0) do pcall(scanTab, tab) end
    if GetGuildBankMoney then
        local money = GetGuildBankMoney()
        local old = Store.Get("bank", "money")
        if money and (not old or old.amount ~= money) then
            Store.Put("bank", { id = "money", amount = money, who = ns.me(), ts = ns.now() })
        end
    end
end
local function scanLogs()
    if not Bank.open then return end
    for tab = 1, (GetNumGuildBankTabs() or 0) do pcall(scanLog, tab) end
    pcall(scanLog, "money")
end

local pendingScan, pendingLog
local function soon(which)
    if which == "items" then
        if pendingScan then return end
        pendingScan = true
        ns.After(1, function() pendingScan = nil scanAll() end)
    else
        if pendingLog then return end
        pendingLog = true
        ns.After(1.5, function() pendingLog = nil scanLogs() end)
    end
end

local function onOpen()
    -- Einstellung "Gildenbank fuer die Gilde einlesen" aus: nichts lesen, nichts teilen
    if ns.db.settings.bankShareScan == false then Bank.open = false return end
    Bank.open = true
    -- alle Faecher und Protokolle nacheinander anfordern (Server drosselt)
    local tabs = GetNumGuildBankTabs() or 0
    for tab = 1, tabs do
        ns.After(tab * 0.4, function()
            if not Bank.open then return end
            QueryGuildBankTab(tab)
            QueryGuildBankLog(tab)
        end)
    end
    ns.After(tabs * 0.4 + 0.4, function() if Bank.open then QueryGuildBankLog(maxTabs() + 1) end end)
    ns.After(tabs * 0.4 + 2, function() scanAll() scanLogs() end)
end
local function onClose() Bank.open = false end

ns.On("GUILDBANKFRAME_OPENED", onOpen)
ns.On("GUILDBANKFRAME_CLOSED", onClose)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(t)
    if Enum and Enum.PlayerInteractionType and t == Enum.PlayerInteractionType.GuildBanker then onOpen() end
end)
ns.On("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(t)
    if Enum and Enum.PlayerInteractionType and t == Enum.PlayerInteractionType.GuildBanker then onClose() end
end)
ns.On("GUILDBANKBAGSLOTS_CHANGED", function() soon("items") end)
ns.On("GUILDBANK_UPDATE_MONEY", function() soon("items") end)
ns.On("GUILDBANKLOG_UPDATE", function() soon("log") end)

------------------------------------------------------------------------
-- Abfragen fuer andere Module
------------------------------------------------------------------------
function Bank.Tabs()
    local out = Store.List("bank", function(r) return r.n end)
    table.sort(out, function(a, b) return a.n < b.n end)
    return out
end
function Bank.Items(tab)
    local out = {}
    for slot, id, count in (tab.items or ""):gmatch("(%d+):(%d+):(%d+)") do
        out[tonumber(slot)] = { id = tonumber(id), count = tonumber(count) }
    end
    return out
end
-- Anzahl eines Items in der ganzen Bank - ueber einen Index (itemID -> Anzahl), neu nur wenn sich die Bank aendert
-- (Performance 0.5.482: vorher pro Tooltip-Aufbau alle Faecher zerlegt, ~600 Tabellen je Aufruf)
local countIdx
ns.Listen("STORE", function(coll) if coll == "bank" then countIdx = nil end end)
function Bank.Count(itemID)
    if not itemID or itemID == 0 then return 0 end
    if not countIdx then
        countIdx = {}
        for _, tab in ipairs(Bank.Tabs()) do
            for _, id, count in (tab.items or ""):gmatch("(%d+):(%d+):(%d+)") do
                id = tonumber(id)
                countIdx[id] = (countIdx[id] or 0) + tonumber(count)
            end
        end
    end
    return countIdx[itemID] or 0
end
function Bank.CountReset() countIdx = nil end
-- Fach nach Nummer (echte Daten "tab-N", Demo "demo-tab-N")
function Bank.Tab(n)
    for _, t in ipairs(Bank.Tabs()) do if t.n == n then return t end end
end
function Bank.Money()
    local r = Store.Get("bank", "money")
    if not r and ns.Demo and ns.Demo.IsActive() then r = Store.Get("bank", "demo-money") end
    return r and r.amount, r
end
function Bank.Log()
    local out = {}
    local names = {}
    for _, t in ipairs(Bank.Tabs()) do names[tostring(t.n)] = t.name end
    for _, rec in ipairs(Store.List("banklog")) do
        for e in (rec.e or ""):gmatch("[^#]+") do
            local typ, who, id, count, ts, t1, t2 = e:match("^([^/]*)/([^/]*)/(%d+)/(%d+)/(%d+)/?(%d*)/?(%d*)$")
            if typ then
                out[#out + 1] = {
                    typ = typ, who = who, id = tonumber(id), count = tonumber(count), ts = tonumber(ts),
                    money = rec.tab == "money", tab = names[rec.tab] or rec.tab, tab2 = names[t2 or ""],
                }
            end
        end
    end
    table.sort(out, function(a, b) return a.ts > b.ts end)
    return out
end

local function money(c)
    c = c or 0
    if GetMoneyString then
        local ok, s = pcall(GetMoneyString, c, true)
        if ok and s then return s end
    end
    return ("%dg %ds %dc"):format(c / 10000, (c % 10000) / 100, c % 100)
end
Bank.MoneyText = money

------------------------------------------------------------------------
-- Auswertungen fuer die Seite
------------------------------------------------------------------------
local function itemName(id)
    local n = C_Item.GetItemNameByID and ns.safe(C_Item.GetItemNameByID(id))
    return n or ("#" .. id)
end
local function qualityColor(id)
    if not (C_Item and C_Item.GetItemQualityByID) then return nil end
    local ok, q = pcall(C_Item.GetItemQualityByID, id)
    q = ok and ns.safe(q)
    if not q or q < 2 then return nil end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return c and { c.r, c.g, c.b } or nil
end
local function priceOf(id) return ns.Market and ns.Market.Price(id) or nil end

function Bank.TabStats(tab)
    local items = Bank.Items(tab)
    local used, worth, priced = 0, 0, 0
    for _, it in pairs(items) do
        used = used + 1
        local pr = priceOf(it.id)
        if pr then worth, priced = worth + pr * it.count, priced + 1 end
    end
    return used, worth, priced, items
end
-- Items ueber alle Faecher zusammengefasst
function Bank.AllItems()
    local by, list = {}, {}
    for _, tab in ipairs(Bank.Tabs()) do
        for _, it in pairs(Bank.Items(tab)) do
            local e = by[it.id]
            if not e then
                e = { id = it.id, count = 0, tabs = {} }
                by[it.id] = e
                list[#list + 1] = e
            end
            e.count = e.count + it.count
            e.tabs[tab.n] = (e.tabs[tab.n] or 0) + it.count
        end
    end
    return list, by
end
function Bank.Search(q)
    local out = {}
    if q == "" then return out end
    for _, e in ipairs(Bank.AllItems()) do
        if itemName(e.id):lower():find(q, 1, true) then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return itemName(a.id) < itemName(b.id) end)
    return out
end
-- von Mitgliedern gesuchte Items
local function wantedSet()
    local set = {}
    if not ns.Wants then return set end
    for _, w in ipairs(ns.Wants.All()) do
        if w.itemID and w.itemID > 0 and not ns.isMe(w.who) then
            set[w.itemID] = set[w.itemID] or {}
            table.insert(set[w.itemID], w.who)
        end
    end
    return set
end
-- wer hat in den letzten Tagen am meisten eingezahlt
ns.GuildOption({ page = "bank", key = "gbTopDay", default = 7, min = 1, max = 30, step = 1, label = "Top donors period",
    desc = "How many days the top donors on the bank home page cover",
    fmt = function(v) return v .. " Tg" end })
function Bank.Contributors(days)
    local cut = ns.now() - (days or 7) * 86400
    local by, list = {}, {}
    for _, e in ipairs(Bank.Log()) do
        if e.ts >= cut and (e.typ == "deposit") then
            local w = by[e.who]
            if not w then w = { who = e.who, items = 0, gold = 0 } by[e.who] = w list[#list + 1] = w end
            if e.money then w.gold = w.gold + (e.count or 0) else w.items = w.items + (e.count or 1) end
        end
    end
    table.sort(list, function(a, b)
        local va, vb = a.items + a.gold / 10000, b.items + b.gold / 10000
        return va > vb
    end)
    return list
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local ACTIONS = {
    deposit = { "eingezahlt", C.mint }, withdraw = { "entnommen", C.amber }, move = { "verschoben", C.blue },
    repair = { "Repair", C.muted }, withdrawForTab = { "for tab purchase", C.muted }, buyTab = { "bought tab", C.muted },
    depositSummary = { "income", C.mint },
}
local view, search, logFilter = "home", "", "all"
local COLS, CELL = 14, 36

local function cellTip(self)
    if not self.id then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
    local pr = priceOf(self.id)
    if pr then GameTooltip:AddLine(L["Market value ~"] .. ns.Market.Format(pr * (self.qty or 1)), 0.9, 0.7, 0.3) end
    if self.wanted then GameTooltip:AddLine(L["Wanted by: "] .. table.concat((function()
        local t = {} for _, w in ipairs(self.wanted) do t[#t + 1] = ns.displayName(w) end return t end)(), ", "), 0.9, 0.7, 0.3) end
    GameTooltip:AddLine(L["Right-click: menu"], 0.45, 0.45, 0.48)
    GameTooltip:Show()
end
local function cellMenu(self)
    if not self.id then return end
    local id = self.id
    local _, link = C_Item.GetItemInfo(id)
    local items = {
        { text = L["Link in chat"], disabled = not link, fn = function() ChatEdit_InsertLink(link) end },
        { text = L["Add to wishlist"], disabled = not (link and ns.Wants), fn = function() ns.Wants.Add(link, 1, L["from the guild bank"]) end },
        { text = L["Ask in guild chat"], disabled = not link, fn = function()
            ns.OpenChat("/g " .. (L["May I take %s from the guild bank?"]):format(link))
        end },
    }
    K.ShowMenu(self, items, itemName(id))
end

local function glass(f, r, a, line)
    local IG = ns.Insta
    if IG and IG.Glass then IG.Glass(f, { 1, 1, 1, a or 0.03 }, line or { 1, 1, 1, 0.10 }, r or 12) end
end
local function animOn() return not (ns.db and ns.db.settings.noAnim) end
-- Glasflaeche mit ruhigem Titel (+ optionalem Zaehler rechts)
local function panel(parent, title)
    local f = CreateFrame("Frame", nil, parent)
    glass(f, 14, 0.025)
    f.head = K.Title(f, 13, C.text)
    f.head:SetPoint("TOPLEFT", 16, -14)
    f.head:SetText(title)
    f.count = K.Text(f, 10, C.dim, "RIGHT")
    f.count:SetPoint("TOPRIGHT", -16, -16)
    return f
end
-- Platz 1-3 in Gold/Silber/Bronze
local MEDAL = { { 1, 0.82, 0.3 }, { 0.78, 0.8, 0.86 }, { 0.84, 0.55, 0.32 } }
-- Zeile mit Hover-Glas
local function hoverRow(r)
    r.card = CreateFrame("Frame", nil, r)
    r.card:SetAllPoints()
    r.card:SetFrameLevel(r:GetFrameLevel())
    glass(r.card, 8, 0, { 1, 1, 1, 0 })
    r:HookScript("OnEnter", function(self) glass(self.card, 8, 0.05, { 1, 1, 1, 0.08 }) end)
    r:HookScript("OnLeave", function(self) glass(self.card, 8, 0, { 1, 1, 1, 0 }) end)
end
local valMode = "value"   -- Uebersicht rechts oben: "value" (wertvoll) | "wanted" (von der Gilde gesucht)

ns.RegisterPage({
    key = "bank", title = "Guild bank", order = 2.2,
    sub = "What's in the guild bank, what it's worth and who deposited what",
    build = function(p)
        p.search = K.Input(p, 200, L["Search all tabs ..."], function(t)
            search = t:lower()
            ns.RefreshPage("bank")
        end)
        p.search:SetPoint("TOPRIGHT", 0, 0)
        if ns.ItemSearch then
            ns.ItemSearch.Attach(p.search, function(id)
                local n = ns.ItemSearch.Name(id) or ""
                p.search.suppress = true
                p.search:SetText(n)
                p.search.suppress = false
                search = n:lower()
                ns.RefreshPage("bank")
            end)
        end
        p.segHolder = CreateFrame("Frame", nil, p)
        p.segHolder:SetPoint("TOPLEFT", 0, 0)
        p.segHolder:SetSize(540, 24)

        ----------------------------------------------------------------
        -- Uebersicht
        ----------------------------------------------------------------
        p.home = CreateFrame("Frame", nil, p)
        p.home:SetPoint("TOPLEFT", 0, -40)
        p.home:SetPoint("BOTTOMRIGHT")
        p.cards = {}
        local CARDCOL = { C.amber, C.text, C.mint, C.blue }
        for i, lab in ipairs({ "Gold", "Items", "Used", "Market value" }) do
            local c = K.StatCard(p.home, L[lab])
            glass(c, 12)
            c.value:SetFont(K.FONT_HEAD or K.FONT, 18, "")
            c.value:SetPoint("TOPLEFT", 14, -11)
            c.label:SetPoint("BOTTOMLEFT", 14, 10)
            c.label:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
            c.col = CARDCOL[i]
            p.cards[i] = c
        end
        -- Karten teilen sich die Breite
        p.home:SetScript("OnSizeChanged", function(self, w)
            local cw = math.floor(((w or 760) - 30) / 4)
            for i, c in ipairs(p.cards) do c:ClearAllPoints() c:SetPoint("TOPLEFT", (i - 1) * (cw + 10), 0) c:SetSize(cw, 58) end
            if p.homePanels then
                local half = math.floor(((w or 760) - 10) / 2)
                p.homePanels[1]:SetWidth(half)
                if p.contribPanel then p.contribPanel:SetWidth(half) end
            end
        end)
        -- Verlauf der letzten 30 Tage in der Marktwert-Kachel
        if ns.Trade then
            p.worthSpark = ns.Trade.Sparkline(p.cards[4], 60, 22, 30)
            p.worthSpark:SetPoint("TOPRIGHT", -10, -12)
        end
        -- Faecher mit Fuellstand
        local tp = panel(p.home, L["Tabs"])
        p.homePanels = { tp }
        tp:SetPoint("TOPLEFT", 0, -68)
        tp:SetSize(370, 214)
        p.tabRows = {}
        for i = 1, 6 do
            local r = CreateFrame("Button", nil, tp)
            r:SetHeight(28)
            r:SetPoint("TOPLEFT", 8, -38 - (i - 1) * 29)
            r:SetPoint("RIGHT", tp, "RIGHT", -8, 0)
            hoverRow(r)
            r.icon = K.Icon(r, 22, nil)
            r.icon:SetPoint("LEFT", 6, 0)
            r.name = K.Text(r, 12, C.text)
            r.name:SetPoint("LEFT", 36, 0)
            r.name:SetWidth(120)
            r.name:SetWordWrap(false)
            r.value = K.Text(r, 10, C.dim, "RIGHT")
            r.value:SetPoint("RIGHT", -6, 0)
            r.value:SetWidth(64)
            r.fill = K.Text(r, 11, C.muted, "RIGHT")
            r.fill:SetPoint("RIGHT", r.value, "LEFT", -8, 0)
            r.fill:SetWidth(48)
            r.bar = K.Bar(r, 100, 3)
            r.bar:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
            r.bar:SetPoint("RIGHT", r.fill, "LEFT", -10, 0)
            r:HookScript("OnEnter", function(self) if self.n then K.ShowTip(self, { self.name:GetText() or "", L["Click: open profession"] }) end end)
            r:HookScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self) if self.n then view = self.n p.seg:Select(view) p.fresh = true ns.RefreshPage("bank") end end)
            p.tabRows[i] = r
        end
        -- wertvollste Items
        local vp = panel(p.home, L["Most valuable items"])
        table.insert(p.homePanels, vp)
        vp:SetPoint("TOPLEFT", tp, "TOPRIGHT", 10, 0)
        vp:SetPoint("TOPRIGHT", 0, -68)
        vp:SetHeight(214)
        p.valPanel = vp
        vp.head:Hide()
        p.valSeg = K.Segments(vp, { { key = "value", text = L["Most valuable items"] }, { key = "wanted", text = L["Wanted"] } },
            function(k) valMode = k p.fresh = true ns.RefreshPage("bank") end, nil, { size = 12, pad = 14 })
        p.valSeg:SetPoint("TOPLEFT", 6, -8)
        p.valRows = {}
        for i = 1, 6 do
            local r = CreateFrame("Button", nil, vp)
            r:SetHeight(28)
            r:SetPoint("TOPLEFT", 8, -38 - (i - 1) * 29)
            r:SetPoint("RIGHT", vp, "RIGHT", -8, 0)
            hoverRow(r)
            r.rank = K.Text(r, 11, C.dim, "CENTER")
            r.rank:SetPoint("LEFT", 2, 0)
            r.rank:SetWidth(16)
            r.icon = K.Icon(r, 22, nil)
            r.icon:SetPoint("LEFT", 22, 0)
            r.name = K.Text(r, 12, C.text)
            r.name:SetPoint("LEFT", 52, 0)
            r.name:SetPoint("RIGHT", r, "RIGHT", -96, 0)
            r.name:SetWordWrap(false)
            r.value = K.Text(r, 11, C.muted, "RIGHT")
            r.value:SetPoint("RIGHT", -6, 0)
            r:HookScript("OnEnter", cellTip)
            r:HookScript("OnLeave", function() GameTooltip:Hide() end)
            r:RegisterForClicks("AnyUp")
            r:SetScript("OnClick", function(self, btn)
                if btn == "RightButton" then GameTooltip:Hide() cellMenu(self)
                elseif IsShiftKeyDown() and self.id then
                    local _, link = C_Item.GetItemInfo(self.id)
                    if link then ChatEdit_InsertLink(link) end
                elseif self.jump then view = self.jump p.fresh = true ns.RefreshPage("bank") end
            end)
            p.valRows[i] = r
        end
        p.valEmpty = K.Text(vp, 11, C.dim)
        p.valEmpty:SetPoint("TOPLEFT", 16, -44)
        p.valEmpty:SetPoint("RIGHT", vp, "RIGHT", -16, 0)
        p.valEmpty:SetWordWrap(true)
        p.valEmpty:SetText(L["Prices come from Midas or Oasis' own auction house tracking."])
        -- Top-Spender
        local cp = panel(p.home, L["Top donors (7 days)"])
        p.contribPanel = cp
        table.insert(p.homePanels, cp)
        cp:SetPoint("TOPLEFT", 0, -292)
        cp:SetPoint("BOTTOMLEFT")
        cp:SetWidth(370)
        p.contrib = K.List(cp, 32, function(l)
            local r = K.Row(l)
            if r.stripe then r.stripe:Hide() r.stripe = nil end
            r:Col("rank", 8, 20, 13, C.dim)
            r.cols.rank:SetFont(K.FONT_HEAD or K.FONT, 13, "")
            r:Col("who", 32, 150, 12)
            r.cols.who:ClearAllPoints() r.cols.who:SetPoint("TOPLEFT", 32, -5)
            r:Col("what", 0, 160, 11, C.muted, "RIGHT")
            r.cols.what:ClearAllPoints()
            r.cols.what:SetPoint("TOPRIGHT", -8, -5)
            r.track = r:CreateTexture(nil, "ARTWORK")
            r.track:SetColorTexture(1, 1, 1, 0.06)
            r.track:SetHeight(3)
            r.track:SetPoint("BOTTOMLEFT", 32, 6)
            r.track:SetPoint("BOTTOMRIGHT", -8, 6)
            r.bar = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.bar:SetHeight(3)
            r.bar:SetPoint("LEFT", r.track, "LEFT")
            return r
        end, function(r, w)
            r.cols.rank:SetText(w.rank)
            local mc = MEDAL[w.rank] or C.dim
            r.cols.rank:SetTextColor(mc[1], mc[2], mc[3])
            local bc = MEDAL[w.rank] or C.muted
            r.bar:SetColorTexture(bc[1], bc[2], bc[3], 0.7)
            local tw = (r.track:GetWidth() or 0) > 10 and r.track:GetWidth() or 280
            r.bar:SetWidth(math.max(2, tw * (w.share or 0)))
            r.cols.who:SetText(ns.Radar.Colored(ns.fullName(w.who)))
            local t = {}
            if w.items > 0 then t[#t + 1] = (L["%d items"]):format(w.items) end
            if w.gold > 0 then t[#t + 1] = money(w.gold) end
            r.cols.what:SetText(table.concat(t, "  ·  "))
        end)
        p.contrib:SetPoint("TOPLEFT", 6, -38)
        p.contrib:SetPoint("BOTTOMRIGHT", -6, 8)
        p.contrib.empty:SetText(L["Nobody has deposited anything this week."])
        -- letzte Bewegungen
        local lp = panel(p.home, L["Recent activity"])
        table.insert(p.homePanels, lp)
        lp:SetPoint("TOPLEFT", cp, "TOPRIGHT", 10, 0)
        lp:SetPoint("BOTTOMRIGHT")
        lp.more = K.Button(lp, L["All"], 60, 20, "ghost", function() view = "log" p.fresh = true ns.RefreshPage("bank") end)
        lp.more:SetPoint("TOPRIGHT", -10, -10)
        lp.more.label:SetFont(K.FONT, 11, "")
        p.recent = K.List(lp, 28, function(l)
            local r = K.Row(l)
            if r.stripe then r.stripe:Hide() r.stripe = nil end
            r.icon = K.Icon(r, 18, nil)
            r.icon:SetPoint("LEFT", 8, 0)
            -- Richtung: + rein / - raus
            r.dir = K.Title(r, 12, C.mint, "CENTER")
            r.dir:SetPoint("LEFT", 30, 0)
            r.dir:SetWidth(12)
            r:Col("text", 46, 250, 11)
            r.cols.text:SetPoint("RIGHT", r, "RIGHT", -70, 0)
            r.cols.text:SetWordWrap(false)
            r:Col("when", 0, 60, 10, C.dim, "RIGHT")
            r.cols.when:ClearAllPoints()
            r.cols.when:SetPoint("RIGHT", -8, 0)
            return r
        end, function(r, e)
            local a = ACTIONS[e.typ] or { e.typ, C.muted }
            local what
            if e.money then
                r.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
                what = money(e.count)
            else
                r.icon:SetTexture(C_Item.GetItemIconByID(e.id or 0) or 134400)
                what = (e.count or 1) .. "x " .. itemName(e.id or 0)
            end
            local inn = e.typ == "deposit" or e.typ == "depositSummary"
            local out = e.typ == "withdraw" or e.typ == "repair" or e.typ == "withdrawForTab" or e.typ == "buyTab"
            r.dir:SetText(inn and "+" or (out and "−" or "↔"))
            local dc = inn and C.mint or (out and C.amber or C.blue)
            r.dir:SetTextColor(dc[1], dc[2], dc[3])
            r.cols.text:SetText(ns.Radar.Colored(ns.fullName(e.who)) .. " " .. K.hex(a[2]) .. L[a[1]] .. "|r " .. what)
            r.cols.when:SetText(ns.ago(e.ts))
        end)
        p.recent:SetPoint("TOPLEFT", 6, -38)
        p.recent:SetPoint("BOTTOMRIGHT", -6, 8)
        p.recent.empty:SetText(L["No log yet."])
        do
            local em = CreateFrame("Frame", nil, p.home)
            em:SetSize(460, 230)
            em:SetPoint("CENTER", 0, 10)
            glass(em, 16, 0.03)
            em.ico = K.Glyph(em, 40, ns.MEDIA .. "icons\\bank", C.amber)
            em.ico:SetPoint("TOP", 0, -24)
            em.t = K.Title(em, 16, C.text, "CENTER")
            em.t:SetPoint("TOP", em.ico, "BOTTOM", 0, -12)
            em.t:SetText(L["The guild bank hasn't been read yet"])
            em.d = K.Text(em, 11, C.muted, "CENTER")
            em.d:SetPoint("TOP", em.t, "BOTTOM", 0, -8)
            em.d:SetWidth(400)
            em.d:SetWordWrap(true)
            em.d:SetText(L["WoW only provides the contents while someone is at the guild vault."])
            local steps = { "Open the guild vault in a capital city", "Click each tab once", "Oasis shares the status with the whole guild" }
            for i, st in ipairs(steps) do
                local n = K.Title(em, 12, C.amber, "CENTER")
                n:SetPoint("TOPLEFT", 70, -128 - (i - 1) * 24)
                n:SetWidth(16)
                n:SetText(i)
                local t = K.Text(em, 12, C.text)
                t:SetPoint("LEFT", n, "RIGHT", 10, 0)
                t:SetText(L[st])
            end
            p.homeEmpty = em
        end

        ----------------------------------------------------------------
        -- Fach-Ansicht
        ----------------------------------------------------------------
        p.grid = CreateFrame("Frame", nil, p)
        p.grid:SetPoint("TOPLEFT", 0, -40)
        p.grid:SetSize(COLS * CELL, 7 * CELL)
        p.cells = {}
        for i = 1, SLOTS do
            local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
            local c = CreateFrame("Button", nil, p.grid)
            c:SetSize(CELL - 3, CELL - 3)
            c:SetPoint("TOPLEFT", col * CELL, -row * CELL)
            glass(c, 6, 0.035)
            c.icon = K.Icon(c, CELL - 7, nil)
            c.icon:SetPoint("CENTER")
            c.count = K.Text(c, 11, C.text, "RIGHT")
            c.count:SetPoint("BOTTOMRIGHT", -2, 2)
            c.mark = c:CreateTexture(nil, "OVERLAY")
            c.mark:SetTexture(ns.MEDIA .. "dot")
            c.mark:SetSize(8, 8)
            c.mark:SetPoint("TOPRIGHT", -1, -1)
            c.mark:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
            c:RegisterForClicks("AnyUp")
            c:SetScript("OnClick", function(self, btn)
                if btn == "RightButton" then GameTooltip:Hide() cellMenu(self)
                elseif IsShiftKeyDown() and self.id then
                    local _, link = C_Item.GetItemInfo(self.id)
                    if link then ChatEdit_InsertLink(link) end
                end
            end)
            c:SetScript("OnEnter", cellTip)
            c:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.cells[i] = c
        end
        p.legend = K.Text(p, 10, C.dim)
        p.legend:SetPoint("TOPLEFT", p.grid, "BOTTOMLEFT", 0, -6)
        p.legend:SetText("|cffe8b44a●|r " .. L["wanted by the guild"] .. "     " .. L["Border color = quality"] .. "     " .. L["Shift-click: link  ·  Right-click: menu"])

        -- Seitenleiste rechts (Fach-Infos oder Suchtreffer)
        local side = CreateFrame("Frame", nil, p)
        glass(side, 14, 0.025)
        side:SetPoint("TOPLEFT", COLS * CELL + 14, -40)
        side:SetPoint("BOTTOMRIGHT", 0, 0)
        p.side = side
        p.sIcon = K.Icon(side, 28, nil)
        p.sIcon:SetPoint("TOPLEFT", 12, -12)
        p.sTitle = K.Title(side, 14, C.text)
        p.sTitle:SetPoint("TOPLEFT", 48, -12)
        p.sTitle:SetPoint("RIGHT", side, "RIGHT", -10, 0)
        p.sSub = K.Text(side, 11, C.muted)
        p.sSub:SetPoint("TOPLEFT", 48, -30)
        p.sBar = K.Bar(side, 200, 5)
        p.sBar:SetPoint("TOPLEFT", 12, -54)
        p.sBar:SetPoint("RIGHT", side, "RIGHT", -12, 0)
        p.sInfo = K.Text(side, 12, C.text)
        p.sInfo:SetPoint("TOPLEFT", 12, -66)
        p.sInfo:SetPoint("RIGHT", side, "RIGHT", -10, 0)
        p.sInfo:SetWordWrap(true)
        p.sInfo:SetJustifyV("TOP")
        local sh = K.Label(side, L["Most valuable here"])
        sh:SetPoint("TOPLEFT", 12, -118)
        p.sHead = sh
        p.sRows = {}
        for i = 1, 8 do
            local r = CreateFrame("Button", nil, side)
            r:SetHeight(22)
            r:SetPoint("TOPLEFT", 12, -136 - (i - 1) * 24)
            r:SetPoint("RIGHT", side, "RIGHT", -10, 0)
            hoverRow(r)
            r.icon = K.Icon(r, 18, nil)
            r.icon:SetPoint("LEFT", 2, 0)
            r.name = K.Text(r, 11, C.text)
            r.name:SetPoint("LEFT", 26, 0)
            r.name:SetPoint("RIGHT", r, "RIGHT", -60, 0)
            r.value = K.Text(r, 10, C.muted, "RIGHT")
            r.value:SetPoint("RIGHT", 0, 0)
            r:HookScript("OnEnter", cellTip)
            r:HookScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self) if self.jump then view = self.jump p.seg:Select(view) p.fresh = true ns.RefreshPage("bank") end end)
            p.sRows[i] = r
        end
        p.sStand = K.Text(side, 10, C.dim)
        p.sStand:SetPoint("BOTTOMLEFT", 12, 12)
        p.sStand:SetPoint("RIGHT", side, "RIGHT", -10, 0)
        p.sStand:SetWordWrap(true)

        ----------------------------------------------------------------
        -- Protokoll
        ----------------------------------------------------------------
        p.logSeg = K.Segments(p, { { key = "all", text = L["All"] }, { key = "items", text = L["Items"] },
            { key = "gold", text = L["Gold"] }, { key = "mine", text = L["Mine"] } }, function(k)
            logFilter = k
            ns.RefreshPage("bank")
        end, 70)
        p.logSeg:SetPoint("TOPLEFT", 0, -40)
        -- Start-Filter aus den Bereichs-Einstellungen (Standard: Alles)
        local lf = ns.db.settings.bankLogFilter
        if lf == "items" or lf == "gold" or lf == "mine" then logFilter = lf end
        p.logSeg:Select(logFilter)
        p.log = K.List(p, 30, function(l)
            local r = K.Row(l)
            r:Col("when", 10, 80, 11, C.dim)
            r:Col("who", 92, 110, 12)
            r:Col("act", 204, 96, 12)
            r.icon = K.Icon(r, 20, nil)
            r.icon:SetPoint("LEFT", 302, 0)
            r:Col("what", 328, 260, 12)
            r:Col("tab", 0, 120, 11, C.muted, "RIGHT")
            r.cols.tab:ClearAllPoints()
            r.cols.tab:SetPoint("RIGHT", -8, 0)
            r:SetScript("OnEnter", function(self)
                if self.item and self.item.id and self.item.id > 0 then
                    self.id, self.qty = self.item.id, self.item.count
                    cellTip(self)
                end
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, e)
            r.cols.when:SetText(ns.ago(e.ts))
            r.cols.who:SetText(ns.Radar.Colored(ns.fullName(e.who)))
            local a = ACTIONS[e.typ] or { e.typ, C.muted }
            r.cols.act:SetText(K.hex(a[2]) .. L[a[1]] .. "|r")
            if e.money then
                r.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
                local sign = (e.typ == "deposit" or e.typ == "depositSummary") and "|cff66db9e+|r " or "|cffe8b44a-|r "
                r.cols.what:SetText(sign .. money(e.count))
                r.cols.tab:SetText(L["Gold"])
            else
                r.icon:SetTexture(C_Item.GetItemIconByID(e.id or 0) or 134400)
                local qc = qualityColor(e.id or 0)
                local hex = qc and ("|cff%02x%02x%02x"):format(math.floor(qc[1] * 255), math.floor(qc[2] * 255), math.floor(qc[3] * 255)) or ""
                r.cols.what:SetText((e.count or 1) .. "x " .. hex .. itemName(e.id or 0) .. (hex ~= "" and "|r" or ""))
                r.cols.tab:SetText((e.tab or "") .. (e.tab2 and (" > " .. e.tab2) or ""))
            end
        end)
        p.log:SetPoint("TOPLEFT", 0, -72)
        p.log:SetPoint("BOTTOMRIGHT")
        p.log.empty:SetText(L["No log yet. It is read when someone with Oasis opens the bank."])
    end,

    refresh = function(p)
        local tabs = Bank.Tabs()
        -- Reiter: Uebersicht, Faecher (mit Symbol), Protokoll
        local key = ""
        for _, t in ipairs(tabs) do key = key .. t.n .. (t.name or "") end
        if key ~= p.segKey then
            p.segKey = key
            if view ~= "log" and view ~= "home" and not Bank.Tab(view) then view = "home" end
            -- erst mit Namen versuchen; passt es nicht neben das Suchfeld, nur Symbole (Name als Tooltip)
            local room = (p:GetWidth() or 0) > 0 and (p:GetWidth() - (p.search:GetWidth() or 200) - 16) or 530
            for _, iconsOnly in ipairs({ false, true }) do
                if p.seg then p.seg:Hide() end
                local items = { { key = "home", text = L["Overview"] } }
                for _, t in ipairs(tabs) do
                    local hasIcon = t.icon and t.icon ~= 0
                    local icon = hasIcon and ("|T" .. t.icon .. ":16:16:0:0:64:64:6:58:6:58|t") or ""
                    local name = t.name or ("Fach " .. t.n)
                    items[#items + 1] = { key = t.n, text = (iconsOnly and hasIcon) and icon or (icon .. (hasIcon and " " or "") .. name), tip = name }
                end
                items[#items + 1] = { key = "log", text = L["Log"] }
                p.seg = K.Segments(p.segHolder, items, function(k) view = k p.fresh = true ns.RefreshPage("bank") end)
                p.seg:SetPoint("LEFT")
                p.seg:Select(view)
                if iconsOnly then
                    for i, b in ipairs(p.seg.buttons) do
                        local tip = items[i].tip
                        if tip then
                            b:HookScript("OnEnter", function(self) K.ShowTip(self, tip) end)
                            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
                        end
                    end
                end
                if (p.seg:GetWidth() or 0) <= room then break end
            end
        end
        local isHome, isLog = view == "home", view == "log"
        local isTab = not isHome and not isLog
        p.home:SetShown(isHome and search == "")
        p.grid:SetShown(isTab or (isHome and search ~= ""))
        p.legend:SetShown(isTab)
        p.side:SetShown(isTab or (isHome and search ~= ""))
        p.log:SetShown(isLog)
        p.logSeg:SetShown(isLog)
        p.search:SetShown(not isLog)

        local amount = Bank.Money()
        local wanted = wantedSet()

        -- Uebersicht
        if isHome and search == "" then
            local allItems = Bank.AllItems()
            local used, slots, worth = 0, 0, 0
            for _, t in ipairs(tabs) do
                local u, w = Bank.TabStats(t)
                used, slots, worth = used + u, slots + SLOTS, worth + w
            end
            local stacks = 0
            for _, e in ipairs(allItems) do stacks = stacks + e.count end
            p.cards[1]:Set(amount and money(amount) or "–")
            if p.fresh and stacks > 0 and animOn() then
                K.CountUp(p.cards[2].value, stacks, 0.6, function(v) return math.floor(v + 0.5) .. " |cff888888(" .. #allItems .. " " .. L["kinds"] .. ")|r" end)
            else
                p.cards[2]:Set(stacks > 0 and (stacks .. " |cff888888(" .. #allItems .. " " .. L["kinds"] .. ")|r") or "–")
            end
            p.cards[3]:Set(slots > 0 and (used .. " |cff888888/ " .. slots .. "|r") or "–")
            p.cards[4]:Set(worth > 0 and ("~" .. ns.Market.Format(worth)) or "–")
            if ns.Trade and p.worthSpark then
                if worth > 0 then pcall(ns.Trade.RecordBankWorth, worth) end
                local hist, week = ns.Trade.BankHistory(30)
                p.worthSpark:SetValues(hist)
                p.cards[4].label:SetText(L["Market value"] .. ((week and worth > 0) and ("  " .. ns.Trade.Signed(worth - week) .. " |cff777777" .. L["7 d"] .. "|r") or ""))
            end
            for i, r in ipairs(p.tabRows) do
                local t = tabs[i]
                if t then
                    local u, w = Bank.TabStats(t)
                    r.n = t.n
                    r.icon:SetTexture((t.icon and t.icon ~= 0) and t.icon or 134400)
                    r.name:SetText(t.name or ("Fach " .. t.n))
                    if p.fresh and animOn() and K.Tween then
                        local tgt = u / SLOTS
                        r.bar:Set(0.001)
                        K.Tween(r.bar, 0.5, function(t) r.bar:Set(tgt * t) end, function() r.bar:Set(tgt) end, i * 0.05)
                    else
                        r.bar:Set(u / SLOTS)
                    end
                    local fc = (u / SLOTS) >= 0.9 and C.red or ((u / SLOTS) >= 0.75 and C.amber or C.mint)
                    r.bar.fill:SetColorTexture(fc[1], fc[2], fc[3], 0.85)
                    r.fill:SetText(u .. " / " .. SLOTS)
                    r.value:SetText(w > 0 and ("~" .. ns.Market.Format(w)) or "")
                    r:Show()
                else
                    r:Hide()
                end
            end
            -- wertvollste bzw. von der Gilde gesuchte Items
            local val = {}
            local nWanted = 0
            for _, e in ipairs(allItems) do
                if wanted[e.id] then nWanted = nWanted + 1 end
                if valMode == "wanted" then
                    if wanted[e.id] then val[#val + 1] = { id = e.id, count = e.count, who = wanted[e.id], tabs = e.tabs } end
                else
                    local pr = priceOf(e.id)
                    if pr then val[#val + 1] = { id = e.id, count = e.count, worth = pr * e.count, tabs = e.tabs } end
                end
            end
            if valMode == "wanted" then table.sort(val, function(a, b) return #a.who > #b.who end)
            else table.sort(val, function(a, b) return a.worth > b.worth end) end
            p.valSeg:Select(valMode)
            p.valSeg.buttons[2].label:SetText(nWanted > 0 and (L["Wanted"] .. "  |cffe8b44a" .. nWanted .. "|r") or L["Wanted"])
            for i, r in ipairs(p.valRows) do
                local v = val[i]
                if v then
                    r.id, r.qty, r.wanted = v.id, v.count, v.who
                    r.jump = nil
                    for n in pairs(v.tabs or {}) do r.jump = r.jump and math.min(r.jump, n) or n end
                    r.rank:SetText(i)
                    local mc = MEDAL[i] or C.dim
                    r.rank:SetTextColor(mc[1], mc[2], mc[3])
                    r.icon:SetTexture(C_Item.GetItemIconByID(v.id) or 134400)
                    local qc = qualityColor(v.id)
                    local hex = qc and ("|cff%02x%02x%02x"):format(qc[1] * 255, qc[2] * 255, qc[3] * 255) or "|cffffffff"
                    r.name:SetText("|cff888888" .. v.count .. "x|r " .. hex .. itemName(v.id) .. "|r")
                    if valMode == "wanted" then
                        r.value:SetText("|cffe8b44a" .. ((#v.who == 1) and ns.displayName(v.who[1]) or (L["%d looking"]):format(#v.who)) .. "|r")
                    else
                        r.value:SetText("~" .. ns.Market.Format(v.worth))
                    end
                    r:Show()
                    if p.fresh and K.FadeIn then r.oasisFadedAt = nil K.FadeIn(r, i * 0.04) end
                else
                    r:Hide()
                end
            end
            p.valEmpty:SetText(valMode == "wanted" and L["Nothing in the bank is on a wanted list right now."] or L["Prices come from Midas or Oasis' own auction house tracking."])
            p.valEmpty:SetShown(#val == 0)
            local tdays = tonumber(ns.GuildOpt("gbTopDay")) or 7
            if p.contribPanel and p.contribPanel.head and p.contribPanel.head.SetText then
                p.contribPanel.head:SetText(tdays == 7 and L["Top donors (7 days)"] or (L["Top donors (%d days)"]):format(tdays))
            end
            local contrib = Bank.Contributors(tdays)
            p.contrib.empty:SetText(tdays == 7 and L["Nobody has deposited anything this week."] or (L["Nobody has deposited in the last %d days."]):format(tdays))
            local top = 0
            for _, w in ipairs(contrib) do top = math.max(top, w.items + w.gold / 10000) end
            for i, w in ipairs(contrib) do w.rank = i w.share = top > 0 and ((w.items + w.gold / 10000) / top) or 0 end
            p.contrib:SetData(contrib)
            local rec = {}
            for i, e in ipairs(Bank.Log()) do if i > 12 then break end rec[i] = e end
            p.recent:SetData(rec)
            local hasData = #tabs > 0 or #rec > 0
            p.homeEmpty:SetShown(not hasData)
            for _, f in ipairs(p.cards) do f:SetShown(hasData) end
            for _, f in ipairs(p.homePanels) do f:SetShown(hasData) end
            p.homePanels[1].count:SetText(#tabs > 0 and ((#tabs == 1) and L["1 slot"] or (L["%d slots"]):format(#tabs)) or "")
            p.fresh = nil
            return
        end

        if isLog then
            local me = ns.short(ns.me())
            local list = {}
            for _, e in ipairs(Bank.Log()) do
                local ok = logFilter == "all" or (logFilter == "gold" and e.money) or (logFilter == "items" and not e.money)
                    or (logFilter == "mine" and (ns.isMe(e.who) or ns.SameName(e.who, me)))
                if ok then list[#list + 1] = e end
            end
            p.log:SetData(list)
            return
        end

        -- Fach-Ansicht oder Suche ueber alle Faecher
        local tab = isTab and Bank.Tab(view) or nil
        local items = tab and Bank.Items(tab) or {}
        local results = search ~= "" and Bank.Search(search) or nil
        local hitSet = {}
        if results then for _, e in ipairs(results) do hitSet[e.id] = true end end
        for i, c in ipairs(p.cells) do
            local it = items[i]
            if it then
                c.id, c.qty, c.wanted = it.id, it.count, wanted[it.id]
                c.icon:SetTexture(C_Item.GetItemIconByID(it.id) or 134400)
                c.icon:Show()
                c.count:SetText(it.count > 1 and it.count or "")
                c.mark:SetShown(wanted[it.id] ~= nil)
                local match = not results or hitSet[it.id]
                c:SetAlpha(match and 1 or 0.2)
                local qc = qualityColor(it.id)
                local lc = (results and match) and C.accent or qc
                glass(c, 6, 0.05, lc and { lc[1], lc[2], lc[3], 0.75 } or nil)
            else
                c.id, c.qty, c.wanted = nil, nil, nil
                c.icon:Hide()
                c.count:SetText("")
                c.mark:Hide()
                c:SetAlpha((results or not tab) and 0.25 or 0.6)
                glass(c, 6, 0.02, { 1, 1, 1, 0.06 })
            end
        end

        if p.fresh and animOn() and K.FadeIn then p.grid.oasisFadedAt = nil K.FadeIn(p.grid, 0) end
        p.fresh = nil
        for _, r in ipairs(p.sRows) do r:Hide() end
        if results then
            p.sIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
            p.sTitle:SetText((L["%d matches"]):format(#results))
            p.sSub:SetText(L["in all tabs"])
            p.sBar:Hide()
            p.sInfo:SetText(#results == 0 and L["Nothing found."] or L["Click a result to jump to its tab"])
            p.sHead:SetText(L["Results"])
            local names = {}
            for _, t in ipairs(tabs) do names[t.n] = t.name end
            for i, e in ipairs(results) do
                local r = p.sRows[i]
                if not r then break end
                local where, first = {}, nil
                for n, cnt in pairs(e.tabs) do where[#where + 1] = (names[n] or n) first = first or n end
                r.id, r.qty, r.jump = e.id, e.count, first
                r.icon:SetTexture(C_Item.GetItemIconByID(e.id) or 134400)
                r.name:SetText(e.count .. "x " .. itemName(e.id))
                r.value:SetText("|cff888888" .. table.concat(where, ", ") .. "|r")
                r:Show()
            end
            p.sStand:SetText("")
            return
        end
        p.sBar:Show()
        p.sHead:SetText(L["Most valuable here"])
        if tab then
            local used, worth, priced = Bank.TabStats(tab)
            p.sIcon:SetTexture((tab.icon and tab.icon ~= 0) and tab.icon or 134400)
            p.sTitle:SetText(tab.name or ("Fach " .. tab.n))
            p.sSub:SetText((L["%d of %d slots used"]):format(used, SLOTS))
            p.sBar:Set(used / SLOTS)
            local nWanted = 0
            for _, it in pairs(items) do if wanted[it.id] then nWanted = nWanted + 1 end end
            local info = {}
            if priced > 0 then info[#info + 1] = L["Market value ~"] .. ns.Market.Format(worth) end
            if nWanted > 0 then info[#info + 1] = "|cffe8b44a" .. (L["%d items here are wanted"]):format(nWanted) .. "|r" end
            p.sInfo:SetText(table.concat(info, "\n"))
            local val = {}
            for _, it in pairs(items) do val[#val + 1] = { id = it.id, count = it.count, worth = (priceOf(it.id) or 0) * it.count } end
            table.sort(val, function(a, b) if a.worth ~= b.worth then return a.worth > b.worth end return a.count > b.count end)
            for i, r in ipairs(p.sRows) do
                local v = val[i]
                if v then
                    r.id, r.qty, r.jump = v.id, v.count, nil
                    r.icon:SetTexture(C_Item.GetItemIconByID(v.id) or 134400)
                    r.name:SetText(v.count .. "x " .. itemName(v.id))
                    r.value:SetText(v.worth > 0 and ("~" .. ns.Market.Format(v.worth)) or "")
                    r:Show()
                end
            end
            p.sStand:SetText(L["As of: "] .. ns.ago(tab.ts) .. "  ·  " .. (L["by %s"]):format(ns.displayName(tab.who or "?")))
        else
            p.sTitle:SetText(L["never read"])
            p.sSub:SetText("")
            p.sInfo:SetText("")
            p.sStand:SetText(L["The bank updates whenever someone with Oasis opens the guild vault."])
        end
    end,
})

ns.Listen("STORE", function(coll)
    if coll == "bank" or coll == "banklog" then ns.RefreshPage("bank") end
end)
end)

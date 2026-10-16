-- Oasis: Einkaufsliste der Gilde + "Wer braucht was"-Tooltip
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

local Wants = {}
ns.Wants = Wants

-- Gilden-Optionen (Gildenleitung)
ns.GuildOption({ page = "wants", key = "wnOffMod", default = true, lead = true, label = "Offiziere entfernen fremde Wuensche",
    desc = "Offiziere duerfen Eintraege anderer Mitglieder von der Gesucht-Liste loeschen" })
ns.GuildOption({ page = "wants", key = "wnLootCd", default = 5, min = 1, max = 60, step = 1, label = "Loot-Hinweis hoechstens alle",
    desc = "Abstand, bevor derselbe Wunsch beim Looten erneut gemeldet wird",
    fmt = function(v) return v .. " Min" end })

------------------------------------------------------------------------
-- Daten
------------------------------------------------------------------------
function Wants.All()
    return Store.List("wants")
end
function Wants.ForItem(itemID, name)
    local out = {}
    for _, w in ipairs(Wants.All()) do
        if (itemID and w.itemID == itemID) or (name and w.name == name) then out[#out + 1] = w end
    end
    return out
end
function Wants.Count(itemID)
    if not itemID or itemID == 0 then return 0 end
    local ok, n = pcall(C_Item.GetItemCount, itemID, true)
    return ok and ns.safe(n) or 0
end

-- Eintrag aus Link oder Name
function Wants.Add(text, qty, note, extra)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    local itemID = ns.itemID(text)
    local name = text:match("%[(.-)%]")
    if not itemID then
        local n, link = C_Item.GetItemInfo(text)
        if n then itemID, name = ns.itemID(link), n end
    end
    -- nur Name getippt: in den bekannten Items nachschlagen
    if not itemID and ns.ItemSearch then
        local id, n = ns.ItemSearch.ExactID(text)
        if id then itemID, name = id, n end
    end
    name = name or text
    local rec = {
        id = ns.newId("want"), itemID = itemID or 0, name = name, qty = qty or 1, note = note or "",
        who = ns.me(), created = ns.now(),
    }
    for k, v in pairs(extra or {}) do rec[k] = v end
    rec = Store.Put("wants", rec)
    if itemID then
        ns.withItem(itemID, function(link)
            local r = Store.Get("wants", rec.id)
            if r and not r.link then
                local copy = {}
                for k, v in pairs(r) do copy[k] = v end
                copy.link = link
                Store.Put("wants", copy)
            end
        end)
    end
    return rec
end

function Wants.Offer(w)
    -- zaehlt nur einmal pro Wunsch und nicht fuer eigene Wuensche
    ns.db.helpedSeen = ns.db.helpedSeen or {}
    if ns.Badges and not ns.isMe(w.who) and not ns.db.helpedSeen[w.id] then
        ns.db.helpedSeen[w.id] = true
        ns.Badges.Add("helped", 1)
    end
    local have = Wants.Count(w.itemID)
    Comm.Whisper(w.who, "HAVE", w.id, w.name or "?", have)
    K.Toast(L["Angebot geschickt"], ns.displayName(w.who) .. L[" bekommt Bescheid."], C.mint)
end
Comm.On("HAVE", function(sender, _, id, name, have)
    have = SEC.Num(have, 0, 100000, true) or 0
    -- nur fuer einen eigenen, offenen Wunsch; Name aus dem eigenen Datensatz; je Absender gedrosselt
    local w = type(id) == "string" and Store.Get("wants", id)
    if not w or w.del or not ns.isMe(w.who) then return end
    if not SEC.Rate("have:" .. sender .. ":" .. id, 60) then return end
    name = w.name or SEC.Text(name, 60)
    ns.Sound.Next("wants")
    K.Toast(ns.displayName(sender) .. L[" hat "] .. (name or "?") .. L[" fuer dich"],
        (have > 0 and (have .. L[" Stueck in den Taschen"]) or L["meldet sich bei dir"]) .. L["  -  Klick zum Anfluestern"], C.mint,
        function() ns.Whisper(sender) end)
end)

------------------------------------------------------------------------
-- Hinweis beim Looten: jemand sucht genau das
------------------------------------------------------------------------
local notified = {}
ns.On("CHAT_MSG_LOOT", function(text, playerName)
    text, playerName = ns.safe(text), ns.safe(playerName)
    if not text then return end
    if playerName and playerName ~= "" and ns.short(playerName) ~= ns.short(ns.me()) then return end
    local id = tonumber(text:match("|Hitem:(%d+)"))
    if not id or ns.db.settings.wantsLootHint == false then return end
    for _, w in ipairs(Wants.ForItem(id)) do
        if not ns.isMe(w.who) and (not notified[w.id] or GetTime() - notified[w.id] > (tonumber(ns.GuildOpt("wnLootCd")) or 5) * 60) then
            notified[w.id] = GetTime()
            ns.Sound.Next("wants")
            K.Toast(ns.displayName(w.who) .. L[" sucht das!"], (tonumber(w.qty) or 1) .. L["x "] .. SEC.Text(w.name or "?", 60) .. L["  -  Klick: Bescheid sagen"], C.amber,
                function() Wants.Offer(w) end)
        end
    end
end)

local function updateBadge()
    local n = 0
    for _, w in ipairs(Wants.All()) do
        if not ns.isMe(w.who) and Wants.Count(w.itemID) > 0 then n = n + 1 end
    end
    if ns.db.settings.wantsBadge == false then n = 0 end
    ns.SetNavBadge("wants", n > 0 and tostring(n) or "")
end
Wants.UpdateBadge = updateBadge
ns.On("BAG_UPDATE_DELAYED", function() ns.Debounce("wantsStore", 0.4, function() updateBadge() ns.RefreshPage("wants") end) end)
ns.Listen("STORE", function(coll, rec, old)
    if coll ~= "wants" then return end
    if not old and not rec.del and not ns.isMe(rec.who) and ns.db.settings.wantsBagHint ~= false and Wants.Count(rec.itemID) > 0 then
        ns.Sound.Next("wants")
        K.Toast(ns.displayName(rec.who) .. L[" sucht "] .. (rec.name or "?"), L["Du hast "] .. Wants.Count(rec.itemID) .. L[" davon in den Taschen"], C.amber,
            function() ns.ShowPage("wants") end)
    end
    ns.Debounce("wantsStore", 0.4, function() updateBadge() ns.RefreshPage("wants") end)
end)

------------------------------------------------------------------------
-- Tooltip: Gesucht von / offene Auftraege / herstellbar von
------------------------------------------------------------------------
-- Zeilen je Item zwischenspeichern (Performance 0.5.482: Tooltips werden ~5x/s neu aufgebaut, vorher jedes Mal
-- volle Scans von Wunschliste, Auftraegen und Gildenbank). Geleert bei Aenderungen und spaetestens nach 10 s.
local tipCache, tipCacheT = {}, 0
local TIP_COLLS = { wants = true, orders = true, bank = true, prices = true }
ns.Listen("STORE", function(coll) if TIP_COLLS[coll] then tipCache = {} end end)
local buildLines
local function addOasisLines(tt, itemID)
    if not itemID or not ns.db then return end
    local st = ns.db.settings
    if st.tipOasis == false then return end
    if GetTime() - tipCacheT > 10 then tipCache, tipCacheT = {}, GetTime() end
    local lines = tipCache[itemID]
    if not lines then
        lines = buildLines(itemID, st)
        tipCache[itemID] = lines
    end
    if #lines == 0 then return end
    tt:AddLine(" ")   -- 0.5.869: nur Abstand, keine rote "Oasis"-Ueberschrift mehr (wirkte im Tooltip wie eine Warnung)
    for _, l in ipairs(lines) do tt:AddLine(l, 0.9, 0.88, 1, true) end
end
function buildLines(itemID, st)
    local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
    name = ns.safe(name)
    local lines = {}
    local wants = Wants.ForItem(itemID, name)
    if #wants > 0 and st.tipWanted ~= false then
        local t = {}
        for i = 1, math.min(4, #wants) do
            local w = wants[i]
            t[#t + 1] = ns.Radar.Label(w.who) .. " |cffffc24d" .. (w.qty or 1) .. L["x|r"]
        end
        if #wants > 4 then t[#t + 1] = "+" .. (#wants - 4) end
        lines[#lines + 1] = L["|cffffc24dGesucht von:|r "] .. table.concat(t, ", ")
    end
    if name then
        local orders = {}
        for _, o in ipairs(Store.List("orders")) do
            local hit = (o.item and o.item ~= 0 and o.item == itemID) or (ns.Crafting and ns.Crafting.OrderName(o) == name)
            if hit and (o.status == "open" or o.status == "accepted") then orders[#orders + 1] = o end
        end
        for i = 1, math.min(3, #orders) do
            local o = orders[i]
            lines[#lines + 1] = L["|cff4f86ffAuftrag:|r "] .. ns.Radar.Label(o.from) .. L[" moechte "] .. (o.qty or 1) .. "x" ..
                (o.status == "accepted" and (L[" |cff888888("] .. ns.displayName(o.worker or "?") .. L[" baut)|r"]) or "")
        end
    end
    if ns.Market and not ns.Market.HasMidas() then
        local p = ns.Market.Price(itemID)
        if p then lines[#lines + 1] = "|cffe8b44a" .. L["Gilden-Preis:"] .. "|r ~" .. ns.Market.Format(p) end
    end
    local bank = ns.GuildBank and ns.GuildBank.Count(itemID) or 0
    if bank > 0 and st.tipBank ~= false then lines[#lines + 1] = "|cff9b8cff" .. L["In der Gildenbank:"] .. "|r " .. bank end
    local src = ns.Dungeons and ns.Dungeons.TooltipLine(itemID)
    if src then lines[#lines + 1] = "|cff888888" .. src .. "|r" end
    if ns.Crafting and st.tipCrafters ~= false then
        local e = ns.Crafting.ForItem(itemID, name)
        if e then lines[#lines + 1] = L["|cff4df2b8Herstellbar von:|r "] .. ns.Crafting.CrafterText(e, 4) end
    end
    return lines
end
Wants.addOasisLines = addOasisLines
function Wants.TipCacheReset() tipCache = {} end

local function hookTooltips()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
            if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
            local ok, e = pcall(function()
                local id = data and ns.safe(data.id)
                if not id and tt.GetItem then
                    local _, link = tt:GetItem()
                    id = ns.itemID(ns.safe(link))
                end
                addOasisLines(tt, id)
            end)
            if not ok then ns.err("Tooltip", e) end
        end)
    else
        for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
            pcall(tt.HookScript, tt, "OnTooltipSetItem", function(self)
                local _, link = self:GetItem()
                addOasisLines(self, ns.itemID(ns.safe(link)))
            end)
        end
    end
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local filter = "all"
local formQty = 1

-- Woher bekommt man ein Item? (fuer Zeile, Filter und Knoepfe)
function Wants.Sources(w)
    local id = w.itemID and w.itemID > 0 and w.itemID or nil
    local s = { have = Wants.Count(id), bank = id and ns.GuildBank and ns.GuildBank.Count(id) or 0 }
    if ns.Crafting and (id or w.name) then
        local e = ns.Crafting.ForItem(id, w.name)
        if e then
            s.recipe = e
            s.crafters = ns.Crafting.CraftersOf(e)
            s.iCanCraft = ns.Crafting.CanCraft(ns.me(), e.name, e.id)
        end
    end
    s.price = id and ns.Market and ns.Market.Price(id) or nil
    s.dungeon = id and ns.Dungeons and ns.Dungeons.TooltipLine(id) or nil
    return s
end


------------------------------------------------------------------------
-- Optik (wie Questitems/Chronik/Gildeninfo): Kacheln, Reiter, Karten
------------------------------------------------------------------------
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local EMBER = ns.MEDIA .. "ember"
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
local ICO = ns.MEDIA .. "icons\\"
local NOICON = 134400
local QCOL = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 0.78, 0.78, 0.80 }, [2] = { 0.12, 1, 0 }, [3] = { 0.1, 0.5, 0.95 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 } }
local PURPLE = C.purple or { 0.62, 0.55, 1 }
local H_HEAD, H_CARD, H_SLIM, GAP = 30, 70, 54, 6
local TABS = {
    { key = "all", text = "Alle", glyph = "wants", color = C.accent },
    { key = "deliver", text = "Kann ich liefern", glyph = "heart", color = C.mint },
    { key = "bank", text = "In der Bank", glyph = "bank", color = PURPLE },
    { key = "craft", text = "Herstellbar", glyph = "crafting", color = C.blue },
    { key = "mine", text = "Meine", glyph = "profile", color = C.amber },
}
local TILES = {
    { key = "all", label = "Wunschliste", glyph = "wants", color = C.accent, tip = "Klick: alle Wuensche" },
    { key = "deliver", label = "Kann ich liefern", glyph = "heart", color = C.mint, tip = "Klick: was du hast oder bauen kannst" },
    { key = "bank", label = "In der Bank", glyph = "bank", color = PURPLE, tip = "Klick: liegt in der Gildenbank" },
    { key = "craft", label = "Herstellbar", glyph = "crafting", color = C.blue, tip = "Klick: kann jemand in der Gilde bauen" },
}
local GROUPS = {
    { key = "deliver", label = "Kannst du liefern", color = C.mint },
    { key = "bank", label = "In der Gildenbank", color = PURPLE },
    { key = "craft", label = "Herstellbar", color = C.blue },
    { key = "rest", label = "Rest", color = C.muted },
}
local SORTS = { { key = "new", text = "Neueste" }, { key = "price", text = "Preisangebot" }, { key = "qty", text = "Menge" }, { key = "name", text = "Name" } }
local search, sortBy = "", "new"
local page, flashKey

local function S() return ns.db.settings end
local function animOn() return not S().noAnim end
-- Glas 2026: ruhige Flaeche + feine Kante (Kante optional in Farbe)
local GLINE = { 1, 1, 1, 0.10 }
local function glass(f, r, a, line)
    local IG = ns.Insta
    if IG and IG.Glass then IG.Glass(f, { 1, 1, 1, a or 0.03 }, line or GLINE, r or 12) return true end
end
local function low(s) return s and tostring(s):lower() or "" end
local function api(t, f) return t ~= nil and type(t[f]) == "function" end
local function gradient(tex, dir, c, a1, a2, fb)
    if not K.Gradient(tex, dir, { c[1], c[2], c[3], a1 }, { c[1], c[2], c[3], a2 }) then
        tex:SetColorTexture(c[1], c[2], c[3], fb or (a1 + a2) / 2)
    end
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
local function setClassIcon(tex, class)
    if ns.GuildInfo and ns.GuildInfo.SetClassIcon then
        local ok, r = pcall(ns.GuildInfo.SetClassIcon, tex, class)
        if ok and r then return true end
    end
    local tc = type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not tc then return false end
    tex:SetTexture(CLASS_SHEET)
    tex:SetTexCoord(tc[1] + 0.015, tc[2] - 0.015, tc[3] + 0.015, tc[4] - 0.015)
    return true
end
local function plain(s)
    return (tostring(s or ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("[%[%]]", ""))
end
local function colored(who)
    if ns.Radar and ns.Radar.Colored then
        local ok, s = pcall(ns.Radar.Colored, who)
        if ok and s then return s end
    end
    return ns.displayName(who)
end
local function isDemo(w) return type(w.id) == "string" and w.id:find("^demo") ~= nil end

-- Item-Daten (fehlende beim Client anfordern; GET_ITEM_INFO_RECEIVED laedt nach)
local requested = {}
local function request(id)
    if id and not requested[id] and C_Item and api(C_Item, "RequestLoadItemDataByID") then
        requested[id] = true
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end
local function iconOf(id)
    if not id or not C_Item or not api(C_Item, "GetItemIconByID") then return nil end
    local ok, t = pcall(C_Item.GetItemIconByID, id)
    t = ok and ns.safe(t) or nil
    if not t or t == NOICON then request(id) return nil end
    return t
end
local function qualityOf(id)
    if not id or not C_Item or not api(C_Item, "GetItemQualityByID") then return nil end
    local ok, q = pcall(C_Item.GetItemQualityByID, id)
    q = ok and tonumber(ns.safe(q)) or nil
    if not q then request(id) end
    return q
end
local function linkItem(w)
    local l = w.link or ((w.itemID or 0) > 0 and ns.ItemSearch and ns.ItemSearch.Link(w.itemID)) or ("[" .. (w.name or "?") .. "]")
    if ChatEdit_InsertLink then
        local ok, r = pcall(ChatEdit_InsertLink, l)
        if ok and r then return true end
    end
    if ns.OpenChat then ns.OpenChat(l) end
end

------------------------------------------------------------------------
-- Aktionen (Demo-Eintraege fluestern niemanden an)
------------------------------------------------------------------------
local function offer(w)
    if isDemo(w) then ns.print((L["Demo: wuerde %s Bescheid sagen."]):format(ns.displayName(w.who))) return end
    Wants.Offer(w)
end
local function whisper(w, who)
    who = who or w.who
    if isDemo(w) then ns.print((L["Demo: wuerde %s anfluestern."]):format(ns.displayName(who))) return end
    ns.Whisper(who)
end
local function order(w, s)
    local e = s.recipe
    if not (e and ns.Crafting) then return end
    if isDemo(w) then ns.print(L["Demo: Auftrag wuerde gesendet."]) return end
    ns.Crafting.NewOrder(e.name, e.prof, nil, w.qty or 1, L["fuer meine Gesucht-Liste"], e.id, e.itemID)
    K.Toast(L["Auftrag gesendet"], (w.qty or 1) .. "x " .. e.name, C.accent)
end
local function done(w)
    Store.Delete("wants", w.id)
    K.Toast(L["Abgehakt!"], w.name or "?", C.mint)
end
local function canDelete(w)
    return ns.isMe(w.who) or (ns.isOfficer() and ns.GuildOpt("wnOffMod") ~= false)
end

------------------------------------------------------------------------
-- Bausteine
------------------------------------------------------------------------
local function emptyState(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(360, 120)
    f.halo = f:CreateTexture(nil, "BACKGROUND")
    f.halo:SetTexture(EMBER)
    f.halo:SetBlendMode("ADD")
    f.halo:SetSize(90, 90)
    f.halo:SetPoint("TOP", 0, 18)
    f.halo:SetAlpha(0)
    f.halo:Hide()
    f.disc = f:CreateTexture(nil, "BORDER")
    f.disc:SetTexture(CIRCLE)
    f.disc:SetSize(44, 44)
    f.disc:SetPoint("TOP", 0, -5)
    f.icon = K.Glyph(f, 22, ICO .. "wants", C.amber)
    f.icon:SetPoint("CENTER", f.disc)
    f.text = K.Text(f, 13, C.muted, "CENTER")
    f.text:SetPoint("TOP", f.disc, "BOTTOM", 0, -10)
    f.text:SetWidth(350)
    f.text:SetWordWrap(true)
    f.btn = K.Button(f, "", 150, 24, "ghost")
    f.btn2 = K.Button(f, "", 110, 24, "ghost")
    function f:Set(glyph, color, msg, b1, fn1, b2, fn2)
        self.icon:SetTexture(ICO .. glyph)
        self.icon:SetVertexColor(color[1], color[2], color[3])
        self.disc:SetVertexColor(color[1] * 0.18, color[2] * 0.18, color[3] * 0.18)
        self.text:SetText(msg)
        self.btn:SetShown(b1 ~= nil)
        self.btn2:SetShown(b2 ~= nil)
        self.btn:ClearAllPoints()
        self.btn2:ClearAllPoints()
        if b1 then
            self.btn:SetLabel(b1)
            self.btn:SetWidth(math.max(110, (self.btn.label:GetStringWidth() or 0) + 26))
            self.btn:SetScript("OnClick", fn1)
        end
        if b2 then
            self.btn2:SetLabel(b2)
            self.btn2:SetWidth(math.max(90, (self.btn2.label:GetStringWidth() or 0) + 26))
            self.btn2:SetScript("OnClick", fn2)
            self.btn:SetPoint("TOPRIGHT", self.text, "BOTTOM", -4, -12)
            self.btn2:SetPoint("TOPLEFT", self.text, "BOTTOM", 4, -12)
        else
            self.btn:SetPoint("TOP", self.text, "BOTTOM", 0, -12)
        end
    end
    f:Hide()
    return f
end

-- Reiterleiste: Symbol + Text + Zaehler, gleitender Balken in der Reiterfarbe
local function buildTabs(p, onPick)
    local f = CreateFrame("Frame", nil, p)
    f:SetHeight(34)
    f.maxW = 480
    f.buttons = {}
    for i, d in ipairs(TABS) do
        local b = CreateFrame("Button", nil, f)
        b.key, b.color = d.key, d.color
        b.hov = b:CreateTexture(nil, "BACKGROUND")
        b.hov:SetAllPoints()
        b.hov:SetColorTexture(1, 1, 1, 0.03)
        b.hov:SetAlpha(0)
        b.ico = K.Glyph(b, 14, ICO .. d.glyph, C.muted)
        b.label = K.Text(b, 13, C.muted)
        b.label:SetText(L[d.text])
        b.count = K.Text(b, 10, C.dim)
        b:SetScript("OnClick", function() onPick(d.key) end)
        b:SetScript("OnEnter", function(self)
            self.hov:SetAlpha(1)
            if f.value ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end
        end)
        b:SetScript("OnLeave", function(self)
            self.hov:SetAlpha(0)
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
        local W = self.maxW or 480
        local nat, sum, withIcon = {}, 0, true
        for pass = 1, 2 do
            sum = 0
            for i, b in ipairs(self.buttons) do
                local cw = (b.count:GetText() or "") ~= "" and ((b.count:GetStringWidth() or 0) + 5) or 0
                nat[i] = (withIcon and 19 or 0) + (b.label:GetStringWidth() or 0) + cw + 22
                sum = sum + nat[i]
            end
            if pass == 1 and sum > W then withIcon = false else break end
        end
        local scale = math.min(1, W / math.max(1, sum))
        local x = 0
        for i, b in ipairs(self.buttons) do
            local bw = math.max(40, math.floor(nat[i] * scale))
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, 0)
            b:SetSize(bw, 33)
            b.x, b.w = x, bw
            x = x + bw + 2
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
        self:SetWidth(math.max(1, x))
        self:MoveInd(self.value, false)
    end
    function f:SetCounts(t)
        local changed = false
        for _, b in ipairs(self.buttons) do
            local n = t[b.key] or 0
            local s = (n > 0 and b.key ~= "all") and tostring(n) or ""
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
        self.indGlow:Hide()
        local x1, w1 = tb.x + 6, math.max(1, tb.w - 12)
        local x0, w0 = self.indX or x1, self.indW or w1
        self.indX, self.indW = x1, w1
        local function put(x, w)
            self.ind:ClearAllPoints()
            self.ind:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 0)
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
            b.hov:SetAlpha(0)
            local cc = on and b.color or C.dim
            b.count:SetTextColor(cc[1], cc[2], cc[3])
        end
        if changed or not self.indX then self:MoveInd(key, animate) end
    end
    return f
end

-- Kennzahl-Kachel (Verlauf, Glow, Hover-Lift, hochzaehlend), Klick = Filter
local function buildTile(parent, d, onClick)
    local c = d.color
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(54)
    t.key, t.lift = d.key, 0
    t.grad = t:CreateTexture(nil, "BORDER", nil, 1)
    t.grad:SetAllPoints()
    t.grad:Hide()
    t.hov = t:CreateTexture(nil, "BORDER", nil, 2)
    t.hov:SetAllPoints()
    t.hov:SetColorTexture(1, 1, 1, 0)
    t.top = t:CreateTexture(nil, "ARTWORK")
    t.top:Hide()
    t.iconGlow = t:CreateTexture(nil, "BORDER", nil, 3)
    t.iconGlow:Hide()
    glass(t, 12)
    t.icon = K.Glyph(t, 20, ICO .. d.glyph, c)
    t.icon:SetPoint("RIGHT", -14, 0)
    t.icon:SetAlpha(0.8)
    t.value = K.Title(t, 20, C.text)
    t.value:SetPoint("TOPLEFT", 14, -9)
    t.sub = K.Text(t, 10, c)
    t.sub:SetPoint("BOTTOMLEFT", t.value, "BOTTOMRIGHT", 6, 2)
    t.sub:SetPoint("RIGHT", t.icon, "LEFT", -4, 0)
    t.label = K.Text(t, 11, C.muted)
    t.label:SetPoint("BOTTOMLEFT", 14, 9)
    t.label:SetPoint("RIGHT", t.icon, "LEFT", -4, 0)
    t.label:SetText(L[d.label])
    t.col = c
    function t:Place()
        if not self.bx then return end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", self:GetParent(), "TOPLEFT", self.bx, self.lift)
        self:SetWidth(self.bw)
    end
    local function hover(on)
        glass(t, 12, (on or t.sel) and 0.06 or 0.03, t.sel and { c[1], c[2], c[3], 0.55 } or GLINE)
        local from, to = t.lift, on and 2 or 0
        local h0, h1 = t.hov:GetAlpha() or 0, (on or t.sel) and 1 or 0
        if animOn() then
            K.Tween(t.hov, 0.16, function(q)
                t.lift = from + (to - from) * q
                t.hov:SetAlpha(h0 + (h1 - h0) * q)
                t:Place()
            end)
        else
            t.lift = to
            t.hov:SetAlpha(h1)
            t:Place()
        end
    end
    t:SetScript("OnEnter", function(self)
        hover(true)
        K.ShowTip(self, { L[d.label], "|cff888888" .. ((self.sel and d.key ~= "all") and L["Klick: Filter aufheben"] or L[d.tip]) .. "|r" })
    end)
    t:SetScript("OnLeave", function() hover(false) GameTooltip:Hide() end)
    t:SetScript("OnClick", function() onClick(d.key) end)
    function t:SetSel(on)
        self.sel = on
        glass(self, 12, on and 0.06 or 0.03, on and { c[1], c[2], c[3], 0.55 } or GLINE)
    end
    return t
end

-- rundes Item-Bild im Qualitaetsring, Symbol-Ersatz statt Fragezeichen
local function makeAvatar(parent, s)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(s, s)
    a.glow = a:CreateTexture(nil, "BACKGROUND", nil, 2)
    a.glow:SetTexture(EMBER)
    a.glow:SetBlendMode("ADD")
    a.glow:SetSize(s * 2, s * 2)
    a.glow:SetPoint("CENTER")
    a.glow:SetAlpha(0.35)
    a.ring = a:CreateTexture(nil, "BORDER")
    a.ring:SetTexture(CIRCLE)
    a.ring:SetAllPoints()
    a.inner = a:CreateTexture(nil, "ARTWORK", nil, -1)
    a.inner:SetTexture(CIRCLE)
    a.inner:SetVertexColor(0.06, 0.06, 0.07)
    a.inner:SetSize(s - 4, s - 4)
    a.inner:SetPoint("CENTER")
    a.icon = a:CreateTexture(nil, "ARTWORK", nil, 1)
    a.icon:SetSize(s - 6, s - 6)
    a.icon:SetPoint("CENTER")
    circleMask(a, a.icon)
    a.glyph = a:CreateTexture(nil, "ARTWORK", nil, 2)
    a.glyph:SetSize(math.floor(s * 0.5), math.floor(s * 0.5))
    a.glyph:SetPoint("CENTER")
    return a
end
local function setAvatar(a, id, color, hot)
    local c = color or C.amber
    local tex = id and iconOf(id)
    local q = id and qualityOf(id)
    local ring = c
    if tex then
        a.icon:SetTexture(tex)
        a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        a.icon:Show()
        a.glyph:Hide()
        ring = (q and QCOL[q]) or C.line
    else
        a.icon:Hide()
        a.glyph:SetTexture(ICO .. "wants")
        a.glyph:SetVertexColor(c[1], c[2], c[3])
        a.glyph:Show()
    end
    a.ring:SetVertexColor(ring[1], ring[2], ring[3])
    a.glow:SetVertexColor(ring[1], ring[2], ring[3])
    a.glow:Hide()
    return ring, q
end

------------------------------------------------------------------------
-- Liste: Lage-Kapitel (oben angeheftet) + Karten, Zeilen je Schluessel wiederverwendet
------------------------------------------------------------------------
local function buildList(p)
    local TL = CreateFrame("Frame", nil, p)
    TL:SetClipsChildren(true)
    TL:EnableMouseWheel(true)
    TL.items, TL.total, TL.off, TL.target = {}, 0, 0, 0
    TL.used, TL.pools, TL.byKey = {}, { head = {}, card = {} }, {}
    TL.thumb = TL:CreateTexture(nil, "OVERLAY")
    TL.thumb:SetWidth(3)
    TL.thumb:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)

    local function newHead(parent)
        local r = CreateFrame("Frame", nil, parent or TL)
        r.mark = r:CreateTexture(nil, "ARTWORK")
        r.mark:SetSize(3, 12)
        r.mark:SetPoint("LEFT", 2, -1)
        r.text = K.Title(r, 12, C.text)
        r.text:SetPoint("LEFT", 12, -1)
        r.info = K.Text(r, 11, C.dim)
        r.info:SetPoint("LEFT", r.text, "RIGHT", 8, 0)
        r.rule = r:CreateTexture(nil, "ARTWORK")
        r.rule:SetHeight(1)
        r.rule:SetPoint("LEFT", r.info, "RIGHT", 10, 0)
        r.rule:SetPoint("RIGHT", r, "RIGHT", 0, -1)
        gradient(r.rule, "HORIZONTAL", C.line, 1, 0, 0.6)
        r.type = "head"
        return r
    end
    local function fillHead(r, it)
        r.text:SetText(it.label)
        r.info:SetText(it.info or "")
        local c = it.color or C.accent
        r.mark:SetColorTexture(c[1], c[2], c[3], 1)
    end

    local function cardHover(r, on)
        if not on and r.IsMouseOver and r:IsMouseOver() then return end
        if r.hovered == on then return end
        r.hovered = on
        r.hov:SetShown(false)
        local vm = r.item and r.item.vm
        local rc = vm and vm.ring
        glass(r, 10, on and 0.06 or 0.03, (on and rc) and { rc[1], rc[2], rc[3], 0.5 } or GLINE)
        r.acts:SetShown(on and (r.nActs or 0) > 0)
        if on and animOn() and (r.nActs or 0) > 0 then
            r.acts:SetAlpha(0)
            K.Tween(r.acts, 0.15, function(q) r.acts:SetAlpha(q) end, function() r.acts:SetAlpha(1) end)
        else
            r.acts:SetAlpha(1)
        end
        if not on then GameTooltip:Hide() end
    end
    local function cardTip(r)
        local vm = r.item and r.item.vm
        if not vm then return end
        local hint = "|cff777777" .. L["Rechtsklick: Aktionen"] .. (vm.id and ("  ·  " .. L["Shift-Klick: verlinken"]) or "") .. "|r"
        if vm.id then
            GameTooltip:SetOwner(r, "ANCHOR_RIGHT")
            if pcall(GameTooltip.SetItemByID, GameTooltip, vm.id) then
                GameTooltip:AddLine(" ")
                for _, l in ipairs(vm.tip or {}) do GameTooltip:AddLine(l, 0.85, 0.85, 0.85, true) end
                GameTooltip:AddLine(hint, 1, 1, 1, true)
                GameTooltip:Show()
                return
            end
        end
        local lines = { vm.name }
        for _, l in ipairs(vm.tip or {}) do lines[#lines + 1] = l end
        lines[#lines + 1] = hint
        K.ShowTip(r, lines)
    end
    local function cardMenu(r, owner)
        local vm = r.item and r.item.vm
        if not vm or not vm.menu then return end
        K.ShowMenu(owner or r, vm.menu(), plain(vm.name), 210)
    end
    -- Quellen-Chip: Symbol oder Klassenkreise + Text
    local function newChip(r)
        local b = CreateFrame("Button", nil, r)
        b:SetHeight(18)
        b:RegisterForClicks("AnyUp")
        glass(b, 9, 0.04)
        b.g = K.Glyph(b, 11, nil, C.muted)
        b.g:SetPoint("LEFT", 5, 0)
        b.text = K.Text(b, 11, C.text)
        b.cls = {}
        b:SetScript("OnEnter", function(self)
            cardHover(r, true)
            glass(self, 9, 0.08)
            if self.x and self.x.tip then K.ShowTip(self, self.x.tip) end
        end)
        b:SetScript("OnLeave", function(self)
            local xc = self.x and self.x.color
            glass(self, 9, 0.04, xc and { xc[1], xc[2], xc[3], 0.4 } or GLINE)
            GameTooltip:Hide()
            cardHover(r, false)
        end)
        b:SetScript("OnClick", function(self, btn)
            if btn == "RightButton" then cardMenu(r, self) return end
            if self.x and self.x.fn then self.x.fn() end
        end)
        return b
    end
    local function classDot(b, i)
        local d = b.cls[i]
        if d then return d end
        d = CreateFrame("Frame", nil, b)
        d:SetSize(14, 14)
        d.tex = d:CreateTexture(nil, "ARTWORK")
        d.tex:SetAllPoints()
        circleMask(d, d.tex)
        d.dot = d:CreateTexture(nil, "OVERLAY")
        d.dot:SetTexture(CIRCLE)
        d.dot:SetSize(6, 6)
        d.dot:SetPoint("CENTER", d, "BOTTOMRIGHT", -1, 1)
        b.cls[i] = d
        return d
    end
    local function setChip(b, x)
        b.x = x
        local c = x.color or C.muted
        local x0 = 6
        if x.glyph then
            b.g:SetTexture(ICO .. x.glyph)
            b.g:SetVertexColor(c[1], c[2], c[3])
            b.g:Show()
            x0 = 20
        else
            b.g:Hide()
        end
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", b, "LEFT", x0, 0)
        b.text:SetText(K.hex(c) .. (x.text or "") .. "|r")
        local w = x0 + (b.text:GetStringWidth() or 30)
        local list = x.classes or {}
        for i, m in ipairs(list) do
            local d = classDot(b, i)
            d.tex:SetVertexColor(1, 1, 1)
            if not (m.class and setClassIcon(d.tex, m.class)) then
                d.tex:SetTexture(CIRCLE)
                d.tex:SetTexCoord(0, 1, 0, 1)
                d.tex:SetVertexColor(C.dim[1], C.dim[2], C.dim[3])
            end
            local dc = m.on and C.mint or C.dim
            d.dot:SetVertexColor(dc[1], dc[2], dc[3])
            d:ClearAllPoints()
            d:SetPoint("LEFT", b, "LEFT", w + (i == 1 and 6 or 2), 0)
            d:Show()
            w = w + (i == 1 and 6 or 2) + 14
        end
        for i = #list + 1, #b.cls do b.cls[i]:Hide() end
        if x.more then
            b.more = b.more or K.Text(b, 10, C.dim)
            b.more:SetText("+" .. x.more)
            b.more:ClearAllPoints()
            b.more:SetPoint("LEFT", b, "LEFT", w + 4, 0)
            b.more:Show()
            w = w + 4 + (b.more:GetStringWidth() or 12)
        elseif b.more then
            b.more:Hide()
        end
        b:SetWidth(math.floor(w + 8))
        glass(b, 9, 0.04, x.color and { x.color[1], x.color[2], x.color[3], 0.4 } or GLINE)
    end
    local function newAct(r)
        local b = CreateFrame("Button", nil, r.acts)
        b:SetSize(22, 22)
        glass(b, 8, 0.04)
        b.g = K.Glyph(b, 13, nil, C.muted)
        b.g:SetPoint("CENTER")
        b:SetScript("OnEnter", function(self)
            cardHover(r, true)
            glass(self, 8, 0.10)
            self.g:SetVertexColor(C.text[1], C.text[2], C.text[3])
            if self.a then K.ShowTip(self, { self.a.tip }) end
        end)
        b:SetScript("OnLeave", function(self)
            glass(self, 8, 0.04)
            self.g:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
            GameTooltip:Hide()
            cardHover(r, false)
        end)
        b:SetScript("OnClick", function(self) if self.a and self.a.fn then self.a.fn() end end)
        return b
    end
    local function newCard()
        local r = CreateFrame("Button", nil, TL)
        r:RegisterForClicks("AnyUp")
        r.tint = r:CreateTexture(nil, "BORDER", nil, 1)
        r.tint:SetAllPoints()
        r.hov = r:CreateTexture(nil, "BORDER", nil, 2)
        r.hov:SetAllPoints()
        r.hov:SetColorTexture(1, 1, 1, 0.045)
        r.hov:Hide()
        r.flash = r:CreateTexture(nil, "BORDER", nil, 3)
        r.flash:SetAllPoints()
        r.flash:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.22)
        r.flash:Hide()
        glass(r, 10, 0.03)
        r.edge = r:CreateTexture(nil, "ARTWORK")
        r.edge:SetPoint("TOPLEFT") r.edge:SetPoint("BOTTOMLEFT")
        r.edge:SetWidth(2)
        r.av = makeAvatar(r, 38)
        r.av:SetPoint("LEFT", 10, 0)
        r.name = K.Text(r, 13, C.text)
        r.price = CreateFrame("Frame", nil, r)
        r.price:SetHeight(18)
        glass(r.price, 9, 0.04, { C.amber[1], C.amber[2], C.amber[3], 0.35 })
        r.price.coin = r.price:CreateTexture(nil, "ARTWORK")
        r.price.coin:SetTexture(COIN)
        r.price.coin:SetSize(11, 11)
        r.price.coin:SetPoint("LEFT", 5, 0)
        r.price.text = K.Text(r.price, 11, C.amber)
        r.price.text:SetPoint("LEFT", r.price.coin, "RIGHT", 4, 0)
        r.price:EnableMouse(true)
        r.price:SetScript("OnEnter", function(self)
            cardHover(r, true)
            if self.tip then K.ShowTip(self, self.tip) end
        end)
        r.price:SetScript("OnLeave", function() GameTooltip:Hide() cardHover(r, false) end)
        r.meta = K.Text(r, 11, C.muted)
        r.more = K.Text(r, 11, C.dim)
        r.chips, r.abtn = {}, {}
        r.prim = K.Button(r, "", 90, 24, "primary")
        r.prim:HookScript("OnEnter", function(self)
            cardHover(r, true)
            local pr = r.item and r.item.vm and r.item.vm.primary
            if pr and pr.tip then K.ShowTip(self, { pr.tip }) end
        end)
        r.prim:HookScript("OnLeave", function() GameTooltip:Hide() cardHover(r, false) end)
        r.prim:SetScript("OnClick", function()
            local pr = r.item and r.item.vm and r.item.vm.primary
            if pr and pr.fn then pr.fn() end
        end)
        r.acts = CreateFrame("Frame", nil, r)
        r.acts:SetHeight(22)
        r.acts:Hide()
        r:SetScript("OnEnter", function(self) cardHover(self, true) cardTip(self) end)
        r:SetScript("OnLeave", function(self) cardHover(self, false) end)
        r:SetScript("OnClick", function(self, btn)
            local vm = self.item and self.item.vm
            if not vm then return end
            if btn == "RightButton" then cardMenu(self) return end
            if IsModifiedClick and IsModifiedClick("CHATLINK") then linkItem(vm.w) end
        end)
        r.type = "card"
        return r
    end
    local function fillCard(r, it)
        local vm = it.vm
        local W = math.max(300, (TL:GetWidth() or 600) - 10)
        local ring, q = setAvatar(r.av, vm.id, vm.color, vm.hot)
        vm.ring = ring
        r.tint:Hide()
        r.edge:Hide()
        if not r.hovered then glass(r, 10, 0.03) end
        -- rechts: Hauptaktion + Symbolknoepfe (beim Ueberfahren)
        local reserve = 10
        r.prim:ClearAllPoints()
        if vm.primary then
            r.prim:SetLabel(vm.primary.text)
            local pw = math.max(96, math.floor((r.prim.label:GetStringWidth() or 60) + 26))
            r.prim:SetWidth(pw)
            r.prim:SetPoint("RIGHT", r, "RIGHT", -10, 0)
            r.prim:Show()
            reserve = reserve + pw + 6
        else
            r.prim:Hide()
        end
        local acts = vm.acts or {}
        for i, a in ipairs(acts) do
            local b = r.abtn[i] or newAct(r)
            r.abtn[i] = b
            b.a = a
            b.g:SetTexture(ICO .. a.glyph)
            b:ClearAllPoints()
            b:SetPoint("RIGHT", r.acts, "RIGHT", -(i - 1) * 26, 0)
            b:Show()
        end
        for i = #acts + 1, #r.abtn do r.abtn[i]:Hide() end
        r.nActs = #acts
        r.acts:SetWidth(math.max(1, #acts * 26))
        r.acts:ClearAllPoints()
        r.acts:SetPoint("RIGHT", r, "RIGHT", -reserve, 0)
        r.acts:SetShown(r.hovered and #acts > 0)
        reserve = reserve + #acts * 26 + 6
        -- Zeile 1: "10x Heiltrank" in Qualitaetsfarbe + Gold-Chip
        local nc = (q and q >= 1 and QCOL[q]) or C.text
        r.name:SetText(K.hex(nc) .. (vm.qty or 1) .. "x  " .. vm.name .. "|r")
        local avail = W - 58 - reserve
        local pw = 0
        if vm.price then
            r.price.text:SetText((L["%dg/Stk"]):format(vm.price))
            pw = math.floor((r.price.text:GetStringWidth() or 40) + 26)
            r.price:SetWidth(pw)
            r.price.tip = { L["Preisangebot"], (L["zahlt %dg/Stk"]):format(vm.price) .. "  |cff888888(" .. (L["gesamt %dg"]):format(vm.price * (vm.qty or 1)) .. ")|r" }
        end
        r.name:SetWidth(math.max(40, math.min((r.name:GetStringWidth() or 0) + 2, avail - (pw > 0 and pw + 8 or 0))))
        r.name:ClearAllPoints()
        r.name:SetPoint("TOPLEFT", 58, it.slim and -11 or -10)
        r.price:SetShown(vm.price ~= nil)
        if vm.price then
            r.price:ClearAllPoints()
            r.price:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
        end
        -- Zeile 2: Wer (Klassenfarbe) · Notiz · Zeit
        r.meta:SetText(vm.meta or "")
        r.meta:ClearAllPoints()
        r.meta:SetPoint("TOPLEFT", 58, it.slim and -30 or -29)
        r.meta:SetPoint("RIGHT", r, "RIGHT", -reserve, 0)
        -- Zeile 3: Quellen-Chips
        local x, shown = 58, 0
        local chips = vm.chips or {}
        for i, c in ipairs(chips) do
            local b = r.chips[i] or newChip(r)
            r.chips[i] = b
            setChip(b, c)
            local cw = b:GetWidth() or 60
            if it.slim or x + cw > W - reserve - 30 then
                b:Hide()
            else
                b:ClearAllPoints()
                b:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 9)
                b:Show()
                x = x + cw + 5
                shown = shown + 1
            end
        end
        for i = #chips + 1, #r.chips do r.chips[i]:Hide() end
        r.more:SetShown(not it.slim and shown < #chips)
        if shown < #chips then
            r.more:SetText("+" .. (#chips - shown))
            r.more:ClearAllPoints()
            r.more:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x + 2, 12)
        end
        -- frisch eingetragen: kurz aufleuchten
        if flashKey and vm.key == flashKey then
            flashKey = nil
            if animOn() then
                r.flash:Show()
                r.flash:SetAlpha(1)
                K.Tween(r.flash, 1.4, function(qq) r.flash:SetAlpha(1 - qq) end, function() r.flash:Hide() end, 0.1)
            end
        elseif not (r.flash:IsShown() and (r.flash:GetAlpha() or 0) > 0) then
            r.flash:Hide()
        end
        if r.IsMouseOver and r:IsMouseOver() and not r.hovered then cardHover(r, true) end
    end

    local MAKE = { head = newHead, card = newCard }
    local FILL = { head = fillHead, card = fillCard }

    TL.sticky = CreateFrame("Frame", nil, TL)
    TL.sticky:SetHeight(H_HEAD - 4)
    TL.sticky:SetFrameLevel((TL:GetFrameLevel() or 1) + 20)
    TL.sticky.bg = TL.sticky:CreateTexture(nil, "BACKGROUND")
    TL.sticky.bg:SetAllPoints()
    TL.sticky.bg:SetColorTexture(C.bg[1], C.bg[2], C.bg[3], 0.97)
    TL.sticky.fade = TL.sticky:CreateTexture(nil, "BACKGROUND")
    TL.sticky.fade:SetPoint("TOPLEFT", TL.sticky, "BOTTOMLEFT")
    TL.sticky.fade:SetPoint("TOPRIGHT", TL.sticky, "BOTTOMRIGHT")
    TL.sticky.fade:SetHeight(8)
    gradient(TL.sticky.fade, "VERTICAL", C.bg, 0, 0.9, 0)
    TL.sticky.row = newHead(TL.sticky)
    TL.sticky.row:SetPoint("TOPLEFT", 0, 0)
    TL.sticky.row:SetPoint("BOTTOMRIGHT", -10, 0)
    TL.sticky:Hide()

    function TL:MaxOff() return math.max(0, self.total - (self:GetHeight() or 0) + 8) end
    function TL:Release(key, r)
        r:Hide()
        r.item = nil
        if r.hovered then r.hovered = false r.hov:Hide() if r.acts then r.acts:Hide() end end
        self.used[key] = nil
        local pool = self.pools[r.type]
        pool[#pool + 1] = r
    end
    function TL:Layout(force)
        local H = self:GetHeight() or 0
        local off = math.floor(self.off + 0.5)
        for key, r in pairs(self.used) do
            local it = self.byKey[key]
            if not it or it.t ~= r.type or not (it.y + it.h > off and it.y < off + H) then self:Release(key, r)
            elseif force then r.item = nil end
        end
        local first, nextH
        for _, it in ipairs(self.items) do
            if it.t == "head" then
                if it.y <= off then first = it elseif not nextH and first then nextH = it end
            end
            if it.y + it.h > off and it.y < off + H then
                local r = self.used[it.key]
                if not r then
                    r = table.remove(self.pools[it.t]) or MAKE[it.t]()
                    self.used[it.key] = r
                    r.item = nil
                    r:Show()
                end
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(it.y - off))
                r:SetPoint("RIGHT", self, "RIGHT", -10, 0)
                r:SetHeight(it.h - (it.t == "card" and GAP or 0))
                if r.item ~= it then
                    r.item = it
                    local ok, err = pcall(FILL[it.t], r, it)
                    if not ok and ns.err then ns.err(L["Gesucht"], err) end
                end
            elseif it.y >= off + H and first then
                if it.t == "head" and not nextH then nextH = it end
                break
            end
        end
        if first and off > 0 then
            local push = 0
            if nextH then push = math.min(0, (nextH.y - off) - (H_HEAD - 4)) end
            self.sticky:ClearAllPoints()
            self.sticky:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -push)
            self.sticky:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            if self.sticky.cur ~= first then self.sticky.cur = first fillHead(self.sticky.row, first) end
            self.sticky:Show()
        else
            self.sticky:Hide()
        end
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

    -- keep = Leseposition halten (Nachladen): Anker ist der oberste sichtbare Eintrag
    function TL:SetItems(items, keep)
        local anchorKey, anchorDy
        if keep and self.off > 0 then
            for _, it in ipairs(self.items) do
                if it.y + it.h > self.off then anchorKey, anchorDy = it.key, it.y - self.off break end
            end
        end
        local y, byKey = 0, {}
        for i, it in ipairs(items) do
            if byKey[it.key] then it.key = it.key .. "#" .. i end
            byKey[it.key] = it
            it.y = y
            y = y + it.h
        end
        self.items, self.total, self.byKey = items, y, byKey
        self.sticky.cur = nil
        if anchorKey and byKey[anchorKey] then
            self.off = byKey[anchorKey].y - anchorDy
            self.target = self.off
        elseif not keep then
            self.off, self.target = 0, 0
            self:SetScript("OnUpdate", nil)
        end
        self.off = math.max(0, math.min(self:MaxOff(), self.off))
        self.target = math.max(0, math.min(self:MaxOff(), self.target))
        self:Layout()
    end
    function TL:Stagger()
        if not animOn() then return end
        local list = {}
        for _, r in pairs(self.used) do if r.item then list[#list + 1] = { r.item.y, r } end end
        table.sort(list, function(a, b) return a[1] < b[1] end)
        for i, x in ipairs(list) do
            local r = x[2]
            r:SetAlpha(0)
            K.Tween(r, 0.26, function(q) r:SetAlpha(q) end, function() r:SetAlpha(1) end, math.min(0.45, (i - 1) * 0.035))
        end
        ns.After(1.2, function() for _, r in pairs(self.used) do r:SetAlpha(1) end end)
    end
    return TL
end

------------------------------------------------------------------------
-- Eintraege aufbereiten (eine Beschreibung je Karte)
------------------------------------------------------------------------
local function shortDungeon(s)
    s = plain(s)
    local inner = s:match("%(([^%(%)]+)%)%s*$")
    return inner or s
end
local function vmWant(w)
    local s = w._src or Wants.Sources(w)
    local mine = ns.isMe(w.who)
    local id = (w.itemID and w.itemID > 0) and w.itemID or nil
    local name = plain(w.link or w.name or "?")
    local deliver = not mine and (s.have > 0 or s.iCanCraft)
    local group = deliver and "deliver" or (s.bank > 0 and "bank") or (s.recipe and "craft") or "rest"
    local color = (group == "deliver" and C.mint) or (group == "bank" and PURPLE) or (group == "craft" and C.blue) or (mine and C.amber) or C.muted
    local v = { key = "w:" .. tostring(w.id), w = w, id = id, name = name, qty = w.qty or 1, price = tonumber(w.price), mine = mine, group = group,
        color = color, hot = deliver, chips = {}, acts = {}, tip = {}, t = w.created or w.u or 0 }
    local who = ns.displayName(w.who)
    -- Zeile 2
    local meta = colored(w.who) .. (mine and ("  |cff888888(" .. L["du"] .. ")|r") or "")
    if (w.note or "") ~= "" then meta = meta .. "  |cff555555·|r  |cffc8c8cc" .. w.note .. "|r" end
    meta = meta .. "  |cff555555·|r  |cff777777" .. ns.ago(w.u or w.created) .. "|r"
    v.meta = meta
    -- Quellen
    if s.have > 0 then
        v.chips[#v.chips + 1] = { glyph = "checklist", text = (L["Du hast %d"]):format(s.have), color = C.mint,
            tip = { (L["Du hast %d"]):format(s.have), "|cff888888" .. L["in deinen Taschen"] .. "|r" }, fn = (not mine) and function() offer(w) end or nil }
    end
    if s.bank > 0 then
        v.chips[#v.chips + 1] = { glyph = "bank", text = (L["Bank %d"]):format(s.bank), color = PURPLE,
            tip = { L["In der Gildenbank:"] .. " " .. s.bank, "|cff888888" .. L["Klick: Gildenbank oeffnen"] .. "|r" }, fn = function() ns.ShowPage("bank") end }
    end
    local firstOn
    if s.iCanCraft then
        v.chips[#v.chips + 1] = { glyph = "crafting", text = L["du kannst es bauen"], color = C.blue, tip = { L["du kannst es bauen"] } }
    elseif s.crafters and #s.crafters > 0 then
        local cls, tip, n = {}, { L["Herstellbar von:"] }, 0
        for _, c in ipairs(s.crafters) do
            if not ns.isMe(c.name) then
                n = n + 1
                if #cls < 4 then cls[#cls + 1] = { class = ns.Radar and ns.Radar.ClassOf and ns.Radar.ClassOf(c.name), on = c.online } end
                if #tip <= 8 then tip[#tip + 1] = colored(c.name) .. "  " .. (c.online and (K.hex(C.mint) .. L["online"] .. "|r") or ("|cff888888" .. L["offline"] .. "|r")) end
                if c.online and not firstOn then firstOn = c.name end
            end
        end
        if n > 0 then
            tip[#tip + 1] = "|cff777777" .. (firstOn and (L["Klick: %s anfluestern"]):format(ns.displayName(firstOn)) or L["gerade niemand online"]) .. "|r"
            v.chips[#v.chips + 1] = { glyph = "crafting", text = L["Baut:"], color = C.blue, classes = cls, more = n > 4 and (n - 4) or nil, tip = tip,
                fn = firstOn and function() whisper(w, firstOn) end or nil }
        end
    end
    if s.price then
        v.chips[#v.chips + 1] = { text = L["AH"] .. " ~" .. plain(ns.Market.Format(s.price)), color = C.amber,
            tip = { L["Auktionshaus"], "~" .. ns.Market.Format(s.price) .. " " .. L[" /Stk"], (L["gesamt %s"]):format(ns.Market.Format(s.price * (w.qty or 1))) } }
    end
    if s.dungeon then
        v.chips[#v.chips + 1] = { glyph = "dungeons", text = shortDungeon(s.dungeon), color = C.muted, tip = { L["Quelle"], s.dungeon } }
    end
    -- eigenes Set ("Pre-Raid 3/7"), siehe WishAlerts.lua
    if w.set and w.set ~= "" and ns.WishAlerts then
        local st = ns.WishAlerts.SetText(w.set)
        if st then v.chips[#v.chips + 1] = { glyph = "checklist", text = st, color = C.mint, tip = { L["Set"], st, "|cff888888" .. L["Rechtsklick: Set aendern"] .. "|r" } } end
    end
    -- Tooltip-Zeilen
    v.tip[1] = (L["Gesucht von %s"]):format(colored(w.who)) .. "  |cffffc24d" .. (w.qty or 1) .. "x|r"
    if (w.note or "") ~= "" then v.tip[#v.tip + 1] = "|cffc8c8cc" .. w.note .. "|r" end
    if v.price then v.tip[#v.tip + 1] = "|cffe8b44a" .. (L["zahlt %dg/Stk"]):format(v.price) .. "|r" end
    -- Hauptaktion je nach Lage
    local others = 0
    for _, c in ipairs(s.crafters or {}) do if not ns.isMe(c.name) then others = others + 1 end end
    if not mine and s.have > 0 then
        v.primary = { text = L["Hab ich!"], tip = (L["%s Bescheid sagen: du hast es"]):format(who), fn = function() offer(w) end }
    elseif not mine and s.iCanCraft then
        v.primary = { text = L["Kann ich bauen"], tip = (L["%s Bescheid sagen: du kannst es bauen"]):format(who), fn = function() offer(w) end }
    elseif mine and s.recipe and others > 0 and not s.iCanCraft then
        v.primary = { text = L["Auftrag geben"], tip = L["Handwerksauftrag an die Gilde schicken"], fn = function() order(w, s) end }
    elseif mine then
        v.primary = { text = L["Erledigt"], tip = L["Wunsch abhaken und entfernen"], fn = function() done(w) end }
    end
    -- weitere Aktionen beim Ueberfahren
    if not mine then
        v.acts[#v.acts + 1] = { glyph = "announce", tip = (L["%s anfluestern"]):format(who), fn = function() whisper(w) end }
    end
    v.acts[#v.acts + 1] = { glyph = "pin", tip = L["Gegenstand im Chat verlinken"], fn = function() linkItem(w) end }
    if mine and v.primary and v.primary.text ~= L["Erledigt"] then
        v.acts[#v.acts + 1] = { glyph = "checklist", tip = L["Erledigt"], fn = function() done(w) end }
    end
    local del = canDelete(w)
    if del then
        v.acts[#v.acts + 1] = { glyph = "eraser", tip = L["Eintrag entfernen"], fn = function() Store.Delete("wants", w.id) end }
    end
    v.search = table.concat({ low(name), low(w.note), low(who), low(s.dungeon) }, " ")
    v.menu = function()
        local m = {}
        if not mine then
            m[#m + 1] = { text = (L["Fluestern: %s"]):format(who), fn = function() whisper(w) end }
            m[#m + 1] = { text = L["Hab ich!"], disabled = not (s.have > 0 or s.iCanCraft), fn = function() offer(w) end }
        end
        if s.recipe and others > 0 and not s.iCanCraft then
            m[#m + 1] = { text = L["Auftrag geben"], fn = function() order(w, s) end }
        end
        if firstOn then m[#m + 1] = { text = (L["Handwerker anfluestern: %s"]):format(ns.displayName(firstOn)), fn = function() whisper(w, firstOn) end } end
        m[#m + 1] = { text = L["Gegenstand im Chat verlinken"], fn = function() linkItem(w) end }
        if mine then m[#m + 1] = { text = L["Erledigt"], fn = function() done(w) end } end
        if mine and ns.WishAlerts then for _, x in ipairs(ns.WishAlerts.MenuItems(w)) do m[#m + 1] = x end end
        if del then m[#m + 1] = { text = L["Loeschen"], fn = function() Store.Delete("wants", w.id) end } end
        return m
    end
    return v
end

-- Daten + Zaehler + Filter
local function collect()
    local all, counts = {}, { all = 0, deliver = 0, bank = 0, craft = 0, mine = 0 }
    for _, w in ipairs(Store.List("wants")) do
        local s = Wants.Sources(w)
        w._src = s
        local mine = ns.isMe(w.who)
        counts.all = counts.all + 1
        if not mine and (s.have > 0 or s.iCanCraft) then counts.deliver = counts.deliver + 1 end
        if s.bank > 0 then counts.bank = counts.bank + 1 end
        if s.recipe then counts.craft = counts.craft + 1 end
        if mine then counts.mine = counts.mine + 1 end
        all[#all + 1] = w
    end
    return all, counts
end
local function passes(v)
    local s = v.w._src
    if filter == "deliver" and v.group ~= "deliver" then return false end
    if filter == "bank" and not (s.bank > 0) then return false end
    if filter == "craft" and not s.recipe then return false end
    if filter == "mine" and not v.mine then return false end
    if search ~= "" and not (v.search or ""):find(search, 1, true) then return false end
    return true
end
local function arrange(vms)
    local byG = {}
    for _, v in ipairs(vms) do
        byG[v.group] = byG[v.group] or {}
        table.insert(byG[v.group], v)
    end
    local function cmp(a, b)
        if sortBy == "price" and (a.price or -1) ~= (b.price or -1) then return (a.price or -1) > (b.price or -1) end
        if sortBy == "qty" and a.qty ~= b.qty then return a.qty > b.qty end
        if sortBy == "name" then
            local na, nb = low(a.name), low(b.name)
            if na ~= nb then return na < nb end
        end
        if a.t ~= b.t then return a.t > b.t end
        return a.key < b.key
    end
    local items = {}
    for _, g in ipairs(GROUPS) do
        local list = byG[g.key]
        if list and #list > 0 then
            table.sort(list, cmp)
            local info = (L["%d Eintraege"]):format(#list)
            if g.key == "deliver" then info = info .. "  ·  " .. K.hex(C.mint) .. L["jemand freut sich"] .. "|r" end
            items[#items + 1] = { t = "head", key = "h:" .. g.key, label = L[g.label], info = info, color = g.color, h = H_HEAD }
            for _, v in ipairs(list) do
                local slim = #v.chips == 0
                items[#items + 1] = { t = "card", key = v.key, vm = v, slim = slim, h = (slim and H_SLIM or H_CARD) + GAP }
            end
        end
    end
    return items
end

local function switchTo(k)
    filter = k
    if page and page.tl then
        page.switch = true
        if animOn() then
            local tl = page.tl
            tl:SetAlpha(0.15)
            K.Tween(tl, 0.22, function(q) tl:SetAlpha(0.15 + 0.85 * q) end, function() tl:SetAlpha(1) end)
        end
    end
    ns.RefreshPage("wants")
end
local function onTile(k)
    if k ~= "all" and filter == k then switchTo("all") else switchTo(k) end
end

------------------------------------------------------------------------
-- Eintragen-Zeile
------------------------------------------------------------------------
local function setQty(p, n)
    formQty = math.max(1, math.min(999, math.floor(tonumber(n) or 1)))
    p.qty:SetText(formQty)
end
local function buildForm(p)
    local f = CreateFrame("Frame", nil, p)
    f:SetHeight(66)
    glass(f, 14, 0.035)
    f.glow = f:CreateTexture(nil, "BORDER")
    f.glow:SetAllPoints()
    gradient(f.glow, "HORIZONTAL", C.mint, 0.22, 0, 0.1)
    f.glow:SetAlpha(0)
    f.av = makeAvatar(f, 32)
    f.av:SetPoint("TOPLEFT", 10, -8)
    local item = K.Input(f, 230, L["Item eintippen oder Shift-Klick ..."])
    item:SetHeight(26)
    glass(item, 8, 0.04)
    item:SetPoint("LEFT", f.av, "RIGHT", 8, 0)
    p.itemBox = item
    if hooksecurefunc and ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", function(link)
            if item:HasFocus() and link then
                item.suppress = true
                item:SetText(link)
                item.suppress = false
                item.pickedID = ns.itemID(link)
                ns.RefreshPage("wants")
            end
        end)
    end
    -- Mengen-Stepper: [-] n [+], Mausrad, Shift = 10er-Schritte
    local st = CreateFrame("Frame", nil, f)
    st:SetSize(82, 26)
    glass(st, 8, 0.04)
    st:EnableMouseWheel(true)
    local function step(d) setQty(p, formQty + d * ((IsShiftKeyDown and IsShiftKeyDown()) and 10 or 1)) end
    st:SetScript("OnMouseWheel", function(_, delta) step(delta) end)
    st.minus = K.Button(st, "-", 22, 22, "ghost", function() step(-1) end)
    st.minus:SetPoint("LEFT", 2, 0)
    st.plus = K.Button(st, "+", 22, 22, "ghost", function() step(1) end)
    st.plus:SetPoint("RIGHT", -2, 0)
    p.qty = K.Title(st, 13, C.text)
    p.qty:SetPoint("LEFT", st.minus, "RIGHT", 0, 0)
    p.qty:SetPoint("RIGHT", st.plus, "LEFT", 0, 0)
    p.qty:SetJustifyH("CENTER")
    p.qty:SetText(formQty)
    st:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Menge"], "|cff888888" .. L["Mausrad oder +/-, mit Shift in 10er-Schritten"] .. "|r" }) end)
    st:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.step = st
    -- Preisangebot mit Gold-Symbol
    local price = K.Input(f, 78, L["Preis"])
    price:SetHeight(26)
    glass(price, 8, 0.04)
    price:SetNumeric(true)
    price:SetMaxLetters(6)
    price:SetTextInsets(7, 22, 0, 0)
    price.coin = price:CreateTexture(nil, "OVERLAY")
    price.coin:SetTexture(COIN)
    price.coin:SetSize(12, 12)
    price.coin:SetPoint("RIGHT", -8, 0)
    price:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Preisangebot"], L["Was du pro Stueck zahlen wuerdest (freiwillig)."] }) end)
    price:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.price = price
    local note = K.Input(f, 150, L["Notiz ..."])
    note:SetHeight(26)
    glass(note, 8, 0.04)
    f.note = note
    local add = K.Button(f, L["Eintragen"], 118, 28, "primary")
    K.SetFontSafe(add.label, K.FONT, 13, "", K.FONT)
    f.add = add
    add:SetScript("OnClick", function()
        local text = item:GetText()
        if item.pickedID and ns.ItemSearch then text = ns.ItemSearch.Link(item.pickedID) end
        local pr = tonumber(price:GetText())
        local rec = Wants.Add(text, formQty, note:GetText(), { price = (pr and pr > 0) and pr or nil })
        if not rec then
            glass(item, 8, 0.04, { C.red[1], C.red[2], C.red[3], 0.8 })
            ns.After(0.8, function() if not item:HasFocus() then glass(item, 8, 0.04) end end)
            item:SetFocus()
            return
        end
        item.suppress = true item:SetText("") item.suppress = false
        item.pickedID = nil
        price:SetText("") note:SetText("")
        setQty(p, 1)
        item:ClearFocus()
        flashKey = "w:" .. tostring(rec.id)
        p.scrollTo = flashKey
        if filter ~= "all" and filter ~= "mine" then filter = "all" p.switch = true end
        -- Bestaetigung: Knopf und Zeile leuchten kurz gruen
        add:SetLabel(L["Eingetragen!"])
        ns.After(1.4, function() add:SetLabel(L["Eintragen"]) end)
        if animOn() then
            f.glow:SetAlpha(1)
            K.Tween(f.glow, 1.0, function(q) f.glow:SetAlpha(1 - q) end, function() f.glow:SetAlpha(0) end, 0.15)
        end
        ns.RefreshPage("wants")
    end)
    item.onEnter = function() add:Click() end
    if ns.ItemSearch then ns.ItemSearch.Attach(item, function() ns.RefreshPage("wants") end) end
    f.info = K.Text(f, 10, C.muted)
    f.info:SetPoint("TOPLEFT", item, "BOTTOMLEFT", 1, -5)
    f.info:SetWordWrap(false)
    function f:Layout(W)
        local fixed = 10 + 32 + 8 + 8 + 82 + 8 + 78 + 8 + 8 + 118 + 10
        local flex = math.max(160, W - fixed)
        local iw = math.floor(flex * 0.6)
        item:SetWidth(iw)
        note:SetWidth(flex - iw)
        st:ClearAllPoints() st:SetPoint("LEFT", item, "RIGHT", 8, 0)
        price:ClearAllPoints() price:SetPoint("LEFT", st, "RIGHT", 8, 0)
        note:ClearAllPoints() note:SetPoint("LEFT", price, "RIGHT", 8, 0)
        add:ClearAllPoints() add:SetPoint("LEFT", note, "RIGHT", 8, 0)
        self.info:SetWidth(math.max(100, W - 70))
    end
    return f
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local FORM_Y, TAB_Y, LIST_Y = 0, -76, -116   -- 0.5.853: Kennzahl-Kacheln entfallen
ns.RegisterPage({
    key = "wants", title = "Gesucht", order = 2.5,
    sub = "Einkaufsliste der Gilde - wer etwas hat oder bauen kann, bekommt beim Looten und im Tooltip Bescheid",
    build = function(p)
        page = p
        p.fresh = true
        p:HookScript("OnShow", function(self) self.fresh = true end)
        -- Kennzahl-Kacheln (Klick = Filter)
        p.tileRow = CreateFrame("Frame", nil, p)
        p.tileRow:SetPoint("TOPLEFT", 0, 0)
        p.tileRow:SetPoint("TOPRIGHT", 0, 0)
        p.tileRow:SetHeight(56)
        p.tiles = {}
        for i, d in ipairs(TILES) do p.tiles[i] = buildTile(p.tileRow, d, onTile) end
        p.tileRow:Hide()
        -- Eintragen
        p.form = buildForm(p)
        p.form:SetPoint("TOPLEFT", 0, FORM_Y)
        p.form:SetPoint("TOPRIGHT", 0, FORM_Y)
        -- Reiter + Suche + Sortierung
        p.tabs = buildTabs(p, function(k) switchTo(k) end)
        p.tabs:SetPoint("TOPLEFT", 0, TAB_Y)
        p.tabLine = p:CreateTexture(nil, "BACKGROUND")
        p.tabLine:SetPoint("TOPLEFT", 0, TAB_Y - 33)
        p.tabLine:SetPoint("TOPRIGHT", 0, TAB_Y - 33)
        p.tabLine:SetHeight(1)
        p.tabLine:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        p.sort = K.Button(p, "", 120, 22, "ghost")
        p.sort.isDropdown = true
        K.SetFontSafe(p.sort.label, K.FONT, 11, "", K.FONT)
        p.sort:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, TAB_Y - 5)
        p.sort:SetScript("OnClick", function(self)
            local items = {}
            for _, s in ipairs(SORTS) do
                items[#items + 1] = { text = L[s.text], checked = sortBy == s.key, fn = function() sortBy = s.key ns.RefreshPage("wants") end }
            end
            K.ShowMenu(self, items, L["Sortieren nach"], 160)
        end)
        p.search = K.Input(p, 140, L["Suchen ..."], function(t)
            local s = (t or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            if s == search then return end
            search = s
            ns.RefreshPage("wants")
        end)
        p.search:SetHeight(22)
        p.search:SetPoint("RIGHT", p.sort, "LEFT", -6, 0)
        -- FojjiCore geladen und dort stehen Wuensche, die hier fehlen: mit einem Klick uebernehmen (die Gilde sieht sie dann)
        p.fojji = K.Button(p, "", 150, 22, "ghost", function()
            if ns.Fojji then
                local n = ns.Fojji.ImportWishes()
                if n > 0 and K.Toast then K.Toast(L["Wunschliste"], (L["%d Wuensche aus FojjiCore in die Oasis-Wunschliste uebernommen."]):format(n), C.mint) end
            end
            ns.RefreshPage("wants")
        end)
        p.fojji:SetPoint("RIGHT", p.search, "LEFT", -6, 0)
        p.fojji:SetScript("OnEnter", function(self) K.ShowTip(self, { "FojjiCore", L["Uebernimmt, was du in FojjiCores Wunschliste markiert hast. Die Gilde sieht diese Wuensche dann hier."] }) end)
        p.fojji:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.fojji:Hide()
        -- Liste + Leerzustand
        p.tl = buildList(p)
        p.tl:SetPoint("TOPLEFT", 0, LIST_Y)
        p.tl:SetPoint("BOTTOMRIGHT", 0, 0)
        p.empty = emptyState(p.tl)
        p.empty:SetPoint("TOP", 0, -30)

        function p:Layout()
            local W = self:GetWidth() or 760
            if W < 50 then return end
            local n, gap = #self.tiles, 8
            local tw = math.floor((W - gap * (n - 1)) / n)
            for i, t in ipairs(self.tiles) do
                t.bx, t.bw = (i - 1) * (tw + gap), tw
                t:Place()
            end
            self.form:Layout(W)
            local sw = W < 680 and 104 or 140
            self.search:SetWidth(sw)
            self.tabs.maxW = math.max(200, W - sw - (self.sort:GetWidth() or 120) - 20 - (self.fojji:IsShown() and 156 or 0))
            self.tabs:Layout()
        end
        p:HookScript("OnSizeChanged", function(self) self:Layout() end)
        p:Layout()
    end,
    refresh = function(p)
        do
            local nf = ns.Fojji and ns.Fojji.Has() and #ns.Fojji.NewWishes() or 0
            local was = p.fojji:IsShown()
            p.fojji:SetShown(nf > 0)
            if nf > 0 then p.fojji:SetLabel((L["Aus FojjiCore (%d)"]):format(nf)) end
            if was ~= p.fojji:IsShown() then p:Layout() end
        end
        local fresh, switch = p.fresh, p.switch
        p.fresh, p.switch = false, nil
        local all, counts = collect()
        -- Kacheln
        for i, t in ipairs(p.tiles) do
            local n = counts[t.key] or 0
            t:SetSel(filter == t.key)
            local vc = n > 0 and (t.col or C.text) or C.dim
            t.value:SetTextColor(vc[1], vc[2], vc[3])
            if fresh and animOn() then K.CountUp(t.value, n, 0.8, nil, (i - 1) * 0.05)
            elseif t.shown ~= n then t.value:SetText(n) end
            t.shown = n
            if t.key == "all" then t.sub:SetText(counts.mine > 0 and (L["%d von dir"]):format(counts.mine) or "") end
        end
        if fresh and animOn() then for i, t in ipairs(p.tiles) do K.FadeIn(t, (i - 1) * 0.05) end end
        p.tabs:SetCounts(counts)
        p.tabs:Select(filter, not fresh)
        -- Karten
        local vms = {}
        for _, w in ipairs(all) do
            local ok, v = pcall(vmWant, w)
            if ok and v then
                if passes(v) then vms[#vms + 1] = v end
            elseif not ok and ns.err then ns.err(L["Gesucht"], v) end
        end
        local items = arrange(vms)
        p.tl:SetItems(items, not (fresh or switch))
        if fresh or switch then p.tl:Stagger() end
        if p.scrollTo then
            local it = p.tl.byKey[p.scrollTo]
            p.scrollTo = nil
            if it then
                local H = p.tl:GetHeight() or 0
                if it.y < p.tl.off or it.y + it.h > p.tl.off + H then p.tl:ScrollTo(it.y - H_HEAD, true) end
            end
        end
        -- Leerzustand
        p.empty:SetShown(#items == 0)
        if #items == 0 then
            local function focusForm() p.itemBox:SetFocus() end
            if counts.all == 0 then
                p.empty:Set("wants", C.accent, L["Noch nichts auf der Wunschliste.\nTrag oben ein, was du brauchst - alle mit Oasis sehen es im Tooltip und beim Looten."],
                    L["Etwas eintragen"], focusForm)
            elseif search ~= "" then
                p.empty:Set("wants", C.muted, L["Nichts gefunden - andere Filter probieren?"], L["Filter zuruecksetzen"], function()
                    search = ""
                    p.search:SetText("")
                    switchTo("all")
                end)
            elseif filter == "mine" then
                p.empty:Set("profile", C.amber, L["Du suchst gerade nichts.\nWas fehlt dir noch? Die Gilde hilft."], L["Etwas eintragen"], focusForm)
            elseif filter == "deliver" then
                p.empty:Set("heart", C.mint, L["Gerade kannst du keinen Wunsch erfuellen.\nOasis meldet sich, sobald du etwas Gesuchtes lootest."], L["Alle Wuensche"], function() switchTo("all") end)
            elseif filter == "bank" then
                p.empty:Set("bank", PURPLE, L["Nichts davon liegt in der Gildenbank."], L["Alle Wuensche"], function() switchTo("all") end,
                    L["Gildenbank"], function() ns.ShowPage("bank") end)
            else
                p.empty:Set("crafting", C.blue, L["Fuer keinen Wunsch ist ein Rezept in der Gilde bekannt."], L["Alle Wuensche"], function() switchTo("all") end)
            end
        end
        -- Sortierknopf
        local sl
        for _, s in ipairs(SORTS) do if s.key == sortBy then sl = L[s.text] end end
        p.sort:SetLabel("|cff888888" .. L["Sortierung:"] .. "|r " .. (sl or "") .. "  |cff666666v|r")
        p.sort:SetWidth(math.floor((p.sort.label:GetStringWidth() or 100) + 24))
        -- Vorschau des gewaehlten Items
        local f = p.form
        local id = p.itemBox.pickedID
        if id then
            setAvatar(f.av, id, C.accent, false)
            local s = Wants.Sources({ itemID = id })
            local t = {}
            if s.have > 0 then t[#t + 1] = "|cff66db9e" .. (L["Du hast %d"]):format(s.have) .. "|r" end
            if s.bank > 0 then t[#t + 1] = "|cffb4a8ff" .. (L["In der Gildenbank: %d"]):format(s.bank) .. "|r" end
            if s.crafters and #s.crafters > 0 then t[#t + 1] = "|cff6099ff" .. (L["%d in der Gilde koennen es bauen"]):format(#s.crafters) .. "|r" end
            if s.price then t[#t + 1] = L["AH"] .. " ~" .. ns.Market.Format(s.price) .. L[" /Stk"] end
            f.info:SetText(#t > 0 and table.concat(t, "   ·   ") or ("|cff777777" .. L["Niemand in der Gilde hat es gerade - ab auf die Liste!"] .. "|r"))
        else
            setAvatar(f.av, nil, C.dim, false)
            f.info:SetText("|cff666666" .. L["Tippen - Oasis schlaegt Items vor (Taschen, Gildenbank, Rezepte, Dungeons, Auktionshaus)."] .. "|r")
        end
        p:Layout()
    end,
})

-- Item-Daten kommen nach: sichtbare Karten nachfuellen (gedrosselt, Leseposition bleibt)
local itemPend
local function itemsArrived()
    if itemPend or not (page and page.IsVisible and page:IsVisible()) then return end
    itemPend = true
    ns.After(0.6, function()
        itemPend = nil
        if page and page:IsVisible() then ns.RefreshPage("wants") end
    end)
end
pcall(ns.On, "GET_ITEM_INFO_RECEIVED", itemsArrived)
pcall(ns.On, "ITEM_DATA_LOAD_RESULT", itemsArrived)

ns.Listen("LOGIN", function()
    hookTooltips()
    ns.After(12, updateBadge)
end)

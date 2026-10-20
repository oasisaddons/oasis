-- Oasis: Item-Vorschlaege beim Tippen
-- Sammelt alle Items, die Oasis kennt (Taschen, Gildenbank, Rezepte + Material, Beute, Gesucht,
-- Dungeon-Beute, Midas-Scans), merkt sich ihre Namen je Sprache und schlaegt beim Tippen passende vor.
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local IS = {}
ns.ItemSearch = IS

local ids = {}          -- [itemID] = { bag = true, bank = true, ... }
local queue, queued = {}, {}
local collected = 0

local NAMES_MAX = 2000   -- Speicherdatei klein halten (der Client liefert Namen jederzeit wieder)
local namesCount
local function names()
    ns.db.itemNames = ns.db.itemNames or {}
    local loc = GetLocale and GetLocale() or "deDE"
    -- andere Sprachen nicht mitschleppen
    for k in pairs(ns.db.itemNames) do if k ~= loc then ns.db.itemNames[k] = nil end end
    ns.db.itemNames[loc] = ns.db.itemNames[loc] or {}
    return ns.db.itemNames[loc]
end

local function add(id, src)
    id = tonumber(id)
    if not id or id <= 0 then return end
    local e = ids[id]
    if not e then e = {} ids[id] = e end
    if src then e[src] = true end
end

-- Name aus Cache oder Client; unbekannte Items zum Nachladen vormerken
function IS.Name(id)
    local N = names()
    if N[id] then return N[id] end
    local n = C_Item and C_Item.GetItemNameByID and ns.safe(C_Item.GetItemNameByID(id))
    if n and n ~= "" then N[id] = n return n end
    if not queued[id] then queued[id] = true queue[#queue + 1] = id end
    return nil
end

function IS.Collect()
    -- eigene Taschen
    if C_Container and C_Container.GetContainerNumSlots then
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
                add(ns.safe(C_Container.GetContainerItemID(bag, slot)), "bag")
            end
        end
    end
    -- Gildenbank
    if ns.GuildBank and ns.GuildBank.AllItems then
        for _, e in ipairs(ns.GuildBank.AllItems()) do add(e.id, "bank") end
    end
    -- Rezepte der Gilde + Material
    if ns.Crafting then
        for _, e in ipairs(ns.Crafting.Index()) do if e.itemID then add(e.itemID, "craft") end end
    end
    for _, r in pairs(ns.db.reagents or {}) do for item in tostring(r):gmatch("(%d+):") do add(item, "mat") end end
    -- Gesucht, Beute
    for _, w in ipairs(Store.List("wants")) do add(w.itemID) end
    for _, x in ipairs(Store.List("loot")) do add(ns.itemID(x.item)) end
    -- Dungeon-Beute
    for _, d in ipairs(ns.DungeonData or {}) do
        for _, b in ipairs(d.bosses or {}) do
            for _, it in ipairs(b.loot or {}) do add(it[1], "dungeon") end
        end
    end
    -- Midas: alles, was im Auktionshaus gescannt wurde
    local db = _G.MidasDB
    for _, realm in pairs(db and db.realms or {}) do
        if type(realm) == "table" then for k in pairs(realm) do add(k, "ah") end end
    end
    -- schon bekannte Namen
    for id in pairs(names()) do add(id) end
    collected = GetTime()
end

-- Namen im Hintergrund nachladen (gedrosselt)
local loader = CreateFrame("Frame")
local acc = 0
loader:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.25 or #queue == 0 then return end
    acc = 0
    for _ = 1, 40 do
        local id = table.remove(queue)
        if not id then break end
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
end)
ns.On("GET_ITEM_INFO_RECEIVED", function(id, ok)
    id = ns.safe(id)
    if id and ok ~= false then
        local n = C_Item.GetItemNameByID and ns.safe(C_Item.GetItemNameByID(id))
        if n and n ~= "" then
            local t = names()
            if t[id] == nil then
                if not namesCount then namesCount = 0 for _ in pairs(t) do namesCount = namesCount + 1 end end
                -- Obergrenze: zu gross -> neu anfangen (der Client liefert Namen jederzeit wieder)
                if namesCount >= NAMES_MAX then wipe(t) namesCount = 0 end
                namesCount = namesCount + 1
            end
            t[id] = n
        end
    end
end)

-- Suche: Wortanfang schlaegt Teiltreffer, Items mit Bezug (Taschen, Bank ...) zuerst
local PRIO = { bag = 3, bank = 3, craft = 2, mat = 1, dungeon = 1, ah = 0 }
function IS.Find(q, max)
    q = (q or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if #q < 2 then return {} end
    if GetTime() - collected > 60 then IS.Collect() end
    local out = {}
    for id, src in pairs(ids) do
        local n = IS.Name(id)
        if n then
            local ln = n:lower()
            local pos = ln:find(q, 1, true)
            if pos then
                local score = (pos == 1 and 0) or ((ln:sub(pos - 1, pos - 1) == " " or ln:sub(pos - 1, pos - 1) == "-") and 1) or 2
                local bonus = 0
                for k in pairs(src) do bonus = math.max(bonus, PRIO[k] or 0) end
                out[#out + 1] = { id = id, name = n, score = score * 10 - bonus, src = src }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        if #a.name ~= #b.name then return #a.name < #b.name end
        return a.name < b.name
    end)
    local res = {}
    for i = 1, math.min(max or 8, #out) do res[i] = out[i] end
    return res
end
-- exakter Name -> ID (fuer Eingaben ohne Link)
function IS.ExactID(text)
    local q = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if q == "" then return nil end
    if GetTime() - collected > 60 then IS.Collect() end
    for id in pairs(ids) do
        local n = IS.Name(id)
        if n and n:lower() == q then return id, n end
    end
end
function IS.Link(id)
    local _, link = C_Item.GetItemInfo(id)
    if link then return link end
    local n = IS.Name(id) or ("#" .. id)
    return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. n .. "]|h|r"
end

------------------------------------------------------------------------
-- Vorschlagsliste unter einem Eingabefeld
------------------------------------------------------------------------
local ROWS = 8
local box, owner
local function hint(src, id)
    local t = {}
    if src.bag then
        local n = ns.Wants and ns.Wants.Count(id) or 0
        t[#t + 1] = "|cff66db9e" .. (n > 0 and ((L["You have %d"]):format(n)) or L["bags"]) .. "|r"
    end
    if src.bank then
        local n = ns.GuildBank and ns.GuildBank.Count(id) or 0
        t[#t + 1] = "|cffb4a8ff" .. (L["Bank %d"]):format(n) .. "|r"
    end
    if src.craft then t[#t + 1] = "|cff6099ff" .. L["craftable"] .. "|r" end
    if #t == 0 and src.dungeon then t[#t + 1] = "|cff888888" .. L["Dungeon"] .. "|r" end
    if #t == 0 and src.ah then t[#t + 1] = "|cff888888" .. L["AH"] .. "|r" end
    return table.concat(t, "  ")
end
local function build()
    box = CreateFrame("Frame", "OasisItemSuggest", UIParent)
    box:SetFrameStrata("FULLSCREEN_DIALOG")
    box:SetClampedToScreen(true)
    K.Fill(box, C.raised)
    K.Border(box, C.line)
    box.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, box)
        r:SetHeight(24)
        r:SetPoint("TOPLEFT", 1, -3 - (i - 1) * 24)
        r:SetPoint("RIGHT", box, "RIGHT", -1, 0)
        r.sel = r:CreateTexture(nil, "BACKGROUND")
        r.sel:SetAllPoints()
        r.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.18)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.06)
        r.icon = K.Icon(r, 18, nil)
        r.icon:SetPoint("LEFT", 6, 0)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("LEFT", 30, 0)
        r.name:SetPoint("RIGHT", r, "RIGHT", -110, 0)
        r.hint = K.Text(r, 10, C.muted, "RIGHT")
        r.hint:SetPoint("RIGHT", -8, 0)
        r:SetScript("OnClick", function(self) IS.Pick(self.id) end)
        r:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(box, "ANCHOR_RIGHT")
            pcall(GameTooltip.SetItemByID, GameTooltip, self.id)
            GameTooltip:Show()
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        box.rows[i] = r
    end
    box:Hide()
end

function IS.Hide() if box then box:Hide() end end
function IS.Pick(id)
    if not (owner and id) then return end
    local eb = owner
    IS.Hide()
    eb.pickedID = id
    eb.suppress = true
    eb:SetText(IS.Link(id))
    eb.suppress = false
    eb:SetCursorPosition(0)
    if eb.onPick then eb.onPick(id) end
end
local function show(eb, list)
    if not box then build() end
    owner = eb
    box.list, box.index = list, 1
    for i, r in ipairs(box.rows) do
        local e = list[i]
        if e then
            r.id = e.id
            r.icon:SetTexture(C_Item.GetItemIconByID(e.id) or 134400)
            local hex = "|cffe6e6e6"
            local ok, q = pcall(C_Item.GetItemQualityByID, e.id)
            q = ok and ns.safe(q)
            if q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then hex = ITEM_QUALITY_COLORS[q].hex end
            r.name:SetText(hex .. e.name .. "|r")
            r.hint:SetText(hint(e.src, e.id))
            r.sel:SetShown(i == 1)
            r:Show()
        else
            r:Hide()
        end
    end
    box:ClearAllPoints()
    box:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -2)
    box:SetSize(math.max(eb:GetWidth() or 300, 340), #list * 24 + 6)
    box:Show()
end
local function move(d)
    if not (box and box:IsShown() and box.list) then return end
    box.index = math.max(1, math.min(#box.list, (box.index or 1) + d))
    for i, r in ipairs(box.rows) do r.sel:SetShown(i == box.index) end
end

-- Eingabefeld mit Vorschlaegen ausstatten; onPick(itemID) optional
function IS.Attach(eb, onPick)
    eb.onPick = onPick
    eb:HookScript("OnTextChanged", function(self, user)
        if self.suppress then return end
        if user then self.pickedID = nil end
        local t = self:GetText() or ""
        if not user or t:find("|H", 1, true) or ns.db.settings.itemSuggest == false then IS.Hide() return end
        local list = IS.Find(t, ROWS)
        if #list == 0 then IS.Hide() else show(self, list) end
    end)
    eb:HookScript("OnEditFocusLost", function() ns.After(0.2, function() if owner == eb then IS.Hide() end end) end)
    eb:HookScript("OnEscapePressed", function() IS.Hide() end)
    eb:HookScript("OnArrowPressed", function(_, key)
        if key == "UP" then move(-1) elseif key == "DOWN" then move(1) end
    end)
    eb:HookScript("OnTabPressed", function(self)
        if box and box:IsShown() and owner == self and box.list then IS.Pick(box.list[box.index or 1].id) end
    end)
    -- Enter: markierten Vorschlag nehmen, sonst normales Enter des Feldes
    local enter = eb.onEnter
    eb.onEnter = function(text)
        if box and box:IsShown() and owner == eb and box.list and not eb.pickedID then
            IS.Pick(box.list[box.index or 1].id)
            return
        end
        if enter then enter(text) end
    end
end

ns.Listen("LOGIN", function()
    ns.After(20, function() pcall(IS.Collect) end)
end)

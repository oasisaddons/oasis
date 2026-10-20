-- Oasis: wishlist on the go
--  * Entering a dungeon: "3 of your wishlist items can drop here" (+ what guild groupmates are looking for here)
--  * Wunsch-Item gelootet: "Ziel erreicht!" (Klick = abhaken), Eintrag in "Mein Weg"
--  * Sets: group wishes into an own set ("Pre-Raid 7/12"); completed (deleted) ones count too
-- drop source: ns.Dungeons.Source (Oasis dungeon database + dungeon compass).
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_Wishlist", function()   -- can be disabled, see ModuleLoader.lua
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local WA = {}
ns.WishAlerts = WA

local function S() return ns.db.settings end
local function on(k) return S()[k] ~= false end

-- own open wishes
local function myOpen()
    local out = {}
    for _, w in ipairs(Store.List("wants")) do
        if ns.isMe(w.who) and (tonumber(w.itemID) or 0) > 0 then out[#out + 1] = w end
    end
    return out
end

------------------------------------------------------------------------
-- Sets
------------------------------------------------------------------------
-- progress of a set: done (deleted = checked off), total - own wishes only
function WA.SetProgress(name)
    if not name or name == "" then return 0, 0 end
    local done, total = 0, 0
    for _, w in pairs(Store.coll("wants")) do
        if w.set == name and ns.isMe(w.who) then
            total = total + 1
            if w.del then done = done + 1 end
        end
    end
    return done, total
end
function WA.SetText(name)
    local d, t = WA.SetProgress(name)
    return t > 0 and ("%s %d/%d"):format(name, d, t) or nil
end
-- all own set names (for the selection)
function WA.MySets()
    local seen, out = {}, {}
    for _, w in pairs(Store.coll("wants")) do
        if w.set and w.set ~= "" and ns.isMe(w.who) and not seen[w.set] then seen[w.set] = true out[#out + 1] = w.set end
    end
    table.sort(out)
    return out
end
function WA.AssignSet(w, name)
    local r = w and Store.Get("wants", w.id)
    if not r then return end
    local copy = {}
    for k, v in pairs(r) do copy[k] = v end
    name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 30)
    copy.set = name ~= "" and name or nil
    Store.Put("wants", copy)
end
StaticPopupDialogs["OASIS_WANT_SET"] = {
    text = "%s", button1 = OKAY or "OK", button2 = CANCEL, hasEditBox = true, maxLetters = 30,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self, data)
        local eb = self.editBox or self.EditBox
        if eb then eb:SetText(data and data.w and data.w.set or "") eb:HighlightText() eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = self.editBox or self.EditBox
        if data and data.w then WA.AssignSet(data.w, eb and eb:GetText() or "") end
    end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}
-- menu entries for an own wish
function WA.MenuItems(w)
    if not (w and ns.isMe(w.who)) then return {} end
    local m = {}
    for _, name in ipairs(WA.MySets()) do
        if name ~= w.set and #m < 6 then
            m[#m + 1] = { text = (L["To set: %s"]):format(name), fn = function() WA.AssignSet(w, name) end }
        end
    end
    m[#m + 1] = { text = w.set and L["Rename set / new set ..."] or L["Add to a set ..."], fn = function()
        StaticPopup_Show("OASIS_WANT_SET", L["Set name (e.g. Pre-Raid, Healer set):"], nil, { w = w })
    end }
    if w.set then m[#m + 1] = { text = L["Remove from set"], fn = function() WA.AssignSet(w, "") end } end
    return m
end

------------------------------------------------------------------------
-- entering a dungeon
------------------------------------------------------------------------
local function currentDungeon()
    local inInst, kind = IsInInstance()
    if not inInst or not (kind == "party" or kind == "raid") then return nil end
    local name = ns.safe(GetInstanceInfo())
    if not name or not (ns.Dungeons and ns.Dungeons.KeyByZone) then return nil end
    return ns.Dungeons and ns.Dungeons.KeyByZone(name), name
end
-- wishes that drop here: own + those of guild groupmates in the party
function WA.HereFor(key)
    local mine, group = {}, {}
    if not key or not (ns.Dungeons and ns.Dungeons.Source) then return mine, group end
    local inGroup = {}
    for i = 1, 4 do
        local n = ns.safe(ns.UnitName("party" .. i))
        if n then inGroup[ns.short(n):lower()] = true end
    end
    for _, w in ipairs(Store.List("wants")) do
        local id = tonumber(w.itemID) or 0
        if id > 0 then
            local src = ns.Dungeons and ns.Dungeons.Source(id)
            if src and src.key == key then
                if ns.isMe(w.who) then mine[#mine + 1] = { w = w, src = src }
                elseif inGroup[ns.short(w.who or ""):lower()] then group[#group + 1] = { w = w, src = src } end
            end
        end
    end
    return mine, group
end
local function itemText(w) return w.link or ("[" .. tostring(w.name or "?") .. "]") end
local lastKey
local function onEnter()
    local key, name = currentDungeon()
    if key == lastKey then return end
    lastKey = key
    if not key or not on("wantsDungeonHint") then return end
    local mine, group = WA.HereFor(key)
    if #mine == 0 and #group == 0 then return end
    ns.print("|cffffc24d" .. (L["Wishlist in %s:"]):format(name or key) .. "|r")
    for _, x in ipairs(mine) do
        ns.print("  " .. itemText(x.w) .. (x.src.boss and ("  |cff888888" .. x.src.boss .. "|r") or "")
            .. (x.w.set and ("  |cff66db9e" .. (WA.SetText(x.w.set) or "") .. "|r") or ""))
    end
    for _, x in ipairs(group) do
        ns.print("  " .. ns.displayName(x.w.who) .. ": " .. itemText(x.w) .. (x.src.boss and ("  |cff888888" .. x.src.boss .. "|r") or ""))
    end
    if ns.Sound and ns.Sound.Next then ns.Sound.Next("wants") end
    local title = #mine > 0 and ((#mine == 1 and L["1 wishlist item can drop here"]) or (L["%d of your wishlist items can drop here"]):format(#mine))
        or (L["Your group is looking for %d items here"]):format(#group)
    local sub = {}
    for i = 1, math.min(3, #mine) do sub[#sub + 1] = tostring(mine[i].w.name or "?") end
    if #group > 0 and #mine > 0 then sub[#sub + 1] = (L["+%d for the group"]):format(#group) end
    K.Toast(title, table.concat(sub, ", "), C.amber, function() ns.ShowPage("wants") end)
end
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(4, function() pcall(onEnter) end) end)
ns.On("ZONE_CHANGED_NEW_AREA", function() ns.After(4, function() pcall(onEnter) end) end)

------------------------------------------------------------------------
-- looted: goal reached
------------------------------------------------------------------------
local reached = {}
ns.On("CHAT_MSG_LOOT", function(text, playerName)
    text, playerName = ns.safe(text), ns.safe(playerName)
    if not text or not on("wantsGotHint") then return end
    if playerName and playerName ~= "" and ns.short(playerName) ~= ns.short(ns.me()) then return end
    -- only own loot ("You receive loot: ..."): for others' loot the name is in the text
    local id = tonumber(text:match("|Hitem:(%d+)"))
    if not id then return end
    for _, w in ipairs(myOpen()) do
        if tonumber(w.itemID) == id and not reached[w.id] then
            reached[w.id] = true
            local have = ns.Wants and ns.Wants.Count(id) or 0
            local qty = tonumber(w.qty) or 1
            if ns.Sound and ns.Sound.Next then ns.Sound.Next("record") end
            local setInfo = w.set and (" · " .. (WA.SetText(w.set) or "")) or ""
            if have >= qty then
                K.Toast(L["Goal reached!"], tostring(w.name or "?") .. setInfo .. "  -  " .. L["Click: tick off"], C.mint, function()
                    Store.Delete("wants", w.id)
                    if w.set then ns.After(0.2, function()
                        K.Toast(L["Set progress"], WA.SetText(w.set) or w.set, C.mint)
                    end) end
                end)
            else
                K.Toast(L["Wishlist item found"], (L["%s: %d of %d"]):format(tostring(w.name or "?"), have, qty) .. setInfo, C.mint,
                    function() ns.ShowPage("wants") end)
            end
            if ns.Life and ns.Life.Event then pcall(ns.Life.Event, "loot", (L["Wish fulfilled: %s"]):format(tostring(w.name or "?")), nil, w.link) end
        end
    end
end)

-- in-game test: /oa wunschtest -> pretends you just entered a dungeon
ns.slash.wunschtest = function() lastKey = nil pcall(onEnter) end
end)

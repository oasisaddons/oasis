-- Oasis: market prices (via Midas, otherwise own AH observation) + OasisAPI for other addons
--
-- Midas (auction house addon by Rebo) provides MidasAPI. If it is installed, Oasis uses
-- its prices. Without Midas, Oasis remembers the cheapest prices seen while browsing the
-- auction house and shares the prices of wanted items with the guild.
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local Market = {}
ns.Market = Market

------------------------------------------------------------------------
-- Midas
------------------------------------------------------------------------
function Market.HasMidas()
    local api = _G.MidasAPI
    if not api or not api.IsReady then return false end
    local ok, ready = pcall(api.IsReady)
    return ok and ready and true or false
end
function Market.MidasVersion()
    local api = _G.MidasAPI
    if not api or not api.GetVersion then return nil end
    local ok, v = pcall(api.GetVersion)
    return ok and v or nil
end

-- Price in copper + source ("midas" | "oasis")
function Market.Price(item)
    if not item or item == 0 then return nil end
    if Market.HasMidas() then
        local api = _G.MidasAPI
        local ok, p = pcall(api.GetFairPrice, item)
        if not (ok and p) then ok, p = pcall(api.GetCurrentPrice, item) end
        if ok and p then return p, "midas" end
    end
    local id = ns.itemID(item)
    -- 0.6.525: without Midas use the Auctionator price if installed
    local ap = id and ns.Compat and ns.Compat.AuctionatorPrice and ns.Compat.AuctionatorPrice(id)
    if ap then return ap, "auctionator" end
    local r = id and Store.Get("prices", "p-" .. id)
    if r and r.price then return r.price, "oasis", r.ts end
    return nil
end
-- 0.6.621: last auction house price Oasis saw, in the item tooltip. Not with Midas or Auctionator installed -
-- they show their own price line, two would only repeat each other.
function Market.TipLine(tt, id)
    local s = ns.db and ns.db.settings
    if not s or s.tipAhPrice == false or s.tipOasis == false or not id then return end
    if Market.HasMidas() or rawget(_G, "Auctionator") then return end
    local r = Store.Get("prices", "p-" .. id)
    if not (r and r.price) then return end
    tt:AddLine("|cffff1200Oasis|r  " .. L["Auction house:"] .. " " .. Market.Format(r.price) .. "  |cff888888" .. ns.ago(r.ts) .. "|r", 0.85, 0.85, 0.85)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        pcall(Market.TipLine, tt, data and ns.safe(data.id))
    end)
end
function Market.Info(item)
    if not Market.HasMidas() then return nil end
    local ok, info = pcall(_G.MidasAPI.GetMarketInfo, item)
    return ok and info or nil
end

function Market.Format(copper)
    if not copper then return "–" end
    copper = math.floor(copper + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
    if g > 0 then return ("%s|cffffd24ag|r %d|cffc0c0c0s|r"):format(g, s) end
    if s > 0 then return ("%d|cffc0c0c0s|r %d|cffb87333c|r"):format(s, c) end
    return ("%d|cffb87333c|r"):format(c)
end
-- "~1g 20s" with source as a tooltip line
function Market.Text(item, qty)
    local p, src = Market.Price(item)
    if not p then return nil end
    return "~" .. Market.Format(p * (qty or 1)), src
end

------------------------------------------------------------------------
-- Own price observation in the modern auction house (only without Midas)
------------------------------------------------------------------------
local function wanted(itemID)
    for _, w in ipairs(Store.List("wants")) do if w.itemID == itemID then return true end end
    return false
end
local function record(itemID, price)
    if not itemID or not price or price <= 0 or Market.HasMidas() then return end
    local id = "p-" .. itemID
    local old = Store.Get("prices", id)
    local fresh = old and (ns.now() - (old.ts or 0)) < 6 * 3600 and math.abs(old.price - price) / old.price < 0.05
    if fresh then return end
    local rec = { id = id, itemID = itemID, price = price, ts = ns.now(), by = ns.me(), u = ns.now() }
    -- only send prices of wanted items to the guild, everything else stays local
    if wanted(itemID) then Store.Put("prices", rec) else Store.merge("prices", rec) end
end

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then return end
    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    if not ok or type(results) ~= "table" then return end
    for _, r in ipairs(results) do
        local key = r.itemKey
        if key and key.itemID then record(key.itemID, ns.safe(r.minPrice)) end
    end
end)
ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if not (C_AuctionHouse and C_AuctionHouse.GetCommoditySearchResultInfo) then return end
    local ok, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
    if ok and type(info) == "table" then record(itemID, ns.safe(info.unitPrice)) end
end)
ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if not (C_AuctionHouse and C_AuctionHouse.GetItemSearchResultInfo) or type(itemKey) ~= "table" then return end
    local ok, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, 1)
    if ok and type(info) == "table" then record(itemKey.itemID, ns.safe(info.buyoutAmount or info.bidAmount)) end
end)

-- Midas reports new scans -> redraw Oasis pages with prices
ns.Listen("LOGIN", function()
    ns.After(5, function()
        local api = _G.MidasAPI
        if api and api.RegisterCallback then
            pcall(api.RegisterCallback, "SCAN_COMPLETE", function()
                ns.RefreshPage("wants")
                ns.RefreshPage("bank")
            end)
            pcall(api.RegisterCallback, "ANALYSIS_COMPLETE", function() ns.RefreshPage("wants") end)
        end
    end)
end)

------------------------------------------------------------------------
-- OasisAPI: Oasis data for other addons (e.g. Midas)
-- All getters return copies; item = ItemID or item link.
------------------------------------------------------------------------
local API = _G.OasisAPI or {}
_G.OasisAPI = API
API.API_VERSION = 1

function API.GetVersion() return ns.version, API.API_VERSION end
function API.IsReady() return ns.db ~= nil and ns.loggedIn == true end
-- Is the name a guild member? (with or without realm)
function API.IsGuildmate(name)
    if not name or not ns.Radar then return false end
    return ns.Radar.byName[ns.fullName(name)] ~= nil
end
-- Main character of a player (alt link)
function API.GetMain(name)
    if not name then return nil end
    local full = ns.fullName(name)
    return ns.Alts and ns.Alts.Main(full) or full
end
-- Who in the guild is looking for this item? -> { {who, qty, note}, ... }
function API.GetWanted(item)
    local id = ns.itemID(item)
    local out = {}
    for _, w in ipairs(Store.List("wants")) do
        if id and w.itemID == id then out[#out + 1] = { who = w.who, qty = w.qty or 1, note = w.note or "" } end
    end
    return out
end
-- How many are in the guild bank? -> count, time of the snapshot
function API.GetBankCount(item)
    local id = ns.itemID(item)
    if not id or not ns.GuildBank then return 0 end
    local newest = 0
    for _, t in ipairs(ns.GuildBank.Tabs()) do newest = math.max(newest, t.ts or 0) end
    return ns.GuildBank.Count(id), newest > 0 and newest or nil
end
-- Who in the guild can craft it? -> { names }
function API.GetCrafters(item)
    local id = ns.itemID(item)
    if not id or not ns.Crafting then return {} end
    local e = ns.Crafting.ForItem(id, C_Item.GetItemNameByID and C_Item.GetItemNameByID(id))
    local out = {}
    if e then for _, n in ipairs(e.crafters) do out[#out + 1] = n end end
    return out
end
-- Open crafting orders for the item
function API.GetOpenOrders(item)
    local id = ns.itemID(item)
    local out = {}
    for _, o in ipairs(Store.List("orders")) do
        if (o.status == "open" or o.status == "accepted") and id and o.item == id then
            out[#out + 1] = { from = o.from, qty = o.qty or 1, status = o.status, worker = o.worker }
        end
    end
    return out
end

-- Callbacks: fn(event, payload)
local callbacks = {}
function API.RegisterCallback(event, fn)
    callbacks[event] = callbacks[event] or {}
    table.insert(callbacks[event], fn)
end
function API.UnregisterCallback(event, fn)
    for i, f in ipairs(callbacks[event] or {}) do if f == fn then table.remove(callbacks[event], i) return end end
end
local EVENT_OF = { wants = "WANTS_UPDATED", bank = "BANK_UPDATED", orders = "ORDERS_UPDATED" }
ns.Listen("STORE", function(coll, rec)
    local ev = EVENT_OF[coll]
    if not ev or not callbacks[ev] then return end
    for _, fn in ipairs(callbacks[ev]) do pcall(fn, ev, { id = rec.id }) end
end)

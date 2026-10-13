-- Oasis Modul 2: Handwerks-Boerse (Rezepte der Gilde + Auftraege)
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

local Crafting = {}
ns.Crafting = Crafting

-- Gilden-Optionen (Gildenleitung)
ns.GuildOption({ page = "crafting", key = "crOffMod", default = true, lead = true, label = "Offiziere verwalten fremde Auftraege",
    desc = "Offiziere duerfen Auftraege anderer Mitglieder stornieren und erledigte entfernen" })
ns.GuildOption({ page = "crafting", key = "crBdgMax", default = 5, min = 1, max = 20, step = 1, label = "Abzeichen-Zaehlung je Auftrag",
    desc = "So viele Stueck eines Auftrags zaehlen hoechstens fuer das Handwerker-Abzeichen",
    fmt = function(v) return v .. " Stk" end })
local function canModerate() return ns.isOfficer() and ns.GuildOpt("crOffMod") ~= false end

------------------------------------------------------------------------
-- Eigene Rezepte erfassen (sobald ein Berufsfenster offen ist)
------------------------------------------------------------------------
local function computeHash(recipes)
    local keys = {}
    for prof, list in pairs(recipes) do
        for id, v in pairs(list) do keys[#keys + 1] = prof .. ":" .. id .. ":" .. tostring(v) end
    end
    if #keys == 0 then return "" end
    table.sort(keys)
    return ns.hash(table.concat(keys, ","))
end

function Crafting.myHash()
    return ns.char and computeHash(ns.char.recipes) or ""
end

local function mirrorOwn()
    local me = ns.me()
    ns.db.recipes[me] = { hash = Crafting.myHash(), u = ns.now(), profs = ns.char.recipes }
    Crafting.dirty = true
end

local function scan()
    local T = C_TradeSkillUI
    if not T or not T.GetAllRecipeIDs then return end
    if T.IsTradeSkillLinked and T.IsTradeSkillLinked() then return end
    if T.IsTradeSkillGuild and T.IsTradeSkillGuild() then return end
    if T.IsNPCCrafting and T.IsNPCCrafting() then return end
    local info = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local prof = info and ns.safe(info.professionName)
    if (not prof or prof == "") and T.GetChildProfessionInfo then
        local ci = T.GetChildProfessionInfo()
        prof = ci and ns.safe(ci.parentProfessionName or ci.professionName)
    end
    if not prof or prof == "" then return end
    local ids = T.GetAllRecipeIDs()
    if not ids or #ids == 0 then return end
    local list, n = {}, 0
    for _, id in ipairs(ids) do
        local r = T.GetRecipeInfo(id)
        if r and r.learned and ns.safe(r.name) then
            -- hergestelltes Item merken (fuer Tooltips): "Name@ItemID"
            local itemID
            if T.GetRecipeSchematic then
                local ok, sch = pcall(T.GetRecipeSchematic, id, false)
                if ok and type(sch) == "table" then
                    itemID = ns.safe(sch.outputItemID)
                    local parts = {}
                    for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
                        local r = slot.reagents and slot.reagents[1]
                        local need = ns.safe(slot.quantityRequired) or 0
                        if r and r.itemID and need > 0 and (slot.reagentType == nil or slot.reagentType == 1) then
                            parts[#parts + 1] = r.itemID .. ":" .. need
                        end
                    end
                    if #parts > 0 then
                        ns.db.reagents = ns.db.reagents or {}
                        ns.db.reagents[id] = table.concat(parts, ",")
                    end
                end
            end
            if not itemID and T.GetRecipeItemLink then
                local ok, l = pcall(T.GetRecipeItemLink, id)
                if ok then itemID = ns.itemID(ns.safe(l)) end
            end
            list[id] = itemID and (r.name .. "@" .. itemID) or r.name
            n = n + 1
        end
    end
    if n == 0 then return end
    local before = Crafting.myHash()
    ns.char.recipes[prof] = list
    mirrorOwn()
    if Crafting.myHash() ~= before then
        ns.print(("%d Rezepte (%s) erfasst und fuer die Gilde freigegeben."):format(n, prof))
        ns.Radar.SendHello()
        ns.RefreshPage("crafting")
    end
end
local scanPending
local function scanSoon()
    if scanPending then return end
    scanPending = true
    ns.After(1.5, function()
        scanPending = nil
        scan()
    end)
end
ns.On("TRADE_SKILL_SHOW", scanSoon)
ns.On("TRADE_SKILL_LIST_UPDATE", scanSoon)
ns.On("TRADE_SKILL_DATA_SOURCE_CHANGED", scanSoon)
ns.On("NEW_RECIPE_LEARNED", scanSoon)

------------------------------------------------------------------------
-- Rezepte austauschen
------------------------------------------------------------------------
local requested = {}
local incoming = {}

ns.Listen("PROFILE", function(name, p)
    if not p.rh or p.rh == "" or ns.isMe(name) then return end
    local have = ns.db.recipes[name]
    if have and have.hash == p.rh then return end
    if requested[name] and GetTime() - requested[name] < 180 then return end
    requested[name] = GetTime()
    ns.After(math.random(10, 80) / 10, function() Comm.Whisper(name, "RREQ") end)
end)

local answered = {}
Comm.On("RREQ", function(sender)
    if answered[sender] and GetTime() - answered[sender] < 60 then return end
    answered[sender] = GetTime()
    for prof, list in pairs(ns.char.recipes) do
        local rec = {}
        for id, name in pairs(list) do rec[tostring(id)] = name end
        Comm.Whisper(sender, "RDATA", prof, Comm.encodeRecord(rec))
    end
    Comm.Whisper(sender, "RDONE", Crafting.myHash())
end)
-- Rezeptlisten nur nach eigener Anfrage annehmen, begrenzt (Berufe, Rezepte, Namenslaenge) - sonst
-- koennte jeder die gespeicherten Daten (SavedVariables) beliebig aufblaehen
local function askedFrom(sender) return requested[sender] and GetTime() - requested[sender] < 300 end
Comm.On("RDATA", function(sender, _, prof, rec)
    if not prof or not rec or not askedFrom(sender) then return end
    prof = SEC.Text(prof, 40)
    incoming[sender] = incoming[sender] or {}
    local nprof = 0
    for _ in pairs(incoming[sender]) do nprof = nprof + 1 end
    if nprof >= 8 and not incoming[sender][prof] then return end
    local list, n = {}, 0
    local decoded = Comm.decodeRecord(rec)
    if not decoded then incoming[sender] = nil requested[sender] = nil return end
    for id, name in pairs(decoded) do
        local nid = SEC.Num(id, 1, 99999999, true)
        if nid and n < 1000 then
            n = n + 1
            list[nid] = type(name) == "string" and SEC.Text(name, 80) or name
        end
    end
    incoming[sender][prof] = list
end)
Comm.On("RDONE", function(sender, _, hash)
    if not askedFrom(sender) or not incoming[sender] then return end
    ns.db.recipes[sender] = { hash = tostring(hash or ""):sub(1, 40), u = ns.now(), profs = incoming[sender] or {} }
    incoming[sender] = nil
    Crafting.dirty = true
    ns.RefreshPage("crafting")
end)

------------------------------------------------------------------------
-- Suchindex: Rezeptname / hergestelltes Item -> Handwerker
------------------------------------------------------------------------
-- Rezept-/Berufsnamen in der eigenen Sprache (Rezept-IDs sind Zauber-IDs)
local nameCache, profCache = {}, {}
function Crafting.LocalName(recipeID, itemID, fallback)
    local key = (recipeID or 0) .. ":" .. (itemID or 0)
    if nameCache[key] then return nameCache[key] end
    local n
    if itemID and C_Item.GetItemNameByID then n = ns.safe(C_Item.GetItemNameByID(itemID)) end
    if not n and recipeID and C_Spell and C_Spell.GetSpellName then
        local ok, s = pcall(C_Spell.GetSpellName, recipeID)
        if ok then n = ns.safe(s) end
    end
    if n and n ~= "" then nameCache[key] = n return n end
    if itemID then
        Crafting.waitNames[itemID] = true   -- Name kommt spaeter (GET_ITEM_INFO_RECEIVED)
        if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    end
    return fallback
end
function Crafting.LocalProf(recipeID, fallback)
    if not recipeID then return fallback end
    if profCache[recipeID] ~= nil then return profCache[recipeID] or fallback end
    local T = C_TradeSkillUI
    if T and T.GetProfessionInfoByRecipeID then
        local ok, info = pcall(T.GetProfessionInfoByRecipeID, recipeID)
        local n = ok and type(info) == "table" and ns.safe(info.parentProfessionName or info.professionName)
        if n and n ~= "" then profCache[recipeID] = n return n end
    end
    profCache[recipeID] = false
    return fallback
end
-- Name eines Materials: kennt der Client das Item noch nicht, wird es angefordert (GET_ITEM_INFO_RECEIVED zeichnet
-- die Seite neu) und bis dahin stehen drei Punkte da - nie die nackte Nummer ("#2452").
function Crafting.MatName(itemID)
    local n = C_Item.GetItemNameByID and ns.safe(C_Item.GetItemNameByID(itemID))
    if n and n ~= "" then return n end
    n = ns.ItemSearch and ns.ItemSearch.Name and ns.ItemSearch.Name(itemID)   -- gemerkte Namen dieser Sprache
    if n and n ~= "" then return n end
    if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
    return "..."
end
-- Item-Namen kommen verzoegert: nur wenn ein im Index noch fehlender Name ankommt, den Index neu bauen -
-- gebuendelt nach 1 s (Performance 0.5.482: vorher machte JEDES geladene Item - Tooltips, Taschen, Chat -
-- den Index ungueltig, er wurde dann bei fast jedem Tooltip komplett neu gebaut)
Crafting.waitNames = {}
local rebuildPending = false
ns.On("GET_ITEM_INFO_RECEIVED", function(itemID)
    itemID = ns.safe(itemID)
    if not (Crafting.cache and itemID and Crafting.waitNames[itemID]) then return end
    Crafting.waitNames[itemID] = nil
    if rebuildPending then return end
    rebuildPending = true
    C_Timer.After(1, function() rebuildPending = false Crafting.dirty = true end)
end)

function Crafting.Split(v)
    local name, item = tostring(v):match("^(.*)@(%d+)$")
    if name then return name, tonumber(item) end
    return tostring(v), nil
end

function Crafting.Index()
    if Crafting.cache and not Crafting.dirty then return Crafting.cache end
    local idx, byItem, list = {}, {}, {}
    for member, data in pairs(ns.db.recipes) do
        for prof, recipes in pairs(data.profs or {}) do
            for id, v in pairs(recipes) do
                local name, itemID = Crafting.Split(v)
                name = Crafting.LocalName(tonumber(id), itemID, name)
                local e = idx[name]
                if not e then
                    e = { name = name, prof = Crafting.LocalProf(tonumber(id), prof), id = tonumber(id), crafters = {} }
                    idx[name] = e
                    list[#list + 1] = e
                end
                if itemID and not e.itemID then e.itemID = itemID end
                if e.itemID then byItem[e.itemID] = e end
                e.crafters[#e.crafters + 1] = member
            end
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    Crafting.cache, Crafting.byName, Crafting.byItem, Crafting.dirty = list, idx, byItem, false
    return list
end
function Crafting.ForItem(itemID, name)
    Crafting.Index()
    return (itemID and Crafting.byItem[itemID]) or (name and Crafting.byName[name]) or nil
end
function Crafting.CanCraft(member, recipeName, recipeID)
    if recipeID and recipeID ~= 0 then
        local d = ns.db.recipes[member]
        for _, list in pairs(d and d.profs or {}) do
            if list[recipeID] or list[tostring(recipeID)] then return true end
        end
        return false
    end
    Crafting.Index()
    local e = Crafting.byName[recipeName]
    if not e then return false end
    local want = ns.Radar.byName[member]
    for _, m in ipairs(e.crafters) do
        if m == member or (want and ns.Radar.byName[m] == want) then return true end
    end
    return false
end
-- Anzeigename eines Auftrags in der eigenen Sprache
function Crafting.OrderName(o)
    return Crafting.LocalName(o.rid ~= 0 and o.rid or nil, o.item ~= 0 and o.item or nil, o.recipe or "?")
end

------------------------------------------------------------------------
-- Auftraege
------------------------------------------------------------------------
local STATUS = {
    open = { "Offen", C.amber },
    accepted = { "In Arbeit", C.blue },
    done = { "Fertig", C.mint },
    cancel = { "Storniert", C.dim },
    declined = { "Abgelehnt", C.red },
}
ns.Relabel(function()
    STATUS.open[1], STATUS.accepted[1], STATUS.done[1] = L["Offen"], L["In Arbeit"], L["Fertig"]
    STATUS.cancel[1], STATUS.declined[1] = L["Storniert"], L["Abgelehnt"]
end)
-- offene Auftraege an alle: "ablehnen" blendet sie nur fuer dich aus
local function hiddenForMe(o)
    return ns.db and ns.db.ordersHidden and ns.db.ordersHidden[o.id] and true or false
end

function Crafting.Relevant(o)
    local me = ns.me()
    if o.status == "done" or o.status == "cancel" or o.status == "declined" then return false end
    if hiddenForMe(o) then return false end
    if ns.isMe(o.to) then return true end
    if (o.to == nil or o.to == "") and o.status == "open" and Crafting.CanCraft(me, o.recipe, o.rid) then return true end
    return false
end

local function updateBadge()
    local n = 0
    for _, o in ipairs(Store.List("orders")) do
        if Crafting.Relevant(o) and o.from ~= ns.me() then n = n + 1 end
    end
    if ns.db.settings.craftBadge == false then n = 0 end
    ns.SetNavBadge("crafting", n > 0 and tostring(n) or "")
    Crafting.badge = n
    ns.Fire("BADGES")
end
Crafting.UpdateBadge = updateBadge

ns.Listen("STORE", function(coll, rec, old)
    if coll ~= "orders" then return end
    local me = ns.me()
    if not old and not rec.del and rec.from ~= me and Crafting.Relevant(rec) then
        ns.Sound.Next("order")
        K.Toast(L["Neuer Handwerks-Auftrag"], (L["%s moechte %dx %s"]):format(ns.displayName(rec.from), rec.qty or 1, Crafting.OrderName(rec)), C.amber,
            function() ns.ShowPage("crafting") end)
    elseif old and rec.from == me and old.status ~= rec.status and ns.db.settings.craftStatusToasts ~= false then
        if rec.status == "accepted" then
            K.Toast(L["Auftrag angenommen"], (L["%s kuemmert sich um %s"]):format(ns.displayName(rec.worker or "?"), Crafting.OrderName(rec)), C.blue)
        elseif rec.status == "done" then
            ns.Sound.Next("order")
            K.Toast(L["Auftrag fertig!"], (L["%s hat %s hergestellt"]):format(ns.displayName(rec.worker or "?"), Crafting.OrderName(rec)), C.mint)
        elseif rec.status == "declined" then
            K.Toast(L["Auftrag abgelehnt"], (L["%s kann %s gerade nicht herstellen"]):format(ns.displayName(rec.declinedBy or "?"), Crafting.OrderName(rec)), C.red,
                function() ns.ShowPage("crafting") end)
        elseif rec.status == "open" and old.status == "accepted" then
            K.Toast(L["Auftrag zurueckgegeben"], (L["%s ist wieder offen fuer alle"]):format(Crafting.OrderName(rec)), C.amber)
        end
    end
    ns.Debounce("craftStore", 0.4, function() updateBadge() ns.RefreshPage("crafting") end)
end)

function Crafting.NewOrder(recipe, prof, to, qty, note, recipeID, itemID, extra)
    local rec = {
        id = ns.newId("ord"), recipe = recipe, prof = prof or "", to = to or "",
        rid = recipeID or 0, item = itemID or 0,
        qty = qty or 1, note = note or "", from = ns.me(), status = "open", created = ns.now(),
    }
    for k, v in pairs(extra or {}) do rec[k] = v end
    Store.Put("orders", rec)
end
local function setStatus(o, status)
    local r = {}
    for k, v in pairs(o) do r[k] = v end
    r.status = status
    if status == "accepted" then r.worker = ns.me() end
    if status == "declined" then r.declinedBy = ns.me() r.worker = nil end
    if status == "open" then r.worker = nil end
    Store.Put("orders", r)
    -- eigene Auftraege zaehlen nicht, und hoechstens 5 Stueck pro Auftrag (sonst liesse sich das aufblasen)
    if status == "done" and ns.isMe(r.worker) and not ns.isMe(r.from) then
        if ns.Badges then ns.Badges.Add("crafted", math.min(tonumber(ns.GuildOpt("crBdgMax")) or 5, math.max(1, tonumber(r.qty) or 1))) end
        if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("crafted", r.from) end
    end
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local search, selected, orderFilter, chosenCrafter = "", nil, "tome", nil
local profFilter, onlyOnline, mode, crafterFilter = nil, false, "recipes", nil
local onlyMine, onlyWanted, onlyFav = false, false, false
-- Favoriten (pro Charakter): immer oben, eigener Filter
local function favs()
    ns.char.craftFav = ns.char.craftFav or {}
    return ns.char.craftFav
end
local function isFav(e) return e and e.name and favs()[e.name] and true or false end
Crafting.IsFav = isFav
local qty, withMats = 1, false
local noteBox, tipBox

------------------------------------------------------------------------
-- Hilfen: Symbol, Qualitaet, Material, Handwerker
------------------------------------------------------------------------
local function profIdOf(name) return ns.Radar.ProfId({ name = name or "" }) end

function Crafting.Icon(e)
    if e.itemID and C_Item and C_Item.GetItemIconByID then
        local ok, t = pcall(C_Item.GetItemIconByID, e.itemID)
        if ok and ns.safe(t) then return t end
    end
    if e.id and C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, e.id)
        if ok and ns.safe(t) then return t end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end
function Crafting.QualityHex(itemID)
    if not itemID or not (C_Item and C_Item.GetItemQualityByID) then return "|cffe6e6e6" end
    local ok, q = pcall(C_Item.GetItemQualityByID, itemID)
    q = ok and ns.safe(q)
    local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    return c and c.hex or "|cffe6e6e6"
end

-- Material: aus eigenem Scan oder Blizzards Rezept-Schema
local reagentCache = {}
function Crafting.Reagents(e)
    if not e or not e.id then return nil end
    if reagentCache[e.id] ~= nil then return reagentCache[e.id] or nil end
    local out
    local own = ns.db.reagents and ns.db.reagents[e.id]
    if own and own ~= "" then
        out = {}
        for item, n in own:gmatch("(%d+):(%d+)") do out[#out + 1] = { itemID = tonumber(item), qty = tonumber(n) } end
    elseif C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, e.id, false)
        if ok and type(sch) == "table" and type(sch.reagentSlotSchematics) == "table" then
            out = {}
            for _, slot in ipairs(sch.reagentSlotSchematics) do
                local r = slot.reagents and slot.reagents[1]
                local need = ns.safe(slot.quantityRequired) or 0
                if r and r.itemID and need > 0 and (slot.reagentType == nil or slot.reagentType == 1) then
                    out[#out + 1] = { itemID = r.itemID, qty = need }
                end
            end
        end
    end
    if out and #out == 0 then out = nil end
    reagentCache[e.id] = out or false
    return out
end

-- alle Handwerker eines Rezepts (Oasis + Blizzard-Rezeptsuche), online zuerst
function Crafting.CraftersOf(e)
    local out, seen = {}, {}
    local function add(m, blizz)
        if seen[m] then return end
        seen[m] = true
        out[#out + 1] = { name = m, online = ns.isMe(m) or ns.Radar.IsOnline(m), blizz = blizz }
    end
    for _, m in ipairs(e.crafters) do add(m) end
    for _, m in ipairs(e.id and Crafting.blizz[e.id] or {}) do add(m, true) end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return out
end
local function onlineCount(e)
    local n = 0
    for _, c in ipairs(Crafting.CraftersOf(e)) do if c.online and not ns.isMe(c.name) then n = n + 1 end end
    return n
end
-- Berufsstufe eines Mitglieds in einem Beruf (aus dem Profil)
function Crafting.SkillOf(member, profName)
    local pid = profIdOf(profName)
    local pr = ns.db.members[member]
    local raw = pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[member])
    for _, pf in ipairs(ns.Radar.decodeProfs(raw)) do
        if ns.Radar.ProfId(pf) == pid then return pf.rank, pf.max end
    end
end
-- von anderen gesucht?
local function wantedBy(e)
    if not e.itemID or not ns.Wants then return nil end
    local who = {}
    for _, w in ipairs(ns.Wants.ForItem(e.itemID)) do if not ns.isMe(w.who) then who[#who + 1] = w.who end end
    return #who > 0 and who or nil
end

local function filteredRecipes()
    local q = search:lower()
    local me = ns.me()
    local out = {}
    for _, e in ipairs(Crafting.Index()) do
        local ok = q == "" or e.name:lower():find(q, 1, true) or e.prof:lower():find(q, 1, true)
        if ok and profFilter and profIdOf(e.prof) ~= profFilter then ok = false end
        if ok and crafterFilter then
            ok = false
            local want = ns.Radar.byName[crafterFilter]
            for _, m in ipairs(e.crafters) do
                if m == crafterFilter or (want and ns.Radar.byName[m] == want) or (ns.isMe(m) and ns.isMe(crafterFilter)) then ok = true end
            end
        end
        if ok and onlyOnline and onlineCount(e) == 0 then ok = false end
        if ok and onlyMine and not Crafting.CanCraft(me, e.name, e.id) then ok = false end
        if ok and onlyWanted and not wantedBy(e) then ok = false end
        if ok and onlyFav and not isFav(e) then ok = false end
        if ok then out[#out + 1] = e end
    end
    -- Favoriten nach oben, Reihenfolge sonst unveraendert
    local pos = {}
    for i, e in ipairs(out) do pos[e] = i end
    table.sort(out, function(a, b)
        local fa, fb = isFav(a), isFav(b)
        if fa ~= fb then return fa end
        return pos[a] < pos[b]
    end)
    return out
end

-- Handwerker-Uebersicht: Beruf -> Mitglieder mit Stufe
local function crafterRows()
    local byProf, names = {}, {}
    local function add(member, pf)
        local pid = ns.Radar.ProfId(pf)
        if not pid or not ns.Radar.CRAFT_PROFS[pid] or (profFilter and pid ~= profFilter) then return end
        local online = ns.isMe(member) or ns.Radar.IsOnline(member)
        if onlyOnline and not online then return end
        local g = byProf[pid]
        if not g then
            g = { pid = pid, name = pf.name, list = {}, seen = {} }
            byProf[pid] = g
            names[#names + 1] = pid
        end
        if g.seen[member] then return end
        g.seen[member] = true
        local n = 0
        local d = ns.db.recipes[member]
        for _, l in pairs(d and d.profs or {}) do for _ in pairs(l) do n = n + 1 end end
        g.list[#g.list + 1] = { member = member, rank = pf.rank, max = pf.max, online = online, recipes = n }
    end
    for _, m in ipairs(ns.Radar.roster) do
        local pr = ns.db.members[m.name]
        local raw = pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[m.name])
        for _, pf in ipairs(ns.Radar.decodeProfs(raw)) do add(m.name, pf) end
    end
    local q = search:lower()
    local out = {}
    table.sort(names, function(a, b) return (byProf[a].name or "") < (byProf[b].name or "") end)
    for _, pid in ipairs(names) do
        local g = byProf[pid]
        local rows = {}
        for _, x in ipairs(g.list) do
            if q == "" or x.member:lower():find(q, 1, true) or (g.name or ""):lower():find(q, 1, true) then rows[#rows + 1] = x end
        end
        if #rows > 0 then
            table.sort(rows, function(a, b)
                if a.online ~= b.online then return a.online end
                return (a.rank or 0) > (b.rank or 0)
            end)
            out[#out + 1] = { header = true, pid = pid, name = g.name, n = #rows }
            for _, x in ipairs(rows) do x.pid = pid out[#out + 1] = x end
        end
    end
    return out
end
local function allProfIds()
    local seen, out = {}, {}
    for _, e in ipairs(Crafting.Index()) do
        local pid = profIdOf(e.prof)
        if pid and not seen[pid] then seen[pid] = true out[#out + 1] = { pid = pid, name = e.prof } end
    end
    for _, m in ipairs(ns.Radar.roster) do
        local pr = ns.db.members[m.name]
        for _, pf in ipairs(ns.Radar.decodeProfs(pr and pr.profs)) do
            local pid = ns.Radar.ProfId(pf)
            if pid and ns.Radar.CRAFT_PROFS[pid] and not seen[pid] then seen[pid] = true out[#out + 1] = { pid = pid, name = pf.name } end
        end
    end
    table.sort(out, function(a, b) return a.pid < b.pid end)
    return out
end

------------------------------------------------------------------------
-- Blizzard-Gildenberufe: Berufe aller Mitglieder (auch ohne Oasis)
-- und "wer in der Gilde kann dieses Rezept" ueber Blizzards Rezeptsuche
------------------------------------------------------------------------
Crafting.blizz = {}   -- [recipeID] = { Namen }
local function scanGuildTradeSkills()
    if not (GetNumGuildTradeSkill and GetGuildTradeSkillInfo) then return end
    -- eingeklappte Berufe aufklappen, sonst fehlen die Mitglieder
    for i = 1, (GetNumGuildTradeSkill() or 0) do
        local skillID, collapsed, _, header = GetGuildTradeSkillInfo(i)
        if header and collapsed and ExpandGuildTradeSkillHeader then ExpandGuildTradeSkillHeader(skillID) end
    end
    local out, prof = {}, nil
    for i = 1, (GetNumGuildTradeSkill() or 0) do
        local skillID, _, _, header, _, _, _, playerName, fullName, _, _, _, skill = GetGuildTradeSkillInfo(i)
        if header then
            prof = { name = header, id = skillID }
        elseif prof and (fullName or playerName) then
            local n = ns.fullName(fullName or playerName)
            out[n] = out[n] or {}
            table.insert(out[n], prof.name .. "/" .. (skill or 0) .. "/0/" .. (prof.id or 0))
        end
    end
    ns.db.guildProfs = {}
    for n, list in pairs(out) do ns.db.guildProfs[n] = table.concat(list, "+") end
    ns.RefreshPage("radar")
end
ns.On("GUILD_TRADESKILL_UPDATE", function() ns.After(1, scanGuildTradeSkills) end)
ns.Listen("LOGIN", function()
    ns.db.guildProfs = ns.db.guildProfs or {}
    ns.After(15, function() if QueryGuildRecipes then pcall(QueryGuildRecipes) end end)
    ns.Every(900, function() if QueryGuildRecipes then pcall(QueryGuildRecipes) end end)
end)

local lastQuery = 0
function Crafting.QueryBlizzard(recipeID)
    if not recipeID or not (C_GuildInfo and C_GuildInfo.QueryGuildMembersForRecipe) then return end
    if GetTime() - lastQuery < 1 then return end
    lastQuery = GetTime()
    pcall(C_GuildInfo.QueryGuildMembersForRecipe, recipeID)
end
ns.On("GUILD_RECIPE_KNOWN_BY_MEMBERS", function()
    if not GetGuildRecipeInfoPostQuery then return end
    local _, recipeID, num = GetGuildRecipeInfoPostQuery()
    if not recipeID then return end
    local names = {}
    for i = 1, (num or 0) do
        local name = GetGuildRecipeMember(i)
        if name then names[#names + 1] = ns.fullName(name) end
    end
    Crafting.blizz[recipeID] = names
    ns.RefreshPage("crafting")
end)

function Crafting.CrafterText(e, max)
    local on, off = {}, {}
    local seen = {}
    for _, m in ipairs(e.crafters) do
        seen[m] = true
        if ns.Radar.IsOnline(m) or ns.isMe(m) then on[#on + 1] = ns.Radar.Label(m) else off[#off + 1] = "|cff777777" .. ns.displayName(m) .. "|r" end
    end
    -- zusaetzlich aus Blizzards Rezeptsuche (Mitglieder ohne Oasis)
    for _, m in ipairs(e.id and Crafting.blizz[e.id] or {}) do
        if not seen[m] then
            seen[m] = true
            if ns.Radar.IsOnline(m) then on[#on + 1] = ns.Radar.Colored(m) .. "|cff777777*|r" else off[#off + 1] = "|cff777777" .. ns.displayName(m) .. "*|r" end
        end
    end
    local all = {}
    for _, x in ipairs(on) do all[#all + 1] = x end
    for _, x in ipairs(off) do all[#all + 1] = x end
    if max and #all > max then
        local rest = #all - max
        local t = {}
        for i = 1, max do t[i] = all[i] end
        return table.concat(t, ", ") .. L[" |cff777777+"] .. rest .. "|r"
    end
    return table.concat(all, ", ")
end

local function orderSets()
    local me = ns.me()
    local sets = { tome = {}, mine = {}, open = {}, done = {} }
    for _, o in ipairs(Store.List("orders")) do
        local closed = o.status == "done" or o.status == "cancel" or o.status == "declined"
        if closed then
            sets.done[#sets.done + 1] = o
        else
            sets.open[#sets.open + 1] = o
            if o.from == me then
                sets.mine[#sets.mine + 1] = o
            elseif Crafting.Relevant(o) or (o.worker == me and o.status == "accepted") then
                sets.tome[#sets.tome + 1] = o
            end
        end
    end
    for _, l in pairs(sets) do table.sort(l, function(a, b) return (a.u or 0) > (b.u or 0) end) end
    return sets
end

local function orderEntry(o)
    return { id = o.rid ~= 0 and o.rid or nil, itemID = o.item ~= 0 and o.item or nil }
end

local function showItemTip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ok
    if e.itemID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, e.itemID) end
    if not ok and e.id then ok = pcall(GameTooltip.SetSpellByID, GameTooltip, e.id) end
    if ok then GameTooltip:Show() else GameTooltip:Hide() end
end

------------------------------------------------------------------------
-- Seite (Neugestaltung): Bausteine
------------------------------------------------------------------------
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local EMBER = ns.MEDIA .. "ember"
local ICO = ns.MEDIA .. "icons\\"
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CHECK_TEX = "Interface\\RaidFrame\\ReadyCheck-Ready"
local GOLD_TEX = "Interface\\MoneyFrame\\UI-GoldIcon"
local QCOL = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 0.86, 0.86, 0.88 }, [2] = { 0.12, 1, 0 }, [3] = { 0.1, 0.5, 0.95 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 } }
local H_HEAD, H_ROW, H_CRAFTER, H_ORDER = 26, 36, 34, 54
local TOP_Y = -2             -- Kacheln entfallen, Inhalt beginnt oben
local MTABS = {
    { key = "recipes", text = "Rezepte", glyph = ICO .. "crafting", color = C.accent },
    { key = "crafters", text = "Handwerker", glyph = ICO .. "social", color = C.blue },
}
local OTABS = {
    { key = "tome", text = "An mich", glyph = ICO .. "checklist", color = C.amber },
    { key = "mine", text = "Meine", glyph = ICO .. "wants", color = C.blue },
    { key = "open", text = "Alle offenen", glyph = ICO .. "crafting", color = C.accent },
    { key = "done", text = "Erledigt", glyph = ICO .. "badges", color = C.mint },
}
local TILES = {
    { key = "recipes", label = "Rezepte", glyph = ICO .. "crafting", color = C.accent, tip = "Klick: alle Rezepte, Filter aufheben" },
    { key = "crafters", label = "Handwerker", glyph = ICO .. "social", color = C.blue, tip = "Klick: Handwerker nach Beruf" },
    { key = "mine", label = "Kannst du", glyph = ICO .. "badges", color = C.mint, tip = "Klick: nur Rezepte, die du kannst" },
    { key = "tome", label = "Fuer dich offen", glyph = ICO .. "checklist", color = C.amber, tip = "Klick: Auftraege an dich" },
}
local page   -- Seitenrahmen nach dem Aufbau

local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
-- Glas 2026: ruhige Flaeche + feine Kante (Kante optional farbig)
local GLINE = { 1, 1, 1, 0.10 }
local function glass(f, r, a, line)
    local IG = ns.Insta
    if IG and IG.Glass then IG.Glass(f, { 1, 1, 1, a or 0.03 }, line or GLINE, r or 12) return true end
end
local function gl(c, a) return { c[1], c[2], c[3], a or 0.5 } end
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
local function classRGB(name)
    local cls = ns.Radar.ClassOf(name)
    local r, g, b = ns.classColor(cls)
    return r or 0.6, g or 0.6, b or 0.62, cls
end
local function qualityOf(id)
    if not id or not (C_Item and C_Item.GetItemQualityByID) then return nil end
    local ok, q = pcall(C_Item.GetItemQualityByID, id)
    return ok and tonumber(ns.safe(q)) or nil
end
local function ringOf(id)
    local q = qualityOf(id)
    return (q and QCOL[q]) or C.line, q
end
local function upper(s) return K.Upper and K.Upper(s) or tostring(s):upper() end
-- Suchtreffer im Text hervorheben (base = Farbcode davor)
local function hl(text, base)
    text = tostring(text or "")
    local q = (search or ""):lower()
    if q == "" then return base .. text .. "|r" end
    local s, e = text:lower():find(q, 1, true)
    if not s then return base .. text .. "|r" end
    return base .. text:sub(1, s - 1) .. "|r|cffffd84a" .. text:sub(s, e) .. "|r" .. base .. text:sub(e + 1) .. "|r"
end
local function linkClick()
    if IsModifiedClick and IsModifiedClick("CHATLINK") then return true end
    return IsShiftKeyDown and IsShiftKeyDown() and true or false
end
local function linkItem(itemID)
    if not itemID or not (C_Item and C_Item.GetItemInfo) then return false end
    local ok, _, l = pcall(C_Item.GetItemInfo, itemID)
    local link = ok and ns.safe(l) or nil
    if not link then return false end
    if ChatEdit_InsertLink then
        local ok2, r = pcall(ChatEdit_InsertLink, link)
        if ok2 and r then return true end
    end
    if ns.OpenChat then pcall(ns.OpenChat, link) end
    return true
end
local function recipeTip(owner, e, hint)
    if not e then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ok
    if e.itemID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, e.itemID) end
    if not ok and e.id then ok = pcall(GameTooltip.SetSpellByID, GameTooltip, e.id) end
    if not ok then GameTooltip:SetText(e.name or "?", 1, 1, 1) end
    if e.crafters then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Wer kann's?"] .. "  " .. Crafting.CrafterText(e, 6), 0.85, 0.85, 0.85, true)
    end
    if hint then GameTooltip:AddLine("|cff777777" .. hint .. "|r", 1, 1, 1, true) end
    GameTooltip:Show()
end
-- neu zeichnen; reset = Liste nach oben + gestaffelt einblenden (Filterwechsel)
local function redraw(reset)
    if reset and page then page.switch = true end
    ns.RefreshPage("crafting")
end
local function toggleFav(e)
    if not (e and e.name) then return end
    favs()[e.name] = (not favs()[e.name]) or nil
    redraw()
end
local function selectRecipe(e)
    if not e then return end
    local changed = not selected or selected.name ~= e.name
    selected = e
    Crafting.QueryBlizzard(e.id)
    chosenCrafter, qty = nil, 1
    if page then page.selAnim, page.cardAnim = true, changed end
    ns.RefreshPage("crafting")
end
local function showCrafterRecipes(who)
    crafterFilter, mode = who, "recipes"
    if page and page.mode then page.mode:Select("recipes", true) end
    redraw(true)
end
local function crafterMenu(owner, who)
    if not who or who == "" then return end
    local items = {
        { text = L["Fluestern"], fn = function() ns.Whisper(who) end },
        { text = L["In Gruppe einladen"], fn = function() ns.InviteName(who) end },
    }
    if ns.Profile and ns.Profile.Show then items[#items + 1] = { text = L["Profil ansehen"], fn = function() ns.Profile.Show(who) end } end
    if ns.Talents then items[#items + 1] = { text = L["Talente ansehen"], fn = function() ns.Talents.Show(who) end } end
    items[#items + 1] = { text = (L["Rezepte von %s zeigen"]):format(ns.displayName(who)), fn = function() showCrafterRecipes(who) end }
    K.ShowMenu(owner, items, ns.displayName(who), 190)
end
local function recipeMenu(owner, e)
    local items = {
        { text = isFav(e) and L["Favorit entfernen"] or L["Als Favorit merken"], fn = function() toggleFav(e) end },
        { text = L["Auswaehlen und Auftrag vorbereiten"], fn = function() selectRecipe(e) end },
    }
    if e.itemID then items[#items + 1] = { text = L["Im Chat verlinken"], fn = function() linkItem(e.itemID) end } end
    local pid = profIdOf(e.prof)
    if pid then
        items[#items + 1] = { text = (L["Nur %s zeigen"]):format(e.prof), checked = profFilter == pid, fn = function()
            profFilter = (profFilter ~= pid) and pid or nil
            redraw(true)
        end }
    end
    K.ShowMenu(owner, items, e.name, 200)
end

-- rundes Item-Bild mit Ring in Qualitaetsfarbe
local function makeAvatar(parent, s)
    local a = CreateFrame("Frame", nil, parent)
    a:SetSize(s, s)
    a.glow = a:CreateTexture(nil, "BACKGROUND", nil, 2)
    a.glow:SetTexture(EMBER)
    a.glow:SetBlendMode("ADD")
    a.glow:SetSize(s * 2, s * 2)
    a.glow:SetPoint("CENTER")
    a.glow:SetAlpha(0.45)
    a.glow:Hide()
    a.ring = a:CreateTexture(nil, "BORDER")
    a.ring:SetTexture(CIRCLE)
    a.ring:SetAllPoints()
    a.inner = a:CreateTexture(nil, "ARTWORK", nil, -1)
    a.inner:SetTexture(CIRCLE)
    a.inner:SetVertexColor(0.06, 0.06, 0.07)
    a.inner:SetSize(s - 3, s - 3)
    a.inner:SetPoint("CENTER")
    a.icon = a:CreateTexture(nil, "ARTWORK", nil, 1)
    a.icon:SetSize(s - 5, s - 5)
    a.icon:SetPoint("CENTER")
    circleMask(a, a.icon)
    return a
end
local function setAvatar(a, itemID, recipeID)
    a.icon:SetTexture(Crafting.Icon({ itemID = itemID, id = recipeID }))
    a.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local ring = ringOf(itemID)
    a.ring:SetVertexColor(ring[1], ring[2], ring[3])
    a.glow:SetVertexColor(ring[1], ring[2], ring[3])
    return ring
end

-- Leerzustand: Symbol im Kreis + Text + bis zu zwei Aktionen
local function emptyState(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(320, 120)
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
    f.icon = K.Glyph(f, 22, ICO .. "crafting", C.amber)
    f.icon:SetPoint("CENTER", f.disc)
    f.text = K.Text(f, 12, C.muted, "CENTER")
    f.text:SetPoint("TOP", f.disc, "BOTTOM", 0, -10)
    f.text:SetWidth(300)
    f.text:SetWordWrap(true)
    f.btn = K.Button(f, "", 150, 24, "ghost")
    f.btn2 = K.Button(f, "", 110, 22, "ghost")
    function f:Set(glyph, color, msg, b1, fn1, b2, fn2)
        self.icon:SetTexture(ICO .. glyph)
        self.icon:SetVertexColor(color[1], color[2], color[3])
        self.halo:SetVertexColor(color[1], color[2], color[3])
        self.disc:SetVertexColor(color[1] * 0.18, color[2] * 0.18, color[3] * 0.18)
        self.text:SetText(msg)
        self.btn:SetShown(b1 ~= nil)
        self.btn2:SetShown(b2 ~= nil)
        self.btn:ClearAllPoints()
        self.btn2:ClearAllPoints()
        if b1 then
            self.btn:SetLabel(b1)
            self.btn:SetWidth(math.max(100, (self.btn.label:GetStringWidth() or 0) + 26))
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
        if not self:IsShown() and animOn() then K.FadeIn(self, 0.05) end
    end
    f:Hide()
    return f
end

-- Reiterleiste: Symbol + Text + Zaehler, gleitender Balken in der Reiterfarbe
local function buildTabs(parent, defs, onPick, h)
    h = h or 30
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(h)
    f.maxW = 300
    f.base = f:CreateTexture(nil, "BACKGROUND")
    f.base:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.base:SetHeight(1)
    f.base:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    f.buttons = {}
    for i, d in ipairs(defs) do
        local b = CreateFrame("Button", nil, f)
        b.key, b.color = d.key, d.color
        b.hov = b:CreateTexture(nil, "BACKGROUND")
        b.hov:SetAllPoints()
        b.hov:SetColorTexture(1, 1, 1, 0.03)
        b.hov:SetAlpha(0)
        b.ico = K.Glyph(b, 14, d.glyph, C.muted)
        b.label = K.Text(b, 12, C.muted)
        b.label:SetText(L[d.text])
        b.count = K.Text(b, 10, C.dim)
        b:SetScript("OnClick", function() if f.value ~= d.key then onPick(d.key) end end)
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
    function f:Btn(key) for _, b in ipairs(self.buttons) do if b.key == key then return b end end end
    function f:Layout()
        local W = math.max(80, self.maxW or 300)
        self.base:SetWidth(W)
        local nat, sum, withIcon = {}, 0, true
        for pass = 1, 2 do
            sum = 0
            for i, b in ipairs(self.buttons) do
                local cw = (b.count:GetText() or "") ~= "" and ((b.count:GetStringWidth() or 0) + 5) or 0
                nat[i] = (withIcon and 19 or 0) + (b.label:GetStringWidth() or 0) + cw + 20
                sum = sum + nat[i]
            end
            if pass == 1 and sum > W then withIcon = false else break end
        end
        local scale = math.min(1, W / math.max(1, sum))
        local x = 0
        for i, b in ipairs(self.buttons) do
            local bw = math.max(36, math.floor(nat[i] * scale))
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, 0)
            b:SetSize(bw, h - 1)
            b.x, b.w = x, bw
            x = x + bw + 2
            local cw = (b.count:GetText() or "") ~= "" and ((b.count:GetStringWidth() or 0) + 5) or 0
            local iw = withIcon and 19 or 0
            local tw = math.max(10, math.min(b.label:GetStringWidth() or 0, bw - iw - cw - 10))
            local x0 = math.max(3, math.floor((bw - (iw + tw + cw)) / 2))
            b.ico:SetShown(withIcon)
            b.ico:ClearAllPoints()
            b.ico:SetPoint("LEFT", b, "LEFT", x0, 0)
            b.label:ClearAllPoints()
            b.label:SetPoint("LEFT", b, "LEFT", x0 + iw, 0)
            b.label:SetWidth(tw + 1)
            b.count:ClearAllPoints()
            b.count:SetPoint("LEFT", b.label, "RIGHT", 4, 0)
        end
        self:SetWidth(math.max(1, x - 2))
        self:MoveInd(self.value, false)
    end
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
        local tb = self:Btn(key)
        if not tb or not tb.x then return end
        local c = tb.color
        self.ind:SetColorTexture(c[1], c[2], c[3], 1)
        self.indGlow:Hide()
        local x1, w1 = tb.x + 5, math.max(1, tb.w - 10)
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
    -- kurz aufleuchten (z.B. Auftrag ist dort gelandet)
    function f:Ping(key)
        local b = self:Btn(key)
        if not b or not animOn() then return end
        K.Tween(b.hov, 0.6, function(q) b.hov:SetAlpha(1 - 0.4 * q) end, function() b.hov:SetAlpha(0) end)
    end
    return f
end

-- Kennzahl-Kachel (Verlauf, Glow, Hover-Lift, hochzaehlend), Klick = Filter
local function buildTile(parent, d, onClick)
    local c = d.color
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(54)
    t.key, t.lift = d.key, 0
    t.hov = t:CreateTexture(nil, "BORDER", nil, 2)
    t.hov:SetColorTexture(1, 1, 1, 0)
    t.top = t:CreateTexture(nil, "ARTWORK")
    t.top:Hide()
    t.iconGlow = t:CreateTexture(nil, "BORDER", nil, 3)
    t.iconGlow:Hide()
    glass(t, 12)
    t.col = c
    t.icon = K.Glyph(t, 20, d.glyph, c)
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
    t.bar = t:CreateTexture(nil, "ARTWORK", nil, 2)
    t.bar:SetPoint("BOTTOMLEFT")
    t.bar:SetHeight(2)
    t.bar:SetColorTexture(c[1], c[2], c[3], 0.9)
    t.bar:Hide()
    function t:Place()
        if not self.bx then return end
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", self:GetParent(), "TOPLEFT", self.bx, self.lift)
        self:SetWidth(self.bw)
    end
    local function hover(on)
        glass(t, 12, (on or t.sel) and 0.06 or 0.03, t.sel and gl(c, 0.55) or GLINE)
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
        K.ShowTip(self, { L[d.label], "|cff888888" .. (self.sel and L["Klick: Filter aufheben"] or L[d.tip]) .. "|r" })
    end)
    t:SetScript("OnLeave", function() hover(false) GameTooltip:Hide() end)
    t:SetScript("OnClick", function() onClick(d.key) end)
    function t:SetSel(on)
        self.sel = on
        glass(self, 12, on and 0.06 or 0.03, on and gl(c, 0.55) or GLINE)
    end
    -- Wert (+ Zusatz, Fortschritt 0..1); animate = hochzaehlen
    function t:SetValue(n, sub, progress, animate, delay)
        n = tonumber(n) or 0
        local vc = n > 0 and (self.col or C.text) or C.dim
        self.value:SetTextColor(vc[1], vc[2], vc[3])
        if animate and animOn() then K.CountUp(self.value, n, 0.8, nil, delay)
        elseif self.shown ~= n then self.value:SetText(n) end
        self.shown = n
        self.sub:SetText(sub or "")
        if progress then
            local w = math.max(1, (self.bw or 100) * math.max(0, math.min(1, progress)))
            self.bar:Show()
            if animate and animOn() then
                self.bar:SetWidth(1)
                K.Tween(self.bar, 0.9, function(q) self.bar:SetWidth(math.max(1, w * q)) end, nil, delay)
            else
                self.bar:SetWidth(w)
            end
        else
            self.bar:Hide()
        end
    end
    return t
end

-- Filter-Schalter mit Farbpunkt und Zaehler
local function buildToggle(parent, text, color, get, set, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b.tint = b:CreateTexture(nil, "BORDER", nil, 1)
    b.tint:Hide()
    glass(b, 11, 0.03)
    b.glow = b:CreateTexture(nil, "ARTWORK", nil, -1)
    b.glow:SetTexture(EMBER)
    b.glow:SetBlendMode("ADD")
    b.glow:SetSize(20, 20)
    b.glow:SetVertexColor(color[1], color[2], color[3])
    b.glow:Hide()
    b.dot = b:CreateTexture(nil, "ARTWORK")
    b.dot:SetTexture(CIRCLE)
    b.dot:SetSize(7, 7)
    b.dot:SetPoint("LEFT", 8, 0)
    b.dot:SetVertexColor(color[1], color[2], color[3])
    b.glow:SetPoint("CENTER", b.dot)
    b.label = K.Text(b, 11, C.muted)
    b.label:SetPoint("LEFT", 20, 0)
    b.label:SetText(text)
    b.count = K.Text(b, 10, C.dim)
    b.count:SetPoint("LEFT", b.label, "RIGHT", 5, 0)
    function b:Update(n)
        local on = get() and true or false
        if n == false then self.count:SetText("") elseif n ~= nil then self.count:SetText(tostring(n)) end
        local cw = (self.count:GetText() or "") ~= "" and ((self.count:GetStringWidth() or 0) + 5) or 0
        self:SetWidth(math.floor(20 + (self.label:GetStringWidth() or 40) + cw + 10))
        self.glow:Hide()
        glass(self, 11, on and 0.07 or 0.03, on and gl(color, 0.6) or GLINE)
        self.dot:SetAlpha(on and 1 or 0.4)
        local c = on and C.text or C.muted
        self.label:SetTextColor(c[1], c[2], c[3])
        local cc = on and color or C.dim
        self.count:SetTextColor(cc[1], cc[2], cc[3])
        if self.was ~= nil and self.was ~= on and on and animOn() then
            K.Tween(self.dot, 0.3, function(q) local s = 7 + 4 * math.sin(math.pi * q) self.dot:SetSize(s, s) end, function() self.dot:SetSize(7, 7) end)
        end
        self.was = on
    end
    b:SetScript("OnClick", function(self) set(not get()) self:Update() end)
    b:SetScript("OnEnter", function(self)
        if not get() then glass(self, 11, 0.06) end
        if tip then K.ShowTip(self, tip) end
    end)
    b:SetScript("OnLeave", function(self) self:Update() GameTooltip:Hide() end)
    b:Update()
    return b
end

-- Abschnittskopf der Karte: Nummer im Kreis + GROSSBUCHSTABEN + Text rechts
local function sectionHead(parent, n, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(16)
    f.disc = f:CreateTexture(nil, "ARTWORK")
    f.disc:SetTexture(CIRCLE)
    f.disc:SetSize(15, 15)
    f.disc:SetPoint("LEFT", 0, 0)
    f.disc:SetVertexColor(C.accent[1] * 0.45, C.accent[2] * 0.45, C.accent[3] * 0.45)
    f.num = K.Title(f, 10, C.text, "CENTER")
    f.num:SetPoint("CENTER", f.disc, "CENTER", 0, 0)
    f.num:SetText(n)
    f.text = K.Text(f, 10, C.muted)
    f.text:SetPoint("LEFT", 21, 0)
    f.text:SetText(text)
    f.right = K.Text(f, 10, C.dim, "RIGHT")
    f.right:SetPoint("LEFT", f.text, "RIGHT", 10, 0)
    f.right:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    return f
end

------------------------------------------------------------------------
-- Listenzeilen
------------------------------------------------------------------------
local function rowHover(r, on)
    if not on and r.IsMouseOver and r:IsMouseOver() then return end   -- nur auf Knopf/Stern gewechselt
    if r.hovered == on then return end
    r.hovered = on
    if r.hov then r.hov:SetShown(on) end
    if r.onHover then r.onHover(r, on) end
    if not on then GameTooltip:Hide() end
end
local function smallBadge(r, text, color, fn, tip)
    local b = CreateFrame("Button", nil, r)
    b:SetHeight(15)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(color[1] * 0.22, color[2] * 0.22, color[3] * 0.22, 1)
    b.text = K.Text(b, 10, { color[1] * 0.5 + 0.5, color[2] * 0.5 + 0.5, color[3] * 0.5 + 0.5, 1 }, "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(text)
    b:SetWidth(math.floor((b.text:GetStringWidth() or 30) + 12))
    b:SetScript("OnClick", fn)
    b:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(color[1] * 0.42, color[2] * 0.42, color[3] * 0.42, 1)
        rowHover(r, true)
        K.ShowTip(self, tip)
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(color[1] * 0.22, color[2] * 0.22, color[3] * 0.22, 1)
        GameTooltip:Hide()
        rowHover(r, false)
    end)
    return b
end
local function newDot(r)
    local d = {}
    d.ring = r:CreateTexture(nil, "ARTWORK", nil, 1)
    d.ring:SetTexture(CIRCLE)
    d.ring:SetSize(10, 10)
    d.dot = r:CreateTexture(nil, "ARTWORK", nil, 2)
    d.dot:SetTexture(CIRCLE)
    d.dot:SetSize(6, 6)
    d.dot:SetPoint("CENTER", d.ring, "CENTER", 0, 0)
    return d
end

-- Kapitel (Beruf / Favoriten)
local function newHead(parent)
    local r = CreateFrame("Frame", nil, parent)
    r.g = K.Glyph(r, 14, nil, C.accent)
    r.g:SetPoint("LEFT", 4, -1)
    r.text = K.Title(r, 12, C.text)
    r.text:SetPoint("LEFT", 24, -1)
    r.info = K.Text(r, 11, C.dim)
    r.info:SetPoint("LEFT", r.text, "RIGHT", 8, 0)
    r.rule = r:CreateTexture(nil, "ARTWORK")
    r.rule:SetHeight(1)
    r.rule:SetPoint("LEFT", r.info, "RIGHT", 10, 0)
    r.rule:SetPoint("RIGHT", r, "RIGHT", 0, -1)
    gradient(r.rule, "HORIZONTAL", C.line, 1, 0, 0.6)
    return r
end
local function fillHead(r, it)
    local c = it.color or C.accent
    r.g:SetTexture(it.glyph)
    r.g:SetVertexColor(c[1], c[2], c[3])
    r.text:SetText(it.label or "?")
    r.info:SetText(it.n and tostring(it.n) or "")
end

-- Rezept-Zeile: rundes Icon, Name (Treffer markiert), Klassenpunkte der Handwerker, Abzeichen, Stern
local function newRecipeRow(TL)
    local r = CreateFrame("Button", nil, TL)
    r:RegisterForClicks("AnyUp")
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.stripe:SetColorTexture(1, 1, 1, 0)
    r.hov = r:CreateTexture(nil, "BORDER")
    r.hov:SetAllPoints()
    r.hov:Hide()
    r.av = makeAvatar(r, 26)
    r.av:SetPoint("LEFT", 6, 0)
    r.name = K.Text(r, 12, C.text)
    r.name:SetPoint("TOPLEFT", 40, -4)
    r.sub = K.Text(r, 10, C.dim)
    r.dots = {}
    r.fav = CreateFrame("Button", nil, r)
    r.fav:SetSize(16, 16)
    r.fav:SetPoint("RIGHT", -6, 0)
    r.fav.t = r.fav:CreateTexture(nil, "OVERLAY")
    r.fav.t:SetAllPoints()
    r.fav.t:SetTexture(ns.MEDIA .. "diamond")   -- eigenes Symbol (fremde Dateien koennen den Client abstuerzen lassen)
    r.fav:SetScript("OnClick", function(self)
        local e = r.item and r.item.e
        toggleFav(e)
        if animOn() then K.Tween(self.t, 0.3, function(q) local s = 16 + 8 * math.sin(math.pi * q) self:SetSize(s, s) end, function() self:SetSize(16, 16) end) end
    end)
    r.fav:SetScript("OnEnter", function(self)
        rowHover(r, true)
        local e = r.item and r.item.e
        K.ShowTip(self, { isFav(e) and L["Favorit entfernen"] or L["Als Favorit merken"], L["Favoriten stehen immer oben."] })
    end)
    r.fav:SetScript("OnLeave", function() GameTooltip:Hide() rowHover(r, false) end)
    r.bCan = smallBadge(r, L["kannst du"], C.mint, function() onlyMine = not onlyMine redraw(true) end,
        { L["kannst du"], "|cff888888" .. L["Klick: nur Rezepte, die du kannst"] .. "|r" })
    r.bWant = smallBadge(r, L["gesucht"], C.amber, function() onlyWanted = not onlyWanted redraw(true) end,
        { L["gesucht"], "|cff888888" .. L["Steht auf einer Wunschliste der Gilde. Klick: nur gesuchte Rezepte"] .. "|r" })
    r.onHover = function(self, on)
        local e = self.item and self.item.e
        if e and not isFav(e) then self.fav:SetAlpha(on and 0.75 or 0.3) end
    end
    r:SetScript("OnEnter", function(self)
        rowHover(self, true)
        local e = self.item and self.item.e
        if e then recipeTip(self, e, L["Klick: auswaehlen"] .. "  ·  " .. L["Shift-Klick: verlinken"] .. "  ·  " .. L["Rechtsklick: Aktionen"]) end
    end)
    r:SetScript("OnLeave", function(self) rowHover(self, false) end)
    r:SetScript("OnClick", function(self, btn)
        local e = self.item and self.item.e
        if not e then return end
        if btn == "RightButton" then recipeMenu(self, e) return end
        if linkClick() and linkItem(e.itemID) then return end
        selectRecipe(e)
    end)
    r.TL = TL
    return r
end
local function fillRecipeRow(r, it)
    local e = it.e
    local W = math.max(220, (r.TL:GetWidth() or 340) - 10)
    local ring = setAvatar(r.av, e.itemID, e.id)
    r.hov:SetColorTexture(1, 1, 1, 0.04)
    local fv = isFav(e)
    r.fav.t:SetVertexColor(fv and 1 or 0.6, fv and 0.82 or 0.6, fv and 0.3 or 0.62)
    r.fav:SetAlpha(fv and 1 or (r.hovered and 0.75 or 0.3))
    local reserve = 28
    local function place(b, show)
        b:SetShown(show)
        if not show then return end
        b:ClearAllPoints()
        b:SetPoint("RIGHT", r, "RIGHT", -reserve, 0)
        reserve = reserve + (b:GetWidth() or 40) + 4
    end
    place(r.bWant, it.wanted)
    place(r.bCan, it.can)
    r.name:SetText(hl(e.name, Crafting.QualityHex(e.itemID)))
    r.name:SetWidth(math.max(40, W - 40 - reserve))
    -- Handwerker als Klassenpunkte (online = gruener Ring)
    local list = it.crafters or {}
    local n = math.min(6, #list)
    for i = 1, n do
        local d = r.dots[i] or newDot(r)
        r.dots[i] = d
        local c = list[i]
        local cr, cg, cb = classRGB(c.name)
        d.ring:ClearAllPoints()
        d.ring:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 40 + (i - 1) * 11, 4)
        if c.online then d.ring:SetVertexColor(C.mint[1], C.mint[2], C.mint[3]) d.ring:SetAlpha(1)
        else d.ring:SetVertexColor(C.line[1], C.line[2], C.line[3]) d.ring:SetAlpha(0.7) end
        d.dot:SetVertexColor(cr, cg, cb)
        d.dot:SetAlpha(c.online and 1 or 0.45)
        d.ring:Show() d.dot:Show()
    end
    for i = n + 1, #r.dots do r.dots[i].ring:Hide() r.dots[i].dot:Hide() end
    local txt = (L["%d koennen"]):format(#list)
    if it.on > 0 then txt = txt .. "  |cff555555·|r  |cff66db9e" .. (L["%d online"]):format(it.on) .. "|r" end
    r.sub:SetText(txt)
    r.sub:ClearAllPoints()
    r.sub:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 40 + n * 11 + (n > 0 and 4 or 0), 4)
    r.sub:SetPoint("RIGHT", r, "RIGHT", -reserve, 0)
end

-- Handwerker-Zeile: Klassenkreis, online-Punkt, Fertigkeit als Balken
local function newCrafterRow(TL)
    local r = CreateFrame("Button", nil, TL)
    r:RegisterForClicks("AnyUp")
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.stripe:SetColorTexture(1, 1, 1, 0)
    r.hov = r:CreateTexture(nil, "BORDER")
    r.hov:SetAllPoints()
    r.hov:Hide()
    r.ring = r:CreateTexture(nil, "ARTWORK", nil, -1)
    r.ring:SetTexture(CIRCLE)
    r.ring:SetSize(26, 26)
    r.ring:SetPoint("LEFT", 6, 0)
    r.cls = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.cls:SetSize(22, 22)
    r.cls:SetPoint("CENTER", r.ring, "CENTER", 0, 0)
    circleMask(r, r.cls)
    r.dot = r:CreateTexture(nil, "OVERLAY")
    r.dot:SetTexture(CIRCLE)
    r.dot:SetSize(8, 8)
    r.dot:SetPoint("CENTER", r.ring, "BOTTOMRIGHT", -3, 3)
    r.name = K.Text(r, 12, C.text)
    r.name:SetPoint("TOPLEFT", 40, -4)
    r.sub = K.Text(r, 10, C.dim)
    r.sub:SetPoint("BOTTOMLEFT", 40, 4)
    r.rank = K.Text(r, 11, C.muted, "RIGHT")
    r.rank:SetPoint("RIGHT", -10, 0)
    r.rank:SetWidth(64)
    r.bar = CreateFrame("Frame", nil, r)
    r.bar:SetSize(64, 4)
    r.bar:SetPoint("RIGHT", r.rank, "LEFT", -8, 0)
    r.bar.bg = K.Fill(r.bar, C.field)
    r.bar.fill = r.bar:CreateTexture(nil, "ARTWORK")
    r.bar.fill:SetPoint("TOPLEFT") r.bar.fill:SetPoint("BOTTOMLEFT")
    r.name:SetPoint("RIGHT", r.bar, "LEFT", -8, 0)
    r.sub:SetPoint("RIGHT", r.bar, "LEFT", -8, 0)
    r:SetScript("OnEnter", function(self)
        rowHover(self, true)
        local x = self.item and self.item.x
        if not x then return end
        ns.Radar.ShowMemberTip(self, ns.Radar.byName[x.member] or { name = x.member, level = 0, zone = "", rank = "" })
        GameTooltip:AddLine("|cff777777" .. L["Klick: Rezepte zeigen"] .. "  ·  " .. L["Rechtsklick: Aktionen"] .. "|r", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) rowHover(self, false) end)
    r:SetScript("OnClick", function(self, btn)
        local x = self.item and self.item.x
        if not x then return end
        if btn == "RightButton" then crafterMenu(self, x.member) return end
        showCrafterRecipes(x.member)
    end)
    r.TL = TL
    return r
end
local function fillCrafterRow(r, it)
    local x = it.x
    local cr, cg, cb, cls = classRGB(x.member)
    r.hov:SetColorTexture(1, 1, 1, 0.04)
    r.ring:SetVertexColor(cr, cg, cb)
    r.ring:SetAlpha(x.online and 1 or 0.35)
    if not setClassIcon(r.cls, cls) then
        r.cls:SetTexture(CIRCLE)
        r.cls:SetTexCoord(0, 1, 0, 1)
        r.cls:SetVertexColor(C.dim[1], C.dim[2], C.dim[3])
    else
        r.cls:SetVertexColor(1, 1, 1)
    end
    r.cls:SetAlpha(x.online and 1 or 0.55)
    local dc = x.online and C.mint or C.dim
    r.dot:SetVertexColor(dc[1], dc[2], dc[3])
    r.name:SetText(hl(ns.displayName(x.member), K.hex({ cr, cg, cb })))
    r.sub:SetText(x.recipes > 0 and (L["%d Rezepte"]):format(x.recipes) or ("|cff666666" .. L["Rezepte unbekannt"] .. "|r"))
    local maxed = x.max and x.rank and x.rank >= x.max
    r.rank:SetText((maxed and "|cffe8b44a" or "|cffc8c8c8") .. (x.rank or "?") .. "|r" .. (x.max and ("|cff777777 / " .. x.max .. "|r") or ""))
    local pct = math.max(0, math.min(1, (tonumber(x.rank) or 0) / math.max(1, tonumber(x.max) or 300)))
    local fc = maxed and C.amber or C.blue
    r.bar.fill:SetColorTexture(fc[1], fc[2], fc[3], 0.9)
    r.bar.fill:SetWidth(math.max(0.01, 64 * pct))
    r.bar.fill:SetShown(pct > 0)
end

-- Auftrag: Aktionen (Symbolknoepfe + Rechtsklick-Menue)
local function orderActs(o)
    local me = ns.me()
    local acts = {}
    if o.status == "open" and o.from ~= me and (ns.isMe(o.to) or ((o.to or "") == "" and Crafting.CanCraft(me, o.recipe, o.rid))) then
        acts[#acts + 1] = { glyph = ICO .. "checklist", color = C.mint, primary = true, text = L["Annehmen"],
            tip = { L["Annehmen"], L["Du stellst es her - der Auftraggeber bekommt Bescheid."] }, fn = function() setStatus(o, "accepted") end }
        -- Ablehnen: direkt an mich -> Auftraggeber bekommt Bescheid; an alle -> nur fuer mich ausblenden
        acts[#acts + 1] = { cross = true, color = C.muted, text = L["Ablehnen"],
            tip = { L["Ablehnen"], ns.isMe(o.to) and L["Der Auftraggeber bekommt Bescheid."] or L["Auftrag an alle - wird nur fuer dich ausgeblendet."] },
            fn = function()
                if ns.isMe(o.to) then
                    setStatus(o, "declined")
                else
                    ns.db.ordersHidden = ns.db.ordersHidden or {}
                    ns.db.ordersHidden[o.id] = ns.now()
                    updateBadge()
                    ns.RefreshPage("crafting")
                end
            end }
    elseif o.status == "accepted" and o.worker == me then
        acts[#acts + 1] = { tex = CHECK_TEX, color = C.mint, primary = true, text = L["Fertig"],
            tip = { L["Fertig"], L["Der Auftraggeber bekommt Bescheid, dass es fertig ist."] }, fn = function() setStatus(o, "done") end }
        -- doch nicht schaffbar: zurueckgeben (an mich gerichtet -> abgelehnt, sonst wieder offen)
        acts[#acts + 1] = { glyph = ICO .. "sync", color = C.amber, text = L["Zurueckgeben"],
            tip = { L["Zurueckgeben"], L["Du schaffst es doch nicht - der Auftrag geht zurueck."] },
            fn = function() setStatus(o, ns.isMe(o.to) and "declined" or "open") end }
    end
    -- anfluestern: der jeweils andere
    local other = (o.from == me) and (o.worker or ((o.to or "") ~= "" and o.to) or nil) or o.from
    if other and not ns.isMe(other) then
        acts[#acts + 1] = { glyph = ICO .. "badges\\chat", color = C.blue, text = L["Anfluestern"],
            tip = { L["Anfluestern"], ns.displayName(other) }, fn = function() ns.Whisper(other, Crafting.OrderName(o) .. ": ") end }
    end
    local closed = o.status == "done" or o.status == "cancel" or o.status == "declined"
    if o.from == me or canModerate() then
        if closed then
            acts[#acts + 1] = { glyph = ICO .. "eraser", color = C.red, text = L["Entfernen"],
                tip = { L["Entfernen"], L["Erledigten Auftrag aus der Liste nehmen."] }, fn = function() Store.Delete("orders", o.id) end }
        else
            acts[#acts + 1] = { cross = true, color = C.red, text = L["Stornieren"],
                tip = { L["Stornieren"], L["Der Auftrag wird fuer alle zurueckgezogen."] }, fn = function() setStatus(o, "cancel") end }
        end
    end
    return acts
end
local function newActBtn(parent, r)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    glass(b, 8, 0.04)
    b.g = b:CreateTexture(nil, "ARTWORK")
    b.g:SetSize(13, 13)
    b.g:SetPoint("CENTER")
    b.x1 = b:CreateTexture(nil, "ARTWORK")
    b.x1:SetSize(11, 1.5)
    b.x1:SetPoint("CENTER")
    b.x2 = b:CreateTexture(nil, "ARTWORK")
    b.x2:SetSize(11, 1.5)
    b.x2:SetPoint("CENTER")
    if b.x1.SetRotation then pcall(b.x1.SetRotation, b.x1, math.pi / 4) pcall(b.x2.SetRotation, b.x2, -math.pi / 4) end
    function b:Tint(hover)
        local a = self.a or {}
        local c = a.color or C.muted
        if a.primary then
            glass(self, 8, hover and 0.12 or 0.07, gl(c, hover and 0.9 or 0.6))
        else
            glass(self, 8, hover and 0.08 or 0.04, hover and gl(c, 0.6) or GLINE)
        end
        local gc = (a.primary or hover) and c or C.muted
        if a.tex then self.g:SetVertexColor(1, 1, 1) else self.g:SetVertexColor(gc[1], gc[2], gc[3]) end
        self.x1:SetColorTexture(gc[1], gc[2], gc[3], 1)
        self.x2:SetColorTexture(gc[1], gc[2], gc[3], 1)
    end
    function b:Set(a)
        self.a = a
        local cross = a.cross and true or false
        self.g:SetShown(not cross)
        self.x1:SetShown(cross)
        self.x2:SetShown(cross)
        if a.tex then self.g:SetTexture(a.tex) elseif a.glyph then self.g:SetTexture(a.glyph) end
        self:Tint(false)
    end
    b:SetScript("OnEnter", function(self)
        if r then rowHover(r, true) end
        self:Tint(true)
        if self.a then K.ShowTip(self, self.a.tip) end
    end)
    b:SetScript("OnLeave", function(self)
        self:Tint(false)
        GameTooltip:Hide()
        if r then rowHover(r, false) end
    end)
    b:SetScript("OnClick", function(self)
        local a = self.a
        if not a then return end
        if animOn() then
            K.Tween(self.g, 0.25, function(q) local s = 13 + 6 * math.sin(math.pi * q) self.g:SetSize(s, s) end, function() self.g:SetSize(13, 13) end)
        end
        a.fn()
    end)
    return b
end

-- Auftrags-Karte: Ampel, rundes Icon, Titel + Status, Wer > Wen, Aktionen
local LAMP = { open = 1, accepted = 2, done = 3, declined = 1 }
local function newOrderCard(TL)
    local r = CreateFrame("Button", nil, TL)
    r:RegisterForClicks("AnyUp")
    r.tint = r:CreateTexture(nil, "BORDER", nil, 1)
    r.tint:Hide()
    r.hov = r:CreateTexture(nil, "BORDER", nil, 2)
    r.hov:SetAllPoints()
    r.hov:SetColorTexture(1, 1, 1, 0.045)
    r.hov:Hide()
    r.flash = r:CreateTexture(nil, "BORDER", nil, 3)
    r.flash:SetAllPoints()
    r.flash:Hide()
    glass(r, 10, 0.03)
    r.lampGlow = r:CreateTexture(nil, "ARTWORK", nil, -1)
    r.lampGlow:SetTexture(EMBER)
    r.lampGlow:SetBlendMode("ADD")
    r.lampGlow:SetSize(20, 20)
    r.lamp = {}
    for i = 1, 3 do
        local t = r:CreateTexture(nil, "ARTWORK")
        t:SetTexture(CIRCLE)
        t:SetSize(6, 6)
        t:SetPoint("LEFT", r, "LEFT", 7, 9 - (i - 1) * 9)
        r.lamp[i] = t
    end
    r.av = makeAvatar(r, 30)
    r.av:SetPoint("LEFT", 20, 0)
    r.title = K.Text(r, 12, C.text)
    r.title:SetPoint("TOPLEFT", 58, -9)
    r.badge = K.Badge(r, 15)
    r.meta = K.Text(r, 10, C.muted)
    r.meta:SetPoint("BOTTOMLEFT", 58, 9)
    r.abtn = {}
    r:SetScript("OnEnter", function(self)
        rowHover(self, true)
        local o = self.item and self.item.o
        if not o then return end
        local lines = { Crafting.OrderName(o) }
        lines[#lines + 1] = L["Von: "] .. ns.Radar.Colored(o.from) .. (o.worker and ("   " .. L["Macht: "] .. ns.Radar.Colored(o.worker)) or "")
        if o.mats then lines[#lines + 1] = "|cff66db9e" .. L["Material bringt der Auftraggeber mit"] .. "|r" end
        if o.tip then lines[#lines + 1] = "|cffe8b44a" .. (L["Trinkgeld: %dg"]):format(o.tip) .. "|r" end
        if (o.note or "") ~= "" then lines[#lines + 1] = L["Notiz: "] .. o.note end
        lines[#lines + 1] = "|cff777777" .. L["erstellt "] .. ns.ago(o.created or o.u) .. "|r"
        lines[#lines + 1] = "|cff777777" .. L["Klick: Rezept zeigen"] .. "  ·  " .. L["Rechtsklick: Aktionen"] .. "|r"
        K.ShowTip(self, lines)
    end)
    r:SetScript("OnLeave", function(self) rowHover(self, false) end)
    r:SetScript("OnClick", function(self, btn)
        local o = self.item and self.item.o
        if not o then return end
        if btn == "RightButton" then
            local items = {}
            for _, a in ipairs(orderActs(o)) do items[#items + 1] = { text = a.text, fn = a.fn } end
            local e = Crafting.ForItem(o.item ~= 0 and o.item or nil, Crafting.OrderName(o))
            if e then items[#items + 1] = { text = L["Rezept zeigen"], fn = function() selectRecipe(e) end } end
            K.ShowMenu(self, items, Crafting.OrderName(o), 180)
            return
        end
        if linkClick() and linkItem(o.item ~= 0 and o.item or nil) then return end
        local e = Crafting.ForItem(o.item ~= 0 and o.item or nil, Crafting.OrderName(o))
        if e then selectRecipe(e) end
    end)
    r.TL = TL
    return r
end
local function fillOrderCard(r, it)
    local o = it.o
    local me = ns.me()
    local W = math.max(220, (r.TL:GetWidth() or 360) - 10)
    local st = STATUS[o.status] or STATUS.open
    local e = orderEntry(o)
    setAvatar(r.av, e.itemID, e.id)
    r.lampGlow:SetAlpha(0)
    -- Ampel: offen (oben) - in Arbeit - fertig (unten)
    local lit = LAMP[o.status]
    local LC = { o.status == "declined" and C.red or C.amber, C.blue, C.mint }
    for i, t in ipairs(r.lamp) do
        local c = (lit == i) and LC[i] or C.dim
        t:SetVertexColor(c[1], c[2], c[3])
        t:SetAlpha(lit == i and 1 or 0.3)
    end
    r.lampGlow:SetShown(lit ~= nil)
    if lit then
        local c = LC[lit]
        r.lampGlow:SetVertexColor(c[1], c[2], c[3])
        r.lampGlow:ClearAllPoints()
        r.lampGlow:SetPoint("CENTER", r.lamp[lit], "CENTER", 0, 0)
    end
    -- Aktionen rechts
    local acts = orderActs(o)
    local x = 8
    for i, a in ipairs(acts) do
        local b = r.abtn[i] or newActBtn(r, r)
        r.abtn[i] = b
        b:Set(a)
        b:ClearAllPoints()
        b:SetPoint("RIGHT", r, "RIGHT", -x, 0)
        b:Show()
        x = x + 25
    end
    for i = #acts + 1, #r.abtn do r.abtn[i]:Hide() end
    local reserve = x + 4
    -- Titel + Status
    r.badge:Set(st[1], st[2])
    local bw = r.badge:GetWidth() or 50
    r.title:SetText((o.qty or 1) .. "x " .. Crafting.QualityHex(e.itemID) .. Crafting.OrderName(o) .. "|r")
    local avail = W - 58 - reserve - bw - 8
    r.title:SetWidth(math.max(30, math.min((r.title:GetStringWidth() or 100) + 2, avail)))
    r.badge:ClearAllPoints()
    r.badge:SetPoint("LEFT", r.title, "RIGHT", 6, 0)
    local to = (o.to and o.to ~= "") and ns.Radar.Colored(o.to) or ("|cff888888" .. L["alle"] .. "|r")
    if o.worker then to = ns.Radar.Colored(o.worker) end
    local ex = {}
    if o.mats then ex[#ex + 1] = "|cff66db9e" .. L["Mats"] .. "|r" end
    if o.tip then ex[#ex + 1] = "|cffe8b44a+" .. o.tip .. "g|r" end
    r.meta:SetText(ns.Radar.Colored(o.from) .. " |cff777777>|r " .. to .. "  |cff777777" .. ns.ago(o.u or o.created) .. "|r"
        .. (#ex > 0 and ("  " .. table.concat(ex, " ")) or ""))
    r.meta:SetPoint("RIGHT", r, "RIGHT", -reserve, 0)
    if not r.hovered then glass(r, 10, 0.03, (o.from ~= me and lit == 1 and o.status == "open") and gl(C.amber, 0.45) or GLINE) end
    -- frisch gesendet: kurz aufleuchten
    if page and page.flashId == o.id and animOn() then
        page.flashId = nil
        r.flash:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        r.flash:Show()
        K.Tween(r.flash, 1.2, function(q) r.flash:SetAlpha(0.35 * (1 - q)) end, function() r.flash:Hide() end, 0.3)
    end
end

------------------------------------------------------------------------
-- Liste mit Kapiteln (oben angeheftet), Zeilen je Schluessel wiederverwendet, gleitende Auswahl
------------------------------------------------------------------------
local function buildVList(parent, kinds, withSticky)
    local TL = CreateFrame("Frame", nil, parent)
    TL:SetClipsChildren(true)
    TL:EnableMouseWheel(true)
    TL.items, TL.total, TL.off, TL.target = {}, 0, 0, 0
    TL.used, TL.pools, TL.byKey = {}, {}, {}
    for k in pairs(kinds) do TL.pools[k] = {} end
    TL.thumb = TL:CreateTexture(nil, "OVERLAY")
    TL.thumb:SetWidth(3)
    TL.thumb:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    -- Auswahl: eigener Rahmen, gleitet zur neuen Zeile
    TL.sel = CreateFrame("Frame", nil, TL)
    TL.sel:SetFrameLevel((TL:GetFrameLevel() or 1) + 8)
    TL.sel.fill = TL.sel:CreateTexture(nil, "ARTWORK")
    TL.sel.fill:SetAllPoints()
    TL.sel.fill:SetColorTexture(1, 1, 1, 0.06)
    TL.sel.edge = TL.sel:CreateTexture(nil, "OVERLAY")
    TL.sel.edge:SetPoint("TOPLEFT") TL.sel.edge:SetPoint("BOTTOMLEFT")
    TL.sel.edge:SetWidth(2)
    TL.sel.edge:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    TL.sel:Hide()
    if withSticky then
        TL.sticky = CreateFrame("Frame", nil, TL)
        TL.sticky:SetHeight(H_HEAD - 2)
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
    end

    function TL:MaxOff() return math.max(0, self.total - (self:GetHeight() or 0) + 6) end
    function TL:Release(key, r)
        r:Hide()
        r.item = nil
        if r.hovered then r.hovered = false if r.hov then r.hov:Hide() end if r.onHover then r.onHover(r, false) end end
        self.used[key] = nil
        local pool = self.pools[r.kind]
        pool[#pool + 1] = r
    end
    function TL:PlaceSel()
        local it = self.selKey and self.byKey[self.selKey]
        local H = self:GetHeight() or 0
        if not it or not self.selY then self.sel:Hide() return end
        local y = self.selY - self.off
        if y + it.h < 0 or y > H then self.sel:Hide() return end
        self.sel:ClearAllPoints()
        self.sel:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -y)
        self.sel:SetPoint("RIGHT", self, "RIGHT", -10, 0)
        self.sel:SetHeight(math.max(1, it.h - (it.gap or 0)))
        self.sel:Show()
    end
    function TL:SetSel(key, animate)
        local it = key and self.byKey[key]
        if not it then self.selKey, self.selY = nil, nil self.sel:Hide() return end
        local from = self.selY
        local same = self.selKey == key
        self.selKey = key
        if animate and animOn() and from and from ~= it.y and not same then
            self.selAnim = true
            K.Tween(self.sel, 0.22, function(q)
                self.selY = from + (it.y - from) * q
                self:PlaceSel()
            end, function() self.selAnim = nil self.selY = it.y self:PlaceSel() end)
            return
        end
        if same and self.selAnim then return end
        self.selY = it.y
        self:PlaceSel()
    end
    function TL:Layout(force)
        local H = self:GetHeight() or 0
        local off = math.floor(self.off + 0.5)
        for key, r in pairs(self.used) do
            local it = self.byKey[key]
            if not it or it.t ~= r.kind or not (it.y + it.h > off and it.y < off + H) then self:Release(key, r)
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
                    r = table.remove(self.pools[it.t]) or kinds[it.t].make(self)
                    r.kind = it.t
                    self.used[it.key] = r
                    r.item = nil
                    r:Show()
                end
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -(it.y - off))
                r:SetPoint("RIGHT", self, "RIGHT", -10, 0)
                r:SetHeight(math.max(1, it.h - (it.gap or 0)))
                if r.item ~= it then
                    r.item = it
                    if r.stripe then r.stripe:SetShown((it.idx or 0) % 2 == 0) end
                    local ok, err = pcall(kinds[it.t].fill, r, it)
                    if not ok and ns.err then ns.err(L["Handwerks-Boerse"], err) end
                end
            elseif it.y >= off + H and first then
                if it.t == "head" and not nextH then nextH = it end
                break
            end
        end
        -- Kapitel oben anheften, vom naechsten sanft hinausschieben
        if self.sticky then
            if first and off > 0 then
                local push = 0
                if nextH then push = math.min(0, (nextH.y - off) - (H_HEAD - 2)) end
                self.sticky:ClearAllPoints()
                self.sticky:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -push)
                self.sticky:SetPoint("RIGHT", self, "RIGHT", 0, 0)
                if self.sticky.cur ~= first then self.sticky.cur = first fillHead(self.sticky.row, first) end
                self.sticky:Show()
            else
                self.sticky:Hide()
            end
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
        self:PlaceSel()
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
    TL:SetScript("OnMouseWheel", function(self, delta) self:ScrollTo(self.target - delta * 3 * H_ROW, true) end)
    TL:SetScript("OnSizeChanged", function(self) self:Layout(true) end)
    TL:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) self.off = self.target end)
    -- keep = Leseposition halten (Daten nachgeladen): Anker ist der oberste sichtbare Eintrag
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
        if self.sticky then self.sticky.cur = nil end
        if anchorKey and byKey[anchorKey] then
            self.off = byKey[anchorKey].y - anchorDy
            self.target = self.off
        elseif not keep then
            self.off, self.target = 0, 0
            self:SetScript("OnUpdate", nil)
        end
        self.off = math.max(0, math.min(self:MaxOff(), self.off))
        self.target = math.max(0, math.min(self:MaxOff(), self.target))
        if self.selKey and not byKey[self.selKey] then self.selKey, self.selY = nil, nil end
        if self.selKey and not self.selAnim then self.selY = byKey[self.selKey].y end
        self:Layout()
    end
    -- sichtbare Zeilen gestaffelt einblenden (Oeffnen/Filterwechsel)
    function TL:Stagger()
        if not animOn() then return end
        local list = {}
        for _, r in pairs(self.used) do if r.item then list[#list + 1] = { r.item.y, r } end end
        table.sort(list, function(a, b) return a[1] < b[1] end)
        for i, x in ipairs(list) do
            local r = x[2]
            r:SetAlpha(0)
            K.Tween(r, 0.24, function(q) r:SetAlpha(q) end, function() r:SetAlpha(1) end, math.min(0.4, (i - 1) * 0.03))
        end
        ns.After(1.2, function() for _, r in pairs(self.used) do r:SetAlpha(1) end end)
    end
    -- Zeile in den sichtbaren Bereich holen
    function TL:Reveal(key)
        local it = key and self.byKey[key]
        if not it then return end
        local H = self:GetHeight() or 0
        if it.y < self.off + (self.sticky and H_HEAD or 0) then self:ScrollTo(it.y - (self.sticky and H_HEAD or 0), true)
        elseif it.y + it.h > self.off + H then self:ScrollTo(it.y + it.h - H, true) end
    end
    return TL
end

------------------------------------------------------------------------
-- Rezept-Karte
------------------------------------------------------------------------
local function newCrafterChip(parent, p)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(22)
    b:RegisterForClicks("AnyUp")
    b.tint = b:CreateTexture(nil, "BORDER", nil, 1)
    b.tint:Hide()
    glass(b, 11, 0.04)
    b.cls = b:CreateTexture(nil, "ARTWORK")
    b.cls:SetSize(16, 16)
    b.cls:SetPoint("LEFT", 3, 0)
    circleMask(b, b.cls)
    b.dot = b:CreateTexture(nil, "OVERLAY")
    b.dot:SetTexture(CIRCLE)
    b.dot:SetSize(6, 6)
    b.dot:SetPoint("CENTER", b.cls, "BOTTOMRIGHT", -1, 1)
    b.text = K.Text(b, 11, C.text)
    b.text:SetPoint("LEFT", b.cls, "RIGHT", 5, 0)
    b.rank = K.Text(b, 10, C.dim)
    b.rank:SetPoint("LEFT", b.text, "RIGHT", 4, 0)
    b:SetScript("OnClick", function(self, btn)
        if not self.who then return end
        if btn == "RightButton" then crafterMenu(self, self.who) return end
        chosenCrafter = (self.who ~= "" and self.who ~= chosenCrafter) and self.who or nil
        p.chipAnim = true
        ns.RefreshPage("crafting")
    end)
    b:SetScript("OnEnter", function(self)
        if not self.on then glass(self, 11, 0.08) end
        if self.who == "" then
            K.ShowTip(self, { L["Alle, die es koennen"], "|cff888888" .. L["Der Auftrag geht an alle Handwerker mit diesem Rezept - wer Zeit hat, nimmt ihn an."] .. "|r" })
        elseif self.who then
            ns.Radar.ShowMemberTip(self, ns.Radar.byName[self.who] or { name = self.who, level = 0, zone = "", rank = "" })
            if self.blizz then GameTooltip:AddLine("|cff777777* " .. L["laut Blizzard-Gildenberufen, ohne Oasis"] .. "|r", 1, 1, 1, true) end
            GameTooltip:AddLine("|cff777777" .. L["Klick: auswaehlen"] .. "  ·  " .. L["Rechtsklick: Fluestern, Einladen, Profil"] .. "|r", 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        glass(self, 11, self.on and 0.08 or 0.04, self.on and gl(C.accent, 0.7) or GLINE)
        GameTooltip:Hide()
    end)
    return b
end
local function setCrafterChip(b, c, on, rank, nAll, animate)
    b.who, b.on, b.blizz = c.name, on, c.blizz
    if c.name == "" then
        b.cls:SetTexture(ICO .. "social")
        b.cls:SetTexCoord(0, 1, 0, 1)
        b.cls:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        b.dot:Hide()
        b.text:SetText(L["Alle, die es koennen"])
        b.rank:SetText(nAll and nAll > 0 and tostring(nAll) or "")
    else
        local cr, cg, cb, cls = classRGB(c.name)
        if setClassIcon(b.cls, cls) then
            b.cls:SetVertexColor(1, 1, 1)
        else
            b.cls:SetTexture(CIRCLE)
            b.cls:SetTexCoord(0, 1, 0, 1)
            b.cls:SetVertexColor(cr, cg, cb)
        end
        b.cls:SetAlpha(c.online and 1 or 0.5)
        local dc = c.online and C.mint or C.dim
        b.dot:SetVertexColor(dc[1], dc[2], dc[3])
        b.dot:Show()
        b.text:SetText((c.online and K.hex({ cr, cg, cb }) or "|cff8a8a90") .. ns.displayName(c.name) .. "|r" .. (c.blizz and "|cff777777*|r" or ""))
        b.rank:SetText(rank and tostring(rank) or "")
    end
    local rw = (b.rank:GetText() or "") ~= "" and ((b.rank:GetStringWidth() or 0) + 4) or 0
    b:SetWidth(math.floor(3 + 16 + 5 + (b.text:GetStringWidth() or 40) + rw + 8))
    b.tint:SetShown(on)
    b.tint:Hide()
    glass(b, 11, on and 0.08 or 0.04, on and gl(C.accent, 0.7) or GLINE)
    if on and animate and animOn() then
        b.tint:SetAlpha(0)
        K.Tween(b.tint, 0.25, function(q) b.tint:SetAlpha(q) end, function() b.tint:SetAlpha(1) end)
    else
        b.tint:SetAlpha(1)
    end
end

-- Bestand eines Materials: eigene Taschen, eigene Bank, Gildenbank, Twinks
local function stockOf(id)
    local bags, all = 0, 0
    if C_Item and C_Item.GetItemCount then
        local ok, n = pcall(C_Item.GetItemCount, id, false)
        bags = ok and tonumber(ns.safe(n)) or 0
        local ok2, n2 = pcall(C_Item.GetItemCount, id, true)
        all = ok2 and tonumber(ns.safe(n2)) or bags
    elseif ns.Wants then
        bags = ns.Wants.Count(id) or 0
        all = bags
    end
    local gb = 0
    if ns.GuildBank and ns.GuildBank.Count then
        local ok, n = pcall(ns.GuildBank.Count, id)
        gb = ok and tonumber(n) or 0
    end
    local tw = 0
    if ns.Inventory and ns.Inventory.OtherCount then
        local ok, n = pcall(ns.Inventory.OtherCount, id)
        tw = ok and tonumber(n) or 0
    end
    return bags, math.max(0, all - bags), gb, tw
end
local function newMatRow(parent)
    local m = CreateFrame("Button", nil, parent)
    m:SetHeight(18)
    m.hl = m:CreateTexture(nil, "HIGHLIGHT")
    m.hl:SetAllPoints()
    m.hl:SetColorTexture(1, 1, 1, 0.05)
    m.icon = K.Icon(m, 16, nil)
    m.icon:SetPoint("LEFT", 0, 0)
    m.price = K.Text(m, 10, C.dim, "RIGHT")
    m.price:SetPoint("RIGHT", -2, 0)
    m.price:SetWidth(62)
    m.have = K.Text(m, 11, C.text, "RIGHT")
    m.have:SetPoint("RIGHT", m.price, "LEFT", -6, 0)
    m.have:SetWidth(78)
    m.name = K.Text(m, 11, C.text)
    m.name:SetPoint("LEFT", 22, 0)
    m.name:SetPoint("RIGHT", m.have, "LEFT", -6, 0)
    m:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID) then GameTooltip:SetText(self.nm or "?", 1, 1, 1) end
        local s = self.stock or {}
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine((L["Gebraucht: %d"]):format(self.need or 0), 1, 0.85, 0.4)
        GameTooltip:AddDoubleLine(L["Taschen"], tostring(s[1] or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        GameTooltip:AddDoubleLine(L["Bank"], tostring(s[2] or 0), 0.8, 0.8, 0.8, 1, 1, 1)
        if (s[3] or 0) > 0 then GameTooltip:AddDoubleLine(L["Gildenbank"], tostring(s[3]), 0.8, 0.8, 0.8, 0.56, 0.73, 1) end
        if (s[4] or 0) > 0 then GameTooltip:AddDoubleLine(L["Twinks"], tostring(s[4]), 0.8, 0.8, 0.8, 0.56, 0.73, 1) end
        if self.priceText then GameTooltip:AddDoubleLine(L["Marktwert"], self.priceText, 0.8, 0.8, 0.8, 1, 1, 1) end
        GameTooltip:AddLine("|cff777777" .. L["Shift-Klick: verlinken"] .. "|r", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    m:SetScript("OnLeave", function() GameTooltip:Hide() end)
    m:SetScript("OnClick", function(self) if linkClick() then linkItem(self.itemID) end end)
    return m
end

local function buildCard(p)
    local card = CreateFrame("Frame", nil, p)
    glass(card, 14, 0.03)
    p.card = card
    p.cBody = CreateFrame("Frame", nil, card)
    p.cBody:SetAllPoints()
    local body = p.cBody
    -- Banner: grosses Item-Icon mit Qualitaetsring, Name, Beruf + Markt, Favorit
    local bn = CreateFrame("Frame", nil, body)
    bn:SetPoint("TOPLEFT", 1, -1)
    bn:SetPoint("TOPRIGHT", -1, -1)
    bn:SetHeight(58)
    bn.grad = bn:CreateTexture(nil, "BACKGROUND", nil, 1)
    bn.grad:SetAllPoints()
    bn.line = bn:CreateTexture(nil, "ARTWORK")
    bn.line:SetPoint("BOTTOMLEFT")
    bn.line:SetPoint("BOTTOMRIGHT")
    bn.line:SetHeight(1)
    p.banner = bn
    p.cAv = makeAvatar(bn, 44)
    p.cAv:SetPoint("LEFT", 10, 0)
    p.cAv.glow:Hide()
    p.cAvBtn = CreateFrame("Button", nil, bn)
    p.cAvBtn:SetAllPoints(p.cAv)
    p.cAvBtn:SetScript("OnEnter", function(self) if selected then recipeTip(self, selected, L["Shift-Klick: verlinken"]) end end)
    p.cAvBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.cAvBtn:SetScript("OnClick", function() if selected and linkClick() then linkItem(selected.itemID) end end)
    p.cName = K.Title(bn, 15, C.text)
    p.cName:SetPoint("TOPLEFT", 64, -12)
    p.cName:SetPoint("RIGHT", bn, "RIGHT", -34, 0)
    p.cSub = K.Text(bn, 11, C.muted)
    p.cSub:SetPoint("TOPLEFT", 64, -34)
    p.cSub:SetPoint("RIGHT", bn, "RIGHT", -12, 0)
    p.cFav = CreateFrame("Button", nil, bn)
    p.cFav:SetSize(18, 18)
    p.cFav:SetPoint("TOPRIGHT", -10, -9)
    p.cFav.t = p.cFav:CreateTexture(nil, "OVERLAY")
    p.cFav.t:SetAllPoints()
    p.cFav.t:SetTexture(ns.MEDIA .. "diamond")
    p.cFav:SetScript("OnClick", function() toggleFav(selected) end)
    p.cFav:SetScript("OnEnter", function(self) K.ShowTip(self, { isFav(selected) and L["Favorit entfernen"] or L["Als Favorit merken"], L["Favoriten stehen immer oben."] }) end)
    p.cFav:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 1: Handwerker
    p.h1 = sectionHead(body, 1, L["Handwerker waehlen"])
    p.h1:SetPoint("TOPLEFT", 12, -68)
    p.h1:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    p.h1.right:SetText(L["Klick: waehlen  ·  Rechtsklick: Menue"])
    p.cChips = {}
    p.cMore = K.Text(body, 10, C.dim)
    -- 2: Material
    p.h2 = sectionHead(body, 2, L["Material"])
    p.cMats = {}
    p.matNone = K.Text(body, 11, C.dim)
    p.matNone:SetWordWrap(true)
    p.matNone:SetText(L["Material erst bekannt, wenn jemand das Rezept kennt oder teilt."])

    -- 3: Auftrag (unten verankert)
    p.h3 = sectionHead(body, 3, L["Auftrag"])
    p.h3:SetPoint("BOTTOMLEFT", 12, 74)
    p.h3:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    local function setQty(v)
        local old = qty
        qty = math.max(1, math.min(200, v))
        if qty ~= old and animOn() then
            K.Tween(p.qty, 0.2, function(q) p.qty:SetAlpha(0.3 + 0.7 * q) end, function() p.qty:SetAlpha(1) end)
        end
        ns.RefreshPage("crafting")
    end
    p.minus = K.Button(body, "-", 22, 22, "ghost", function() setQty(qty - 1) end)
    p.minus:SetPoint("BOTTOMLEFT", 12, 44)
    p.qtyBox = CreateFrame("Frame", nil, body)
    p.qtyBox:SetSize(36, 22)
    p.qtyBox:SetPoint("LEFT", p.minus, "RIGHT", 2, 0)
    glass(p.qtyBox, 8, 0.05)
    p.qty = K.Title(p.qtyBox, 14, C.text, "CENTER")
    p.qty:SetPoint("CENTER", 0, 0)
    p.plus = K.Button(body, "+", 22, 22, "ghost", function() setQty(qty + 1) end)
    p.plus:SetPoint("LEFT", p.qtyBox, "RIGHT", 2, 0)
    p.x5 = K.Button(body, "+5", 30, 22, "ghost", function() setQty(qty + 5) end)
    p.x5:SetPoint("LEFT", p.plus, "RIGHT", 4, 0)
    p.x5.label:SetFont(K.FONT, 11, "")
    p.matChip = buildToggle(body, L["Mats dabei"], C.mint, function() return withMats end, function(v) withMats = v ns.RefreshPage("crafting") end,
        { L["Mats dabei"], "|cff888888" .. L["Du bringst das Material mit - der Handwerker braucht nichts zu besorgen."] .. "|r" })
    p.matChip:SetPoint("LEFT", p.x5, "RIGHT", 10, 0)
    tipBox = K.Input(body, 62, L["Gold"])
    tipBox:SetNumeric(true)
    tipBox:SetHeight(22)
    tipBox:SetTextInsets(7, 20, 0, 0)
    tipBox:SetPoint("LEFT", p.matChip, "RIGHT", 10, 0)
    tipBox.coin = tipBox:CreateTexture(nil, "OVERLAY")
    tipBox.coin:SetTexture(GOLD_TEX)
    tipBox.coin:SetSize(12, 12)
    tipBox.coin:SetPoint("RIGHT", -6, 0)
    tipBox:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Trinkgeld"], L["Wie viel Gold du dem Handwerker als Dank zahlst (freiwillig)."] }) end)
    tipBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.send = K.Button(body, "", 160, 26, "primary", function() if p.sendNow then p.sendNow() end end)
    p.send:SetPoint("BOTTOMRIGHT", -12, 12)
    p.send.check = p.send:CreateTexture(nil, "OVERLAY")
    p.send.check:SetTexture(CHECK_TEX)
    p.send.check:SetSize(16, 16)
    p.send.check:SetPoint("RIGHT", p.send.label, "LEFT", -5, 0)
    p.send.check:Hide()
    p.send:HookScript("OnEnter", function(self)
        if not selected then return end
        K.ShowTip(self, { L["Auftrag senden"], chosenCrafter and (L["an %s"]):format(ns.Radar.Colored(chosenCrafter)) or L["an alle, die es koennen"],
            "|cff888888" .. qty .. "x " .. selected.name .. (withMats and ("  ·  " .. L["Mats dabei"]) or "") .. "|r" })
    end)
    p.send:HookScript("OnLeave", function() GameTooltip:Hide() end)
    noteBox = K.Input(body, 200, L["Notiz, z.B. 'bis Freitag'"])
    noteBox:SetHeight(26)
    noteBox:SetPoint("BOTTOMLEFT", 12, 12)
    noteBox:SetPoint("RIGHT", p.send, "LEFT", -8, 0)

    -- leere Karte: kurze Anleitung + Aktionen
    p.cEmpty = emptyState(card)
    p.cEmpty:SetPoint("CENTER", 0, 22)
    p.cSteps = K.Text(p.cEmpty, 11, C.dim, "CENTER")
    p.cSteps:SetPoint("TOP", p.cEmpty.text, "BOTTOM", 0, -46)
    p.cSteps:SetWidth(320)
    p.cSteps:SetText("|cffe8b44a1|r " .. L["Rezept finden"] .. "   |cffe8b44a2|r " .. L["Handwerker waehlen"] .. "   |cffe8b44a3|r " .. L["Auftrag senden"])
end

-- Karte fuellen (Breite/Hoehe aus p:Layout)
local function fillCard(p)
    local e = selected
    p.cBody:SetShown(e ~= nil)
    p.cEmpty:SetShown(e == nil)
    if not e then
        local nw, nf = p.nWanted or 0, p.nFav or 0
        p.cEmpty:Set("crafting", C.accent, L["Links ein Rezept anklicken"],
            nw > 0 and (L["Gesucht: %d"]):format(nw) or L["Handwerker ansehen"], function()
                if nw > 0 then onlyWanted = true mode = "recipes" p.mode:Select("recipes", true)
                else mode = "crafters" p.mode:Select("crafters", true) end
                redraw(true)
            end,
            nf > 0 and (L["Favoriten: %d"]):format(nf) or nil, function() onlyFav = true mode = "recipes" p.mode:Select("recipes", true) redraw(true) end)
        p.cEmpty:Show()
        return
    end
    local RW = math.max(240, p.RW or 370)
    local CH = p.cardH or 290
    -- Banner
    local ring = setAvatar(p.cAv, e.itemID, e.id)
    local bc = ring == C.line and C.accent or ring
    gradient(p.banner.grad, "HORIZONTAL", bc, 0.08, 0, 0.04)
    p.banner.line:SetColorTexture(1, 1, 1, 0.08)
    p.cName:SetText(Crafting.QualityHex(e.itemID) .. e.name .. "|r")
    local pid = profIdOf(e.prof)
    local sub = (pid and ns.Radar.ProfIcon({ id = pid }, 12, C.muted) .. " " or "") .. e.prof
    local wanted = wantedBy(e)
    if wanted then sub = sub .. "   |cffe8b44a" .. (L["gesucht von %s"]):format(ns.displayName(wanted[1])) .. (#wanted > 1 and (" +" .. (#wanted - 1)) or "") .. "|r" end
    local price = ns.Market and e.itemID and ns.Market.Text(e.itemID)
    if price then sub = sub .. "   |cff888888" .. L["Markt"] .. " " .. price .. "|r" end
    p.cSub:SetText(sub)
    local fv = isFav(e)
    p.cFav.t:SetVertexColor(fv and 1 or 0.6, fv and 0.82 or 0.6, fv and 0.3 or 0.62)
    p.cFav:SetAlpha(fv and 1 or 0.45)

    -- 1: Handwerker-Chips ("Alle" zuerst), fliessend in bis zu zwei Zeilen
    local crafters = Crafting.CraftersOf(e)
    local opts = { { name = "", online = true } }
    local others = 0
    for _, c in ipairs(crafters) do if not ns.isMe(c.name) then opts[#opts + 1] = c others = others + 1 end end
    if chosenCrafter then
        local found = false
        for _, c in ipairs(opts) do if c.name == chosenCrafter then found = true end end
        if not found then chosenCrafter = nil end
    end
    local x, y, row, shown, stop = 12, -88, 1, 0, false
    local maxX = RW - 12
    local animChip = p.chipAnim
    p.chipAnim = nil
    for i, c in ipairs(opts) do
        local b = p.cChips[i] or newCrafterChip(p.cBody, p)
        p.cChips[i] = b
        local on = (c.name == "" and chosenCrafter == nil) or c.name == chosenCrafter
        setCrafterChip(b, c, on, c.name ~= "" and Crafting.SkillOf(c.name, e.prof) or nil, others, animChip)
        local w = b:GetWidth() or 80
        if not stop and x > 12 and x + w + ((row == 2 and i < #opts) and 30 or 0) > maxX then
            if row == 1 then row, x, y = 2, 12, y - 26 else stop = true end
        end
        if not stop and row == 2 and i < #opts and x > 12 and x + w + 30 > maxX then stop = true end
        if stop then
            b:Hide()
        else
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", p.cBody, "TOPLEFT", x, y)
            b:Show()
            x = x + w + 4
            shown = i
        end
    end
    for i = #opts + 1, #p.cChips do p.cChips[i]:Hide() end
    if shown < #opts then
        p.cMore:SetText("+" .. (#opts - shown))
        p.cMore:ClearAllPoints()
        p.cMore:SetPoint("TOPLEFT", p.cBody, "TOPLEFT", x + 2, y - 5)
        p.cMore:Show()
    else
        p.cMore:Hide()
    end
    if #opts == 1 then
        p.cMore:SetText("|cff888888" .. L["Noch niemand sonst kennt das Rezept."] .. "|r")
        p.cMore:ClearAllPoints()
        p.cMore:SetPoint("TOPLEFT", p.cBody, "TOPLEFT", x + 4, y - 5)
        p.cMore:Show()
    end

    -- 2: Material mit Bestand und Marktwert
    local top = -y + 30
    p.h2:ClearAllPoints()
    p.h2:SetPoint("TOPLEFT", p.cBody, "TOPLEFT", 12, -top)
    p.h2:SetPoint("RIGHT", p.cBody, "RIGHT", -12, 0)
    local rowsTop = top + 20
    local maxRows = math.max(1, math.floor((CH - 94 - rowsTop) / 18))
    local mats = Crafting.Reagents(e)
    for _, m in ipairs(p.cMats) do m:Hide() end
    p.matNone:Hide()
    if mats then
        local total, known = 0, true
        local nShow = #mats > maxRows and (maxRows - 1) or #mats
        for i, m in ipairs(mats) do
            local need = m.qty * qty
            local pr = ns.Market and ns.Market.Price(m.itemID)
            if pr then total = total + pr * need else known = false end
            if i <= nShow then
                local w = p.cMats[i] or newMatRow(p.cBody)
                p.cMats[i] = w
                w.itemID, w.need = m.itemID, need
                w.icon:SetTexture(Crafting.Icon({ itemID = m.itemID }))
                local nm = Crafting.MatName(m.itemID)
                w.nm = nm
                w.name:SetText("|cffc8c8c8" .. need .. "x|r " .. Crafting.QualityHex(m.itemID) .. nm .. "|r")
                local bags, bank, gb, tw = stockOf(m.itemID)
                w.stock = { bags, bank, gb, tw }
                local have = bags + bank
                local col = have >= need and "|cff66db9e" or ((have + gb + tw >= need) and "|cffe8b44a" or "|cffff5a4a")
                local extra = (gb + tw > 0) and (" |cff8fbaff+" .. (gb + tw) .. "|r") or ""
                w.have:SetText(col .. have .. "|r|cff777777/" .. need .. "|r" .. extra)
                w.priceText = pr and ns.Market.Format(pr * need) or nil
                w.price:SetText(w.priceText or "|cff555555–|r")
                w:ClearAllPoints()
                w:SetPoint("TOPLEFT", p.cBody, "TOPLEFT", 12, -(rowsTop + (i - 1) * 18))
                w:SetPoint("RIGHT", p.cBody, "RIGHT", -12, 0)
                w:Show()
            end
        end
        if nShow < #mats then
            local w = p.cMats[nShow + 1] or newMatRow(p.cBody)
            p.cMats[nShow + 1] = w
            w.itemID = nil
            w.icon:SetTexture(nil)
            w.name:SetText("|cff777777" .. (L["+%d weitere Materialien"]):format(#mats - nShow) .. "|r")
            w.have:SetText("")
            w.price:SetText("")
            w:ClearAllPoints()
            w:SetPoint("TOPLEFT", p.cBody, "TOPLEFT", 12, -(rowsTop + nShow * 18))
            w:SetPoint("RIGHT", p.cBody, "RIGHT", -12, 0)
            w:Show()
        end
        local line = total > 0 and ((known and "" or "≥ ") .. L["Materialwert "] .. "~" .. ns.Market.Format(total)) or ""
        -- lohnt sich das Herstellen? Verkaufspreis des fertigen Teils gegen die Materialkosten
        local sell = e.itemID and ns.Market and ns.Market.Price(e.itemID)
        if sell and total > 0 and known then
            local made = (e.yield or 1) * qty
            local diff = sell * made - total
            line = line .. "  " .. (diff >= 0 and ("|cff66db9e" .. L["lohnt sich"] .. " +" .. ns.Market.Format(diff) .. "|r")
                or ("|cffe8b44a" .. L["lieber kaufen"] .. " -" .. ns.Market.Format(-diff) .. "|r"))
        end
        p.h2.right:SetText(line)
    else
        p.h2.right:SetText("")
        p.matNone:ClearAllPoints()
        p.matNone:SetPoint("TOPLEFT", p.cBody, "TOPLEFT", 12, -rowsTop)
        p.matNone:SetPoint("RIGHT", p.cBody, "RIGHT", -12, 0)
        p.matNone:Show()
    end

    -- 3: Auftrag
    p.qty:SetText(qty)
    p.matChip:Update(false)
    p.minus:SetEnabledState(qty > 1)
    -- Trinkgeld nur, wenn Platz ist
    local rowW = 12 + 22 + 2 + 36 + 2 + 22 + 4 + 30 + 10 + (p.matChip:GetWidth() or 90) + 10 + 62
    tipBox:SetShown(rowW <= RW - 12)
    local sent = p.sentUntil and GetTime() < p.sentUntil
    local label
    if sent then
        label = L["Gesendet!"]
    elseif chosenCrafter then
        label = (L["Auftrag an %s senden"]):format(ns.displayName(chosenCrafter))
    else
        label = L["Auftrag an alle senden"]
    end
    p.send:SetLabel(label)
    local maxW = RW - 24 - 130
    local w = (p.send.label:GetStringWidth() or 100) + (sent and 50 or 30)
    if w > maxW and not sent then
        p.send:SetLabel(L["Auftrag senden"])
        w = (p.send.label:GetStringWidth() or 100) + 30
    end
    p.send:SetWidth(math.floor(math.max(100, math.min(maxW, w))))
    p.send.label:ClearAllPoints()
    p.send.label:SetPoint("CENTER", sent and 9 or 0, 0)
    p.send.check:SetShown(sent and true or false)
    -- neues Rezept gewaehlt: Karte weich einblenden
    if p.cardAnim then
        p.cardAnim = nil
        if animOn() then
            local body = p.cBody
            body:SetAlpha(0.25)
            K.Tween(body, 0.25, function(q) body:SetAlpha(0.25 + 0.75 * q) end, function() body:SetAlpha(1) end)
            K.Tween(p.cAv.glow, 0.6, function(q) p.cAv.glow:SetAlpha(0.9 - 0.45 * q) end, function() p.cAv.glow:SetAlpha(0.45) end)
        end
    end
end

-- Auftrag gesendet: kleines Icon fliegt zum Reiter "Meine"
local function flyToTab(p, e)
    if not animOn() or not p.oTabs then return end
    local tb = p.oTabs:Btn("mine")
    if not tb then return end
    local sx, sy = p.cAv:GetCenter()
    local tx, ty = tb:GetCenter()
    local l, b = p:GetLeft(), p:GetBottom()
    if not (sx and sy and tx and ty and l and b) then return end
    sx, sy, tx, ty = sx - l, sy - b, tx - l, ty - b
    local f = p.fly
    if not f then
        f = CreateFrame("Frame", nil, p)
        f:SetFrameLevel((p:GetFrameLevel() or 1) + 40)
        f:SetSize(28, 28)
        f.av = makeAvatar(f, 28)
        f.av:SetPoint("CENTER")
        f.av.glow:Show()
        p.fly = f
    end
    setAvatar(f.av, e.itemID, e.id)
    f:SetAlpha(1)
    f:Show()
    K.Tween(f, 0.6, function(q)
        local x = sx + (tx - sx) * q
        local y = sy + (ty - sy) * q + 46 * math.sin(math.pi * q)
        f:ClearAllPoints()
        f:SetPoint("CENTER", p, "BOTTOMLEFT", x, y)
        f:SetAlpha(q < 0.75 and 1 or (1 - (q - 0.75) * 4))
    end, function()
        f:Hide()
        p.oTabs:Ping("mine")
    end)
end

------------------------------------------------------------------------
-- Daten fuer die Seite (Zaehler gedrosselt, damit Nachladen billig bleibt)
------------------------------------------------------------------------
local infoCache = { t = -100 }
local function recipeInfo(force)
    local index = Crafting.Index()
    if not force and infoCache.list == index and GetTime() - infoCache.t < 3 then return infoCache end
    local me = ns.me()
    local map, nOnline, nMine, nWanted, nFav, byProf = {}, 0, 0, 0, 0, {}
    for _, e in ipairs(index) do
        local cr = Crafting.CraftersOf(e)
        local on = 0
        for _, c in ipairs(cr) do if c.online and not ns.isMe(c.name) then on = on + 1 end end
        local can = Crafting.CanCraft(me, e.name, e.id)
        local w = wantedBy(e) and true or false
        map[e] = { crafters = cr, on = on, can = can, wanted = w }
        if on > 0 then nOnline = nOnline + 1 end
        if can then nMine = nMine + 1 end
        if w then nWanted = nWanted + 1 end
        if isFav(e) then nFav = nFav + 1 end
        local pid = profIdOf(e.prof)
        if pid then byProf[pid] = (byProf[pid] or 0) + 1 end
    end
    infoCache = { list = index, t = GetTime(), map = map, nOnline = nOnline, nMine = nMine, nWanted = nWanted, nFav = nFav, byProf = byProf }
    return infoCache
end
local function crafterStats()
    local all, on = 0, 0
    for _, m in ipairs(ns.Radar.roster) do
        local pr = ns.db.members[m.name]
        local raw = pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[m.name])
        for _, pf in ipairs(ns.Radar.decodeProfs(raw)) do
            local pid = ns.Radar.ProfId(pf)
            if pid and ns.Radar.CRAFT_PROFS[pid] then
                all = all + 1
                if ns.isMe(m.name) or ns.Radar.IsOnline(m.name) then on = on + 1 end
                break
            end
        end
    end
    return all, on
end
local function profButton(p)
    local b = CreateFrame("Button", nil, p.profBar)
    glass(b, 7, 0.03)
    b.glow = b:CreateTexture(nil, "BACKGROUND", nil, -1)
    b.glow:SetTexture(EMBER)
    b.glow:SetBlendMode("ADD")
    b.glow:SetSize(42, 42)
    b.glow:SetPoint("CENTER")
    b.glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    b.glow:Hide()
    b.icon = K.Glyph(b, 16, nil)
    b.icon:SetPoint("CENTER")
    function b:Paint(hover)
        local on = profFilter == self.pid
        local c = on and C.accent or (hover and C.text or C.muted)
        self.icon:SetVertexColor(c[1], c[2], c[3])
        glass(self, 7, on and 0.09 or (hover and 0.06 or 0.03), on and gl(C.accent, 0.75) or GLINE)
        self.glow:Hide()
    end
    b:SetScript("OnClick", function(self)
        profFilter = (profFilter ~= self.pid) and self.pid or nil
        redraw(true)
    end)
    b:SetScript("OnEnter", function(self)
        self:Paint(true)
        K.ShowTip(self, { self.pname or "?", "|cff888888" .. (L["%d Rezepte"]):format(self.n or 0) .. "|r",
            "|cff777777" .. (profFilter == self.pid and L["Klick: Filter aufheben"] or L["Klick: nur dieser Beruf"]) .. "|r" })
    end)
    b:SetScript("OnLeave", function(self) self:Paint(false) GameTooltip:Hide() end)
    return b
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local function onTile(k)
    local p = page
    if not p then return end
    if k == "recipes" then
        search, profFilter, crafterFilter = "", nil, nil
        onlyOnline, onlyMine, onlyWanted, onlyFav = false, false, false, false
        mode = "recipes"
        p.search:SetText("")
        p.mode:Select("recipes", true)
        redraw(true)
    elseif k == "crafters" then
        mode = (mode == "crafters") and "recipes" or "crafters"
        p.mode:Select(mode, true)
        redraw(true)
    elseif k == "mine" then
        onlyMine = not onlyMine
        mode = "recipes"
        p.mode:Select("recipes", true)
        redraw(true)
    elseif k == "tome" then
        orderFilter = "tome"
        p.oTabs:Select("tome", true)
        p.oswitch = true
        ns.RefreshPage("crafting")
    end
end

ns.RegisterPage({
    key = "crafting", title = "Handwerks-Boerse", order = 2,
    sub = "Wer kann was herstellen - Rezepte, Material, Preise und Auftraege der Gilde",
    build = function(p)
        page = p
        p.fresh = true
        p:HookScript("OnShow", function(self) self.fresh = true end)

        -- Kennzahl-Kacheln (Klick = Filter)
        p.tiles = {}
        for i, d in ipairs(TILES) do
            p.tiles[i] = buildTile(p, d, onTile)
            p.tiles[i]:Hide()
            p.tiles[i].Show = function() end   -- bleiben aus: Filter laufen ueber die Reiter/Suche
        end

        -- links: Reiter Rezepte | Handwerker + Suche
        p.mode = buildTabs(p, MTABS, function(k)
            mode = k
            p.mode:Select(k, true)
            redraw(true)
        end)
        p.mode:SetPoint("TOPLEFT", 0, TOP_Y)
        p.mode:Select(mode)
        p.search = K.Input(p, 170, L["Rezept oder Item suchen ..."], function(t)
            local s = (t or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if s == search then return end
            search = s
            p.searchX:SetShown(s ~= "")
            redraw(true)
        end)
        p.searchX = K.IconButton(p.search, "x", 14, function()
            p.search:SetText("")
            search = ""
            p.searchX:Hide()
            redraw(true)
        end, L["Suche leeren"])
        p.searchX:SetPoint("RIGHT", -5, 0)
        p.searchX:Hide()

        -- Berufe als Symbol-Leiste
        p.profBar = CreateFrame("Frame", nil, p)
        p.profBar:SetHeight(24)
        p.profBtns = {}

        -- Filter-Schalter mit Zaehlern
        p.chips = {
            buildToggle(p, L["nur online"], C.mint, function() return onlyOnline end, function(v) onlyOnline = v redraw(true) end,
                { L["nur online"], "|cff888888" .. L["Nur Rezepte, die gerade jemand online herstellen kann"] .. "|r" }),
            buildToggle(p, L["kannst du"], C.blue, function() return onlyMine end, function(v) onlyMine = v redraw(true) end,
                { L["kannst du"], "|cff888888" .. L["Nur Rezepte, die du selbst kannst"] .. "|r" }),
            buildToggle(p, L["gesucht"], C.amber, function() return onlyWanted end, function(v) onlyWanted = v redraw(true) end,
                { L["gesucht"], "|cff888888" .. L["Steht auf einer Wunschliste der Gilde"] .. "|r" }),
            buildToggle(p, L["Favoriten"], C.pink, function() return onlyFav end, function(v) onlyFav = v redraw(true) end,
                { L["Favoriten"], "|cff888888" .. L["Favoriten mit dem Stern merken"] .. "|r" }),
        }
        p.count = K.Text(p, 10, C.dim, "RIGHT")

        -- Filter "Rezepte von X"
        p.cfStrip = CreateFrame("Frame", nil, p)
        p.cfStrip:SetHeight(22)
        p.cfStrip.bg = p.cfStrip:CreateTexture(nil, "BACKGROUND")
        p.cfStrip.bg:SetAllPoints()
        p.cfStrip.bg:SetColorTexture(C.blue[1], C.blue[2], C.blue[3], 0.07)
        p.cfStrip.text = K.Text(p.cfStrip, 11, C.text)
        p.cfStrip.text:SetPoint("LEFT", 8, 0)
        p.cfStrip.text:SetPoint("RIGHT", -26, 0)
        p.cfStrip.x = K.IconButton(p.cfStrip, "x", 16, function()
            crafterFilter = nil
            redraw(true)
        end, L["Filter aufheben"])
        p.cfStrip.x:SetPoint("RIGHT", -4, 0)
        p.cfStrip:Hide()

        -- Liste mit Berufs-Kapiteln
        p.tl = buildVList(p, {
            head = { make = function(TL) return newHead(TL) end, fill = fillHead },
            row = { make = newRecipeRow, fill = fillRecipeRow },
            crafter = { make = newCrafterRow, fill = fillCrafterRow },
        }, true)
        p.list = p.tl
        p.empty = emptyState(p.tl)
        p.empty:SetPoint("TOP", 0, -30)

        -- rechts: Rezept-Karte
        buildCard(p)

        -- rechts unten: Auftraege
        p.oTabs = buildTabs(p, OTABS, function(k)
            orderFilter = k
            p.oTabs:Select(k, true)
            p.oswitch = true
            ns.RefreshPage("crafting")
        end)
        p.oTabs:Select(orderFilter)
        p.seg = p.oTabs
        p.ol = buildVList(p, { order = { make = newOrderCard, fill = fillOrderCard } }, false)
        p.orders = p.ol
        p.oEmpty = emptyState(p.ol)
        p.oEmpty:SetPoint("TOP", 0, -10)

        p.sendNow = function()
            if not selected or (p.sentUntil and GetTime() < p.sentUntil) then return end
            local e, to, n = selected, chosenCrafter, qty
            local tip = tonumber(tipBox:GetText())
            Crafting.NewOrder(e.name, e.prof, to, n, noteBox:GetText(), e.id, e.itemID,
                { mats = withMats or nil, tip = (tip and tip > 0) and tip or nil })
            noteBox:SetText("")
            tipBox:SetText("")
            K.Toast(L["Auftrag gesendet"], n .. "x " .. e.name .. (to and (" > " .. ns.displayName(to)) or ""), C.accent)
            qty, withMats = 1, false
            flyToTab(p, e)
            p.sentUntil = GetTime() + 1.4
            p.justSent = true
            orderFilter = "mine"
            p.oTabs:Select("mine", true)
            p.oswitch = true
            ns.RefreshPage("crafting")
            ns.After(1.5, function() if page and page:IsVisible() then ns.RefreshPage("crafting") end end)
        end

        function p:Layout()
            local W, H = self:GetWidth() or 750, self:GetHeight() or 540
            if W < 100 then return end
            -- Kacheln
            local gap = 8
            local tw = math.floor((W - gap * 3) / 4)
            for i, t in ipairs(self.tiles) do
                t.bx, t.bw = (i - 1) * (tw + gap), tw
                t:Place()
            end
            local LW = math.max(280, math.min(390, math.floor(W * 0.47)))
            local RX = LW + 14
            local RW = math.max(240, W - RX)
            self.LW, self.RW = LW, RW
            -- links oben: Reiter + Suche
            self.mode.maxW = math.max(120, LW - 150)
            self.mode:Layout()
            local sw = math.max(110, LW - (self.mode:GetWidth() or 160) - 10)
            self.search:ClearAllPoints()
            self.search:SetPoint("TOPRIGHT", self, "TOPLEFT", LW, TOP_Y - 3)
            self.search:SetWidth(sw)
            self.profBar:ClearAllPoints()
            self.profBar:SetPoint("TOPLEFT", 0, TOP_Y - 36)
            self.profBar:SetWidth(LW)
            -- Filter-Schalter: was nicht passt, wird ausgeblendet
            local x = 0
            for _, c in ipairs(self.chips) do
                local w = c:GetWidth() or 80
                local show = c.want ~= false and x + w <= LW
                c:SetShown(show)
                if show then
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", self, "TOPLEFT", x, TOP_Y - 66)
                    x = x + w + 5
                end
            end
            self.count:ClearAllPoints()
            self.count:SetPoint("TOPRIGHT", self, "TOPLEFT", LW - 12, TOP_Y - 71)
            self.count:SetWidth(math.max(1, LW - x - 14))
            self.count:SetShown(LW - x > 60)
            local listTop = TOP_Y - 96
            if self.cfStrip:IsShown() then
                self.cfStrip:ClearAllPoints()
                self.cfStrip:SetPoint("TOPLEFT", 0, listTop)
                self.cfStrip:SetWidth(LW)
                listTop = listTop - 26
            end
            self.tl:ClearAllPoints()
            self.tl:SetPoint("TOPLEFT", 0, listTop)
            self.tl:SetPoint("BOTTOMLEFT", 0, 0)
            self.tl:SetWidth(LW)
            -- rechts: Karte oben, Auftraege darunter
            local cardH = math.max(250, math.min(320, H + TOP_Y - 150))
            self.cardH = cardH
            self.card:ClearAllPoints()
            self.card:SetPoint("TOPLEFT", RX, TOP_Y)
            self.card:SetSize(RW, cardH)
            self.oTabs.maxW = RW
            self.oTabs:Layout()
            self.oTabs:ClearAllPoints()
            self.oTabs:SetPoint("TOPLEFT", RX, TOP_Y - cardH - 8)
            self.ol:ClearAllPoints()
            self.ol:SetPoint("TOPLEFT", RX, TOP_Y - cardH - 44)
            self.ol:SetPoint("BOTTOMRIGHT", 0, 0)
        end
        p:HookScript("OnSizeChanged", function(self)
            self:Layout()
            pcall(fillCard, self)
        end)
        p:Layout()
    end,

    refresh = function(p)
        local fresh, switch, oswitch = p.fresh, p.switch, p.oswitch
        p.fresh, p.switch, p.oswitch = false, nil, nil
        local index = Crafting.Index()
        -- Auswahl nach Neuaufbau des Index wiederfinden (Name kann sich nach dem Nachladen aendern)
        if selected then
            selected = Crafting.byName[selected.name] or (selected.itemID and Crafting.byItem[selected.itemID]) or nil
        end
        local info = recipeInfo(fresh or switch)
        p.nWanted, p.nFav = info.nWanted, info.nFav

        -- Kacheln
        local nCrafters, nOn = crafterStats()
        local sets = orderSets()
        local vals = {
            recipes = { #index },
            crafters = { nCrafters, nOn > 0 and ("· " .. (L["%d online"]):format(nOn)) or nil, nCrafters > 0 and nOn / nCrafters or nil },
            mine = { info.nMine, nil, #index > 0 and info.nMine / #index or nil },
            tome = { #sets.tome },
        }
        for i, t in ipairs(p.tiles) do
            local v = vals[t.key]
            t:SetValue(v[1], v[2], v[3], fresh, (i - 1) * 0.05)
            local filtered = search ~= "" or profFilter or crafterFilter or onlyOnline or onlyMine or onlyWanted or onlyFav
            t:SetSel((t.key == "recipes" and mode == "recipes" and not filtered) or (t.key == "crafters" and mode == "crafters")
                or (t.key == "mine" and onlyMine and mode == "recipes") or (t.key == "tome" and orderFilter == "tome"))
        end
        if fresh and animOn() then for i, t in ipairs(p.tiles) do K.FadeIn(t, (i - 1) * 0.05) end end

        -- Berufs-Symbole
        local profs = allProfIds()
        local n = math.min(#profs, 14)
        local bs = math.max(18, math.min(24, math.floor(((p.LW or 360) + 2) / math.max(1, n)) - 2))
        for _, b in ipairs(p.profBtns) do b:Hide() end
        for i = 1, n do
            local pf = profs[i]
            local b = p.profBtns[i] or profButton(p)
            p.profBtns[i] = b
            b.pid, b.pname, b.n = pf.pid, pf.name, info.byProf[pf.pid] or 0
            b:SetSize(bs, bs)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", (i - 1) * (bs + 2), 0)
            b.icon:SetSize(bs - 8, bs - 8)
            b.icon:SetTexture(ICO .. "prof_" .. pf.pid)
            b:Paint(false)
            b:Show()
        end

        -- Reiter + Filter-Schalter
        p.mode:SetCounts({ recipes = #index, crafters = nCrafters })
        p.mode:Select(mode, not fresh)
        p.chips[1]:Update(info.nOnline)
        p.chips[2]:Update(info.nMine)
        p.chips[3]:Update(info.nWanted)
        p.chips[4]:Update(info.nFav)
        for i = 2, 4 do p.chips[i].want = mode == "recipes" end
        p.chips[1].want = true
        p.cfStrip:SetShown(crafterFilter ~= nil and mode == "recipes")
        if crafterFilter then p.cfStrip.text:SetText((L["Rezepte von %s"]):format(ns.Radar.Colored(crafterFilter))) end

        -- linke Liste: Kapitel je Beruf (Favoriten zuerst)
        local items = {}
        local filtered = search ~= "" or crafterFilter or onlyMine or onlyWanted or onlyFav or onlyOnline or profFilter
        local shownN = 0
        if mode == "crafters" then
            local idx = 0
            for _, x in ipairs(crafterRows()) do
                if x.header then
                    items[#items + 1] = { t = "head", key = "h:" .. tostring(x.pid), h = H_HEAD, label = x.name or "?", n = x.n, glyph = ICO .. "prof_" .. x.pid, color = C.blue }
                    idx = 0
                else
                    idx = idx + 1
                    shownN = shownN + 1
                    items[#items + 1] = { t = "crafter", key = "c:" .. tostring(x.pid) .. ":" .. x.member, h = H_CRAFTER, gap = 2, x = x, idx = idx }
                end
            end
            p.count:SetText((L["%d Handwerker"]):format(shownN))
        else
            local recs = filteredRecipes()
            local favList, groups, order = {}, {}, {}
            for _, e in ipairs(recs) do
                if isFav(e) then
                    favList[#favList + 1] = e
                else
                    local g = groups[e.prof]
                    if not g then
                        g = { name = e.prof, pid = profIdOf(e.prof), list = {} }
                        groups[e.prof] = g
                        order[#order + 1] = g
                    end
                    g.list[#g.list + 1] = e
                end
            end
            table.sort(order, function(a, b) return (a.name or "") < (b.name or "") end)
            local function addRows(list, prefix)
                for i, e in ipairs(list) do
                    local inf = info.map[e] or { crafters = Crafting.CraftersOf(e), on = 0 }
                    items[#items + 1] = { t = "row", key = "r:" .. e.name, h = H_ROW, gap = 2, e = e, idx = i,
                        crafters = inf.crafters, on = inf.on or 0, can = inf.can, wanted = inf.wanted }
                end
            end
            if #favList > 0 then
                items[#items + 1] = { t = "head", key = "h:fav", h = H_HEAD, label = L["Favoriten"], n = #favList, glyph = ns.MEDIA .. "diamond", color = C.amber }
                addRows(favList)
            end
            for _, g in ipairs(order) do
                items[#items + 1] = { t = "head", key = "h:" .. g.name, h = H_HEAD, label = g.name, n = #g.list, glyph = g.pid and (ICO .. "prof_" .. g.pid) or (ICO .. "crafting"), color = C.accent }
                addRows(g.list)
            end
            shownN = #recs
            p.count:SetText(#recs ~= #index and (L["%d von %d"]):format(#recs, #index) or "")
        end
        p.tl:SetItems(items, not (fresh or switch))
        p.tl:SetSel(selected and mode == "recipes" and ("r:" .. selected.name) or nil, p.selAnim)
        if p.selAnim and selected then p.tl:Reveal("r:" .. selected.name) end
        p.selAnim = nil
        if fresh or switch then p.tl:Stagger() end

        -- Leerzustand links
        p.empty:SetShown(#items == 0)
        if #items == 0 then
            if mode == "crafters" then
                p.empty:Set("social", C.blue, L["Keine Berufe bekannt."], filtered and L["Filter zuruecksetzen"] or nil, function() onTile("recipes") end)
            elseif filtered then
                p.empty:Set("crafting", C.muted, L["Nichts gefunden - Filter lockern oder aufheben."], L["Filter zuruecksetzen"], function() onTile("recipes") end)
            else
                p.empty:Set("crafting", C.accent, L["Noch keine Rezepte geteilt.\n\nSobald jemand mit Oasis sein Berufsfenster oeffnet, erscheinen die Rezepte hier. Wer welchen Beruf hat, siehst du schon jetzt:"],
                    L["Handwerker ansehen"], function() mode = "crafters" p.mode:Select("crafters", true) redraw(true) end)
            end
        end

        -- Rezept-Karte
        local ok, err = pcall(fillCard, p)
        if not ok and ns.err then ns.err(L["Handwerks-Boerse"], err) end

        -- Auftraege
        p.oTabs:SetCounts({ tome = #sets.tome, mine = #sets.mine, open = #sets.open, done = #sets.done })
        p.oTabs:Select(orderFilter, not fresh)
        if p.justSent then
            p.justSent = nil
            local o = sets.mine[1]
            if o and o.from == ns.me() then p.flashId = o.id end
        end
        local olist = sets[orderFilter] or {}
        local oitems = {}
        for i, o in ipairs(olist) do oitems[#oitems + 1] = { t = "order", key = "o:" .. tostring(o.id), h = H_ORDER, gap = 4, o = o, idx = i } end
        p.ol:SetItems(oitems, not (fresh or oswitch))
        if fresh or oswitch then p.ol:Stagger() end
        p.oEmpty:SetShown(#oitems == 0)
        if #oitems == 0 then
            if orderFilter == "tome" then
                p.oEmpty:Set("checklist", C.amber, L["Gerade will niemand etwas von dir."], #sets.open > 0 and L["Alle offenen ansehen"] or nil, function()
                    orderFilter = "open" p.oTabs:Select("open", true) p.oswitch = true ns.RefreshPage("crafting")
                end)
            elseif orderFilter == "mine" then
                p.oEmpty:Set("wants", C.blue, L["Du hast keine offenen Auftraege."], L["Rezept suchen"], function()
                    p.search:SetFocus()
                end)
            elseif orderFilter == "open" then
                p.oEmpty:Set("crafting", C.accent, L["Keine offenen Auftraege in der Gilde."], L["Rezept suchen"], function() p.search:SetFocus() end)
            else
                p.oEmpty:Set("badges", C.mint, L["Noch nichts erledigt."])
            end
        end
        p:Layout()
    end,
})

-- Item-Daten kommen nach: Seite gedrosselt neu zeichnen (Leseposition bleibt)
local itemPend
local function itemsArrived()
    if itemPend or not (page and page.IsVisible and page:IsVisible()) then return end
    itemPend = true
    ns.After(0.8, function()
        itemPend = nil
        if page and page:IsVisible() then ns.RefreshPage("crafting") end
    end)
end
pcall(ns.On, "GET_ITEM_INFO_RECEIVED", itemsArrived)

ns.Listen("LOGIN", function()
    mirrorOwn()
    Crafting.dirty = true
    ns.After(10, updateBadge)
end)
ns.Listen("ROSTER", function() ns.RefreshPage("crafting") end)


-- von aussen: Handwerks-Boerse oeffnen und nach einem Item suchen (z.B. aus "Verbrauchsgueter" im Profil)
function Crafting.ShowItem(name)
    if not name or name == "" then return end
    search = name:lower()
    mode = "recipes"
    -- andere Filter weg, sonst findet die Suche das Item evtl. nicht
    profFilter, crafterFilter = nil, nil
    onlyOnline, onlyMine, onlyWanted, onlyFav = false, false, false, false
    ns.ShowPage("crafting")
    local def = ns.PageDef and ns.PageDef("crafting")
    local p = def and def.frame
    if p then
        if p.search then p.search:SetText(name) end
        if p.searchX then p.searchX:Show() end
        if p.mode then p.mode:Select("recipes") end
        p.switch = true
    end
    ns.RefreshPage("crafting")
end

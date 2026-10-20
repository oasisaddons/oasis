-- Oasis: Aktionsleisten speichern und laden (0.6.521)
-- Belegung aller 120 Plaetze (Zauber, Makros, Items) unter einem Namen je Charakter; Laden legt sie wieder hin.
-- Nur ausserhalb des Kampfes. /oa leisten [speichern|laden|loeschen] Name, ohne Namen: Liste
-- Einstellungen > Komfort: Knoepfe dazu.
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Comfort", function()
local L = ns.L
local AB = {}
ns.ActionBars = AB
local SLOTS = 120

local function store()
    ns.char.barSets = ns.char.barSets or {}
    return ns.char.barSets
end
function AB.Names()
    local out = {}
    for n in pairs(store()) do out[#out + 1] = n end
    table.sort(out)
    return out
end
function AB.Save(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or not GetActionInfo then return end
    local set = {}
    for i = 1, SLOTS do
        local kind, id, sub = GetActionInfo(i)
        kind, id, sub = ns.safe(kind), ns.safe(id), ns.safe(sub)
        if kind == "spell" or kind == "item" or kind == "macro" then
            local e = { k = kind, id = id }
            if kind == "macro" then e.n = ns.safe(GetMacroInfo(id)) end
            set[i] = e
        end
    end
    store()[name] = { slots = set, ts = time() }
    ns.print((L["Action bars saved: %s"]):format(name))
end
function AB.Load(name)
    local s = store()[name]
    if not s then ns.print((L["No saved bars named %s."]):format(tostring(name))) return end
    if InCombatLockdown() then ns.print(L["Not possible in combat - try again shortly."]) return end
    if GetCursorInfo() then ClearCursor() end
    local placed, missing = 0, 0
    for i = 1, SLOTS do
        local want = s.slots[i]
        local kind, id = GetActionInfo(i)
        kind, id = ns.safe(kind), ns.safe(id)
        local same = want and kind == want.k and id == want.id
        if not same then
            if want then
                local ok = false
                if want.k == "spell" and PickupSpell then ok = pcall(PickupSpell, want.id)
                elseif want.k == "item" and PickupItem then ok = pcall(PickupItem, want.id)
                elseif want.k == "macro" and PickupMacro then
                    local idx = want.n and GetMacroIndexByName and GetMacroIndexByName(want.n) or want.id
                    if idx and idx > 0 then ok = pcall(PickupMacro, idx) end
                end
                if ok and GetCursorInfo() then
                    PlaceAction(i)
                    placed = placed + 1
                else
                    missing = missing + 1
                end
                ClearCursor()
            elseif kind then
                PickupAction(i)
                ClearCursor()
            end
        end
    end
    ns.print((L["Action bars loaded: %s (%d placed, %d unavailable)"]):format(name, placed, missing))
end
function AB.Delete(name)
    if store()[name] then store()[name] = nil ns.print((L["Deleted: %s"]):format(name)) end
end
ns.slash.leisten = function(arg)
    local cmd, name = (arg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "speichern" or cmd == "save" then AB.Save(name)
    elseif cmd == "laden" or cmd == "load" then AB.Load(name)
    elseif cmd == "loeschen" or cmd == "l\195\182schen" or cmd == "delete" then AB.Delete(name)
    else
        local n = AB.Names()
        ns.print(#n > 0 and (L["Saved bars: %s"]):format(table.concat(n, ", ")) or L["No bars saved yet."])
        ns.print(L["/oa bars save Name  -  /oa bars load Name  -  /oa bars delete Name"])
    end
end
ns.slash.bars = ns.slash.leisten

end)

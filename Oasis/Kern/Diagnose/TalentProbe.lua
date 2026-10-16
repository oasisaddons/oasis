-- Oasis: Pruefung, wie WoW Forever Talente bereitstellt (Grundlage fuer "Talente anderer ansehen").
-- /oa talentprobe  -> schreibt alles nach OasisDB.talentProbe (nach /reload in der Speicherdatei lesbar)
-- Nur lesende Abfragen, alles in pcall, nicht im Kampf.
local ADDON, ns = ...

local function probe()
    if ns.inCombat() then ns.print("Im Kampf nicht - gleich nochmal.") return end
    local out = {}
    local function put(k, v) out[#out + 1] = k .. " = " .. tostring(v) end
    local function try(label, fn, ...)
        local r = { pcall(fn, ...) }
        local ok = table.remove(r, 1)
        if not ok then put(label, "FEHLER " .. tostring(r[1])) return nil end
        local parts = {}
        for i = 1, math.min(#r, 12) do
            local v = r[i]
            if type(v) == "table" then
                local t = {}
                for k2, v2 in pairs(v) do if #t < 20 then t[#t + 1] = tostring(k2) .. ":" .. tostring(type(v2) == "table" and ("{" .. #v2 .. "}") or v2) end end
                parts[#parts + 1] = "{" .. table.concat(t, ", ") .. "}"
            else
                parts[#parts + 1] = tostring(v)
            end
        end
        put(label, table.concat(parts, " | "))
        return unpack(r)
    end
    -- welche Talent-Schnittstellen gibt es?
    for _, n in ipairs({ "GetNumTalentTabs", "GetTalentTabInfo", "GetTalentInfo", "GetNumTalents", "LearnTalent", "GetActiveTalentGroup",
        "GetUnspentTalentPoints", "GetTalentLink", "NotifyInspect", "GetInspectSpecialization", "GetSpecialization", "UnitClass" }) do
        put("G." .. n, type(_G[n]))
    end
    for _, ns2 in ipairs({ "C_ClassTalents", "C_Traits", "C_SpecializationInfo", "C_TalentTree", "C_Talent", "C_TalentUI" }) do
        local t = _G[ns2]
        if type(t) == "table" then
            local fns = {}
            for k in pairs(t) do fns[#fns + 1] = k end
            table.sort(fns)
            put(ns2, table.concat(fns, ","))
        else
            put(ns2, type(t))
        end
    end
    for _, n in ipairs({ "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "TalentFrame", "InspectFrame", "ClassTalentLoadoutViewFrame" }) do
        put("Frame." .. n, type(_G[n]))
    end
    local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    for _, a in ipairs({ "Blizzard_PlayerSpells", "Blizzard_ClassTalentUI", "Blizzard_TalentUI", "Blizzard_InspectUI" }) do
        if IsLoaded then put("Loaded." .. a, tostring(IsLoaded(a))) end
    end
    -- klassisch
    if GetNumTalentTabs then
        local nt = try("GetNumTalentTabs()", GetNumTalentTabs)
        for tab = 1, math.min(nt or 0, 3) do
            try("GetTalentTabInfo(" .. tab .. ")", GetTalentTabInfo, tab)
            if GetNumTalents then
                local n = try("GetNumTalents(" .. tab .. ")", GetNumTalents, tab)
                for i = 1, math.min(n or 0, 3) do try("GetTalentInfo(" .. tab .. "," .. i .. ")", GetTalentInfo, tab, i) end
            end
        end
    end
    -- Retail-System
    if C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        local cfg = try("C_ClassTalents.GetActiveConfigID()", C_ClassTalents.GetActiveConfigID)
        if cfg and C_Traits then
            local info = try("C_Traits.GetConfigInfo(cfg)", C_Traits.GetConfigInfo, cfg)
            if C_Traits.GenerateImportString then try("C_Traits.GenerateImportString(cfg)", C_Traits.GenerateImportString, cfg) end
            local tree = info and info.treeIDs and info.treeIDs[1]
            if tree then
                local nodes = try("C_Traits.GetTreeNodes(tree)", C_Traits.GetTreeNodes, tree)
                if type(nodes) == "table" then
                    put("nodes.count", #nodes)
                    for i = 1, math.min(3, #nodes) do
                        local ni = try("C_Traits.GetNodeInfo(" .. tostring(nodes[i]) .. ")", C_Traits.GetNodeInfo, cfg, nodes[i])
                        if ni and ni.entryIDs and ni.entryIDs[1] then
                            local ei = try("C_Traits.GetEntryInfo", C_Traits.GetEntryInfo, cfg, ni.entryIDs[1])
                            if ei and ei.definitionID then try("C_Traits.GetDefinitionInfo", C_Traits.GetDefinitionInfo, ei.definitionID) end
                        end
                    end
                end
            end
        end
    end
    if C_SpecializationInfo and C_SpecializationInfo.GetSpecialization then try("C_SpecializationInfo.GetSpecialization()", C_SpecializationInfo.GetSpecialization) end
    if GetSpecialization then try("GetSpecialization()", GetSpecialization) end
    -- Symbole: fuer einige Knoten alle Wege pruefen (sofort und nach dem Nachladen der Zauberdaten)
    local icons = {}
    if C_ClassTalents and C_Traits then
        local cfg = C_ClassTalents.GetActiveConfigID()
        local okI, info = pcall(C_Traits.GetConfigInfo, cfg)
        local tree = okI and info and info.treeIDs and info.treeIDs[1]
        local okN, nodes = pcall(C_Traits.GetTreeNodes, tree)
        if okN and type(nodes) == "table" then
            for i = 1, math.min(6, #nodes) do
                local okNi, ni = pcall(C_Traits.GetNodeInfo, cfg, nodes[i])
                local eid = okNi and ni and ni.entryIDs and ni.entryIDs[1]
                local okE, ei = eid and pcall(C_Traits.GetEntryInfo, cfg, eid)
                local def = okE and ei and ei.definitionID
                local okD, di = def and pcall(C_Traits.GetDefinitionInfo, def)
                if okD and di then
                    local f = {}
                    for k, v in pairs(di) do f[#f + 1] = tostring(k) .. "=" .. tostring(v) end
                    icons[#icons + 1] = { node = nodes[i], def = def, spell = di.spellID, defFields = table.concat(f, ",") }
                end
            end
        end
    end
    local function iconLine(e, when)
        local sp = e.spell
        local parts = { when, "node=" .. tostring(e.node), "def=" .. tostring(e.def), "spell=" .. tostring(sp), "[" .. e.defFields .. "]" }
        local function t(label, fn, ...)
            if not fn then parts[#parts + 1] = label .. "=fehlt" return end
            local ok, a, b, c2 = pcall(fn, ...)
            if type(a) == "table" then
                local f = {}
                for k, v in pairs(a) do f[#f + 1] = tostring(k) .. ":" .. tostring(v) end
                a = "{" .. table.concat(f, ",") .. "}"
            end
            parts[#parts + 1] = label .. "=" .. (ok and (tostring(a) .. (b ~= nil and ("|" .. tostring(b)) or "") .. (c2 ~= nil and ("|" .. tostring(c2)) or "")) or ("FEHLER " .. tostring(a)))
        end
        t("C_Spell.GetSpellTexture", C_Spell and C_Spell.GetSpellTexture, sp)
        t("C_Spell.GetSpellInfo", C_Spell and C_Spell.GetSpellInfo, sp)
        t("C_Spell.GetSpellName", C_Spell and C_Spell.GetSpellName, sp)
        t("C_Spell.DoesSpellExist", C_Spell and C_Spell.DoesSpellExist, sp)
        t("C_Spell.IsSpellDataCached", C_Spell and C_Spell.IsSpellDataCached, sp)
        t("G.GetSpellTexture", _G.GetSpellTexture, sp)
        t("G.GetSpellInfo", _G.GetSpellInfo, sp)
        t("C_Traits.GetDefinitionInfo.overrideIcon", function() local d = C_Traits.GetDefinitionInfo(e.def) return d and d.overrideIcon end)
        return table.concat(parts, "  ")
    end
    -- klassische Talent-Schnittstelle (Forever-Talentfenster sieht klassisch aus)
    local S2 = C_SpecializationInfo
    if S2 and S2.GetTalentInfo then
        for _, q in ipairs({ { tier = 1, column = 1 }, { tabIndex = 1, talentIndex = 1 }, { specializationIndex = 1, talentIndex = 1 }, { tier = 1, column = 1, groupIndex = 1 } }) do
            local parts = {}
            for k, v in pairs(q) do parts[#parts + 1] = k .. "=" .. v end
            try("C_SpecializationInfo.GetTalentInfo{" .. table.concat(parts, ",") .. "}", S2.GetTalentInfo, q)
        end
        try("C_SpecializationInfo.GetTalentInfo(1,1)", S2.GetTalentInfo, 1, 1)
    end
    for _, n in ipairs({ "GetTalentTabInfo", "GetNumTalentTabs" }) do
        if S2 and S2[n] then try("C_SpecializationInfo." .. n .. "(1)", S2[n], 1) end
    end
    -- klassische Hintergrund-Grafiken vorhanden?
    local tx = UIParent:CreateTexture()
    for _, path in ipairs({ "Interface\\TalentFrame\\ShamanElementalCombat-TopLeft", "Interface\\TalentFrame\\WarlockCurses-TopLeft", "Interface\\TalentFrame\\PaladinHoly-TopLeft" }) do
        local ok, r = pcall(tx.SetTexture, tx, path)
        put("TEX " .. path, tostring(ok) .. " " .. tostring(r) .. " " .. tostring(tx:GetTexture()))
    end
    for _, e in ipairs(icons) do
        put("ICON", iconLine(e, "sofort"))
        if C_Spell and C_Spell.RequestLoadSpellData then pcall(C_Spell.RequestLoadSpellData, e.spell) end
    end
    ns.db.talentProbe = { ts = ns.now(), v = ns.version, lines = out }
    ns.print("Talent-Pruefung laeuft ... (3 Sekunden)")
    C_Timer.After(3, function()
        for _, e in ipairs(icons) do out[#out + 1] = "ICON = " .. iconLine(e, "nach 3s") end
        ns.db.talentProbe = { ts = ns.now(), v = ns.version, lines = out }
        ns.print(("Talent-Pruefung: %d Zeilen gespeichert - jetzt /reload, dann sind sie gespeichert."):format(#out))
    end)
end
ns.slash.talentprobe = probe

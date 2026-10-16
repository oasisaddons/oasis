-- Oasis: Talente anderer ansehen
--  * jeder Oasis-Nutzer teilt seinen Talent-Export (Blizzards Import-Text, sehr kurz) in der Gilden-Sammlung "talents"
--  * betrachtete Spieler (Inspect, auch fremde) werden lokal gemerkt (ns.db.inspTalents)
--  * eigenes Fenster zeichnet den Baum: Knoten mit Symbol + Rang, Verbindungen, Zauber-Tooltip
-- WoW Forever nutzt das Retail-Talentsystem (C_ClassTalents / C_Traits, gemessen per /oa talentprobe 08.10.).
-- Baum-Aufbau fuer fremde Klassen: Blizzards "Ansichts-Loadout" (C_ClassTalents.InitializeViewLoadout).
local ADDON, ns = ...
ns.ModuleFile("Oasis_Talente", function()   -- Modul Talente (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local T = {}
ns.Talents = T
local COLL = "talents"

------------------------------------------------------------------------
-- Export-Text lesen (Blizzard ExportUtil: Base64, Bits von hinten nach vorn je Zeichen)
------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64V = {}
for i = 1, #B64 do B64V[B64:sub(i, i)] = i - 1 end
local function reader(s)
    local vals = {}
    for ch in tostring(s or ""):gmatch(".") do
        local v = B64V[ch]
        if not v then return nil end
        vals[#vals + 1] = v
    end
    local idx, pos = 1, 0
    local r = {}
    function r.take(bits)
        local out, mul = 0, 1
        for _ = 1, bits do
            local v = vals[idx]
            if v == nil then r.eof = true return out end
            local bit = math.floor(v / (2 ^ pos)) % 2
            out = out + bit * mul
            mul = mul * 2
            pos = pos + 1
            if pos == 6 then pos, idx = 0, idx + 1 end
        end
        return out
    end
    return r
end
-- Kopf: Version, Spezialisierung
function T.Header(s)
    local r = reader(s)
    if not r then return nil end
    local ver = r.take(8)
    local spec = r.take(16)
    return ver, spec, r
end
-- Knoten-Raenge: nodes = Liste der Knoten-IDs in Baum-Reihenfolge, maxOf(nodeID) -> max. Rang
function T.Decode(s, nodes, maxOf)
    local ver, spec, r = T.Header(s)
    if not r then return nil end
    for _ = 1, 16 do r.take(8) end   -- Baum-Pruefsumme
    local ranks, choice = {}, {}
    for _, id in ipairs(nodes) do
        if r.eof then break end
        local selected = r.take(1) == 1
        if selected then
            local purchased = true
            if ver >= 2 then purchased = r.take(1) == 1 end
            local rank = maxOf(id) or 1
            if purchased then
                if r.take(1) == 1 then rank = r.take(6) end
                if r.take(1) == 1 then choice[id] = r.take(2) + 1 end
            end
            ranks[id] = rank
        end
    end
    return ranks, choice, spec, ver
end

------------------------------------------------------------------------
-- Baum-Aufbau (Positionen, Zauber, Verbindungen) fuer eine Spezialisierung
------------------------------------------------------------------------
local layoutCache = {}
local function nodeLayout(cfg, id)
    local ok, ni = pcall(C_Traits.GetNodeInfo, cfg, id)
    if not ok or type(ni) ~= "table" or not ni.posX or ni.isVisible == false then return nil end
    local spells, icons, entries = {}, {}, {}
    for i, eid in ipairs(ni.entryIDs or {}) do
        entries[i] = eid
        local okE, ei = pcall(C_Traits.GetEntryInfo, cfg, eid)
        local def = okE and ei and ei.definitionID
        local okD, di = def and pcall(C_Traits.GetDefinitionInfo, def)
        -- 0.5.507: overriddenSpellID ist in Forever oft 0 (in Lua "wahr") -> dann den normalen Zauber nehmen
        local ov = okD and di and di.overriddenSpellID
        spells[i] = okD and di and ((ov and ov ~= 0) and ov or di.spellID) or 0
        icons[i] = okD and di and di.overrideIcon or nil
    end
    local edges = {}
    for _, e in ipairs(ni.visibleEdges or {}) do if e.targetNode then edges[#edges + 1] = e.targetNode end end
    return { id = id, x = ni.posX, y = ni.posY, max = ni.maxRanks or 1, type = ni.type or 0, spells = spells, icons = icons, entries = entries, edges = edges,
        rank = ni.currentRank or 0 }
end
-- eigene, aktive Konfiguration (mit echten Raengen)
function T.MyLayout()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return nil end
    local cfg = C_ClassTalents.GetActiveConfigID()
    if not cfg then return nil end
    local okI, info = pcall(C_Traits.GetConfigInfo, cfg)
    local tree = okI and info and info.treeIDs and info.treeIDs[1]
    if not tree then return nil end
    local ok, nodes = pcall(C_Traits.GetTreeNodes, tree)
    if not ok or type(nodes) ~= "table" then return nil end
    local list, byId = {}, {}
    for _, id in ipairs(nodes) do
        local n = nodeLayout(cfg, id)
        if n then list[#list + 1] = n byId[id] = n end
    end
    return { order = nodes, list = list, byId = byId, tree = tree, cfg = cfg }
end
-- fremde Spezialisierung: Blizzards Ansichts-Loadout (wie beim Anklicken eines Talent-Links)
function T.SpecLayout(spec)
    if layoutCache[spec] then return layoutCache[spec] end
    if not (C_ClassTalents and C_ClassTalents.GetTraitTreeForSpec and C_Traits) then return nil end
    local okT, tree = pcall(C_ClassTalents.GetTraitTreeForSpec, spec)
    if not okT or not tree then return nil end
    local viewCfg = Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID
    if viewCfg and C_ClassTalents.InitializeViewLoadout then pcall(C_ClassTalents.InitializeViewLoadout, spec, 60) end
    local ok, nodes = pcall(C_Traits.GetTreeNodes, tree)
    if not ok or type(nodes) ~= "table" then return nil end
    local list, byId = {}, {}
    for _, id in ipairs(nodes) do
        local n = viewCfg and nodeLayout(viewCfg, id)
        if n then n.rank = 0 list[#list + 1] = n byId[id] = n end
    end
    if #list == 0 then return nil end
    local lay = { order = nodes, list = list, byId = byId, tree = tree, cfg = viewCfg }
    layoutCache[spec] = lay
    return lay
end

------------------------------------------------------------------------
-- eigenen Stand teilen
------------------------------------------------------------------------
local function mySpec()
    local S = C_SpecializationInfo
    local idx = S and S.GetSpecialization and S.GetSpecialization()
    local id = idx and S.GetSpecializationInfo and S.GetSpecializationInfo(idx)
    return ns.safe(id)
end
function T.MyExport()
    if not (C_ClassTalents and C_Traits and C_Traits.GenerateImportString) then return nil end
    local cfg = C_ClassTalents.GetActiveConfigID()
    if not cfg then return nil end
    local ok, s = pcall(C_Traits.GenerateImportString, cfg)
    return ok and ns.safe(s) or nil
end
local function share()
    if ns.inCombat() or not (ns.me and ns.me()) then return end
    local s = T.MyExport()
    if not s or s == "" or #s > 1500 then return end
    local id = "tal-" .. ns.me()
    local old = Store.Get(COLL, id)
    local _, cls = UnitClass("player")
    local lvl = ns.safe(UnitLevel("player")) or 0
    -- gelernte Symbole der eigenen Talente (zauber=symbol;...) - andere sehen dann auch Symbole
    local ic
    do
        local db, parts, seen = ns.db.talIcons or {}, {}, {}
        local lay = T.MyLayout()
        for _, n in ipairs(lay and lay.list or {}) do
            local nv = db["n" .. n.id]
            if type(nv) == "number" then parts[#parts + 1] = "n" .. n.id .. "=" .. nv end
            for _, sp in ipairs(n.spells) do
                local v = db[sp]
                if sp and sp ~= 0 and type(v) == "number" and not seen[sp] then seen[sp] = true parts[#parts + 1] = sp .. "=" .. v end
            end
        end
        ic = #parts > 0 and table.concat(parts, ";"):sub(1, 2400) or nil
    end
    -- Zauber der eigenen Talente je Knoten (knoten=zauber;...): andere Klassen bekommen ihn aus WoW oft nicht -> Tooltip ohne Text
    local sp
    do
        local parts = {}
        local lay = T.MyLayout()
        for _, n in ipairs(lay and lay.list or {}) do
            local v = n.spells and n.spells[1]
            if type(v) == "number" and v > 0 then parts[#parts + 1] = n.id .. "=" .. v end
        end
        sp = #parts > 0 and table.concat(parts, ";") or nil
        if sp and #sp > 2400 then sp = nil end
    end
    local bg = T.EncodeBg and T.EncodeBg(ns.db.talBg and ns.db.talBg[ns.safe(cls) or ""])
    if old and old.s == s and old.lvl == lvl and old.ic == ic and old.bg == bg and old.sp == sp and not T.forceShare then return end
    T.forceShare = nil
    Store.Put(COLL, { id = id, who = ns.me(), s = s, spec = mySpec() or 0, lvl = lvl, cls = ns.safe(cls) or "", ic = ic, bg = bg, sp = sp })
end
T.Share = share
local function shareSoon() ns.Debounce("talShare", 5, share) end
for _, ev in ipairs({ "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED", "PLAYER_LEVEL_UP" }) do
    ns.On(ev, shareSoon)
end
ns.Listen("LOGIN", function() ns.After(20, share) end)
ns.On("PLAYER_REGEN_ENABLED", function() if T.pendingShare then T.pendingShare = nil shareSoon() end end)

-- Rechte beim Empfang: nur der eigene Datensatz
local function installAuth()
    local A = ns.Admin
    if not (A and A.AUTH) then return end
    A.AUTH[COLL] = function(rec, actor) return rec.who ~= nil and A.SameName(rec.who, actor) end
end
installAuth()
ns.Listen("LOGIN", installAuth)

------------------------------------------------------------------------
-- Betrachten (Inspect): Talente fremder Spieler mitlesen (nur lokal)
------------------------------------------------------------------------
local inspecting   -- { unit, name, show }
local function inspDB()
    ns.db.inspTalents = ns.db.inspTalents or {}
    return ns.db.inspTalents
end
function T.Inspect(unit, show)
    if not unit or ns.inCombat() or not (NotifyInspect and CanInspect) then return false end
    if not ns.safe(CanInspect(unit)) then return false end
    local n = ns.safe(ns.UnitName(unit))
    if not n then return false end
    inspecting = { unit = unit, name = ns.fullName(n), show = show, t = GetTime() }
    pcall(NotifyInspect, unit)
    return true
end
ns.On("INSPECT_READY", function(guid)
    -- auch Blizzards eigenes Betrachten: Ziel/Maus pruefen
    local unit, name
    if inspecting and GetTime() - inspecting.t < 10 then unit, name = inspecting.unit, inspecting.name end
    if not unit then
        for _, u in ipairs({ "target", "mouseover" }) do
            if ns.safe(UnitGUID(u)) == ns.safe(guid) then unit = u name = ns.fullName(ns.safe(ns.UnitName(u)) or "") break end
        end
    end
    if not (unit and name and C_Traits and C_Traits.GenerateInspectImportString) then return end
    local ok, s = pcall(C_Traits.GenerateInspectImportString, unit)
    s = ok and ns.safe(s) or nil
    if s and s ~= "" then
        local _, cls = UnitClass(unit)
        local db = inspDB()
        db[name] = { s = s, lvl = ns.safe(UnitLevel(unit)) or 0, cls = ns.safe(cls) or "", t = ns.now() }
        local n = 0 for _ in pairs(db) do n = n + 1 end
        if n > 150 then
            local oldest, ok2
            for k, v in pairs(db) do if not ok2 or v.t < oldest then oldest, ok2 = v.t, k end end
            if ok2 then db[ok2] = nil end
        end
        if inspecting and inspecting.show and inspecting.name == name then T.Show(name) end
    end
    if inspecting and inspecting.name == name then inspecting = nil end
end)

------------------------------------------------------------------------
-- Daten zu einer Person
------------------------------------------------------------------------
function T.DataFor(name)
    if ns.isMe(name) then
        local _, cls = UnitClass("player")
        return { s = T.MyExport(), lvl = ns.safe(UnitLevel("player")) or 0, cls = ns.safe(cls), me = true, src = "self" }
    end
    local r = Store.Get(COLL, "tal-" .. name)
    if not r and ns.Radar and ns.Radar.AliasOf then
        local a = ns.Radar.AliasOf(name)
        if a then r = Store.Get(COLL, "tal-" .. a) end
    end
    if not r or r.del then
        -- Vorname vergleichen (Realm kann abweichen, z.B. ClassicBetaPvE / ClassicBetaPvE2)
        local best
        for _, x in ipairs(Store.List(COLL)) do
            if x.who and ns.SameName(x.who, name) and (not best or (x.u or 0) > (best.u or 0)) then best = x end
        end
        r = best
    end
    if r and not r.del then return { s = r.s, lvl = r.lvl, cls = r.cls, spec = r.spec, t = r.u, src = "oasis" } end
    local i = inspDB()[name]
    if i then return { s = i.s, lvl = i.lvl, cls = i.cls, t = i.t, src = "inspect" } end
end

------------------------------------------------------------------------
-- Fenster
------------------------------------------------------------------------
local win
local NODE = 34
local function build()
    local f = CreateFrame("Frame", "OasisTalentView", UIParent)
    f:SetSize(700, 640)
    f:SetPoint("CENTER", 60, 20)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    K.Fill(f, C.bg)
    K.Border(f, C.line)
    if K.ApplySkin then K.ApplySkin(f, "panel", C.bg) end
    ns.EscClose("OasisTalentView")
    -- Kopf: Verlauf in der Klassenfarbe + Klassensymbol (Farbe setzt T.Show)
    f.head = f:CreateTexture(nil, "BORDER")
    f.head:SetPoint("TOPLEFT", 1, -1) f.head:SetPoint("TOPRIGHT", -1, -1) f.head:SetHeight(58)
    f.headLine = f:CreateTexture(nil, "ARTWORK")
    f.headLine:SetPoint("TOPLEFT", f.head, "BOTTOMLEFT") f.headLine:SetPoint("TOPRIGHT", f.head, "BOTTOMRIGHT") f.headLine:SetHeight(1)
    f.clsIcon = f:CreateTexture(nil, "ARTWORK")
    f.clsIcon:SetSize(32, 32)
    f.clsIcon:SetPoint("TOPLEFT", 16, -13)
    f.title = K.Title(f, 16, C.text)
    f.title:SetPoint("TOPLEFT", f.clsIcon, "TOPRIGHT", 10, -1)
    f.sub = K.Text(f, 11, C.muted)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
    f.sub:SetPoint("RIGHT", -50, 0)
    function f:SetClass(cls)
        local cr, cg, cb = ns.classColor(cls)
        if not K.Gradient(self.head, "HORIZONTAL", { cr, cg, cb, 0.26 }, { cr, cg, cb, 0.02 }) then self.head:SetColorTexture(cr, cg, cb, 0.1) end
        self.headLine:SetColorTexture(cr, cg, cb, 0.4)
        local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
        if tc then
            self.clsIcon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            self.clsIcon:SetTexCoord(unpack(tc))
            self.clsIcon:Show()
        else
            self.clsIcon:Hide()
        end
    end
    local close = K.CloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    f.canvas = CreateFrame("Frame", nil, f)
    f.canvas:SetPoint("TOPLEFT", 20, -64)
    f.canvas:SetPoint("BOTTOMRIGHT", -20, 52)
    f.empty = K.Text(f.canvas, 13, C.dim, "CENTER")
    f.empty:SetPoint("CENTER")
    f.empty:SetWidth(520)
    f.empty:SetWordWrap(true)
    f.nodes, f.lines = {}, {}
    f.copy = K.Button(f, L["Export-Text kopieren"], 150, 24, "ghost", function()
        if f.export and ns.Bugs and ns.Bugs.ShowCopy then ns.Bugs.ShowCopy(f.export) end
    end)
    f.copy:SetPoint("BOTTOMLEFT", 18, 16)
    -- Build uebernehmen (zweimal klicken = bestaetigen)
    f.apply = K.Button(f, L["Bei mir uebernehmen"], 170, 24, "primary", function(self)
        if not f.data then return end
        if not self.armed then
            self.armed = GetTime()
            self:SetLabel(L["Wirklich? Nochmal klicken"])
            C_Timer.After(4, function() if self.armed and GetTime() - self.armed >= 3.9 then self.armed = nil self:SetLabel(L["Bei mir uebernehmen"]) end end)
            return
        end
        self.armed = nil
        self:SetLabel(L["Bei mir uebernehmen"])
        T.Apply(f.data)
    end)
    f.apply:SetPoint("LEFT", f.copy, "RIGHT", 8, 0)
    f.apply:SetScript("OnEnter", function(self)
        local ok, why = T.CanApply(f.data)
        K.ShowTip(self, { L["Bei mir uebernehmen"], ok and L["Setzt deinen Baum zurueck und verteilt die Punkte wie hier - so weit deine Punkte reichen."] or (why or "") })
    end)
    f.apply:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.foot = K.Text(f, 10, C.dim, "RIGHT")
    f.foot:SetPoint("BOTTOMRIGHT", -18, 22)
    win = f
    return f
end
-- Tooltip eines Knotens wie in Blizzards Talentbaum: Name als Ueberschrift, Rang, Beschreibung, naechster Rang.
-- 0.5.585: selbst aus Blizzards Tooltip-Daten gebaut - der fertige Tooltip zeigte in Forever bei passiven Talenten
-- keinen Namen ("Passiv" stand oben).
local function tipData(kind, a, b)
    local fn = C_TooltipInfo and C_TooltipInfo[kind]
    if not fn or a == nil then return nil end
    local ok, d = pcall(fn, a, b)
    if ok and type(d) == "table" and type(d.lines) == "table" and #d.lines > 0 then return d.lines end
end
local function isRankLine(t) return t:gsub("%s", ""):find("%d+/%d+$") ~= nil and #t < 24 end
local function rgb(c, dr, dg, db) if c and c.GetRGB then return c:GetRGB() end return dr, dg, db end
local function addLines(lines, name, seen)
    for i, ln in ipairs(lines) do
        local t = type(ln) == "table" and ln.leftText
        if issecretvalue and issecretvalue(t) then t = nil end
        if type(t) == "string" and t ~= "" and t ~= name and not seen[t] and not isRankLine(t) and not t:find("^Press F%d") then
            seen[t] = true
            local lr, lg, lb = rgb(ln.leftColor, 1, 0.82, 0)
            local rt = ln.rightText
            if type(rt) == "string" and rt ~= "" then
                local rr, rg, rb = rgb(ln.rightColor, 1, 1, 1)
                GameTooltip:AddDoubleLine(t, rt, lr, lg, lb, rr, rg, rb)
            else
                GameTooltip:AddLine(t, lr, lg, lb, true)
            end
        end
    end
end
local showNodeTip
-- 0.5.890: der Aufbau laeuft geschuetzt. Scheitert er (oder bleibt der Tooltip leer), kommt wenigstens Name + Rang -
-- vorher blieb der Tooltip bei fremden Talenten dann ganz weg. Der Fehler landet einmal im Oasis-Fehlerprotokoll.
-- Zauber eines Knotens nachtraeglich holen: beim ersten Aufbau des Ansichts-Baums sind die Daten oft noch nicht geladen
-- (dann steht 0 im Zwischenspeicher). Beim Ueberfahren noch einmal fragen und merken.
local function lateSpell(self)
    if self.spell and self.spell ~= 0 then return end
    if not (self.entry and C_Traits) then return end
    local cfgs = { self.cfg, Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID,
        C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() }
    for i = 1, 3 do
        local cfg = cfgs[i]
        if cfg then
            local okE, ei = pcall(C_Traits.GetEntryInfo, cfg, self.entry)
            local def = okE and type(ei) == "table" and ei.definitionID
            local okD, di = def and pcall(C_Traits.GetDefinitionInfo, def)
            if okD and type(di) == "table" then
                local ov = di.overriddenSpellID
                local sp = (ov and ov ~= 0) and ov or di.spellID
                if type(sp) == "number" and sp > 0 then
                    self.spell = sp
                    if self.node and self.node.spells then self.node.spells[1] = self.node.spells[1] ~= 0 and self.node.spells[1] or sp end
                    return
                end
                if type(di.overrideName) == "string" and di.overrideName ~= "" then self.defName = di.overrideName end
            end
        end
    end
end
function T.ShowNodeTip(self)
    pcall(lateSpell, self)
    local ok, e = pcall(showNodeTip, self)
    local shown = ok and GameTooltip:IsShown() and (GameTooltip:NumLines() or 0) > 0
    if shown then return end
    if not ok and not T.tipErr then T.tipErr = true if ns.err then pcall(ns.err, "Talent-Tooltip", e) end end
    local name
    if self.spell and self.spell ~= 0 then
        local okN, n = pcall(function() return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(self.spell)) or (GetSpellInfo and GetSpellInfo(self.spell)) end)
        if okN and type(n) == "string" and not (issecretvalue and issecretvalue(n)) and n ~= "" then name = n end
    end
    pcall(function()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(name or self.defName or L["Talent"], 1, 1, 1)
        GameTooltip:AddLine((L["Rang %d / %d"]):format(self.r or 0, self.max or 1), 1, 0.82, 0.3)
        -- nur fuer Entwickler: woran es liegt (Zauber, Eintrag, Knoten, Fehler)
        if ns.IsDev and ns.IsDev() then
            GameTooltip:AddLine(("spell %s  entry %s  node %s  cfg %s"):format(tostring(self.spell), tostring(self.entry), tostring(self.node and self.node.id), tostring(self.cfg)), 0.5, 0.5, 0.5)
            if not ok then GameTooltip:AddLine(tostring(e):sub(1, 200), 1, 0.4, 0.4, true) end
        end
        GameTooltip:Show()
    end)
end
showNodeTip = function(self)
    local r, max = self.r or 0, self.max or 1
    local name
    if self.spell and self.spell ~= 0 and C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, self.spell)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    -- 0.5.676: aeltere Zauber-Abfrage als Ersatz (bei fremden Talenten lieferte Forever sonst nichts -> kein Tooltip)
    if not name and self.spell and self.spell ~= 0 and GetSpellInfo then
        local ok, n = pcall(GetSpellInfo, self.spell)
        if ok and type(n) == "string" and n ~= "" then name = n end
    end
    local lines = (self.entry and tipData("GetTraitEntry", self.entry, math.max(r, 1))) or tipData("GetSpellByID", self.spell)
    if not name and lines and lines[1] and type(lines[1].leftText) == "string" then name = lines[1].leftText end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- keine Tooltip-Daten: Blizzards fertigen Zauber-Tooltip nehmen, Rang darunter
    if not lines and self.spell and self.spell ~= 0 and GameTooltip.SetSpellByID then
        local ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.spell)
        if ok and GameTooltip:NumLines() > 0 then
            GameTooltip:AddLine((L["Rang %d / %d"]):format(r, max), 1, 0.82, 0.3)
            GameTooltip:Show()
            return
        end
    end
    GameTooltip:SetText(name or "?", 1, 1, 1)
    GameTooltip:AddLine((L["Rang %d / %d"]):format(r, max), 1, 0.82, 0.3)
    local seen = {}
    if lines then addLines(lines, name, seen) end
    -- naechster Rang (nur bei mehrstufigen, nicht vollen Talenten)
    if r > 0 and r < max and self.entry then
        local nxt = tipData("GetTraitEntry", self.entry, r + 1)
        if nxt then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(TALENT_BUTTON_TOOLTIP_NEXT_RANK or L["Naechster Rang:"], 0.1, 1, 0.1)
            addLines(nxt, name, seen)
        end
    end
    GameTooltip:Show()
end

local function nodeBtn(f, i)
    local b = f.nodes[i]
    if b then return b end
    b = CreateFrame("Button", nil, f.canvas)
    b:SetSize(NODE, NODE)
    b:SetFrameLevel(f.canvas:GetFrameLevel() + 5)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.6)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.border = K.Border(b, C.line)
    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetPoint("CENTER")
    b.glow:SetSize(NODE * 1.9, NODE * 1.9)
    b.glow:SetVertexColor(C.amber[1], C.amber[2], C.amber[3], 0.55)
    b.glow:Hide()
    b.rankBg = b:CreateTexture(nil, "OVERLAY", nil, 2)
    b.rankBg:SetColorTexture(0, 0, 0, 0.75)
    b.rankBg:SetPoint("BOTTOMRIGHT", 4, -4)
    b.rankBg:SetSize(24, 12)
    b.rank = K.Text(b, 9, C.text, "CENTER")
    b.rank:SetDrawLayer("OVERLAY", 3)
    b.rank:SetPoint("CENTER", b.rankBg, "CENTER", 0, 0)
    b.rank:SetShadowColor(0, 0, 0, 1)
    hooksecurefunc(b.rank, "SetText", function(self, t) b.rankBg:SetShown(t ~= nil and t ~= "") end)
    -- 0.5.584: Tooltip wie in Blizzards Talentbaum (Talent-Eintrag mit Rang-Beschreibung + naechster Rang),
    -- sonst Zauber-Tooltip
    b:EnableMouse(true)
    if b.SetMouseMotionEnabled then b:SetMouseMotionEnabled(true) end
    b:SetScript("OnEnter", function(self) T.ShowNodeTip(self) end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.nodes[i] = b
    return b
end
local function line(f, i)
    local l = f.lines[i]
    if l then return l end
    -- eigene Ebene ueber den Hintergruenden, unter den Knoten
    if not f.lineLayer then
        f.lineLayer = CreateFrame("Frame", nil, f.canvas)
        f.lineLayer:SetAllPoints()
        f.lineLayer:SetFrameLevel(f.canvas:GetFrameLevel() + 3)
    end
    if not f.lineLayer.CreateLine then return nil end
    l = f.lineLayer:CreateLine(nil, "ARTWORK")
    if not (l and l.SetThickness) then return nil end
    l:SetThickness(2)
    f.lines[i] = l
    return l
end
-- Hintergruende: Blizzards klassische Talent-Bilder je Klasse und Baum (liegen im Client, keine fremden Dateien)
local TREE_BG = {
    WARRIOR = { "WarriorArms", "WarriorFury", "WarriorProtection" },
    PALADIN = { "PaladinHoly", "PaladinProtection", "PaladinCombat" },
    HUNTER = { "HunterBeastMastery", "HunterMarksmanship", "HunterSurvival" },
    ROGUE = { "RogueAssassination", "RogueCombat", "RogueSubtlety" },
    PRIEST = { "PriestDiscipline", "PriestHoly", "PriestShadow" },
    SHAMAN = { "ShamanElementalCombat", "ShamanEnhancement", "ShamanRestoration" },
    MAGE = { "MageArcane", "MageFire", "MageFrost" },
    WARLOCK = { "WarlockCurses", "WarlockSummoning", "WarlockDestruction" },
    DRUID = { "DruidBalance", "DruidFeralCombat", "DruidRestoration" },
}
local function columnBg(f, i)
    f.bgs = f.bgs or {}
    local c = f.bgs[i]
    if c then return c end
    c = CreateFrame("Frame", nil, f.canvas)
    c:SetFrameLevel(f.canvas:GetFrameLevel())
    c.parts = {}
    for j, k in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight" }) do
        local t = c:CreateTexture(nil, "BACKGROUND", nil, 0)
        t.key = k
        c.parts[j] = t
    end
    c.art = c:CreateTexture(nil, "BACKGROUND", nil, -1)
    c.art:SetAllPoints()
    c.art:Hide()
    c.grad = c:CreateTexture(nil, "BACKGROUND", nil, 1)
    c.grad:SetAllPoints()
    c.shade = c:CreateTexture(nil, "BACKGROUND", nil, 2)
    c.shade:SetAllPoints()
    c.shade:SetColorTexture(0, 0, 0, 0.38)
    c.edge = c:CreateTexture(nil, "BORDER")
    c.edge:SetPoint("TOPLEFT") c.edge:SetPoint("TOPRIGHT") c.edge:SetHeight(2)
    if K.Border then K.Border(c, { 1, 1, 1, 0.08 }) end
    f.bgs[i] = c
    return c
end
local function drawBackgrounds(f, lay, minX, s, ox, cls)
    for _, c in ipairs(f.bgs or {}) do c:Hide() end
    -- Baeume = Spalten: die zwei groessten Luecken in den x-Positionen trennen sie
    local xs, seen = {}, {}
    for _, n in ipairs(lay.list) do if not seen[n.x] then seen[n.x] = true xs[#xs + 1] = n.x end end
    table.sort(xs)
    local gaps = {}
    for i = 2, #xs do gaps[#gaps + 1] = { i = i, d = xs[i] - xs[i - 1] } end
    table.sort(gaps, function(a, b) return a.d > b.d end)
    local cuts = {}
    for i = 1, math.min(2, #gaps) do if gaps[i].d > 0 then cuts[#cuts + 1] = gaps[i].i end end
    table.sort(cuts)
    local cols, start = {}, 1
    for _, ci in ipairs(cuts) do cols[#cols + 1] = { xs[start], xs[ci - 1] } start = ci end
    cols[#cols + 1] = { xs[start], xs[#xs] }
    local H = f.canvas:GetHeight()
    if not H or H < 50 then H = 524 end
    local names = TREE_BG[cls or ""] or {}
    local cr, cg, cb = ns.classColor(cls)
    for i, col in ipairs(cols) do
        local c = columnBg(f, i)
        local l = ox + (col[1] - minX) * s - 14
        local r = ox + (col[2] - minX) * s + NODE + 14
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", f.canvas, "TOPLEFT", l, 8)
        c:SetSize(math.max(40, r - l), H - 0)
        local w, h = c:GetWidth(), c:GetHeight()
        local ok = false   -- alte klassische Talentbilder wirken gestaucht -> nicht mehr benutzt
        local art = T.BgFor and T.BgFor(cls)
        local a = art and art[i]
        local hasArt = false
        if a then
            if a.a and c.art.SetAtlas then hasArt = pcall(c.art.SetAtlas, c.art, a.a) and true or false
            elseif a.f then
                hasArt = pcall(c.art.SetTexture, c.art, a.f) and true or false
                if hasArt and a.tc then pcall(c.art.SetTexCoord, c.art, a.tc[1], a.tc[2], a.tc[3], a.tc[4]) end
            end
        end
        c.art:SetShown(hasArt)
        if ok and names[i] then
            for _, t in ipairs(c.parts) do
                local okT, res = pcall(t.SetTexture, t, "Interface\\TalentFrame\\" .. names[i] .. "-" .. t.key)
                if not okT or res == false then ok = false end
                t:ClearAllPoints()
                local left = t.key:find("Left") ~= nil
                local top = t.key:find("Top") ~= nil
                t:SetPoint(top and (left and "TOPLEFT" or "TOPRIGHT") or (left and "BOTTOMLEFT" or "BOTTOMRIGHT"))
                t:SetSize(w * (left and 0.8 or 0.2), h * (top and 0.667 or 0.333))
                t:SetTexCoord(0, 1, 0, left and (top and 1 or 0.75) or (top and 1 or 0.75))
                t:Show()
            end
        end
        for _, t in ipairs(c.parts) do t:SetShown(ok) end
        -- ohne Bild: Verlauf in der Klassenfarbe; mit Bild nur eine leichte Toenung
        if hasArt then ok = true end
        if not K.Gradient(c.grad, "VERTICAL", { cr * 0.25, cg * 0.25, cb * 0.25, ok and 0.25 or 0.9 }, { cr * 0.5, cg * 0.5, cb * 0.5, ok and 0.05 or 0.45 }) then
            c.grad:SetColorTexture(cr * 0.3, cg * 0.3, cb * 0.3, ok and 0.15 or 0.6)
        end
        c.shade:SetAlpha(ok and 1 or 0.3)
        c.edge:SetColorTexture(cr, cg, cb, 0.8)
        c:Show()
    end
end

-- Talent-Symbol: Definition -> Zauber (Info/Textur/Item) ; 134400 = Fragezeichen = nichts gefunden
local QMARK = 134400
local function good(t) return t and t ~= QMARK and t ~= 0 and t ~= "" end
function T.IconFor(n, ci, spell)
    local t = n.icons and (n.icons[ci] or n.icons[1])
    if good(t) then return t end
    local db = ns.db and ns.db.talIcons
    if db and n.id and good(db["n" .. n.id]) then return db["n" .. n.id] end
    if n.id and T.SharedIcon then local shn = T.SharedIcon("n" .. n.id) if good(shn) then return shn end end
    if spell and spell ~= 0 then
        if db and good(db[spell]) then return db[spell] end
        local sh = T.SharedIcon and T.SharedIcon(spell)
        if good(sh) then return sh end
    end
    if spell and spell ~= 0 then
        if C_Spell then
            local okI, si = pcall(C_Spell.GetSpellInfo, spell)
            if okI and si then
                if good(si.iconID) then return si.iconID end
                if good(si.originalIconID) then return si.originalIconID end
            end
            if C_Spell.GetSpellTexture then
                local okT, a, b = pcall(C_Spell.GetSpellTexture, spell)
                if okT and good(a) then return a end
                if okT and good(b) then return b end
            end
        end
        if GetSpellTexture then local okG, g = pcall(GetSpellTexture, spell); if okG and good(g) then return g end end
        if C_Spell and C_Spell.RequestLoadSpellData and not (T.asked and T.asked[spell]) then
            T.asked = T.asked or {}; T.asked[spell] = true
            pcall(C_Spell.RequestLoadSpellData, spell); T.waitIcons = true
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Symbole aus Blizzards Talentfenster lernen (0.5.506): die Symbol-Schnittstellen liefern in Forever
-- fuer viele Talente nur das Fragezeichen - Blizzards eigenes Fenster zeigt sie aber richtig.
-- Beim Oeffnen (Taste N) liest Oasis die Symbole der Knoepfe aus (nur lesen, nichts veraendern),
-- merkt sie je Zauber (account-weit) und teilt sie mit den eigenen Talenten (rec.ic).
-- Zusaetzlich: Diagnose der Knopf-Felder in ns.db.talHarvest (fuer Fehlersuche nach /reload).
------------------------------------------------------------------------
local function iconDB() ns.db.talIcons = ns.db.talIcons or {} return ns.db.talIcons end
T.IconDB = iconDB
local function texOf(fr)
    for _, k in ipairs({ "Icon", "icon", "IconTexture", "iconTexture", "Texture" }) do
        local t = fr[k]
        if type(t) == "table" and t.GetTexture then
            local ok, v = pcall(t.GetTexture, t)
            if ok and good(v) then return v end
        end
    end
    local okN, n = pcall(function() return fr.GetName and fr:GetName() end)
    if okN and type(n) == "string" then
        local t = _G[n .. "IconTexture"] or _G[n .. "Icon"]
        if type(t) == "table" and t.GetTexture then
            local ok, v = pcall(t.GetTexture, t)
            if ok and good(v) then return v end
        end
    end
end
-- Zahlen am Knopf, die einen Zauber/Knoten benennen koennten
local ID_FIELDS = { "spellID", "nodeID", "talentID", "definitionID", "entryID", "id" }
local ID_METHODS = { "GetSpellID", "GetNodeID", "GetTalentID", "GetDefinitionID", "GetEntryID" }
local function idsOf(fr)
    local out = {}
    for _, k in ipairs(ID_FIELDS) do local v = fr[k] if type(v) == "number" then out[k] = v end end
    for _, m in ipairs(ID_METHODS) do
        local fn = fr[m]
        if type(fn) == "function" then local ok, v = pcall(fn, fr) if ok and type(v) == "number" then out[m] = v end end
    end
    for _, k in ipairs({ "nodeInfo", "entryInfo", "definitionInfo", "talentInfo" }) do
        local t = fr[k]
        if type(t) == "table" then
            for _, f2 in ipairs({ "ID", "spellID", "definitionID", "nodeID" }) do
                if type(t[f2]) == "number" then out[k .. "." .. f2] = t[f2] end
            end
        end
    end
    return out
end
function T.Harvest(frame)
    if not frame or ns.inCombat() then return 0 end
    local lay = T.MyLayout()
    local spellOfNode, isSpell = {}, {}
    for _, n in ipairs(lay and lay.list or {}) do
        spellOfNode[n.id] = n.spells[1]
        for _, sp in ipairs(n.spells) do if sp and sp ~= 0 then isSpell[sp] = true end end
    end
    local db, learned, seen, sample = iconDB(), 0, 0, {}
    local function visit(fr, depth)
        if depth > 9 or seen > 3000 then return end
        seen = seen + 1
        local tex = texOf(fr)
        if tex then
            local ids = idsOf(fr)
            local spell
            for k, v in pairs(ids) do
                if isSpell[v] or (k:lower():find("spell") and v > 0) then spell = v break end
                if spellOfNode[v] then spell = spellOfNode[v] break end
                if k:find("definition") and C_Traits and C_Traits.GetDefinitionInfo then
                    local okD, di = pcall(C_Traits.GetDefinitionInfo, v)
                    if okD and di and di.spellID then spell = di.spellID break end
                end
            end
            if spell and spell ~= 0 then
                if db[spell] ~= tex then db[spell] = tex learned = learned + 1 end
            end
            local node = ids.nodeID or ids.GetNodeID or ids["nodeInfo.ID"]
            if node and type(tex) == "number" and db["n" .. node] ~= tex then db["n" .. node] = tex learned = learned + 1 end
            if #sample < 10 then
                local parts = {}
                for k, v in pairs(ids) do parts[#parts + 1] = k .. "=" .. v end
                local okN, nm = pcall(function() return fr.GetName and fr:GetName() end)
                local okI, gid = pcall(function() return fr.GetID and fr:GetID() end)
                local keys = {}
                for k, v in pairs(fr) do if type(k) == "string" and #keys < 25 then keys[#keys + 1] = k .. ":" .. type(v):sub(1, 1) end end
                sample[#sample + 1] = ("%s id=%s tex=%s ids={%s} spell=%s keys=%s"):format(tostring(okN and nm), tostring(okI and gid), tostring(tex),
                    table.concat(parts, ","), tostring(spell), table.concat(keys, ","))
            end
        end
        local ok, kids = pcall(function() return { fr:GetChildren() } end)
        if ok then for _, c in ipairs(kids) do visit(c, depth + 1) end end
    end
    pcall(visit, frame, 0)
    -- Baum-Hintergruende: grosse Texturen (hoch, mindestens 150 x 250), von links nach rechts
    local bgs, seenBg = {}, {}
    local function scanRegions(fr, depth)
        if depth > 6 then return end
        local okR, regs = pcall(function() return { fr:GetRegions() } end)
        for _, rg in ipairs(okR and regs or {}) do
            if rg.GetObjectType and rg:GetObjectType() == "Texture" and rg:IsShown() then
                local w, h = rg:GetWidth() or 0, rg:GetHeight() or 0
                if w >= 150 and h >= 250 and h > w then
                    local atlas = rg.GetAtlas and rg:GetAtlas()
                    local file = rg:GetTexture()
                    local key = tostring(atlas or file)
                    if (atlas or file) and not seenBg[key] then
                        seenBg[key] = true
                        local tc = { rg:GetTexCoord() }
                        bgs[#bgs + 1] = { x = rg:GetLeft() or 0, a = atlas, f = (not atlas) and file or nil,
                            tc = (not atlas) and { tc[1], tc[7] or tc[3], tc[2], tc[8] or tc[4] } or nil, w = w, h = h }
                    end
                end
            end
        end
        local okK, kids = pcall(function() return { fr:GetChildren() } end)
        for _, c in ipairs(okK and kids or {}) do scanRegions(c, depth + 1) end
    end
    pcall(scanRegions, frame, 0)
    table.sort(bgs, function(x, y) return x.x < y.x end)
    if #bgs >= 2 then
        local _, myCls = UnitClass("player")
        ns.db.talBg = ns.db.talBg or {}
        local keep = {}
        for i = 1, math.min(3, #bgs) do keep[i] = { a = bgs[i].a, f = bgs[i].f, tc = bgs[i].tc } end
        if myCls then ns.db.talBg[myCls] = keep end
        learned = learned + 1
    end
    local bgDiag = {}
    for i = 1, math.min(6, #bgs) do local b = bgs[i] bgDiag[i] = ("x=%d %dx%d a=%s f=%s"):format(b.x, b.w, b.h, tostring(b.a), tostring(b.f)) end
    ns.db.talHarvest = { ts = ns.now(), v = ns.version, frame = tostring(frame.GetName and frame:GetName()), seen = seen, learned = learned, sample = sample, bgs = bgDiag }
    if learned > 0 then
        ns.Debounce("talShare", 2, function() T.forceShare = true pcall(T.Share) end)
        if win and win:IsShown() and win.who then T.Show(win.who) end
    end
    return learned
end
-- Baum-Hintergruende je Klasse: eigene (Harvest) oder von einem Mitglied derselben Klasse geteilt (rec.bg)
local function decodeBg(str)
    local out = {}
    for part in tostring(str or ""):gmatch("[^;]+") do
        local kind, rest = part:match("^(%a):(.+)$")
        if kind == "a" then out[#out + 1] = { a = rest }
        elseif kind == "f" then
            local f, a1, a2, a3, a4 = rest:match("^(%d+),([%d%.]+),([%d%.]+),([%d%.]+),([%d%.]+)$")
            if f then out[#out + 1] = { f = tonumber(f), tc = { tonumber(a1), tonumber(a2), tonumber(a3), tonumber(a4) } }
            elseif rest:match("^%d+$") then out[#out + 1] = { f = tonumber(rest) } end
        end
    end
    return #out > 0 and out or nil
end
function T.EncodeBg(list)
    local parts = {}
    for _, b in ipairs(list or {}) do
        if b.a then parts[#parts + 1] = "a:" .. b.a
        elseif type(b.f) == "number" then
            local tc = b.tc or { 0, 1, 0, 1 }
            parts[#parts + 1] = ("f:%d,%.3f,%.3f,%.3f,%.3f"):format(b.f, tc[1] or 0, tc[2] or 1, tc[3] or 0, tc[4] or 1)
        end
    end
    return #parts > 0 and table.concat(parts, ";") or nil
end
function T.BgFor(cls)
    do return nil end   -- 0.5.573: gelernte Bilder waren Effekt-Atlanten, nicht die Klassenbilder
    if not cls or cls == "" then return nil end
    local own = ns.db and ns.db.talBg and ns.db.talBg[cls]
    if own and #own > 0 then return own end
    for _, r in ipairs(Store.List(COLL)) do
        if r.cls == cls and type(r.bg) == "string" then
            local d = decodeBg(r.bg)
            if d then return d end
        end
    end
end
-- geteilte Symbole aller Oasis-Nutzer (aus rec.ic: "zauber=symbol;...")
local sharedIcons, sharedSig = {}, nil
function T.SharedIcon(spell)
    local list = Store.List(COLL)
    local sig = #list
    for _, r in ipairs(list) do sig = sig + (r.u or 0) end
    if sig ~= sharedSig then
        sharedSig = sig
        sharedIcons = {}
        for _, r in ipairs(list) do
            if type(r.ic) == "string" then
                for key, ic in r.ic:gmatch("(n?%d+)=(%d+)") do sharedIcons[tonumber(key) or key] = tonumber(ic) end
            end
        end
    end
    return sharedIcons[spell]
end

-- von Mitgliedern geteilter Zauber eines Knotens (rec.sp)
local sharedSpells, sharedSpSig
function T.SharedSpell(nodeID)
    local list = Store.List(COLL)
    local sig = #list
    for _, r in ipairs(list) do sig = sig + (r.u or 0) end
    if sig ~= sharedSpSig then
        sharedSpSig = sig
        sharedSpells = {}
        for _, r in ipairs(list) do
            if type(r.sp) == "string" then
                for key, v in r.sp:gmatch("(%d+)=(%d+)") do sharedSpells[tonumber(key)] = tonumber(v) end
            end
        end
    end
    return sharedSpells[nodeID]
end

-- 0.5.542: Talentfenster neu - jeder Baum in einer eigenen, gleich breiten Spalte (Knoten so gross wie moeglich,
-- mittig), Kopf je Baum (Spezialisierung + Punkte), Hintergrund: gelerntes Blizzard-Baumbild, sonst Blizzards
-- klassisches Talentbild (zugeschnitten statt gestaucht), sonst Verlauf in Klassenfarbe; Wasserzeichen-Symbol.
local CLASS_ID = {}
do
    local GCI = (C_CreatureInfo and C_CreatureInfo.GetClassInfo)
    for i = 1, 15 do
        local ok, info = pcall(function() return GCI and GCI(i) end)
        if ok and type(info) == "table" and info.classFile then CLASS_ID[info.classFile] = info.classID or i
        else
            local ok2, _, file, id = pcall(GetClassInfo, i)
            if ok2 and file then CLASS_ID[file] = id or i end
        end
    end
end
local TREE_NAME = {
    WARRIOR = { "Waffen", "Furor", "Schutz" },
    PALADIN = { "Heilig", "Schutz", "Vergeltung" },
    HUNTER = { "Tierherrschaft", "Treffsicherheit", "Ueberleben" },
    ROGUE = { "Meucheln", "Kampf", "Taeuschung" },
    PRIEST = { "Disziplin", "Heilig", "Schatten" },
    SHAMAN = { "Elementar", "Verstaerkung", "Wiederherstellung" },
    MAGE = { "Arkan", "Feuer", "Frost" },
    WARLOCK = { "Gebrechen", "Daemonologie", "Zerstoerung" },
    DRUID = { "Gleichgewicht", "Wilder Kampf", "Wiederherstellung" },
}
local function specInfo(cls, i)
    local cid = CLASS_ID[cls or ""]
    local fn = GetSpecializationInfoForClassID or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfoForClassID)
    local name, icon
    if cid and fn then
        local ok, _, n, _, ic = pcall(fn, cid, i)
        if ok and n then name, icon = n, ic end
    end
    -- Forever: Baum 1 heisst wie die Klasse, Baum 2/3 fehlen -> eigene Namen
    local own = TREE_NAME[cls or ""] and TREE_NAME[cls][i]
    local clsName = cls and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls]
    if own and (not name or name == clsName or name == (LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[cls])) then
        return L[own], icon
    end
    return name or (L["Baum %d"]):format(i), icon
end
local function colFrame(f, i)
    f.cols = f.cols or {}
    local c = f.cols[i]
    if c then return c end
    c = CreateFrame("Frame", nil, f.canvas)
    c:SetFrameLevel(f.canvas:GetFrameLevel() + 1)
    if c.SetClipsChildren then c:SetClipsChildren(true) end
    c.base = c:CreateTexture(nil, "BACKGROUND", nil, -8)
    c.base:SetAllPoints()
    c.base:SetColorTexture(0.03, 0.03, 0.04, 1)
    -- gelerntes Blizzard-Bild (ganze Flaeche)
    c.art = c:CreateTexture(nil, "BACKGROUND", nil, -7)
    c.art:SetAllPoints()
    c.art:Hide()
    -- klassisches Talentbild aus 4 Teilen (256+64 x 256+128), auf Spaltenhoehe skaliert, mittig beschnitten
    c.clsArt = CreateFrame("Frame", nil, c)
    c.clsArt:SetFrameLevel(c:GetFrameLevel())
    c.parts = {}
    for j, k in ipairs({ "TopLeft", "TopRight", "BottomLeft", "BottomRight" }) do
        local t = c.clsArt:CreateTexture(nil, "BACKGROUND", nil, -6)
        t.key = k
        c.parts[j] = t
    end
    c.grad = c:CreateTexture(nil, "BACKGROUND", nil, -5)
    c.grad:SetAllPoints()
    c.shade = c:CreateTexture(nil, "BACKGROUND", nil, -4)
    c.shade:SetAllPoints()
    c.mark = c:CreateTexture(nil, "BORDER")
    c.mark:SetSize(150, 150)
    c.mark:SetPoint("CENTER", c, "CENTER", 0, -30)
    if c.mark.SetMask then pcall(c.mark.SetMask, c.mark, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask") end
    -- Kopf
    c.headBg = c:CreateTexture(nil, "BORDER", nil, 1)
    c.headBg:SetPoint("TOPLEFT") c.headBg:SetPoint("TOPRIGHT") c.headBg:SetHeight(40)
    c.headLine = c:CreateTexture(nil, "ARTWORK")
    c.headLine:SetPoint("TOPLEFT", c.headBg, "BOTTOMLEFT") c.headLine:SetPoint("TOPRIGHT", c.headBg, "BOTTOMRIGHT") c.headLine:SetHeight(1)
    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetSize(24, 24)
    c.icon:SetPoint("LEFT", c.headBg, "LEFT", 10, 0)
    if c.icon.SetMask then pcall(c.icon.SetMask, c.icon, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask") end
    c.name = K.Title(c, 13, C.text)
    c.name:SetPoint("LEFT", c.icon, "RIGHT", 8, 0)
    c.name:SetPoint("RIGHT", c.headBg, "RIGHT", -40, 0)
    c.name:SetJustifyH("LEFT")
    c.name:SetWordWrap(false)
    c.pts = K.Title(c, 16, C.muted, "RIGHT")
    c.pts:SetPoint("RIGHT", c.headBg, "RIGHT", -12, 0)
    if K.Border then K.Border(c, { 1, 1, 1, 0.08 }) end
    f.cols[i] = c
    return c
end
local function paintCol(f, c, i, cls, pts, w, h)
    local cr, cg, cb = ns.classColor(cls)
    local name, icon = specInfo(cls, i)
    c.name:SetText(name)
    c.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    c.icon:SetShown(icon ~= nil)
    c.pts:SetText(tostring(pts))
    if pts > 0 then c.pts:SetTextColor(C.amber[1], C.amber[2], C.amber[3]) else c.pts:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
    c.mark:SetTexture(icon)
    c.mark:SetShown(icon ~= nil)
    c.mark:SetAlpha(0.06)
    -- 1) gelerntes Blizzard-Bild: AUS (0.5.573) - gelernt wurden nur Effekt-Atlanten (Sonnenstrahl, Glanz, Sterne),
    --    nie die Klassenbilder. Jetzt immer Blizzards klassische Talentbaum-Hintergruende je Klasse und Baum.
    local a = nil
    local hasArt = false
    if a then
        if a.a and c.art.SetAtlas then hasArt = pcall(c.art.SetAtlas, c.art, a.a) and true or false
        elseif a.f then
            hasArt = pcall(c.art.SetTexture, c.art, a.f) and true or false
            if hasArt and a.tc then pcall(c.art.SetTexCoord, c.art, a.tc[1], a.tc[2], a.tc[3], a.tc[4]) end
        end
    end
    c.art:SetShown(hasArt)
    -- 2) klassisches Talentbild, Seitenverhaeltnis 320:384 behalten, auf Spaltenhoehe, mittig
    local names = TREE_BG[cls or ""]
    local classic = false
    if not hasArt and names and names[i] then
        classic = true
        local ih = h
        local iw = ih * 320 / 384
        c.clsArt:ClearAllPoints()
        c.clsArt:SetPoint("CENTER", c, "CENTER", 0, 0)
        c.clsArt:SetSize(iw, ih)
        for _, t in ipairs(c.parts) do
            local okT = pcall(t.SetTexture, t, "Interface\\TalentFrame\\" .. names[i] .. "-" .. t.key)
            if not okT then classic = false end
            local left = t.key:find("Left") ~= nil
            local top = t.key:find("Top") ~= nil
            t:ClearAllPoints()
            t:SetPoint(top and (left and "TOPLEFT" or "TOPRIGHT") or (left and "BOTTOMLEFT" or "BOTTOMRIGHT"), c.clsArt)
            t:SetSize(iw * (left and 256 / 320 or 64 / 320), ih * (top and 256 / 384 or 128 / 384))
            -- rechte Teile sind 64 breit in einer 64er-Datei, untere 128 hoch in 128er-Datei
            t:SetTexCoord(0, 1, 0, 1)
        end
    end
    c.clsArt:SetShown(classic)
    -- Toenung + Abdunklung, damit Knoten lesbar bleiben
    local pic = hasArt or classic
    if not K.Gradient(c.grad, "VERTICAL", { cr * 0.18, cg * 0.18, cb * 0.18, pic and 0.35 or 0.95 }, { cr * 0.42, cg * 0.42, cb * 0.42, pic and 0.1 or 0.55 }) then
        c.grad:SetColorTexture(cr * 0.25, cg * 0.25, cb * 0.25, pic and 0.2 or 0.7)
    end
    c.shade:SetColorTexture(0, 0, 0, pic and 0.38 or 0.1)
    if not K.Gradient(c.headBg, "HORIZONTAL", { cr * 0.5, cg * 0.5, cb * 0.5, 0.55 }, { 0, 0, 0, 0.35 }) then c.headBg:SetColorTexture(0, 0, 0, 0.45) end
    c.headLine:SetColorTexture(cr, cg, cb, pts > 0 and 0.9 or 0.4)
    c:Show()
end

-- Ausreisser entfernen: Blizzards Ansichts-Loadout liefert bei fremden Klassen vereinzelt Knoten weit abseits der Baeume
-- (z.B. ganz rechts oder ganz unten). Die ziehen den Massstab auseinander - alle echten Talente kleben dann auf einem Haufen.
-- Regel: liegen hoechstens 2 Knoten am Rand weiter weg als 40 % der uebrigen Ausdehnung, gehoeren sie nicht zum Baum.
local function trimOutliers(list)
    local out = {}
    for i, n in ipairs(list) do out[i] = n end
    for _, key in ipairs({ "x", "y" }) do
        for _ = 1, 4 do
            local vals, cnt = {}, {}
            for _, n in ipairs(out) do
                local v = n[key]
                if not cnt[v] then cnt[v] = 0 vals[#vals + 1] = v end
                cnt[v] = cnt[v] + 1
            end
            table.sort(vals)
            local m = #vals
            if m < 5 then break end
            local drop
            if cnt[vals[m]] <= 2 and (vals[m] - vals[m - 1]) > 0.4 * (vals[m - 1] - vals[1]) then drop = vals[m]
            elseif cnt[vals[1]] <= 2 and (vals[2] - vals[1]) > 0.4 * (vals[m] - vals[2]) then drop = vals[1] end
            if drop == nil then break end
            local keep = {}
            for _, n in ipairs(out) do if n[key] ~= drop then keep[#keep + 1] = n end end
            out = keep
        end
    end
    return out
end
T._trimOutliers = trimOutliers   -- fuer Tests
local function draw(f, lay, ranks, choice, cls)
    for _, b in ipairs(f.nodes) do b:Hide() end
    for _, l in ipairs(f.lines) do l:Hide() end
    for _, c in ipairs(f.cols or {}) do c:Hide() end
    for _, c in ipairs(f.bgs or {}) do c:Hide() end
    if #lay.list == 0 then return 0 end
    local nodes = trimOutliers(lay.list)
    -- Baeume = Spalten: die zwei groessten Luecken in den x-Positionen trennen sie
    local xs, seen = {}, {}
    for _, n in ipairs(nodes) do if not seen[n.x] then seen[n.x] = true xs[#xs + 1] = n.x end end
    table.sort(xs)
    local gaps = {}
    for i = 2, #xs do gaps[#gaps + 1] = { i = i, d = xs[i] - xs[i - 1] } end
    table.sort(gaps, function(a, b) return a.d > b.d end)
    local cuts = {}
    local avg = (#xs > 1) and (xs[#xs] - xs[1]) / (#xs - 1) or 0
    for i = 1, math.min(2, #gaps) do if gaps[i].d > avg * 1.5 then cuts[#cuts + 1] = xs[gaps[i].i] end end
    table.sort(cuts)
    local function colOf(x)
        local k = 1
        for _, cx in ipairs(cuts) do if x >= cx then k = k + 1 end end
        return k
    end
    local trees = {}
    for _, n in ipairs(nodes) do
        local k = colOf(n.x)
        local t = trees[k] or { list = {}, pts = 0 }
        trees[k] = t
        t.list[#t.list + 1] = n
        t.pts = t.pts + (ranks[n.id] or 0)
        t.minX, t.maxX = math.min(t.minX or n.x, n.x), math.max(t.maxX or n.x, n.x)
        t.minY, t.maxY = math.min(t.minY or n.y, n.y), math.max(t.maxY or n.y, n.y)
    end
    local nCol = #trees
    local CW, CH = f.canvas:GetWidth(), f.canvas:GetHeight()
    if not CW or CW < 50 then CW, CH = 660, 524 end
    local GAP, HEAD = 10, 48
    local cw = (CW - GAP * (nCol - 1)) / nCol
    local ah = CH - HEAD - 14
    -- ein gemeinsamer Massstab fuer alle Baeume (gleiche Knotenabstaende), so gross wie moeglich
    local NODEZ = 36
    local s
    for _, t in ipairs(trees) do
        local dx, dy = math.max(1, t.maxX - t.minX), math.max(1, t.maxY - t.minY)
        local sx = (cw - 28 - NODEZ) / dx
        local sy = (ah - NODEZ) / dy
        local ss = math.min(sx, sy)
        s = s and math.min(s, ss) or ss
    end
    s = s or 1
    local btnOf, total, bi = {}, 0, 0
    for k, t in ipairs(trees) do
        local cx0 = (k - 1) * (cw + GAP)
        local c = colFrame(f, k)
        c:ClearAllPoints()
        c:SetPoint("TOPLEFT", f.canvas, "TOPLEFT", cx0, 0)
        c:SetSize(cw, CH)
        pcall(paintCol, f, c, k, cls, t.pts, cw, CH)
        local tw = (t.maxX - t.minX) * s
        local ox = cx0 + (cw - tw - NODEZ) / 2
        local oy = -HEAD - 4
        for _, n in ipairs(t.list) do
            bi = bi + 1
            local b = nodeBtn(f, bi)
            b:SetSize(NODEZ, NODEZ)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", f.canvas, "TOPLEFT", ox + (n.x - t.minX) * s, oy - (n.y - t.minY) * s)
            local r = ranks[n.id] or 0
            local ci = choice[n.id] or 1
            local spell = n.spells[ci] or n.spells[1] or 0
            if spell == 0 and T.SharedSpell then spell = T.SharedSpell(n.id) or 0 end
            b.spell, b.r, b.max = spell, r, n.max
            b.node, b.cfg, b.defName = n, lay.cfg, nil
            b.entry = n.entries and (n.entries[ci] or n.entries[1]) or nil
            local tex = T.IconFor(n, ci, spell)
            if not tex then f.missing = (f.missing or 0) + 1 end
            b.icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")
            b.icon:SetDesaturated(r == 0)
            b.icon:SetAlpha(r == 0 and 0.5 or 1)
            local full = r >= n.max and r > 0
            local col = full and C.amber or ((r > 0) and C.mint or { 0.35, 0.35, 0.38, 1 })
            K.SetBorderColor(b, col)
            if b.glow then b.glow:SetShown(full) end
            b.rank:SetText(n.max > 1 and (r .. "/" .. n.max) or "")
            if r > 0 then b.rank:SetTextColor(full and C.amber[1] or C.mint[1], full and C.amber[2] or C.mint[2], full and C.amber[3] or C.mint[3])
            else b.rank:SetTextColor(0.6, 0.6, 0.62) end
            b:SetFrameLevel(f.canvas:GetFrameLevel() + 6)
            b:Show()
            btnOf[n.id] = b
            total = total + r
        end
    end
    local li = 0
    for _, n in ipairs(nodes) do
        for _, t in ipairs(n.edges) do
            local a, bb = btnOf[n.id], btnOf[t]
            if a and bb then
                li = li + 1
                local l = line(f, li)
                if not l then break end
                l:SetStartPoint("CENTER", a)
                l:SetEndPoint("CENTER", bb)
                local on = (ranks[n.id] or 0) > 0 and (ranks[t] or 0) > 0
                local c = on and C.amber or { 0.4, 0.4, 0.44, 1 }
                l:SetThickness(on and 3 or 2)
                l:SetColorTexture(c[1], c[2], c[3], on and 0.95 or 0.55)
                l:Show()
            end
        end
    end
    if f.lineLayer then f.lineLayer:SetFrameLevel(f.canvas:GetFrameLevel() + 4) end
    return total
end
T._draw = function(...) return draw(...) end   -- fuer Tests

------------------------------------------------------------------------
-- Build uebernehmen: gleiche Spezialisierung -> Baum zuruecksetzen, Raenge von oben nach unten kaufen
-- (so weit die eigenen Punkte reichen), Wahlknoten gleich waehlen, dann bestaetigen. Nur per Klick.
------------------------------------------------------------------------
function T.CanApply(d)
    if not d or not d.s or d.me then return false, nil end
    if ns.inCombat() then return false, L["Im Kampf nicht moeglich."] end
    if not (C_Traits and C_Traits.PurchaseRank and C_ClassTalents and C_ClassTalents.GetActiveConfigID) then return false, L["Dein Client kann das nicht."] end
    local _, spec = T.Header(d.s)
    if not spec or spec ~= mySpec() then return false, L["Nur bei gleicher Klasse und Spezialisierung."] end
    return true
end
function T.Apply(d)
    local ok, why = T.CanApply(d)
    if not ok then if why then ns.print(why) end return false end
    local lay = T.MyLayout()
    if not lay then ns.print(L["Dein Talentbaum ist nicht lesbar."]) return false end
    local ranks, choice = T.Decode(d.s, lay.order, function(id) local n = lay.byId[id] return n and n.max end)
    if not ranks then ns.print(L["Export-Text unlesbar."]) return false end
    local cfg, tree = lay.cfg, lay.tree
    -- alles zuruecksetzen (vorgemerkt, wird erst mit Bestaetigen wirksam)
    if C_Traits.ResetTree then pcall(C_Traits.ResetTree, cfg, tree) end
    -- von oben nach unten, links nach rechts (Voraussetzungen zuerst)
    local list = {}
    for _, n in ipairs(lay.list) do if (ranks[n.id] or 0) > 0 then list[#list + 1] = n end end
    table.sort(list, function(a, b) if a.y ~= b.y then return a.y < b.y end return a.x < b.x end)
    local want, got = 0, 0
    for _, n in ipairs(list) do want = want + ranks[n.id] end
    -- mehrere Durchgaenge: was wegen Reihenfolge noch nicht ging, beim naechsten Mal
    for _ = 1, 3 do
        local progress = false
        for _, n in ipairs(list) do
            local okI, ni = pcall(C_Traits.GetNodeInfo, cfg, n.id)
            local cur = okI and ni and (ni.ranksPurchased or ni.currentRank) or 0
            local target = ranks[n.id]
            if n.type == 2 and choice[n.id] and ni and ni.entryIDs and ni.entryIDs[choice[n.id]] and cur == 0 then
                if pcall(C_Traits.SetSelection, cfg, n.id, ni.entryIDs[choice[n.id]]) then progress = true cur = 1 end
            end
            while cur < target do
                local okP, r = pcall(C_Traits.PurchaseRank, cfg, n.id)
                if not (okP and r ~= false) then break end
                cur = cur + 1
                progress = true
            end
        end
        if not progress then break end
    end
    for _, n in ipairs(list) do
        local okI, ni = pcall(C_Traits.GetNodeInfo, cfg, n.id)
        got = got + math.min(ranks[n.id], okI and ni and (ni.ranksPurchased or ni.currentRank) or 0)
    end
    local commit = (C_ClassTalents.CommitConfig and function() return C_ClassTalents.CommitConfig(cfg) end)
        or function() return C_Traits.CommitConfig(cfg) end
    local okC, res = pcall(commit)
    if okC and res ~= false then
        K.Toast(L["Talente uebernommen"], (L["%d von %d Punkten uebernommen"]):format(got, want), C.mint)
        ns.After(1.5, function() if win and win:IsShown() and win.who then T.Show(win.who) end end)
        return true
    end
    if C_Traits.RollbackConfig then pcall(C_Traits.RollbackConfig, cfg) end
    ns.print(L["WoW hat die Aenderung nicht angenommen (evtl. nur in Ruhe-Zonen oder ausserhalb von Instanzen moeglich)."])
    return false
end

-- Zauberdaten nachgeladen: offenes Fenster neu zeichnen (gebuendelt)
ns.On("SPELL_DATA_LOAD_RESULT", function()
    if T.waitIcons and win and win:IsShown() and win.who then
        ns.Debounce("talIcons", 0.3, function() T.waitIcons = nil T.Show(win.who) end)
    end
end)
function T.Show(name)
    name = name or ns.me()
    local f = win or build()
    f.who = name
    local d = T.DataFor(name)
    f.title:SetText((L["Talente: %s"]):format(ns.displayName(name)))
    f.export = d and d.s or nil
    f.copy:SetShown(f.export ~= nil)
    f.data = d
    if f.apply then
        local ok = T.CanApply(d)
        f.apply:SetShown(d ~= nil and not d.me and d.s ~= nil)
        f.apply:SetAlpha(ok and 1 or 0.45)
    end
    f:Show()
    f.empty:Hide()
    if not d or not d.s or d.s == "" then
        for _, b in ipairs(f.nodes) do b:Hide() end
        for _, l in ipairs(f.lines) do l:Hide() end
        for _, c in ipairs(f.cols or {}) do c:Hide() end
        for _, c in ipairs(f.bgs or {}) do c:Hide() end
        if f.SetClass then pcall(f.SetClass, f, d and d.cls or nil) end
        f.sub:SetText("")
        f.foot:SetText("")
        f.empty:SetText(L["Noch keine Talente bekannt. Mitglieder mit Oasis teilen sie automatisch; andere Spieler: anvisieren und betrachten (Rechtsklick > Betrachten) oder hier mit Ziel erneut oeffnen."])
        f.empty:Show()
        -- Ziel in Reichweite? Dann gleich betrachten
        if ns.safe(UnitExists("target")) and ns.fullName(ns.safe(ns.UnitName("target")) or "") == name then T.Inspect("target", true) end
        return
    end
    local ver, spec = T.Header(d.s)
    local lay
    if d.me then lay = T.MyLayout() end
    if not lay and spec and spec > 0 then
        local mine = T.MyLayout()
        -- gleiche Spezialisierung wie ich: eigener Baum hat die richtige Reihenfolge
        if mine and mySpec() == spec then lay = mine else lay = T.SpecLayout(spec) end
    end
    if not lay then
        for _, b in ipairs(f.nodes) do b:Hide() end
        for _, l in ipairs(f.lines) do l:Hide() end
        for _, c in ipairs(f.cols or {}) do c:Hide() end
        for _, c in ipairs(f.bgs or {}) do c:Hide() end
        if f.SetClass then pcall(f.SetClass, f, d.cls) end
        f.sub:SetText("")
        f.foot:SetText("")
        f.empty:SetText(L["Den Talentbaum dieser Klasse kann WoW hier nicht anzeigen. Der Export-Text laesst sich unten kopieren."])
        f.empty:Show()
        return
    end
    local maxOf = function(id) local n = lay.byId[id] return n and n.max end
    local ranks, choice
    if d.me then
        ranks, choice = {}, {}
        for _, n in ipairs(lay.list) do ranks[n.id] = n.rank end
    else
        ranks, choice = T.Decode(d.s, lay.order, maxOf)
        ranks, choice = ranks or {}, choice or {}
    end
    f.missing = 0
    if f.SetClass then f:SetClass(d.cls) end
    local total = draw(f, lay, ranks, choice, d.cls)
    -- viele Fragezeichen: einmal je Sitzung still pruefen, was die Symbol-Schnittstellen liefern (nach /reload lesbar)
    if f.missing > #lay.list / 2 and not T.probed then
        T.probed = true
        if ns.probes and ns.probes.talicons then pcall(ns.probes.talicons, true) end
    end
    local cls = d.cls and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[d.cls]) or d.cls) or ""
    f.sub:SetText(("%s  ·  %s  ·  %s"):format(cls, (L["Level %d"]):format(d.lvl or 0), (L["%d Punkte verteilt"]):format(total)))
    local src = d.src == "oasis" and L["geteilt per Oasis"] or (d.src == "inspect" and L["beim Betrachten gemerkt"] or L["dein aktueller Stand"])
    f.foot:SetText(src .. ((d.t and not d.me) and ("  ·  " .. ns.ago(d.t)) or ""))
end
ns.slash.talente = function(arg)
    arg = tostring(arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if arg == "" then
        if ns.safe(UnitExists("target")) and UnitIsPlayer("target") then
            local n = ns.fullName(ns.safe(ns.UnitName("target")) or "")
            if T.DataFor(n) then T.Show(n) else T.Inspect("target", true) end
            return
        end
        T.Show(ns.me())
        return
    end
    local found
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        if ns.short(m.name):lower() == arg:lower() or ns.displayName(m.name):lower() == arg:lower() then found = m.name break end
    end
    T.Show(found or ns.fullName(arg))
end
ns.slash.talents = ns.slash.talente

------------------------------------------------------------------------
-- Seitenfenster an Blizzards Talentfenster: "Builds aus der Gilde" (gleiche Spezialisierung)
-- Eigenes Fenster an UIParent, nur daneben ausgerichtet - Blizzards Fenster wird nicht veraendert.
------------------------------------------------------------------------
local side, hookedFrame
local CANDIDATES = { "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "TalentFrame" }
function T.GuildBuilds()
    local spec, out = mySpec(), {}
    local lay = T.MyLayout()
    for _, r in ipairs(Store.List(COLL)) do
        if r.s and r.who and not ns.isMe(r.who) and tonumber(r.spec) == spec then
            local pts = 0
            if lay then
                local ranks = T.Decode(r.s, lay.order, function(id) local n = lay.byId[id] return n and n.max end)
                for _, v in pairs(ranks or {}) do pts = pts + v end
            end
            out[#out + 1] = { who = r.who, lvl = r.lvl or 0, cls = r.cls, pts = pts, u = r.u }
        end
    end
    table.sort(out, function(a, b) if a.lvl ~= b.lvl then return a.lvl > b.lvl end return a.pts > b.pts end)
    return out
end
-- 0.5.785: Position (angedockt am Talentfenster oder frei verschoben), eingeklappt/ausgeklappt - ueber das Zahnrad im Fenster
local function sidePlace(f, anchor)
    local st = ns.db and ns.db.settings or {}
    f:ClearAllPoints()
    local p = st.talentSidePos
    if p and p[1] then
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p[1], p[2])
    elseif anchor then
        f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 4, 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    end
end
local function buildSide()
    local f = CreateFrame("Frame", "OasisTalentBuilds", UIParent)
    f:SetSize(230, 300)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if ns.db.settings.talentSidePos and not ns.inCombat() then self:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local l, t = self:GetLeft(), self:GetTop()
        if l and t and ns.db.settings.talentSidePos then ns.db.settings.talentSidePos = { l, t } end
    end)
    -- Zahnrad: Menue (einklappen, frei verschieben / andocken, ausblenden)
    f.gear = CreateFrame("Button", nil, f)
    f.gear:SetSize(18, 18)
    f.gear:SetPoint("TOPRIGHT", -8, -10)
    f.gear.icon = K.Glyph(f.gear, 13, ns.MEDIA .. "icons\\settings", C.muted)
    f.gear.icon:SetPoint("CENTER")
    f.gear:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3])
        K.ShowTip(self, { L["Einstellungen"], L["Einklappen, verschieben, ausblenden"] })
    end)
    f.gear:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
    -- 0.5.787: Klick aufs Zahnrad oeffnet ein kleines Feld mit Schaltern (statt Menue) - deckend, ueber allem
    f.gear:SetScript("OnClick", function(self)
        local o = f.opts
        if not o then
            o = CreateFrame("Frame", nil, UIParent)
            f.opts = o
            o:SetSize(250, 122)
            o:SetFrameStrata("DIALOG")
            o:SetClampedToScreen(true)
            o:EnableMouse(true)
            K.Fill(o, { C.bg[1], C.bg[2], C.bg[3], 1 })
            K.Border(o, C.line)
            o.head = K.Text(o, 10, C.dim)
            o.head:SetPoint("TOPLEFT", 12, -10)
            o.head:SetText(K.Upper(L["Builds aus der Gilde"]))
            local st = ns.db.settings
            o.t = {}
            local function row(i, label, get, set, tip)
                local t = K.Toggle(o, label, get, set)
                t:SetPoint("TOPLEFT", 12, -28 - (i - 1) * 28)
                t:SetWidth(226)
                if tip then
                    t:HookScript("OnEnter", function(x) K.ShowTip(x, { label, tip }) end)
                    t:HookScript("OnLeave", function() GameTooltip:Hide() end)
                end
                o.t[i] = t
            end
            row(1, L["Eingeklappt"], function() return st.talentSideFold and true or false end, function(v)
                st.talentSideFold = v or nil
                T.UpdateSide()
            end, L["Zeigt nur die Kopfzeile mit der Anzahl der Builds."])
            row(2, L["Frei verschiebbar"], function() return st.talentSidePos ~= nil end, function(v)
                if v then
                    local l, t = f:GetLeft(), f:GetTop()
                    st.talentSidePos = { l or 600, t or 600 }
                else
                    st.talentSidePos = nil
                end
                sidePlace(f, f.anchor)
            end, L["An: mit der Maus an eine eigene Stelle ziehen. Aus: haengt am Talentfenster."])
            row(3, L["Neben dem Talentfenster zeigen"], function() return st.talentSide ~= false end, function(v)
                if v then
                    st.talentSide = nil
                else
                    st.talentSide = false
                    o:Hide()
                    f:Hide()
                    ns.print(L["Builds aus der Gilde ausgeblendet. Wieder einblenden: /oa builds"])
                end
            end, L["Aus: das Fenster verschwindet. Zurueck mit /oa builds."])
            f:HookScript("OnHide", function() o:Hide() end)
        end
        if o:IsShown() then o:Hide() return end
        o:ClearAllPoints()
        o:SetPoint("TOPLEFT", self, "BOTTOMLEFT", -4, -4)
        for _, t in ipairs(o.t) do t:Refresh() end
        o:Show()
    end)
    -- kleiner Pfeil daneben: schnell ein-/ausklappen
    f.fold = CreateFrame("Button", nil, f)
    f.fold:SetSize(18, 18)
    f.fold:SetPoint("RIGHT", f.gear, "LEFT", -2, 0)
    f.fold.t = K.Text(f.fold, 12, C.muted, "CENTER")
    f.fold.t:SetPoint("CENTER")
    f.fold:SetScript("OnClick", function()
        ns.db.settings.talentSideFold = (not ns.db.settings.talentSideFold) or nil
        T.UpdateSide()
    end)
    f.fold:SetScript("OnEnter", function(self) self.t:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
    f.fold:SetScript("OnLeave", function(self) self.t:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
    K.Fill(f, C.bg)
    K.Border(f, C.line)
    if K.ApplySkin then K.ApplySkin(f, "panel", C.bg) end
    f.logo = f:CreateTexture(nil, "ARTWORK")
    f.logo:SetTexture(ns.MEDIA .. "logo64")
    f.logo:SetSize(16, 16)
    f.logo:SetPoint("TOPLEFT", 12, -12)
    f.title = K.Title(f, 13, C.text)
    f.title:SetPoint("LEFT", f.logo, "RIGHT", 6, 0)
    f.title:SetPoint("RIGHT", f, "RIGHT", -50, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetWordWrap(false)
    f.title:SetText(L["Builds aus der Gilde"])
    f.sub = K.Text(f, 10, C.muted)
    f.sub:SetPoint("TOPLEFT", 12, -34)
    f.sub:SetPoint("RIGHT", -12, 0)
    f.sub:SetWordWrap(true)
    f.sub:SetText(L["Gleiche Spezialisierung - Klick: Baum ansehen und uebernehmen"])
    f.rows = {}
    f.empty = K.Text(f, 11, C.dim, "CENTER")
    f.empty:SetPoint("TOP", 0, -80)
    f.empty:SetWidth(200)
    f.empty:SetWordWrap(true)
    f.empty:SetText(L["Noch niemand aus der Gilde mit deiner Spezialisierung teilt seine Talente (Oasis-Nutzer teilen automatisch)."])
    side = f
    return f
end
function T.UpdateSide()
    if not (side and side:IsShown()) then return end
    local list = T.GuildBuilds()
    for _, r in ipairs(side.rows) do r:Hide() end
    -- eingeklappt: nur die Kopfzeile (mit Anzahl), kein Inhalt
    local fold = ns.db.settings.talentSideFold and true or false
    side.fold.t:SetText(fold and "+" or "-")
    side.sub:SetShown(not fold)
    if fold then
        side.empty:Hide()
        side.title:SetText(L["Builds aus der Gilde"] .. (#list > 0 and ("  |cff888888" .. #list .. "|r") or ""))
        side:SetHeight(40)
        return
    end
    side.title:SetText(L["Builds aus der Gilde"])
    for i = 1, math.min(8, #list) do
        local e = list[i]
        local r = side.rows[i]
        if not r then
            r = CreateFrame("Button", nil, side)
            r:SetHeight(30)
            r:SetPoint("TOPLEFT", 8, -58 - (i - 1) * 32)
            r:SetPoint("RIGHT", -8, 0)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT") r.hl:SetAllPoints() r.hl:SetColorTexture(1, 1, 1, 0.06)
            r.name = K.Text(r, 12, C.text) r.name:SetPoint("TOPLEFT", 6, -3) r.name:SetPoint("RIGHT", -6, 0) r.name:SetWordWrap(false)
            r.info = K.Text(r, 10, C.muted) r.info:SetPoint("BOTTOMLEFT", 6, 3)
            r:SetScript("OnClick", function(self) if self.who then T.Show(self.who) end end)
            side.rows[i] = r
        end
        r.who = e.who
        r.name:SetText(ns.colorName(e.who, e.cls))
        r.info:SetText((L["Level %d"]):format(e.lvl) .. "  ·  " .. (L["%d Punkte verteilt"]):format(e.pts))
        r:Show()
    end
    side.empty:SetShown(#list == 0)
    side:SetHeight(math.max(130, 66 + math.min(8, #list) * 32 + 8))
end
local function attach(frame)
    if hookedFrame or not frame or not frame.HookScript then return end
    hookedFrame = frame
    frame:HookScript("OnShow", function(self)
        if ns.db and ns.db.settings.talentSide == false then return end
        local f = side or buildSide()
        f.anchor = self
        sidePlace(f, self)
        f:Show()
        T.UpdateSide()
    end)
    frame:HookScript("OnShow", function(self) ns.After(0.8, function() if self:IsShown() then pcall(T.Harvest, self) end end) end)
    if frame:IsShown() then ns.After(0.8, function() pcall(T.Harvest, frame) end) end
    frame:HookScript("OnHide", function() if side then side:Hide() end end)
    if frame:IsShown() and not (ns.db and ns.db.settings.talentSide == false) then
        local f = side or buildSide()
        f.anchor = frame
        sidePlace(f, frame)
        f:Show()
        T.UpdateSide()
    end
end
-- /oa builds: Seitenfenster wieder einblenden (nach "Ausblenden" im Zahnrad-Menue)
ns.slash.builds = function()
    ns.db.settings.talentSide = nil
    if hookedFrame and hookedFrame:IsShown() then
        local f = side or buildSide()
        f.anchor = hookedFrame
        sidePlace(f, hookedFrame)
        f:Show()
        T.UpdateSide()
    end
    ns.print(L["Builds aus der Gilde wird wieder neben dem Talentfenster gezeigt."])
end
local function findTalentFrame()
    for _, n in ipairs(CANDIDATES) do
        local fr = _G[n]
        if type(fr) == "table" and fr.HookScript then return fr end
    end
    -- Forever kann das Fenster anders nennen: einmalig nach "...TalentFrame" suchen (nur Hauptfenster an UIParent)
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find("Talent") and k:find("Frame$") and type(v) == "table" and v.HookScript and v.GetParent then
            local okP, par = pcall(v.GetParent, v)
            if okP and par == UIParent then CANDIDATES[#CANDIDATES + 1] = k return v end
        end
    end
end
ns.On("ADDON_LOADED", function(name)
    if hookedFrame or type(name) ~= "string" or not name:find("^Blizzard_") then return end
    if not (name:find("Talent") or name:find("PlayerSpells") or name:find("Spell")) then return end
    ns.After(0.5, function() attach(findTalentFrame()) end)
end)
ns.Listen("LOGIN", function() ns.After(5, function() attach(findTalentFrame()) end) end)
ns.Listen("STORE", function(coll) if coll == COLL then ns.Debounce("talSide", 0.5, T.UpdateSide) end end)
ns.On("TRAIT_CONFIG_UPDATED", function()
    if hookedFrame and hookedFrame:IsShown() then ns.Debounce("talHarvest", 1, function() pcall(T.Harvest, hookedFrame) end) end
end)
ns.slash.talentsymbole = function()
    local fr = hookedFrame or findTalentFrame()
    if not fr then ns.print(L["Erst das Talentfenster (Taste N) einmal oeffnen."]) return end
    ns.print((L["Talent-Symbole gelernt: %d"]):format(T.Harvest(fr) or 0))
end

-- Diagnose: /oa probe talicons  -> was liefern die Symbol-APIs fuer die ersten Talente?
ns.probes = ns.probes or {}
ns.probes.talicons = function(quiet)
    local lay = T.MyLayout and T.MyLayout()
    local out = {}
    if not lay then out[1] = "kein Layout" else
        for i = 1, math.min(6, #lay.list) do
            local n = lay.list[i]
            local sp = n.spells[1] or 0
            local okI, si = pcall(C_Spell.GetSpellInfo, sp)
            local okT, a, b = pcall(C_Spell.GetSpellTexture, sp)
            local okG, g = GetSpellTexture and pcall(GetSpellTexture, sp)
            local okN, nm = pcall(C_Spell.GetSpellName, sp)
            local okD, di = pcall(C_Traits.GetDefinitionInfo, 0)
            out[#out + 1] = ("%d spell=%s defIcon=%s info=%s/%s tex=%s/%s old=%s name=%s"):format(i, tostring(sp), tostring(n.icons[1]),
                tostring(okI and si and si.iconID), tostring(okI and si and si.originalIconID), tostring(okT and a), tostring(okT and b),
                tostring(okG and g), tostring(okN and nm))
        end
    end
    local S2 = C_SpecializationInfo
    if S2 and S2.GetTalentInfo then
        for _, q in ipairs({ { tier = 1, column = 1 }, { tier = 1, column = 2 }, { tabIndex = 1, talentIndex = 1 }, { specializationIndex = 1, talentIndex = 1 } }) do
            local okQ, r = pcall(S2.GetTalentInfo, q)
            local parts = {}
            if okQ and type(r) == "table" then for k, v in pairs(r) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end end
            local qs = {}
            for k, v in pairs(q) do qs[#qs + 1] = k .. "=" .. v end
            out[#out + 1] = "GetTalentInfo{" .. table.concat(qs, ",") .. "} " .. (okQ and ("{" .. table.concat(parts, ",") .. "}") or ("FEHLER " .. tostring(r)))
        end
    end
    out[#out + 1] = "harvest " .. tostring(ns.db.talHarvest and ns.db.talHarvest.learned) .. " gelernt, Symbole gemerkt: " .. tostring((function() local c = 0 for _ in pairs(ns.db.talIcons or {}) do c = c + 1 end return c end)())
    ns.db.talIconProbe = { ts = time(), v = ns.version, lines = out }
    if not quiet then for _, l in ipairs(out) do ns.print(l) end end
end
end)

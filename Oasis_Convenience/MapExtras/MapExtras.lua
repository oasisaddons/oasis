-- Oasis - Map extras (0.5.936): markers and notes, trails, danger zones, dungeon entrances,
-- quest givers of dungeon quests, coordinates and target arrow on the minimap, visited vendors/mailboxes/flight points.
-- Hooks onto Map.UpdateWorldPins like GatherMap; minimap math comes from GatherMap (GM.MiniCtx / GM.MiniPlace).
-- everything can be disabled separately: Settings > Areas > Map.
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_MapExtras", function()   -- module map extras (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local X = {}
ns.MapExtras = X

local function S() return ns.db.settings end
local function on(key) return S()[key] ~= false end     -- Standard an
local function opt(key) return S()[key] == true end     -- off by default
local function clean(s, max)
    s = tostring(s or ""):gsub("[%c|]", " ")
    max = max or 120
    if #s > max then s = s:sub(1, max):gsub("[\192-\255][\128-\191]*$", "") end
    return s
end
local function dur(sec)
    if ns.Rares and ns.Rares.dur then return ns.Rares.dur(sec) end
    return (L["%d min"]):format(math.max(1, math.ceil((sec or 0) / 60)))
end
X.clean = clean

------------------------------------------------------------------------
-- helpers: pool of icons per layer, world map state, conversion between maps
------------------------------------------------------------------------
local pools = {}
local function hideAll(name)
    local p = pools[name]
    if not p then return end
    for i = 1, p.used do p[i]:Hide() end
    p.used = 0
end
local function take(name, parent, make)
    local p = pools[name]
    if not p then p = { used = 0 } pools[name] = p end
    p.used = p.used + 1
    local f = p[p.used]
    if not f then f = make(parent) p[p.used] = f end
    if f:GetParent() ~= parent then f:SetParent(parent) end
    return f
end
local function world()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return nil end
    local mapID, canvas = WorldMapFrame:GetMapID(), WorldMapFrame:GetCanvas()
    if not mapID or not canvas then return nil end
    local cscale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    local cs = 1 / math.max(cscale, 0.01)
    return { map = mapID, canvas = canvas, cw = canvas:GetWidth(), ch = canvas:GetHeight(), cs = cs, s = cs * (S().mapPinScale or 1) }
end
local function put(w, p, x, y, level)
    p:SetScale(w.s)
    p:ClearAllPoints()
    p:SetPoint("CENTER", w.canvas, "TOPLEFT", (x * w.cw) / w.s, (-y * w.ch) / w.s)
    p:SetFrameStrata(w.canvas:GetFrameStrata())
    p:SetFrameLevel(w.canvas:GetFrameLevel() + level)
    p:Show()
end
-- point from map src on map dst; nil if it is not on it
local function tr(src, x, y, dst)
    if src == dst then return x, y end
    local T = ns.Map and ns.Map.translate
    if not T then return nil end
    local a, b = T(src, x, y, dst)
    if a and b and a > 0 and a < 1 and b > 0 and b < 1 then return a, b end
end
X.tr = tr

-- round icon: dark disc, image, ring, label below
local function iconPin(parent)
    local p = CreateFrame("Button", nil, parent)
    p:SetSize(20, 20)
    p.bg = p:CreateTexture(nil, "BACKGROUND")
    p.bg:SetTexture(ns.MEDIA .. "pindisc")
    p.bg:SetAllPoints()
    p.bg:SetVertexColor(0.04, 0.04, 0.05, 1)
    p.icon = p:CreateTexture(nil, "ARTWORK")
    p.icon:SetPoint("TOPLEFT", 4, -4) p.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    p.ring = p:CreateTexture(nil, "OVERLAY")
    p.ring:SetTexture(ns.MEDIA .. "pinring")
    p.ring:SetAllPoints()
    p.lbl = K.Text(p, 10, C.text, "CENTER")
    p.lbl:SetPoint("TOP", p, "BOTTOM", 0, -1)
    p.lbl:SetShadowOffset(1, -1)
    p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    p:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
    p:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p:SetScript("OnClick", function(self, btn) if self.click then self.click(self, btn) end end)
    return p
end
local function style(p, icon, color, tint, label)
    p.icon:SetTexture(icon)
    if tint then p.icon:SetVertexColor(color[1], color[2], color[3]) else p.icon:SetVertexColor(1, 1, 1) end
    p.ring:SetVertexColor(color[1], color[2], color[3])
    p.lbl:SetText(label or "")
end
local function guideTo(map, x, y, label)
    if ns.Map and ns.Map.SetTarget then ns.Map.SetTarget({ mapID = map, x = x, y = y, label = label }) end
end

------------------------------------------------------------------------
-- Markers and notes. Guild markers live in the collection "markers" (they expire), own notes local only.
------------------------------------------------------------------------
X.KINDS = {
    meet = { name = "Meeting point", icon = ns.MEDIA .. "icons\\groups", tint = true, color = { 0.4, 0.86, 0.62 }, ttl = 3600 },
    danger = { name = "Caution", icon = ns.MEDIA .. "icons\\deaths", tint = true, color = { 0.92, 0.3, 0.32 }, ttl = 2 * 3600 },
    note = { name = "Note", icon = "Interface\\Icons\\INV_Misc_Note_01", color = { 0.98, 0.82, 0.3 }, ttl = 7 * 86400 },
}
local function validMarker(m)
    return type(m) == "table" and X.KINDS[m.kind] and type(m.map) == "number" and type(m.x) == "number" and type(m.y) == "number"
        and m.x > 0 and m.x < 1 and m.y > 0 and m.y < 1
end
function X.Markers()
    local now, out = ns.now(), {}
    for _, m in ipairs(Store.List("markers", function(m) return not m.del and validMarker(m) and (m.exp or 0) > now end)) do out[#out + 1] = m end
    for _, m in ipairs(S().mapNotes or {}) do if validMarker(m) then out[#out + 1] = m end end
    return out
end
local markerSeq = 0
function X.AddMarker(kind, map, x, y, text, private)
    local k = X.KINDS[kind]
    if not (k and map and x and y) then return nil end
    local now = ns.now()
    markerSeq = markerSeq + 1   -- two markers in the same second must not overwrite each other
    local rec = { id = "mk-" .. ns.short(ns.me()) .. "-" .. now .. "-" .. markerSeq, kind = kind, text = clean(text), map = map,
        x = math.floor(x * 10000) / 10000, y = math.floor(y * 10000) / 10000, by = ns.me(), ts = now }
    if private then
        rec.private = true
        S().mapNotes = S().mapNotes or {}
        table.insert(S().mapNotes, rec)
    else
        rec.exp = now + k.ttl
        Store.Put("markers", rec)
    end
    X.Redraw()
    return rec
end
function X.CanRemove(m) return m.private or ns.isMe(m.by) or (ns.isOfficer and ns.isOfficer()) or false end
function X.RemoveMarker(m)
    if m.private then
        for i, n in ipairs(S().mapNotes or {}) do if n.id == m.id then table.remove(S().mapNotes, i) break end end
    else
        Store.Delete("markers", m.id)
    end
    X.Redraw()
end
local function markerLabel(m)
    local k = X.KINDS[m.kind]
    local t = clean(m.text, 60)
    return t ~= "" and t or L[k.name]
end
local function markerTip(m)
    local k = X.KINDS[m.kind]
    local tip = { K.hex(k.color) .. L[k.name] .. "|r" }
    if (m.text or "") ~= "" then tip[#tip + 1] = clean(m.text) end
    if m.private then
        tip[#tip + 1] = "|cff888888" .. L["only visible to you"] .. "|r"
    else
        tip[#tip + 1] = "|cff888888" .. (L["by %s"]):format(ns.displayName(m.by or "?")) .. "  ·  " .. (L["%s left"]):format(dur((m.exp or 0) - ns.now())) .. "|r"
    end
    return tip
end
local function markerMenu(self)
    local m = self.rec
    if not m then return end
    local items = { { text = L["Guide me there"], fn = function() guideTo(m.map, m.x, m.y, markerLabel(m)) end } }
    if X.CanRemove(m) then items[#items + 1] = { text = L["Remove marker"], fn = function() X.RemoveMarker(m) end } end
    K.ShowMenu(self, items, markerLabel(m))
end

-- placing: choose kind (bar below the map), then click on the map
StaticPopupDialogs["OASIS_MAP_NOTE"] = {
    text = "%s", button1 = OKAY or "OK", button2 = CANCEL, hasEditBox = true, editBoxWidth = 320, maxLetters = 100,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText("") eb:SetFocus() end end,
    OnAccept = function(self, data)
        local eb = self.editBox or self.EditBox
        local t = eb and (eb:GetText() or "") or ""
        if data and data.fn then data.fn(t) end
    end,
    EditBoxOnEnterPressed = function(self) local p = self:GetParent() if p.button1 then p.button1:Click() end end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}
local placing, overlay, hint
local function cursorXY(canvas)
    local cx, cy = GetCursorPosition()
    local es = canvas:GetEffectiveScale()
    local l, t, w, h = canvas:GetLeft(), canvas:GetTop(), canvas:GetWidth(), canvas:GetHeight()
    if not (cx and es and es > 0 and l and t and w and w > 0 and h and h > 0) then return nil end
    local x, y = (cx / es - l) / w, (t - cy / es) / h
    if x <= 0 or x >= 1 or y <= 0 or y >= 1 then return nil end
    return x, y
end
function X.StopPlacing()
    placing = nil
    if overlay then overlay:Hide() end
    if hint then hint:Hide() end
end
function X.StartPlacing(kind, private)
    local w = world()
    if not (w and X.KINDS[kind]) then return end
    placing = { kind = kind, private = private }
    if not overlay then
        overlay = CreateFrame("Button", nil, w.canvas)
        overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        overlay:SetScript("OnClick", function(self, btn)
            local p = placing
            local x, y = cursorXY(self:GetParent())
            local map = WorldMapFrame:GetMapID()
            X.StopPlacing()
            if btn == "RightButton" or not (p and x and map) then return end
            if p.kind == "note" then
                StaticPopup_Show("OASIS_MAP_NOTE", L["Note text (optional):"], nil,
                    { fn = function(t) X.AddMarker(p.kind, map, x, y, t, p.private) end })
            else
                X.AddMarker(p.kind, map, x, y, "", false)
            end
        end)
        hint = CreateFrame("Frame", nil, WorldMapFrame)
        hint:SetSize(460, 26)
        hint:SetFrameStrata("TOOLTIP")
        K.Fill(hint, { 0.04, 0.04, 0.05, 0.94 })
        K.Border(hint, C.accent)
        hint.t = K.Text(hint, 12, C.text, "CENTER")
        hint.t:SetPoint("CENTER")
    end
    if overlay:GetParent() ~= w.canvas then overlay:SetParent(w.canvas) end
    overlay:SetAllPoints(w.canvas)
    overlay:SetFrameStrata(w.canvas:GetFrameStrata())
    overlay:SetFrameLevel(w.canvas:GetFrameLevel() + 300)
    overlay:Show()
    hint.t:SetText(K.hex(X.KINDS[kind].color) .. L[X.KINDS[kind].name] .. "|r   " .. L["Click the map to place the marker  ·  Right-click to cancel"])
    hint:SetWidth(hint.t:GetStringWidth() + 36)
    hint:ClearAllPoints()
    hint:SetPoint("TOP", WorldMapFrame, "TOP", 0, -76)
    hint:Show()
end
function X.MenuItems()
    return {
        { text = L["Meeting point"], fn = function() X.StartPlacing("meet") end },
        { text = L["Caution"], fn = function() X.StartPlacing("danger") end },
        { text = L["Note for the guild"], fn = function() X.StartPlacing("note") end },
        { text = L["Note just for me"], fn = function() X.StartPlacing("note", true) end },
    }
end

local function drawMarkers(w)
    hideAll("mk")
    if not on("mapMarkers") then return end
    for _, m in ipairs(X.Markers()) do
        local x, y = tr(m.map, m.x, m.y, w.map)
        if x then
            local k = X.KINDS[m.kind]
            local p = take("mk", w.canvas, iconPin)
            style(p, k.icon, k.color, k.tint, clean(markerLabel(m), 28))
            p.rec, p.tip, p.click = m, markerTip(m), markerMenu
            put(w, p, x, y, 60)
        end
    end
end

------------------------------------------------------------------------
-- Trails: the path of the last 5 minutes per member (recorded locally only, from the shared positions)
------------------------------------------------------------------------
local TRAIL_SEC, TRAIL_STEP = 300, 0.002
local trails = {}
local function trailAdd(name, map, x, y, class, now)
    local t = trails[name]
    if not t then t = {} trails[name] = t end
    t.class = class or t.class
    local last = t[#t]
    if not last or last.map ~= map or math.abs(last.x - x) + math.abs(last.y - y) > TRAIL_STEP then
        t[#t + 1] = { map = map, x = x, y = y, t = now }
    end
end
function X.SampleTrails(now)
    if not opt("mapTrails") and not opt("mapTrailsGuild") and not X.rec then
        if next(trails) then trails = {} end
        return
    end
    now = now or GetTime()
    for name, p in pairs(ns.Map and ns.Map.pos or {}) do
        if p.mapID and p.x and p.y then trailAdd(name, p.mapID, p.x, p.y, p.class, now) end
    end
    local G = ns.Gather
    local c = G and G.MiniCtx and G.MiniCtx()
    if c then
        local _, class = UnitClass("player")
        trailAdd("\1me", c.map, c.mx, c.my, class, now)
        -- 0.6.486: eigene Route aufnehmen (gespeichert in ns.db.routes)
        local rec = X.rec
        if rec and not (UnitOnTaxi and UnitOnTaxi("player")) then   -- 0.6.520: do not record flight paths
            local last = rec.pts[#rec.pts]
            if not last or last.map ~= c.map or math.abs(last.x - c.mx) + math.abs(last.y - c.my) > TRAIL_STEP then
                rec.pts[#rec.pts + 1] = { map = c.map, x = c.mx, y = c.my, t = time() }
                if #rec.pts > 4000 then table.remove(rec.pts, 1) end
            end
        end
    end
    for name, t in pairs(trails) do
        while t[1] and now - t[1].t > TRAIL_SEC do table.remove(t, 1) end
        if #t == 0 then trails[name] = nil end
    end
end
function X.Trails() return trails end
local tFrame, tLines, tUsed = nil, {}, 0
local gLines, gUsed, endGlow = {}, 0, nil   -- 0.6.498: glow under the routes + shine at the current end
local function drawTrails(w)
    for i = 1, tUsed do tLines[i]:Hide() end
    tUsed = 0
    for i = 1, gUsed do gLines[i]:Hide() end
    gUsed = 0
    if endGlow then endGlow:Hide() end
    local routes = {}
    for _, r in ipairs(ns.db and ns.db.routes or {}) do if r.show then routes[#routes + 1] = r end end
    local recOn = X.rec and X.recShow ~= false and not S().routesOff
    if S().routesOff then for k = #routes, 1, -1 do routes[k] = nil end end   -- 0.6.502: lines off
    if not opt("mapTrails") and not opt("mapTrailsGuild") and #routes == 0 and not recOn and not S().routesOff then return end
    if not tFrame then tFrame = CreateFrame("Frame", nil, w.canvas) end
    if tFrame:GetParent() ~= w.canvas then tFrame:SetParent(w.canvas) end
    tFrame:SetAllPoints(w.canvas)
    tFrame:SetFrameStrata(w.canvas:GetFrameStrata())
    tFrame:SetFrameLevel(math.min(8800, w.canvas:GetFrameLevel() + 2300))   -- 0.6.482: above the map layers (covered at +53, trail looked broken)
    -- 0.6.470: trail always ends at the current position (previously it stopped at the last sample)
    local live = {}
    for name, p in pairs(ns.Map and ns.Map.pos or {}) do if p.mapID and p.x and p.y then live[name] = { map = p.mapID, x = p.x, y = p.y } end end
    local G = ns.Gather
    local c = G and G.MiniCtx and G.MiniCtx()
    if c then live["\1me"] = { map = c.map, x = c.mx, y = c.my } end
    -- 0.6.486: saved routes (gold) and the running recording (red)
    -- 0.6.495: opacity runs from a0 (start) to a1 (end) - old routes faint, stronger toward the current end
    local function drawPts(pts, cr, cg, cb, a0, a1, glow)
        a1 = a1 or a0
        local px, py
        local n = #pts
        for i, pt in ipairs(pts) do
            local ca = a0 + (a1 - a0) * (n > 1 and (i - 1) / (n - 1) or 1)
            local x, y = tr(pt.map, pt.x, pt.y, w.map)
            if x and px and math.abs(x - px) + math.abs(y - py) < 0.35 then
                tUsed = tUsed + 1
                local l = tLines[tUsed]
                if not l then l = tFrame:CreateLine(nil, "ARTWORK") tLines[tUsed] = l end
                l:SetColorTexture(cr, cg, cb, ca)
                l:SetThickness(math.max(1.5, 3 * w.cs))
                l:SetStartPoint("TOPLEFT", tFrame, px * w.cw, -py * w.ch)
                l:SetEndPoint("TOPLEFT", tFrame, x * w.cw, -y * w.ch)
                l:Show()
                -- soft glow below (additive), stronger toward the end
                if glow and glow > 0 then
                    gUsed = gUsed + 1
                    local gl = gLines[gUsed]
                    if not gl then gl = tFrame:CreateLine(nil, "BACKGROUND") gl:SetBlendMode("ADD") gLines[gUsed] = gl end
                    local q = n > 1 and (i - 1) / (n - 1) or 1
                    local ga = glow * q * q
                    gl:SetColorTexture(cr * ga, cg * ga, cb * ga, 1)
                    gl:SetThickness(math.max(4, 10 * w.cs))
                    gl:SetStartPoint("TOPLEFT", tFrame, px * w.cw, -py * w.ch)
                    gl:SetEndPoint("TOPLEFT", tFrame, x * w.cw, -y * w.ch)
                    gl:Show()
                end
            end
            px, py = x, y
        end
        -- glow at the last point (current end)
        if glow ~= nil and px then
            if not endGlow then
                endGlow = tFrame:CreateTexture(nil, "OVERLAY")
                endGlow:SetTexture(ns.MEDIA .. "softglow")
                endGlow:SetBlendMode("ADD")
            end
            local sz = math.max(12, 18 * w.cs)   -- 0.6.499: smaller, subtle dot
            endGlow:SetSize(sz, sz)
            endGlow:ClearAllPoints()
            endGlow:SetPoint("CENTER", tFrame, "TOPLEFT", px * w.cw, -py * w.ch)
            endGlow:SetVertexColor(cr, cg, cb, 1)
            endGlow:Show()
        end
    end
    -- 0.6.494: routes and recording in your own class color (like the trail)
    local _, myClass = UnitClass("player")
    local mr, mg, mb = 1, 1, 1
    if myClass and ns.classColor then mr, mg, mb = ns.classColor(myClass) end
    mr, mg, mb = mr or 1, mg or 1, mb or 1
    -- past routes faint (oldest faintest), current recording strong and full toward the end
    for k, r in ipairs(routes) do
        local fade = math.max(0.35, 1 - (k - 1) * 0.15)
        drawPts(r.pts or {}, mr, mg, mb, 0.18 * fade, 0.6 * fade)   -- 0.6.497: a bit stronger
    end
    -- 0.6.520: running recording only as long as configured (default 10 min), older points disappear;
    -- at most 600 lines (map stuttered with thousands of strokes)
    if recOn then
        local mins = S().trailMinutes or 10
        local all, pts = X.rec.pts, {}
        local cut = mins > 0 and (time() - mins * 60) or nil
        for _, pt in ipairs(all) do if not cut or (pt.t and pt.t >= cut) then pts[#pts + 1] = pt end end
        if #pts > 600 then
            local step, thin = #pts / 600, {}
            for i = 1, 600 do thin[i] = pts[math.floor((i - 1) * step) + 1] end
            thin[#thin + 1] = pts[#pts]
            pts = thin
        end
        drawPts(pts, mr, mg, mb, 0.1, 1)
    end   -- 0.6.500: no shine at the end (sat on the player arrow)   -- 0.6.499: no wide glow anymore (looked restless)
    -- 0.6.504: lines off = only a short fading tail behind you (last 60 s)
    local tail = S().routesOff
    if not tail and not opt("mapTrails") and not opt("mapTrailsGuild") then return end
    local nowT = GetTime()
    for name, t in pairs(trails) do
        -- 0.6.495: other players' lines only with their own toggle (off by default)
        -- 0.6.523: own trail only with "Own trail", guild members independently with their own toggle
        if (name == "\1me" and (tail or opt("mapTrails"))) or (name ~= "\1me" and not tail and opt("mapTrailsGuild")) then
        local r, g, b = 1, 1, 1
        if t.class and ns.classColor then r, g, b = ns.classColor(t.class) end
        local pts = {}
        for _, pt in ipairs(t) do if not tail or nowT - (pt.t or 0) < 60 then pts[#pts + 1] = pt end end
        if live[name] then pts[#pts + 1] = live[name] end
        local n, px, py = #pts, nil, nil
        for i, pt in ipairs(pts) do
            local x, y = tr(pt.map, pt.x, pt.y, w.map)
            if x and px and math.abs(x - px) + math.abs(y - py) < 0.35 then   -- do not connect jumps (portal, hearthstone)
                tUsed = tUsed + 1
                local l = tLines[tUsed]
                if not l then l = tFrame:CreateLine(nil, "ARTWORK") tLines[tUsed] = l end
                l:SetColorTexture(r or 1, g or 1, b or 1, tail and (0.7 * (i / n) ^ 1.5) or (0.25 + 0.6 * (i / n)))
                l:SetThickness(math.max(1, 2 * w.cs))
                l:SetStartPoint("TOPLEFT", tFrame, px * w.cw, -py * w.ch)
                l:SetEndPoint("TOPLEFT", tFrame, x * w.cw, -y * w.ch)
                l:Show()
            end
            px, py = x, y
        end
        end
    end
end

------------------------------------------------------------------------
-- Danger zones: red shimmer where at least three guild members died in the last 7 days
------------------------------------------------------------------------
local DANGER_CELL, DANGER_MIN, DANGER_DAYS = 0.05, 3, 7
function X.DangerZones(deaths, mapID, now)
    local cells, out = {}, {}
    for _, d in ipairs(deaths) do
        if now - (d.ts or 0) < DANGER_DAYS * 86400 then
            local x, y = tr(d.mapID, (d.x or 0) / 10000, (d.y or 0) / 10000, mapID)
            if x then
                local key = math.floor(x / DANGER_CELL) .. ":" .. math.floor(y / DANGER_CELL)
                local c = cells[key]
                if not c then c = { n = 0, x = 0, y = 0 } cells[key] = c end
                c.n, c.x, c.y = c.n + 1, c.x + x, c.y + y
            end
        end
    end
    for _, c in pairs(cells) do
        if c.n >= DANGER_MIN then out[#out + 1] = { n = c.n, x = c.x / c.n, y = c.y / c.n } end
    end
    return out
end
local function drawDanger(w)
    hideAll("dz")
    if not opt("mapDanger") or not (ns.Deaths and ns.Deaths.MapPins) then return end
    -- 0.5.967: zone maps only. On continent and world maps the shimmer got huge and colored whole regions red.
    local info = C_Map and C_Map.GetMapInfo and w.map and C_Map.GetMapInfo(w.map)
    local mt = info and ns.safe(info.mapType)
    if type(mt) == "number" and mt < ((Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3) then return end
    for _, z in ipairs(ns.Deaths and X.DangerZones(ns.Deaths.MapPins(), w.map, ns.now()) or {}) do   -- deaths module may be off
        local f = take("dz", w.canvas, function(parent)
            local fr = CreateFrame("Frame", nil, parent)
            fr.tex = fr:CreateTexture(nil, "BACKGROUND")
            fr.tex:SetTexture(ns.MEDIA .. "pinglow")
            fr.tex:SetAllPoints()
            fr.tex:SetVertexColor(1, 0.12, 0.1)
            return fr
        end)
        local size = w.cw * 0.11
        f:SetScale(1)
        f:SetSize(size, size)
        f.tex:SetAlpha(math.min(0.75, 0.3 + 0.07 * z.n))
        f:ClearAllPoints()
        f:SetPoint("CENTER", w.canvas, "TOPLEFT", z.x * w.cw, -z.y * w.ch)
        f:SetFrameStrata(w.canvas:GetFrameStrata())
        f:SetFrameLevel(w.canvas:GetFrameLevel() + 50)
        f:Show()
    end
end

------------------------------------------------------------------------
-- Dungeon entrances: level range and how many guild members are in range (from the guild roster)
------------------------------------------------------------------------
local rosterAt, roster = -999, {}
local function guildLevels()
    if GetTime() - rosterAt < 60 then return roster end
    rosterAt, roster = GetTime(), {}
    local n = ns.safe(GetNumGuildMembers and GetNumGuildMembers()) or 0
    for i = 1, n do
        local _, _, _, lvl = GetGuildRosterInfo(i)
        lvl = ns.safe(lvl)
        if type(lvl) == "number" then roster[#roster + 1] = lvl end
    end
    return roster
end
function X.InRange(levels, lo, hi)
    local n = 0
    for _, l in ipairs(levels) do if l >= lo and l <= hi then n = n + 1 end end
    return n
end
local function drawDungeons(w)
    hideAll("dg")
    if not on("mapDungeons") or not (ns.Groups and ns.Groups.Entrances) then return end
    for _, e in ipairs(ns.Groups.Entrances()) do
        local x, y = tr(e.map, e.x, e.y, w.map)
        if x then
            local d = e.d
            local name = e.alt or d.name or "?"
            local p = take("dg", w.canvas, iconPin)
            style(p, ns.MEDIA .. "icons\\dungeons", C.amber, true, d.lo and (d.lo .. "-" .. (d.hi or d.lo)) or "")
            local tip = { "|cffffd24a" .. name .. "|r" }
            if d.lo then
                tip[#tip + 1] = (L["Level %d-%d"]):format(d.lo, d.hi or d.lo)
                tip[#tip + 1] = "|cff888888" .. (L["%d guild members in level range"]):format(X.InRange(guildLevels(), d.lo, d.hi or d.lo)) .. "|r"
            end
            p.tip = tip
            p.click = function() guideTo(e.map, e.x, e.y, name) end
            put(w, p, x, y, 57)
        end
    end
end

------------------------------------------------------------------------
-- quest givers of dungeon quests in the open world (from QuestLocations; bosses are already shown by the dungeon atlas)
------------------------------------------------------------------------
local giverIdx
function X.QuestGivers(map)
    if not giverIdx then
        if not (ns.QuestLocations and ns.DungeonData) then return {} end
        giverIdx = {}
        local info = {}
        for _, d in ipairs(ns.DungeonData) do
            for _, q in ipairs(d.quests or {}) do info[q.id] = { name = q.name, faction = q.faction, dungeon = d.name } end
        end
        local byKey = {}
        for id, loc in pairs(ns.QuestLocations) do
            local s = loc.start
            if s and s.map and s.x and s.y and not s.inside and info[id] then
                local key = s.map .. ":" .. s.x .. ":" .. s.y
                local g = byKey[key]
                if not g then
                    g = { map = s.map, x = s.x / 100, y = s.y / 100, name = s.npc or s.object or "?", quests = {} }
                    byKey[key] = g
                    giverIdx[s.map] = giverIdx[s.map] or {}
                    table.insert(giverIdx[s.map], g)
                end
                g.quests[#g.quests + 1] = { id = id, name = info[id].name, faction = info[id].faction, dungeon = info[id].dungeon }
            end
        end
    end
    return giverIdx[map] or {}
end
local function drawGivers(w)
    hideAll("qg")
    if not opt("mapQuestGivers") then return end
    local mine = ns.safe(UnitFactionGroup and UnitFactionGroup("player"))
    for _, g in ipairs(X.QuestGivers(w.map)) do
        local tip = { "|cffffd24a" .. g.name .. "|r" }
        for _, q in ipairs(g.quests) do
            if not q.faction or q.faction == "Both" or not mine or q.faction == mine then
                local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and ns.safe(C_QuestLog.GetTitleForQuestID(q.id)) or q.name
                tip[#tip + 1] = (title or q.name or "?") .. "  |cff888888" .. (q.dungeon or L["Dungeon quest"]) .. "|r"
            end
        end
        if #tip > 1 then
            local p = take("qg", w.canvas, function(parent)
                local b = CreateFrame("Button", nil, parent)
                b:SetSize(16, 16)
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetAllPoints()
                b.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
                b:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                b:SetScript("OnClick", function(self) if self.click then self.click() end end)
                return b
            end)
            p.tip = tip
            p.click = function() guideTo(g.map, g.x, g.y, g.name) end
            put(w, p, g.x, g.y, 52)
        end
    end
end

------------------------------------------------------------------------
-- world map: draw everything
------------------------------------------------------------------------
function X.DrawWorld()
    local w = world()
    if not w then
        for name in pairs(pools) do if name ~= "mkm" then hideAll(name) end end
        for i = 1, tUsed do tLines[i]:Hide() end
        tUsed = 0
        return
    end
    pcall(drawDanger, w)
    pcall(drawTrails, w)
    pcall(drawGivers, w)
    pcall(drawDungeons, w)
    pcall(drawMarkers, w)
end

------------------------------------------------------------------------
-- minimap: nearby markers, coordinates, arrow with distance to the target
------------------------------------------------------------------------
local mkList, mkAt, mkMap = {}, -999, nil
local coordF, tArrow
function X.DrawMini()
    local G = ns.Gather
    local c = G and G.MiniCtx and G.MiniCtx()
    hideAll("mkm")
    if not c then
        if coordF then coordF:Hide() end
        if tArrow then tArrow:Hide() end
        return
    end
    -- markers (list rebuilt every 2 s, conversion to your own map cached)
    if on("mapMarkers") then
        local t = GetTime()
        if t - mkAt > 2 or mkMap ~= c.map then
            mkAt, mkMap, mkList = t, c.map, {}
            for _, m in ipairs(X.Markers()) do
                local x, y = tr(m.map, m.x, m.y, c.map)
                if x then mkList[#mkList + 1] = { m = m, x = x, y = y } end
            end
        end
        for _, e in ipairs(mkList) do
            local ox, oy, d = G.MiniPlace(c, e.x, e.y)
            if d < 0.9 and (not ns.MiniPinVisible or ns.MiniPinVisible(ox, oy)) then
                local k = X.KINDS[e.m.kind]
                local p = take("mkm", Minimap, iconPin)
                if ns.MiniPinLayer then ns.MiniPinLayer(p, 3) end
                p:SetScale(0.8)
                style(p, k.icon, k.color, k.tint, "")
                p.rec, p.tip, p.click = e.m, markerTip(e.m), markerMenu
                p:ClearAllPoints()
                p:SetPoint("CENTER", Minimap, "CENTER", ox / 0.8, oy / 0.8)
                p:Show()
            end
        end
    end
    -- target: distance and arrow at the edge
    local tg = ns.Map and ns.Map.FollowTarget and ns.Map.FollowTarget()
    local dist
    if tg and tg.mapID and tg.x and ns.Map.translate then
        local x, y = tg.x, tg.y
        if tg.mapID ~= c.map then x, y = ns.Map.translate(tg.mapID, tg.x, tg.y, c.map) end
        if x and y then
            local ox, oy, d, meters = G.MiniPlace(c, x, y)
            dist = meters
            local len = math.sqrt(ox * ox + oy * oy)
            if d > 0.9 and len > 0 then
                if not tArrow then
                    tArrow = CreateFrame("Frame", nil, Minimap)
                    tArrow:SetSize(18, 18)
                    tArrow:SetFrameLevel(Minimap:GetFrameLevel() + 9)
                    tArrow.sh = tArrow:CreateTexture(nil, "BACKGROUND")
                    tArrow.sh:SetTexture(ns.MEDIA .. "pinarrow")
                    tArrow.sh:SetPoint("TOPLEFT", -3, 3) tArrow.sh:SetPoint("BOTTOMRIGHT", 3, -3)
                    tArrow.sh:SetVertexColor(0, 0, 0, 0.85)
                    tArrow.tex = tArrow:CreateTexture(nil, "ARTWORK")
                    tArrow.tex:SetTexture(ns.MEDIA .. "pinarrow")
                    tArrow.tex:SetAllPoints()
                    tArrow.tex:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
                    tArrow.txt = K.Text(tArrow, 10, C.text, "CENTER")
                    tArrow.txt:SetPoint("TOP", tArrow, "BOTTOM", 0, 1)
                    tArrow.txt:SetShadowOffset(1, -1)
                end
                local ux, uy = ox / len, oy / len
                local atan2 = math.atan2 or math.atan
                tArrow.tex:SetRotation(atan2(-ux, uy))
                tArrow.sh:SetRotation(atan2(-ux, uy))
                tArrow.txt:SetText(math.floor(meters + 0.5) .. " m")
                tArrow:ClearAllPoints()
                tArrow:SetPoint("CENTER", Minimap, "CENTER", ux * c.half * 0.7, uy * c.half * 0.7)
                tArrow:Show()
            elseif tArrow then
                tArrow:Hide()
            end
        elseif tArrow then
            tArrow:Hide()
        end
    elseif tArrow then
        tArrow:Hide()
    end
    -- coordinates below the minimap
    if opt("mmCoords") then
        if not coordF then
            coordF = CreateFrame("Frame", nil, Minimap)
            coordF:SetSize(160, 14)
            coordF:SetPoint("TOP", Minimap, "BOTTOM", 0, -4)
            coordF.t = K.Text(coordF, 11, C.text, "CENTER")
            coordF.t:SetPoint("CENTER")
            coordF.t:SetShadowOffset(1, -1)
        end
        coordF.t:SetText(("%.1f, %.1f"):format(c.mx * 100, c.my * 100)
            .. (dist and ("   |cffe8b44a" .. math.floor(dist + 0.5) .. " m|r") or ""))   -- yellow = distance to target (no word: "target" also means attack target in many languages)
        coordF:Show()
    elseif coordF then
        coordF:Hide()
    end
end

function X.Redraw()
    mkAt = -999
    pcall(X.DrawWorld)
    pcall(X.DrawMini)
end

-- 0.6.379: quick toggle on the world map (top right): dungeon entrances on/off - the same toggle as in
-- Settings > Tooltips & Map > Map. Own button as child of the map, nothing is written on Blizzard's frame.
local dgBtn
local function dgBtnPaint()
    if not dgBtn then return end
    local onNow = on("mapDungeons")
    dgBtn.icon:SetVertexColor(onNow and 1 or 0.45, onNow and 0.82 or 0.45, onNow and 0.3 or 0.45)
    dgBtn.bg:SetColorTexture(0, 0, 0, onNow and 0.55 or 0.35)
end
local function makeDgBtn()
    if dgBtn or not WorldMapFrame then return end
    local host = WorldMapFrame.ScrollContainer or WorldMapFrame
    dgBtn = CreateFrame("Button", nil, WorldMapFrame)
    dgBtn:SetSize(28, 28)
    dgBtn:SetPoint("TOPRIGHT", host, "TOPRIGHT", -8, -8)
    dgBtn:SetFrameLevel((host:GetFrameLevel() or 1) + 400)
    dgBtn.bg = dgBtn:CreateTexture(nil, "BACKGROUND")
    dgBtn.bg:SetAllPoints()
    dgBtn.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    dgBtn.icon = K.Glyph(dgBtn, 16, ns.MEDIA .. "icons\\dungeons", C.text)
    dgBtn.icon:SetPoint("CENTER")
    dgBtn:SetScript("OnClick", function()
        S().mapDungeons = not on("mapDungeons")
        dgBtnPaint()
        X.Redraw()
    end)
    dgBtn:SetScript("OnEnter", function(self)
        K.ShowTip(self, { L["Dungeon entrances"], on("mapDungeons") and L["Click: hide"] or L["Click: show"] })
    end)
    dgBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    dgBtnPaint()
end
ns.Listen("LOGIN", function() pcall(makeDgBtn) end)
if WorldMapFrame then WorldMapFrame:HookScript("OnShow", function() pcall(makeDgBtn) dgBtnPaint() end) end

-- 0.6.486: own routes - click: start/stop recording and save, right-click: show/delete saved ones
local rtBtn
local function rtPaint()
    if not rtBtn then return end
    local shown = false
    for _, r in ipairs(ns.db and ns.db.routes or {}) do if r.show then shown = true break end end
    if X.rec and X.recShow ~= false then shown = true end
    if S().routesOff then shown = false end
    rtBtn.icon:SetVertexColor(shown and 1 or 0.55, shown and 0.82 or 0.55, shown and 0.3 or 0.55)
    rtBtn.bg:SetColorTexture(0, 0, 0, shown and 0.65 or 0.4)
    if not rtBtn.recDot then
        rtBtn.recDot = rtBtn:CreateTexture(nil, "OVERLAY")
        rtBtn.recDot:SetTexture(ns.MEDIA .. "dot")
        rtBtn.recDot:SetSize(7, 7)
        rtBtn.recDot:SetPoint("TOPRIGHT", -2, -2)
        rtBtn.recDot:SetVertexColor(1, 0.3, 0.3)
    end
    rtBtn.recDot:SetShown(X.rec ~= nil)
end
-- 0.6.490: save running recording (auto = on logout, without notice and hidden by default)
function X.SaveRecord(auto)
    local rec = X.rec
    X.rec = nil
    if not rec then return end
    if #rec.pts >= 2 then
        ns.db.routes = ns.db.routes or {}
        table.insert(ns.db.routes, 1, { name = (L["Route %s"]):format(date("%d.%m. %H:%M")), ts = time(), pts = rec.pts, show = (not auto) or nil })
        while #ns.db.routes > 30 do table.remove(ns.db.routes) end
        if not auto then K.Toast(L["Route saved"], (L["%d points - right-click the button to show all routes"]):format(#rec.pts), C.mint) end
    elseif not auto then
        K.Toast(L["Route discarded"], L["Too short - walk a bit while recording."], C.dim)
    end
end
function X.ToggleRecord()
    if X.rec then
        X.SaveRecord(false)
        -- automatic recording: start the next route right away
        X.rec = { pts = {} }   -- 0.6.502: always keep recording right away
    else
        X.rec = { pts = {} }
        pcall(X.SampleTrails)
        K.Toast(L["Recording route"], L["Start walking - click again to save the route."], C.accent)
    end
    rtPaint()
    local w = world() if w then pcall(drawTrails, w) end
end
local function makeRtBtn()
    if rtBtn or not dgBtn then return end
    rtBtn = CreateFrame("Button", nil, WorldMapFrame)
    rtBtn:SetSize(28, 28)
    rtBtn:SetPoint("TOP", dgBtn, "BOTTOM", 0, -6)
    rtBtn:SetFrameLevel(dgBtn:GetFrameLevel())
    rtBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    rtBtn.bg = rtBtn:CreateTexture(nil, "BACKGROUND")
    rtBtn.bg:SetAllPoints()
    rtBtn.bg:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    rtBtn.icon = K.Glyph(rtBtn, 16, ns.MEDIA .. "icons\\map", C.text)
    rtBtn.icon:SetPoint("CENTER")
    rtBtn:SetScript("OnClick", function(self, btn)
        -- 0.6.493: left-click = show all routes / hide all; recording is in the right-click menu
        local list = ns.db.routes or {}
        -- 0.6.501: left-click turns routes off completely (hide + stop recording, the running one gets saved)
        -- or back on (show all + start recording); state persists across /reload
        if btn ~= "RightButton" then
            -- 0.6.502: recording always runs - the click only shows or hides the lines
            S().routesOff = (not S().routesOff) or nil
            if not S().routesOff then
                for _, r in ipairs(list) do r.show = true end
                X.recShow = true
            end
            rtPaint()
            local w = world() if w then pcall(drawTrails, w) end
            return
        end
        local items = {
            { text = X.rec and L["Save recording"] or L["Start recording"], fn = function() X.ToggleRecord() end },
        }
        for i, r in ipairs(ns.db.routes or {}) do
            items[#items + 1] = { text = r.name or "?", checked = r.show and true or false, fn = function()
                r.show = not r.show or nil
                local w = world() if w then pcall(drawTrails, w) end
            end }
        end
        if #items == 0 then items[1] = { text = L["No routes saved yet"], disabled = true } end
        if ns.db.routes and #ns.db.routes > 0 then
            items[#items + 1] = { text = L["Hide all"], fn = function()
                for _, r in ipairs(ns.db.routes) do r.show = nil end
                local w = world() if w then pcall(drawTrails, w) end
            end }
            items[#items + 1] = { text = "|cffff6060" .. L["Delete newest route"] .. "|r", fn = function()
                table.remove(ns.db.routes, 1)
                local w = world() if w then pcall(drawTrails, w) end
            end }
        end
        K.ShowMenu(self, items, L["My routes"], 200)
    end)
    rtBtn:SetScript("OnEnter", function(self)
        K.ShowTip(self, { L["My routes"], (S().routesOff and L["Click: show lines"] or L["Click: hide lines"]), L["Right-click: single routes, recording, delete"],
            X.rec and ("|cffff6060" .. L["Recording"] .. "|r") or nil })
    end)
    rtBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rtPaint()
end
ns.Listen("LOGIN", function()
    ns.After(1, function() pcall(makeRtBtn) end)
    -- 0.6.490: routes are recorded automatically by default and saved on logout
    -- 0.6.491: running recording survives /reload and short logouts (under 30 min) - otherwise it is stored as a route
    local cur = ns.db.curRoute
    ns.db.curRoute = nil
    if cur and cur.pts and #cur.pts > 0 then
        if time() - (cur.t or 0) < 1800 then
            X.rec = { pts = cur.pts }
        else
            X.rec = { pts = cur.pts }
            pcall(X.SaveRecord, true)
        end
    end
    if not X.rec then X.rec = { pts = {} } end   -- 0.6.502: recording always active
end)
ns.On("PLAYER_LOGOUT", function()
    if X.rec and #X.rec.pts > 0 then ns.db.curRoute = { pts = X.rec.pts, t = time() } end
end)
if WorldMapFrame then WorldMapFrame:HookScript("OnShow", function() pcall(makeRtBtn) rtPaint() end) end

------------------------------------------------------------------------
-- Visited vendors, repair, mailboxes, flight points -> gathering map (kinds with poi = true)
------------------------------------------------------------------------
local function npcName()
    local n = UnitName and UnitName("npc")
    return ns.safe(n) or ""
end
local function visit(kind, name)
    local G = ns.Gather
    if G and G.Record and S().mapPoi ~= false then pcall(G.Record, kind, name) end
end
ns.On("MERCHANT_SHOW", function() visit((CanMerchantRepair and ns.safe(CanMerchantRepair())) and "repair" or "vendor", npcName()) end)
ns.On("MAIL_SHOW", function() visit("mail", "") end)
ns.On("TAXIMAP_OPENED", function() visit("flight", npcName()) end)

------------------------------------------------------------------------
-- wiring
------------------------------------------------------------------------
ns.Listen("LOGIN", function()
    -- 0.5.984: danger zones are off by default (once also for everyone who already had them on)
    if not S().dangerOffV1 then S().dangerOffV1 = true S().mapDanger = false end
    if ns.Map and ns.Map.UpdateWorldPins then hooksecurefunc(ns.Map, "UpdateWorldPins", function() pcall(X.DrawWorld) end) end
    if WorldMapFrame then WorldMapFrame:HookScript("OnHide", function() X.StopPlacing() end) end
    local f, acc, tacc = CreateFrame("Frame"), 0, 0
    f:SetScript("OnUpdate", function(_, el)
        acc, tacc = acc + el, tacc + el
        if acc >= 0.05 then
            acc = 0
            pcall(X.DrawMini)
        end
        -- 0.6.505: with the world map open measure and draw every second (tail follows immediately), otherwise every 4 s
        local wm = WorldMapFrame and WorldMapFrame:IsShown()
        if tacc >= (wm and 1 or 4) then
            tacc = 0
            local w = world()
            pcall(X.SampleTrails)
            if w then pcall(drawTrails, w) end   -- 0.6.490: also for routes (drawTrails checks itself)
        end
    end)
end)
ns.Listen("STORE", function(coll, rec, old)
    if coll == "markers" then
        X.Redraw()
        if rec and not old and not rec.del and rec.kind == "meet" and not ns.demoLoading and on("mapMarkers")
            and not ns.isMe(rec.by) and ns.now() - (rec.ts or 0) < 120 and validMarker(rec) then
            K.Toast(L["New meeting point"], ns.displayName(rec.by or "?") .. ((rec.text or "") ~= "" and (": " .. clean(rec.text, 60)) or ""), C.mint,
                function() if ns.Map and ns.Map.ShowOnWorldMap then ns.Map.ShowOnWorldMap(rec.map) end end)
        end
    elseif coll == "deaths" then
        local w = world()
        if w then pcall(drawDanger, w) end
    end
end)

------------------------------------------------------------------------
-- Layer switcher (0.5.937). An addon cannot switch layers itself - that only works via a group:
-- whoever gets invited lands on the inviter's layer. Oasis shows who from the guild in the same zone is on
-- another layer, and asks for an invite with one click. The other gets a notice and invites with a
-- click - never automatically.
------------------------------------------------------------------------
local Comm = ns.Comm
local askAt, askedBy = {}, {}
-- members in your own zone with known layer: { name, layer, same }
function X.LayerList()
    local M = ns.Map
    local out = {}
    if not M then return out end
    local G = ns.Gather
    local c = G and G.MiniCtx and G.MiniCtx()
    local myMap = c and c.map or (C_Map and C_Map.GetBestMapForUnit and ns.safe(C_Map.GetBestMapForUnit("player")))
    local now = GetTime()
    for name, p in pairs(M.pos) do
        if p.layer and p.mapID == myMap and now - (p.t or 0) < 150 and not ns.isMe(name) then
            out[#out + 1] = { name = name, layer = tostring(p.layer), same = M.myLayer ~= nil and tostring(p.layer) == tostring(M.myLayer) }
        end
    end
    table.sort(out, function(a, b) if a.same ~= b.same then return not a.same end if a.layer ~= b.layer then return a.layer < b.layer end return a.name < b.name end)
    return out
end
function X.AskLayer(name)
    local now = GetTime()
    if askAt[name] and now - askAt[name] < 20 then return false end
    askAt[name] = now
    if Comm and Comm.Whisper then Comm.Whisper(name, "LAYERQ") end
    ns.print((L["Request sent to %s. If accepted, you switch to their layer with the group."]):format(ns.displayName(name)))
    return true
end
function X.LayerMenuItems()
    local M = ns.Map
    local items = {}
    if M and M.myLayer then
        items[#items + 1] = { text = "|cffaaaaaa" .. (L["Your layer: %s"]):format(tostring(M.myLayer)) .. "|r", disabled = true }
    else
        items[#items + 1] = { text = "|cffe8b44a" .. L["Your layer is still unknown - briefly target an NPC."] .. "|r", disabled = true }
    end
    local other = 0
    for _, e in ipairs(X.LayerList()) do
        local label = (L["Layer %s"]):format(e.layer) .. "  ·  " .. ns.displayName(e.name)
        if e.same then
            items[#items + 1] = { text = "|cff888888" .. label .. "  (" .. L["same layer"] .. ")|r", disabled = true }
        else
            other = other + 1
            items[#items + 1] = { text = (L["Ask for an invite: %s"]):format(label), fn = function() X.AskLayer(e.name) end }
        end
    end
    if other == 0 then items[#items + 1] = { text = L["No guild member in this zone is on a different layer."], disabled = true } end
    return items
end
if Comm and Comm.On then
    Comm.On("LAYERQ", function(sender)
        if type(sender) ~= "string" or S().layerAsk == false or ns.isMe(sender) then return end
        if Comm.FromGuild and not Comm.FromGuild(sender) then return end
        local now = GetTime()
        if askedBy[sender] and now - askedBy[sender] < 30 then return end   -- at most one notice per sender in 30 s
        askedBy[sender] = now
        K.Toast(L["Layer switch"], (L["%s wants to join your layer. Click to invite to the group."]):format(ns.displayName(sender)), C.accent, function()
            if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, ns.ChatName and ns.ChatName(sender) or sender) end
        end)
    end)
end
end)

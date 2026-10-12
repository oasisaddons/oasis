-- Oasis - Buff-Monitor als eigener Reiter: wer hat welche Buffs, was fehlt, wer kann es geben
-- Glas 2026: vorhandene Buffs als Symbol, fehlende als ruhige leere Felder; Rot nur, wo es zaehlt
-- (fehlt allen bzw. du kannst es selbst beheben). Klick auf ein fehlendes Feld fragt den Verteiler.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

if ns.ICONS then ns.ICONS.buffs = ns.MEDIA .. "icons\\badges\\buffer" end

local RH, NAMEW, CNTW = 28, 150, 46
local CLASSNAME = { PRIEST = "Priester", MAGE = "Magier", DRUID = "Druide", PALADIN = "Paladin", SHAMAN = "Schamane" }
local CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local SOON = 120
local GLINE = { 1, 1, 1, 0.10 }
local view = "all"       -- "all" | "missing" | "mine"
local off = 0            -- Scroll-Versatz der Zeilen

local function glass(f, r, a, line)
    local IG = ns.Insta
    if IG and IG.Glass then IG.Glass(f, { 1, 1, 1, a or 0.03 }, line or GLINE, r or 12) end
end
local function animOn() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
local function hexOf(c) return ("|cff%02x%02x%02x"):format((c[1] or 1) * 255, (c[2] or 1) * 255, (c[3] or 1) * 255) end
local function clsHex(cls)
    local r, g, b = ns.classColor(cls)
    return hexOf({ r or 0.8, g or 0.8, b or 0.8 })
end
local function classIcon(tex, cls)
    local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
    if tc then tex:SetTexture(CIRCLES) tex:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) tex:Show() else tex:Hide() end
end
local function myClass() local _, c = UnitClass("player") return c end
local function isMine(b, info) return (info.mine and info.mine[b.key]) or (b.cls and b.cls == myClass()) end

-- Kennzahl als Glaskarte
local function tile(parent, label, col)
    local t = CreateFrame("Frame", nil, parent)
    t:SetHeight(62)
    glass(t, 12)
    t.v = K.Title(t, 22, C.text)
    t.v:SetPoint("TOPLEFT", 14, -10)
    t.sub = K.Text(t, 11, C.dim)
    t.sub:SetPoint("BOTTOMLEFT", t.v, "BOTTOMRIGHT", 8, 3)
    t.l = K.Text(t, 11, C.muted)
    t.l:SetPoint("BOTTOMLEFT", 14, 10)
    t.l:SetText(label)
    t.col = col
    t.track = t:CreateTexture(nil, "ARTWORK")
    t.track:SetColorTexture(1, 1, 1, 0.06)
    t.track:SetHeight(2)
    t.track:SetPoint("BOTTOMLEFT", 12, 3)
    t.track:SetPoint("BOTTOMRIGHT", -12, 3)
    t.fill = t:CreateTexture(nil, "ARTWORK", nil, 1)
    t.fill:SetHeight(2)
    t.fill:SetPoint("LEFT", t.track, "LEFT")
    t.track:Hide() t.fill:Hide()
    function t:Set(v, sub, pct, vc)
        local key = tostring(v)
        if self.last ~= key then
            local n = tonumber(v)
            if n and animOn() and self.last ~= nil then K.CountUp(self.v, n, 0.4) else self.v:SetText(v) end
            self.last = key
        end
        local c = vc or self.col
        self.v:SetTextColor(c[1], c[2], c[3])
        self.sub:SetText(sub or "")
        self.track:SetShown(pct ~= nil)
        self.fill:SetShown(pct ~= nil and pct > 0)
        if pct then
            local w = math.max(1, ((self:GetWidth() or 200) - 24) * math.max(0, math.min(1, pct)))
            self.fill:SetColorTexture(c[1], c[2], c[3], 0.8)
            if animOn() and self.lastPct ~= pct and K.Tween then
                local from = self.fill:GetWidth() or 1
                K.Tween(self.fill, 0.4, function(q) self.fill:SetWidth(math.max(1, from + (w - from) * q)) end, function() self.fill:SetWidth(w) end)
            else
                self.fill:SetWidth(w)
            end
            self.lastPct = pct
        end
    end
    return t
end

ns.RegisterPage({
    key = "buffs", title = "Buff-Monitor", order = 2.75,
    sub = "Wer in Gruppe oder Raid welche Buffs hat - und wer das Fehlende geben kann",
    build = function(p)
        local BM = ns.BuffMonitor
        p.tiles = {
            tile(p, L["Abdeckung"], C.mint),
            tile(p, L["Fehlende Buffs"], C.amber),
            tile(p, L["Laufen bald ab"], C.blue),
        }
        p:HookScript("OnSizeChanged", function(self, w)
            local tw = math.floor(((w or 750) - 20) / 3)
            for i, t in ipairs(self.tiles) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", (i - 1) * (tw + 10), 0)
                t:SetWidth(tw)
            end
            if self.built then ns.RefreshPage("buffs") end
        end)

        -- Filter links, Aktionen rechts
        p.seg = K.Segments(p, { { key = "all", text = L["Alle"] }, { key = "missing", text = L["Nur fehlende"] }, { key = "mine", text = L["Meine Buffs"] } },
            function(k) view = k off = 0 p.fresh = true ns.RefreshPage("buffs") end, nil, { size = 12, pad = 16 })
        p.seg:SetPoint("TOPLEFT", 0, -74)
        p.floatBtn = K.Button(p, L["Schwebendes Fenster"], 150, 24, "ghost", function() if BM then BM.Toggle() end ns.RefreshPage("buffs") end)
        p.floatBtn:SetPoint("TOPRIGHT", 0, -74)
        p.postBtn = K.Button(p, L["Fehlende melden"], 130, 24, "ghost", function() if BM then BM.Post() end end)
        p.postBtn:SetPoint("RIGHT", p.floatBtn, "LEFT", -8, 0)
        for _, b in ipairs({ p.floatBtn, p.postBtn }) do b.label:SetFont(K.FONT, 11, "") end
        p.postBtn:HookScript("OnEnter", function(self) K.ShowTip(self, { L["Fehlende melden"], L["Schreibt die fehlenden Buffs in den Gruppen- bzw. Raidchat."] }) end)
        p.postBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

        -- Tabelle
        local tab = CreateFrame("Frame", nil, p)
        glass(tab, 14, 0.025)
        tab:SetPoint("TOPLEFT", 0, -108)
        tab:SetPoint("BOTTOMRIGHT", 0, 30)
        tab:EnableMouseWheel(true)
        tab:SetScript("OnMouseWheel", function(_, d) off = math.max(0, off - d * 3) ns.RefreshPage("buffs") end)
        p.tab = tab
        tab.title = K.Title(tab, 13, C.text)
        tab.title:SetPoint("TOPLEFT", 16, -14)
        tab.sum = K.Text(tab, 11, C.dim)
        tab.sum:SetPoint("LEFT", tab.title, "RIGHT", 10, -1)
        tab.legend = K.Text(tab, 10, C.dim, "RIGHT")
        tab.legend:SetPoint("TOPRIGHT", -16, -16)
        tab.legend:SetText("|cffe8b44a■|r " .. L["kannst du geben"] .. "     |cff6aa0ff●|r " .. L["laeuft bald ab"] .. "     " .. L["Klick auf ein leeres Feld: Verteiler fragen"])
        tab.heads, tab.rows, tab.info = {}, {}, {}
        tab.note = K.Text(tab, 12, C.muted, "CENTER")
        tab.note:SetPoint("TOP", 0, -48)
        tab.note:SetWidth(520)
        tab.note:SetWordWrap(true)
        tab.more = K.Text(tab, 10, C.dim, "CENTER")

        -- unten: was du tun kannst
        p.todo = CreateFrame("Frame", nil, p)
        p.todo:SetPoint("BOTTOMLEFT", 0, 0)
        p.todo:SetPoint("BOTTOMRIGHT", -330, 0)
        p.todo:SetHeight(24)
        p.todo.t = K.Text(p.todo, 12, C.text)
        p.todo.t:SetPoint("LEFT", 2, 0)
        p.todo.t:SetPoint("RIGHT", 0, 0)
        p.todo.t:SetWordWrap(false)
        p.todo:EnableMouse(true)
        p.todo:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
        p.todo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.auto = K.Toggle(p, L["Beim Gruppenbeitritt automatisch einblenden"],
            function() return ns.db.settings.buffAuto end,
            function(v) ns.db.settings.buffAuto = v end)
        p.auto:SetPoint("BOTTOMRIGHT", 0, 2)
        p.fresh, p.built = true, true
        p:HookScript("OnShow", function(self) self.fresh = true end)
    end,
    refresh = function(p)
        local BM = ns.BuffMonitor
        if not BM then return end
        local tab = p.tab
        local list, cols, missing, total, done, info = BM.Scan()
        info = info or { providers = {}, mine = {}, soon = 0 }
        local inGroup = #list > 1
        local pct = total > 0 and done / total or (inGroup and 1 or 0)
        local nMiss = total - done
        local pc = pct >= 1 and C.mint or (pct >= 0.7 and C.amber or C.red)
        p.tiles[1]:Set(inGroup and (math.floor(pct * 100) .. " %") or "–", inGroup and (done .. " / " .. total) or nil, inGroup and pct or nil, inGroup and pc or C.dim)
        p.tiles[2]:Set(inGroup and nMiss or "–", inGroup and ((L["bei %d Spielern"]):format(math.max(0, (info.players or 0) - (info.complete or 0)))) or nil, nil,
            (inGroup and nMiss > 0) and C.amber or C.dim)
        p.tiles[3]:Set(inGroup and (info.soon or 0) or "–", inGroup and L["unter 2 Min"] or nil, nil, (inGroup and (info.soon or 0) > 0) and C.blue or C.dim)
        -- ohne Gruppe standen dort drei Striche: Kacheln nur zeigen, wenn es Werte gibt
        for _, t in ipairs(p.tiles) do t:SetShown(inGroup) end
        p.seg:Select(view)
        p.postBtn:SetEnabled(inGroup and nMiss > 0)
        p.auto:Refresh()
        local shown = _G.OasisBuffMonitor and _G.OasisBuffMonitor:IsShown()
        p.floatBtn.label:SetText(shown and L["Fenster aus"] or L["Schwebendes Fenster"])

        for _, h in ipairs(tab.heads) do h:Hide() end
        for _, r in ipairs(tab.rows) do r:Hide() end
        for _, x in ipairs(tab.info) do x:Hide() end
        tab.more:Hide()
        tab.title:SetText((IsInRaid and IsInRaid()) and L["Schlachtzug"] or L["Gruppe"])
        tab.sum:SetText(inGroup and #cols > 0 and ((L["%d Spieler"]):format(#list)) or "")
        tab.legend:SetShown(inGroup and #cols > 0)

        -- ohne Gruppe: welche Klasse verteilt welchen Buff
        if not inGroup or #cols == 0 then
            p.todo.t:SetText("")
            p.todo.tip = nil
            tab.note:SetText(not inGroup and L["Du bist in keiner Gruppe. Sobald du in einer Gruppe oder einem Raid bist, siehst du hier, wem welcher Buff fehlt und wer ihn geben kann."]
                or L["Keine Klasse in der Gruppe, die diese Buffs verteilt."])
            tab.note:Show()
            BM.Prep()
            local W = tab:GetWidth() or 700
            if W < 100 then W = 700 end
            local cw = math.floor((W - 48) / 2)
            for i, b in ipairs(BM.BUFFS) do
                local x = tab.info[i]
                if not x then
                    x = CreateFrame("Frame", nil, tab)
                    x:SetHeight(34)
                    glass(x, 9, 0.025)
                    x.icon = x:CreateTexture(nil, "ARTWORK")
                    x.icon:SetSize(22, 22)
                    x.icon:SetPoint("LEFT", 8, 0)
                    x.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    x.t = K.Text(x, 12, C.text)
                    x.t:SetPoint("LEFT", x.icon, "RIGHT", 10, 0)
                    x.c = x:CreateTexture(nil, "ARTWORK")
                    x.c:SetSize(16, 16)
                    x.c:SetPoint("RIGHT", -10, 0)
                    x.w = K.Text(x, 11, C.muted, "RIGHT")
                    x.w:SetPoint("RIGHT", x.c, "LEFT", -6, 0)
                    tab.info[i] = x
                end
                local col, rowI = (i - 1) % 2, math.floor((i - 1) / 2)
                x:ClearAllPoints()
                x:SetPoint("TOPLEFT", tab, "TOPLEFT", 16 + col * (cw + 16), -96 - rowI * 40)
                x:SetWidth(cw)
                if b.icon then x.icon:SetTexture(b.icon) end
                x.t:SetText(b.label or b.short)
                if b.cons then
                    x.c:Hide()
                    x.w:SetText(L["Verbrauchsgut"])
                    x.w:ClearAllPoints() x.w:SetPoint("RIGHT", -10, 0)
                else
                    classIcon(x.c, b.cls)
                    x.w:ClearAllPoints() x.w:SetPoint("RIGHT", x.c, "LEFT", -6, 0)
                    x.w:SetText(clsHex(b.cls) .. L[CLASSNAME[b.cls] or b.cls or "?"] .. "|r")
                end
                x:Show()
            end
            p.fresh = nil
            return
        end
        tab.note:Hide()

        -- Spalten nach Filter
        local my = {}
        for _, b in ipairs(cols) do if isMine(b, info) then my[b.key] = true end end
        local vcols = {}
        for _, b in ipairs(cols) do if view ~= "mine" or my[b.key] then vcols[#vcols + 1] = b end end
        local active = 0
        for _, r in ipairs(list) do if not r.away and not r.dead then active = active + 1 end end
        -- Zeilen nach Filter
        local vrows = {}
        for _, r in ipairs(list) do
            local miss = 0
            for _, b in ipairs(vcols) do if not b.soft and not r.has[b.key] then miss = miss + 1 end end
            r.vmiss = miss
            if view == "all" or (miss > 0 and not r.away and not r.dead) then vrows[#vrows + 1] = r end
        end

        local W = tab:GetWidth() or 720
        if W < 200 then W = 720 end
        local n = math.max(1, #vcols)
        local CW = math.max(34, math.min(64, math.floor((W - 32 - NAMEW - CNTW) / n)))
        local x0 = 16 + NAMEW
        local now = GetTime and GetTime() or 0

        -- Spaltenkoepfe: Symbol, Name, "fehlt N", wer es geben kann
        for j, b in ipairs(vcols) do
            local h = tab.heads[j]
            if not h then
                h = CreateFrame("Frame", nil, tab)
                h:SetHeight(64)
                h.icon = h:CreateTexture(nil, "ARTWORK")
                h.icon:SetSize(24, 24)
                h.icon:SetPoint("TOP", 0, 0)
                h.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                h.name = K.Text(h, 10, C.muted, "CENTER")
                h.name:SetPoint("TOP", h.icon, "BOTTOM", 0, -4)
                h.name:SetWordWrap(false)
                h.n = K.Text(h, 10, C.text, "CENTER")
                h.n:SetPoint("TOP", h.name, "BOTTOM", 0, -2)
                h.prov = {}
                for k = 1, 3 do
                    local t = h:CreateTexture(nil, "ARTWORK")
                    t:SetSize(12, 12)
                    h.prov[k] = t
                end
                h:EnableMouse(true)
                h:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
                h:SetScript("OnLeave", function() GameTooltip:Hide() end)
                tab.heads[j] = h
            end
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", tab, "TOPLEFT", x0 + (j - 1) * CW, -40)
            h:SetWidth(CW)
            h.name:SetWidth(CW - 2)
            if b.icon then h.icon:SetTexture(b.icon) end
            h.icon:SetAlpha(b.soft and 0.6 or 1)
            h.name:SetText(L[b.short] or b.short)
            local m = missing[b.key] or 0
            local all = active > 0 and m >= active
            if b.soft then h.n:SetText("|cff777777" .. L["Hinweis"] .. "|r")
            elseif m == 0 then h.n:SetText("|cff66db9e" .. L["ok"] .. "|r")
            else h.n:SetText((all and "|cffff5a4a" or "|cffe8b44a") .. (L["fehlt %d"]):format(m) .. "|r") end
            -- Verteiler (Klasse) unter dem Kopf; Verbrauchsgut ohne
            local provs = info.providers and info.providers[b.key] or {}
            for k, t in ipairs(h.prov) do
                if not b.cons and provs[k] then
                    classIcon(t, b.cls)
                    t:ClearAllPoints()
                    local cnt = math.min(3, #provs)
                    t:SetPoint("BOTTOM", h, "BOTTOM", (k - (cnt + 1) / 2) * 13, 0)
                else
                    t:Hide()
                end
            end
            local who = {}
            for _, r in ipairs(list) do if not r.has[b.key] and not r.away and not r.dead then who[#who + 1] = ns.displayName(r.name) end end
            local pn = {}
            for _, nm in ipairs(provs) do pn[#pn + 1] = ns.displayName(nm) end
            h.tip = { b.label or b.short,
                m > 0 and ((L["fehlt bei %d"]):format(m) .. ": " .. table.concat(who, ", ")) or L["alle haben ihn"],
                b.cons and ("|cff888888" .. L["Verbrauchsgut - jeder selbst"] .. "|r")
                    or (#pn > 0 and ("|cff888888" .. L["Geben kann: "] .. "|r" .. table.concat(pn, ", ")) or ("|cff888888" .. L["Niemand in der Gruppe kann ihn geben"] .. "|r")),
                my[b.key] and ("|cffe8b44a" .. L["Du kannst ihn geben"] .. "|r") or nil }
            h:Show()
        end

        -- Zeilen
        local top = -112
        local avail = (tab:GetHeight() or 400) + top - 12
        local maxRows = math.max(3, math.floor(avail / RH))
        off = math.max(0, math.min(off, math.max(0, #vrows - maxRows)))
        for i = 1, math.min(maxRows, #vrows - off) do
            local m = vrows[i + off]
            local r = tab.rows[i]
            if not r then
                r = CreateFrame("Frame", nil, tab)
                r:SetHeight(RH - 2)
                r.card = CreateFrame("Frame", nil, r)
                r.card:SetAllPoints()
                glass(r.card, 8, 0, { 1, 1, 1, 0 })
                r.ci = r:CreateTexture(nil, "ARTWORK")
                r.ci:SetSize(16, 16)
                r.ci:SetPoint("LEFT", 6, 0)
                r.name = K.Text(r, 12, C.text)
                r.name:SetPoint("LEFT", 28, 0)
                r.name:SetWidth(NAMEW - 30)
                r.name:SetWordWrap(false)
                r.cnt = K.Text(r, 11, C.muted, "RIGHT")
                r.cnt:SetPoint("RIGHT", -8, 0)
                r.cells = {}
                r:EnableMouse(true)
                r:SetScript("OnEnter", function(self) glass(self.card, 8, 0.04, { 1, 1, 1, 0.06 }) end)
                r:SetScript("OnLeave", function(self) glass(self.card, 8, 0, { 1, 1, 1, 0 }) end)
                tab.rows[i] = r
            end
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", tab, "TOPLEFT", 10, top - (i - 1) * RH)
            r:SetPoint("RIGHT", tab, "RIGHT", -10, 0)
            classIcon(r.ci, m.class)
            local tag = m.away and ("  |cff777777" .. L["offline"] .. "|r") or (m.dead and ("  |cff777777" .. L["tot"] .. "|r") or "")
            r.name:SetText(clsHex(m.class) .. ns.displayName(m.name) .. "|r" .. tag)
            r:SetAlpha((m.away or m.dead) and 0.45 or 1)
            for _, c in pairs(r.cells) do c:Hide() end
            local have, cnt = 0, 0
            for j, b in ipairs(vcols) do
                local c = r.cells[j]
                if not c then
                    c = CreateFrame("Button", nil, r)
                    c:SetSize(22, 22)
                    glass(c, 5, 0.04)
                    c.icon = c:CreateTexture(nil, "ARTWORK")
                    c.icon:SetPoint("TOPLEFT", 1, -1) c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
                    c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    c.soon = c:CreateTexture(nil, "OVERLAY")
                    c.soon:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                    c.soon:SetSize(7, 7)
                    c.soon:SetPoint("TOPRIGHT", 2, 2)
                    c.soon:SetVertexColor(C.blue[1], C.blue[2], C.blue[3])
                    c:SetScript("OnEnter", function(self)
                        r:GetScript("OnEnter")(r)
                        if self.tip then K.ShowTip(self, self.tip) end
                    end)
                    c:SetScript("OnLeave", function() r:GetScript("OnLeave")(r) GameTooltip:Hide() end)
                    c:SetScript("OnClick", function(self) if self.act then self.act() end end)
                    r.cells[j] = c
                end
                c:ClearAllPoints()
                c:SetPoint("LEFT", r, "LEFT", x0 - 10 + (j - 1) * CW + (CW - 22) / 2, 0)
                local has = m.has[b.key]
                if not b.soft then cnt = cnt + 1 if has then have = have + 1 end end
                local exp = m.exp and m.exp[b.key]
                local left = exp and (exp - now) or nil
                c.soon:SetShown(has and left ~= nil and left < SOON and left > 0 or false)
                c.act = nil
                if has then
                    if b.icon then c.icon:SetTexture(b.icon) end
                    c.icon:Show()
                    c.icon:SetDesaturated(false)
                    c.icon:SetAlpha(b.soft and 0.6 or 1)
                    glass(c, 5, 0.04)
                    c.tip = { b.label or b.short, left and left > 0 and ((L["noch %d Min"]):format(math.ceil(left / 60))) or L["aktiv"] }
                else
                    -- fehlt: leeres Feld; deins = Bernstein-Rand, fehlt allen = roter Rand
                    c.icon:Hide()
                    local all = active > 0 and (missing[b.key] or 0) >= active
                    local line = (m.away or m.dead or b.soft) and GLINE or (my[b.key] and { C.amber[1], C.amber[2], C.amber[3], 0.8 })
                        or (all and { C.red[1], C.red[2], C.red[3], 0.55 }) or GLINE
                    glass(c, 5, 0.025, line)
                    local provs = info.providers and info.providers[b.key] or {}
                    local giver
                    for _, nm in ipairs(provs) do if not ns.isMe(nm) then giver = nm break end end
                    local tip = { (b.label or b.short) .. "  |cff888888" .. L["fehlt"] .. "|r" }
                    if my[b.key] then
                        tip[#tip + 1] = "|cffe8b44a" .. L["Du kannst ihn geben"] .. "|r"
                    elseif b.cons then
                        tip[#tip + 1] = "|cff888888" .. L["Verbrauchsgut - jeder selbst"] .. "|r"
                        if not ns.isMe(m.name) and not m.away then
                            tip[#tip + 1] = "|cff888888" .. L["Klick: freundlich erinnern"] .. "|r"
                            c.act = function() ns.Whisper(m.name, (L["Kleiner Hinweis: dir fehlt noch %s."]):format(b.label or b.short)) end
                        end
                    elseif giver then
                        tip[#tip + 1] = "|cff888888" .. (L["Klick: %s fragen"]):format(ns.displayName(giver)) .. "|r"
                        c.act = function() ns.Whisper(giver, (L["Kannst du %s %s geben? Danke!"]):format(ns.displayName(m.name), b.label or b.short)) end
                    else
                        tip[#tip + 1] = "|cff888888" .. L["Niemand in der Gruppe kann ihn geben"] .. "|r"
                    end
                    c.tip = tip
                end
                c:Show()
            end
            r.cnt:SetText((have == cnt and "|cff66db9e" or (have == 0 and "|cffff5a4a" or "|cffe8b44a")) .. have .. "/" .. cnt .. "|r")
            r:Show()
            if p.fresh and K.FadeIn and i <= 14 then r.oasisFadedAt = nil K.FadeIn(r, i * 0.025) end
        end
        if #vrows > maxRows then
            tab.more:ClearAllPoints()
            tab.more:SetPoint("BOTTOM", tab, "BOTTOM", 0, 4)
            tab.more:SetText((L["%d-%d von %d  ·  Mausrad scrollt"]):format(off + 1, math.min(#vrows, off + maxRows), #vrows))
            tab.more:Show()
        end
        if #vrows == 0 then
            tab.note:SetText(view == "mine" and L["Deine Buffs sind bei allen drauf."] or L["Allen fehlt nichts - bereit fuer den Pull."])
            tab.note:ClearAllPoints()
            tab.note:SetPoint("TOP", 0, -130)
            tab.note:Show()
        else
            tab.note:ClearAllPoints()
            tab.note:SetPoint("TOP", 0, -48)
        end

        -- unten: was du tun kannst
        local todo, tip = {}, { L["Was du tun kannst"] }
        local provides = false
        for _, b in ipairs(cols) do
            if my[b.key] then
                provides = true
                if (missing[b.key] or 0) > 0 then
                    local who = {}
                    for _, r in ipairs(list) do if not r.has[b.key] and not r.away and not r.dead then who[#who + 1] = ns.displayName(r.name) end end
                    todo[#todo + 1] = "|cffe8b44a" .. (b.label or b.short) .. "|r " .. (L["bei %d"]):format(#who)
                    tip[#tip + 1] = "|cffe8b44a" .. (b.label or b.short) .. ":|r " .. table.concat(who, ", ")
                end
            end
        end
        if #todo > 0 then
            p.todo.t:SetText(L["Du kannst geben:"] .. "  " .. table.concat(todo, "   ·   "))
            p.todo.tip = tip
        elseif provides then
            p.todo.t:SetText("|cff66db9e" .. L["Deine Buffs sind bei allen drauf."] .. "|r")
            p.todo.tip = nil
        else
            p.todo.t:SetText("|cff888888" .. L["Du verteilst in dieser Gruppe keine Buffs."] .. "|r")
            p.todo.tip = nil
        end
        p.fresh = nil
    end,
})

-- aktuell halten, solange der Reiter offen ist (gedrosselt)
local pending
local function soon()
    if pending then return end
    pending = true
    ns.After(0.6, function()
        pending = false
        if ns.CurrentPage and ns.CurrentPage() == "buffs" then ns.RefreshPage("buffs") end
    end)
end
ns.On("UNIT_AURA", function(u)
    if ns.CurrentPage and ns.CurrentPage() == "buffs" and u and (u == "player" or u:find("^party") or u:find("^raid")) then soon() end
end)
ns.On("GROUP_ROSTER_UPDATE", soon)
ns.On("PLAYER_REGEN_ENABLED", soon)

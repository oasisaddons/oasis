-- Oasis: switch tile (0.6.656) - the tile look of the comfort pages for every settings tab: glass card, icon,
-- title, short explanation, switch on the right. Soft hover, press, the knob glides; children are indented with a
-- tree line and greyed while their parent is off.
local ADDON, ns = ...
local K, C = ns.K, ns.K.C

local INDENT = 26
K.TILE_INDENT = INDENT

-- o = { title, desc, icon, glyph (true = flat Oasis icon, tinted), tint, get, set, child (indent), usable (fn),
--       gear (fn: shows a cog left of the switch), onEnter, onLeave, h (min height) }
function K.Tile(parent, w, o)
    local G = ns.Insta and ns.Insta.Glass
    if o.child then w = w - INDENT end
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(w, 46)
    t.o = o
    t.glass = G and pcall(G, t, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 9)
    if not t.glass then t.bg = K.Fill(t, { 1, 1, 1, 0.03 }) K.Border(t, C.line) end
    t.onFill = t:CreateTexture(nil, "BACKGROUND", nil, 3)
    t.onFill:SetPoint("TOPLEFT", 1, -1) t.onFill:SetPoint("BOTTOMLEFT", 1, 1) t.onFill:SetWidth(w * 0.6)
    t.onFill:SetColorTexture(1, 1, 1, 1)
    local left = 12
    if o.icon then
        t.iconBox = CreateFrame("Frame", nil, t)
        t.iconBox:SetSize(28, 28) t.iconBox:SetPoint("LEFT", 9, 0)
        t.ring = t.iconBox:CreateTexture(nil, "BACKGROUND")
        t.ring:SetPoint("TOPLEFT", -2, 2) t.ring:SetPoint("BOTTOMRIGHT", 2, -2)
        t.ring:SetTexture(ns.MEDIA .. "pinring")
        t.icon = t.iconBox:CreateTexture(nil, "ARTWORK")
        if o.glyph then
            t.icon:SetSize(16, 16) t.icon:SetPoint("CENTER")
            t.icon:SetTexture(o.icon)
        else
            t.icon:SetAllPoints()
            t.icon:SetTexture(o.icon) t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if t.iconBox.CreateMaskTexture and t.icon.AddMaskTexture then
                pcall(function()
                    local m = t.iconBox:CreateMaskTexture()
                    m:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    m:SetAllPoints(t.icon)
                    t.icon:AddMaskTexture(m)
                end)
            end
        end
        left = 48
    end
    local right = o.gear and -74 or -54
    t.title = K.Text(t, 12, C.text)
    t.title:SetPoint("TOPLEFT", left, (o.desc and o.desc ~= "") and -8 or -16)
    t.title:SetPoint("RIGHT", t, "RIGHT", right, 0) t.title:SetJustifyH("LEFT") t.title:SetWordWrap(false)
    t.title:SetText(o.title or "")
    t.lbl = t.title   -- the settings search looks for .lbl
    t.desc = K.Text(t, 10, C.dim) t.desc:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -3)
    t.desc:SetPoint("RIGHT", t, "RIGHT", right, 0) t.desc:SetJustifyH("LEFT") t.desc:SetWordWrap(true)
    if t.desc.SetMaxLines then t.desc:SetMaxLines(2) end
    t.desc:SetText(o.desc or "")
    local dh = (o.desc and o.desc ~= "" and t.desc.GetStringHeight and t.desc:GetStringHeight()) or 0
    t:SetHeight(math.max(o.h or 46, 30 + math.min(dh, 24)))
    if o.child then
        t.treeV = t:CreateTexture(nil, "BACKGROUND")
        t.treeV:SetColorTexture(1, 1, 1, 0.12) t.treeV:SetWidth(1)
        t.treeV:SetPoint("TOPRIGHT", t, "TOPLEFT", -12, 6) t.treeV:SetPoint("BOTTOMRIGHT", t, "LEFT", -12, 0)
        t.treeH = t:CreateTexture(nil, "BACKGROUND")
        t.treeH:SetColorTexture(1, 1, 1, 0.12) t.treeH:SetHeight(1)
        t.treeH:SetPoint("LEFT", t, "LEFT", -12, 0) t.treeH:SetPoint("RIGHT", t, "LEFT", 0, 0)
    end
    t.pill = K.Pill(t, 32, 17) t.pill:SetPoint("RIGHT", -12, 0)
    t.knob = K.KnobCircle(t.pill, 13)
    if o.gear then
        t.gear = CreateFrame("Button", nil, t)
        t.gear:SetSize(20, 20) t.gear:SetPoint("RIGHT", t.pill, "LEFT", -8, 0)
        t.gear.ic = K.Glyph(t.gear, 14, ns.MEDIA .. "icons\\settings", C.dim)
        t.gear.ic:SetPoint("CENTER")
        t.gear:SetScript("OnClick", function() o.gear(t) end)
        t.gear:SetScript("OnEnter", function(self) self.ic:SetVertexColor(C.text[1], C.text[2], C.text[3]) K.ShowTip(self, { o.title, ns.L["Settings of this area"] }) end)
        t.gear:SetScript("OnLeave", function(self) self.ic:SetVertexColor(C.dim[1], C.dim[2], C.dim[3]) GameTooltip:Hide() end)
    end
    t.hov, t.kx, t.kTarget, t.press = 0, 0, 0, 0
    local function paint(self)
        local ac, on = self.o.tint or C.accent, self.onv
        local h = self.hov
        if self.glass and G then
            local fa = 0.03 + h * 0.05 + (on and 0.02 or 0)
            local la = on and (0.35 + h * 0.25) or (0.08 + h * 0.10)
            local lc = on and ac or { 1, 1, 1 }
            pcall(G, self, { 1, 1, 1, fa }, { lc[1], lc[2], lc[3], la }, 9)
        end
        if K.Gradient and on then
            K.Gradient(self.onFill, "HORIZONTAL", { ac[1], ac[2], ac[3], 0.16 + h * 0.06 }, { ac[1], ac[2], ac[3], 0 })
        end
        self.onFill:SetShown(on and true or false)
        if self.iconBox then
            self.iconBox:SetScale(1 + h * 0.08 - self.press * 0.06)
            local rc = on and ac or { 0.35, 0.35, 0.4 }
            self.ring:SetVertexColor(rc[1], rc[2], rc[3], on and 0.9 or 0.6)
        end
        self.knob:ClearAllPoints()
        self.knob:SetPoint("CENTER", self.pill, "LEFT", 8.5 + self.kx * 15, 0)
        self:SetAlpha((self.usable == false and 0.35) or 1)
    end
    t.Paint = paint
    t:SetScript("OnUpdate", function(self, el)
        el = math.min(el or 0, 0.05)
        local hT = (self:IsMouseOver() and self.usable ~= false) and 1 or 0
        local busy = false
        if math.abs(self.hov - hT) > 0.01 then self.hov = self.hov + (hT - self.hov) * math.min(1, el * 12) busy = true else self.hov = hT end
        if math.abs(self.kx - self.kTarget) > 0.01 then self.kx = self.kx + (self.kTarget - self.kx) * math.min(1, el * 16) busy = true else self.kx = self.kTarget end
        if self.press > 0 then self.press = math.max(0, self.press - el * 6) busy = true end
        if busy or self.dirty then self.dirty = nil paint(self) end
    end)
    function t:Refresh()
        local o2 = self.o
        local onv = o2.get and o2.get() and true or false
        self.onv = onv
        self.usable = not (o2.usable and not o2.usable())
        self:EnableMouse(self.usable)
        self.kTarget = onv and 1 or 0
        local ac = o2.tint or C.accent
        local pc = onv and ac or { 0.22, 0.22, 0.25 }
        self.pill:SetColor(pc[1], pc[2], pc[3], 1)
        local kc = onv and 1 or 0.62
        self.knob:SetVertexColor(kc, kc, kc + (onv and 0 or 0.04), 1)
        local tc = onv and C.text or C.muted
        self.title:SetTextColor(tc[1], tc[2], tc[3])
        if self.icon then
            if o2.glyph then
                local ic = onv and ac or C.dim
                self.icon:SetVertexColor(ic[1], ic[2], ic[3])
            else
                self.icon:SetDesaturated(not onv) self.icon:SetAlpha(onv and 1 or 0.6)
            end
        end
        self.dirty = true
        paint(self)
    end
    t:SetScript("OnMouseDown", function(self) self.press = 1 self.dirty = true end)
    t:SetScript("OnEnter", function(self) if self.o.onEnter then pcall(self.o.onEnter, self) end end)
    t:SetScript("OnLeave", function(self) if self.o.onLeave then pcall(self.o.onLeave, self) end end)
    t:SetScript("OnClick", function(self)
        local v = not (self.o.get and self.o.get())
        if self.o.set then self.o.set(v) end
        self:Refresh()
        if PlaySound and SOUNDKIT then pcall(PlaySound, v and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF) end
    end)
    t.kx = (o.get and o.get()) and 1 or 0
    t:Refresh()
    return t
end

-- 0.6.657: the same look for the classic switches on the freely built settings pages (design, notices, sound,
-- profile, system): a glass card behind the row, switch moved to the right, soft hover, accent edge when on.
-- Position and size of the row stay, so nothing on those pages moves.
function K.SkinToggle(f)
    if f.oaSkinned or not (f.lbl and f.track) then return end
    f.oaSkinned = true
    local G = ns.Insta and ns.Insta.Glass
    local card = CreateFrame("Frame", nil, f)
    card:SetPoint("TOPLEFT", -6, 4) card:SetPoint("BOTTOMRIGHT", 4, -4)
    card:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    card.glass = G and pcall(G, card, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.08 }, 8)
    if not card.glass then K.Fill(card, { 1, 1, 1, 0.03 }) end
    f.oaCard = card
    f.track:ClearAllPoints() f.track:SetPoint("RIGHT", f, "RIGHT", -6, 0)
    if f.cb then f.cb:ClearAllPoints() f.cb:SetPoint("RIGHT", f, "RIGHT", -6, 0) end
    local sub = f.sub or f.desc
    f.lbl:ClearAllPoints()
    if sub then
        f.lbl:SetPoint("TOPLEFT", f, "TOPLEFT", 6, 0)
        sub:SetPoint("RIGHT", f, "RIGHT", -46, 0)
    else
        f.lbl:SetPoint("LEFT", f, "LEFT", 6, 0)
    end
    f.lbl:SetPoint("RIGHT", f, "RIGHT", -46, 0) f.lbl:SetJustifyH("LEFT")
    local hov = false
    local function paint()
        if not card.glass then return end
        local on = f.GetChecked and f:GetChecked()
        if on == nil and f.kpos ~= nil then on = f.kpos == 1 end
        local ac = C.accent
        local fa = 0.03 + (hov and 0.05 or 0) + (on and 0.02 or 0)
        local lc = on and ac or { 1, 1, 1 }
        local la = on and (hov and 0.6 or 0.35) or (hov and 0.18 or 0.08)
        pcall(G, card, { 1, 1, 1, fa }, { lc[1], lc[2], lc[3], la }, 8)
    end
    f:HookScript("OnEnter", function() hov = true paint() end)
    f:HookScript("OnLeave", function() hov = false paint() end)
    if f.Refresh then hooksecurefunc(f, "Refresh", paint) end
    paint()
end

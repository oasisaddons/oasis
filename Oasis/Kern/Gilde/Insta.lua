-- Oasis: Oasigram - Profil mit Posts, Likes, Kommentaren und Followern (nur in der Gilde)
-- Ein "Foto" ist eine Szene aus Daten: dein Charakter mit Ausruestung, Pose, Blickwinkel, Hintergrund,
-- Ort und Bildunterschrift. Bei allen anderen wird daraus live ein 3D-Bild gebaut.
-- (Addons koennen keine Bilddateien laden oder senden - der echte Screenshot bleibt bei dir im Screenshots-Ordner.)
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local IG = {}
ns.Insta = IG
-- Oasigram ist vorerst "Kommt bald" (echte Screenshots lassen sich im Addon nicht teilen).
-- Auf false setzen, um alles wieder einzuschalten.
IG.SOON = true
local MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local ICON = ns.MEDIA .. "icons\\"
local function S() return ns.db.settings end

------------------------------------------------------------------------
-- Posen und Hintergruende
------------------------------------------------------------------------
IG.POSES = {
    { id = 0, name = "Stehen" }, { id = 64, name = "Winken" }, { id = 65, name = "Jubeln" }, { id = 66, name = "Tanzen" },
    { id = 67, name = "Lachen" }, { id = 63, name = "Verbeugen" }, { id = 113, name = "Salutieren" }, { id = 71, name = "Bruellen" },
    { id = 79, name = "Muskeln" }, { id = 77, name = "Applaus" }, { id = 81, name = "Zeigen" }, { id = 72, name = "Knien" },
    { id = 69, name = "Sitzen" }, { id = 68, name = "Schlafen" }, { id = 73, name = "Kuss" }, { id = 75, name = "Huhn" },
}
-- Hintergruende: oben/unten-Farbe + Lichtschein; "reward" = Belohnung des Oasis-Rangs
IG.BGS = {
    { key = "oase", name = "Oase", top = { 0.05, 0.28, 0.30 }, bot = { 0.02, 0.08, 0.08 }, glow = { 0.3, 1, 0.8 } },
    { key = "wueste", name = "Wueste", top = { 0.55, 0.32, 0.12 }, bot = { 0.15, 0.07, 0.02 }, glow = { 1, 0.75, 0.35 } },
    { key = "nacht", name = "Nacht", top = { 0.06, 0.07, 0.22 }, bot = { 0.01, 0.01, 0.05 }, glow = { 0.5, 0.55, 1 } },
    { key = "wald", name = "Wald", top = { 0.08, 0.26, 0.10 }, bot = { 0.02, 0.06, 0.02 }, glow = { 0.5, 1, 0.4 } },
    { key = "abend", name = "Sonnenuntergang", top = { 0.75, 0.30, 0.20 }, bot = { 0.18, 0.04, 0.12 }, glow = { 1, 0.55, 0.3 }, reward = true },
    { key = "gewitter", name = "Gewitter", top = { 0.18, 0.20, 0.30 }, bot = { 0.03, 0.03, 0.06 }, glow = { 0.7, 0.8, 1 }, reward = true, flash = true },
    { key = "polar", name = "Polarlicht", top = { 0.05, 0.35, 0.30 }, bot = { 0.02, 0.03, 0.12 }, glow = { 0.4, 1, 0.7 }, reward = true, shift = true },
    { key = "vulkan", name = "Vulkan", top = { 0.45, 0.06, 0.02 }, bot = { 0.06, 0.01, 0.01 }, glow = { 1, 0.35, 0.1 }, reward = true, flicker = true },
    { key = "sterne", name = "Sternennacht", top = { 0.03, 0.03, 0.12 }, bot = { 0, 0, 0.02 }, glow = { 0.8, 0.8, 1 }, reward = true, stars = true },
    { key = "tiefsee", name = "Tiefsee", top = { 0.02, 0.20, 0.35 }, bot = { 0, 0.03, 0.08 }, glow = { 0.3, 0.7, 1 }, reward = true },
    { key = "kristall", name = "Kristallhoehle", top = { 0.30, 0.20, 0.45 }, bot = { 0.05, 0.03, 0.10 }, glow = { 0.85, 0.6, 1 }, reward = true },
    { key = "gold", name = "Goldstaub", top = { 0.45, 0.35, 0.08 }, bot = { 0.10, 0.07, 0.01 }, glow = { 1, 0.85, 0.3 }, reward = true, stars = true },
    { key = "astral", name = "Astralebene", top = { 0.25, 0.10, 0.40 }, bot = { 0.02, 0.01, 0.08 }, glow = { 0.9, 0.5, 1 }, reward = true, shift = true, stars = true },
    { key = "legende", name = "Legende", top = { 0.55, 0.20, 0.05 }, bot = { 0.10, 0.02, 0.05 }, glow = { 1, 0.6, 0.2 }, reward = true, shift = true, stars = true },
}
IG.bgByKey = {}
for _, b in ipairs(IG.BGS) do IG.bgByKey[b.key] = b end
function IG.BgUnlocked(key)
    local b = IG.bgByKey[key]
    if not b then return false end
    if not b.reward then return true end
    return ns.Rewards and ns.Rewards.Unlocked("bg", key) or false
end

------------------------------------------------------------------------
-- Daten
------------------------------------------------------------------------
local function me() return ns.me() end
local function same(a, b) return ns.SameName(a, b) end
function IG.PostsBy(name)
    local out = {}
    for _, p in ipairs(Store.List("posts")) do if same(p.by, name) then out[#out + 1] = p end end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end
function IG.AllPosts()
    local out = Store.List("posts")
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end
function IG.Likes(post)
    local out = {}
    for _, l in ipairs(Store.List("likes")) do if l.post == post.id then out[#out + 1] = l end end
    return out
end
function IG.Liked(post)
    for _, l in ipairs(IG.Likes(post)) do if ns.isMe(l.by) then return l end end
end
function IG.Comments(post)
    local out = {}
    for _, c in ipairs(Store.List("comments")) do if c.post == post.id then out[#out + 1] = c end end
    table.sort(out, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
    return out
end
function IG.Followers(name)
    local out = {}
    for _, f in ipairs(Store.List("follows")) do if same(f.target, name) then out[#out + 1] = f.by end end
    return out
end
function IG.Following(name)
    local out = {}
    for _, f in ipairs(Store.List("follows")) do if same(f.by, name) then out[#out + 1] = f.target end end
    return out
end
function IG.IFollow(name)
    for _, f in ipairs(Store.List("follows")) do if ns.isMe(f.by) and same(f.target, name) then return f end end
end
function IG.LikesReceived(name)
    local mine = {}
    for _, p in ipairs(IG.PostsBy(name)) do mine[p.id] = true end
    local n = 0
    for _, l in ipairs(Store.List("likes")) do if mine[l.post] then n = n + 1 end end
    return n
end
function IG.Feed()
    local follow = { [ns.short(me())] = true }
    for _, n in ipairs(IG.Following(me())) do follow[ns.short(n)] = true end
    local out = {}
    for _, p in ipairs(IG.AllPosts()) do if follow[ns.short(p.by)] then out[#out + 1] = p end end
    return out
end

function IG.ToggleLike(post)
    local l = IG.Liked(post)
    if l then
        Store.Delete("likes", l.id)
    else
        Store.Put("likes", { id = "like-" .. post.id .. "-" .. ns.short(me()), post = post.id, owner = post.by, by = me(), ts = ns.now() })
        if ns.Badges then ns.Badges.Add("instaLikes", 1) end
    end
    ns.RefreshPage("insta")
end
function IG.ToggleFollow(name)
    local f = IG.IFollow(name)
    if f then
        Store.Delete("follows", f.id)
    else
        Store.Put("follows", { id = "fol-" .. ns.short(me()) .. "-" .. ns.short(name), by = me(), target = name, ts = ns.now() })
        if ns.Badges then ns.Badges.Add("instaFollows", 1) end
    end
    ns.RefreshPage("insta")
end
function IG.Comment(post, text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    Store.Put("comments", { id = ns.newId("cm"), post = post.id, owner = post.by, by = me(), text = text:sub(1, 120), ts = ns.now() })
    ns.RefreshPage("insta")
end
function IG.Delete(post)
    if not post then return end
    if not (ns.isMe(post.by) or same(post.by, me())) then
        ns.print(L["Nur eigene Posts lassen sich loeschen."] .. " (" .. tostring(post.by) .. ")")
        return
    end
    local before = #IG.PostsBy(me())
    Store.Delete("posts", post.id)
    -- Sicherheitsnetz: lokal auf jeden Fall als geloescht markieren
    local c = Store.coll("posts")
    if c[post.id] and not c[post.id].del then
        c[post.id].del = true
        c[post.id].u = math.max(ns.now(), (c[post.id].u or 0) + 1)
    end
    -- alle weiteren Kopien desselben Posts (gleiche Zeit, gleicher Autor) ebenfalls entfernen
    for id, r in pairs(c) do
        if id ~= post.id and not r.del and same(r.by, post.by) and r.ts == post.ts then Store.Delete("posts", id) end
    end
    for _, l in ipairs(IG.Likes(post)) do if ns.isMe(l.by) then Store.Delete("likes", l.id) end end
    local after = #IG.PostsBy(me())
    ns.print((L["Post geloescht - du hast jetzt %d Posts (vorher %d)."]):format(after, before))
    K.Toast(L["Post geloescht"], post.cap ~= "" and post.cap or "", C.muted)
    ns.RefreshPage("insta")
end
-- Loeschen mit kleiner Abfrage: "Post loeschen?" [Loeschen] [Abbrechen]
local confirm
function IG.ArmDelete(btn, post, after)
    if not post then return end
    if not confirm then
        local f = CreateFrame("Frame", "OasisInstaConfirm", UIParent)
        f:SetSize(240, 96)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        K.Fill(f, C.bg)
        K.Border(f, C.red)
        f.title = K.Title(f, 13, C.text, "CENTER")
        f.title:SetPoint("TOP", 0, -14)
        f.title:SetText(L["Post loeschen?"])
        f.sub = K.Text(f, 11, C.muted, "CENTER")
        f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -4)
        f.sub:SetWidth(220)
        f.sub:SetWordWrap(false)
        f.yes = K.Button(f, L["Loeschen"], 100, 26, "danger", function()
            local p, cb = f.post, f.after
            f:Hide()
            local ok, e = pcall(IG.Delete, p)
            if not ok then ns.err(L["Post loeschen"], e) end
            if cb then pcall(cb) end
        end)
        f.yes:SetPoint("BOTTOMLEFT", 14, 12)
        f.no = K.Button(f, L["Abbrechen"], 100, 26, "ghost", function() f:Hide() end)
        f.no:SetPoint("BOTTOMRIGHT", -14, 12)
        ns.EscClose("OasisInstaConfirm")
        f:Hide()
        confirm = f
    end
    confirm.post, confirm.after = post, after
    confirm.sub:SetText(post.cap ~= "" and ("\"" .. post.cap .. "\"") or "")
    confirm:ClearAllPoints()
    confirm:SetPoint("TOP", btn, "BOTTOM", 0, -4)
    confirm:Show()
    confirm:Raise()
end

-- eigene Ausruestung als "Slot:ItemID,..."
local SLOTS = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19 }
local function gearString()
    local t = {}
    for _, s in ipairs(SLOTS) do
        local id = GetInventoryItemID and ns.safe(GetInventoryItemID("player", s))
        if id then t[#t + 1] = s .. ":" .. id end
    end
    return table.concat(t, ",")
end
function IG.Publish(d)
    local mapID = C_Map and C_Map.GetBestMapForUnit and ns.safe(C_Map.GetBestMapForUnit("player"))
    local race = UnitRace and ns.safe(select(3, UnitRace("player")))
    local sex = UnitSex and ns.safe(UnitSex("player"))
    local _, cls = UnitClass("player")
    local rec = {
        id = ns.newId("post"), kind = "post", by = me(), ts = ns.now(),
        cap = (d.cap or ""):sub(1, 140), pose = d.pose or 0, bg = d.bg or "oase",
        face = math.floor((d.face or 0) * 100 + 0.5), zoom = math.floor((d.zoom or 0) * 100 + 0.5),
        zone = ns.safe(GetRealZoneText and GetRealZoneText()) or "", mapID = mapID,
        rc = race, sx = (sex == 3) and 1 or 0, cls = ns.safe(cls), it = gearString(),
    }
    Store.Put("posts", rec)
    if ns.Badges then ns.Badges.Add("instaPosts", 1) end
    if ns.Sound then ns.Sound.PlayChoice("erfolg") end
    K.Toast(L["Gepostet!"], rec.cap ~= "" and rec.cap or L["Dein Schnappschuss ist jetzt in deinem Profil."], C.pink, function() IG.ShowProfile(me()) end)
    ns.RefreshPage("insta")
    return rec
end

------------------------------------------------------------------------
-- Szene: Hintergrund + 3D-Modell (fuer Kacheln, Detail und Editor)
------------------------------------------------------------------------
function IG.Scene(parent, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.glow = f:CreateTexture(nil, "BORDER")
    f.glow:SetTexture(MASK)
    f.glow:SetPoint("CENTER", 0, -h * 0.05)
    f.glow:SetSize(w * 0.95, w * 0.95)
    f.stars = {}
    for i = 1, 14 do
        local s = f:CreateTexture(nil, "BORDER", nil, 1)
        s:SetTexture(MASK)
        local sz = 1.5 + (i % 3)
        s:SetSize(sz, sz)
        s:SetPoint("TOPLEFT", (i * 37) % math.max(10, w - 6), -((i * 53) % math.max(10, math.floor(h * 0.55))))
        s:Hide()
        f.stars[i] = s
    end
    f.model = CreateFrame("DressUpModel", nil, f)
    f.model:SetAllPoints()
    f.shade = f:CreateTexture(nil, "OVERLAY")
    f.shade:SetPoint("BOTTOMLEFT")
    f.shade:SetPoint("BOTTOMRIGHT")
    f.shade:SetHeight(math.floor(h * 0.35))
    if not K.Gradient(f.shade, "VERTICAL", { 0, 0, 0, 0.75 }, { 0, 0, 0, 0 }) then f.shade:SetColorTexture(0, 0, 0, 0.3) end
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(math.min(w, h) * 0.4, math.min(w, h) * 0.4)
    f.icon:SetPoint("CENTER")
    f.icon:Hide()
    function f:SetBg(key)
        local b = IG.bgByKey[key] or IG.BGS[1]
        self.bgDef = b
        if not K.Gradient(self.bg, "VERTICAL", { b.bot[1], b.bot[2], b.bot[3], 1 }, { b.top[1], b.top[2], b.top[3], 1 }) then
            self.bg:SetColorTexture(b.top[1], b.top[2], b.top[3], 1)
        end
        self.glow:SetVertexColor(b.glow[1], b.glow[2], b.glow[3], 0.22)
        for _, s in ipairs(self.stars) do s:SetShown(b.stars and true or false) end
    end
    -- lebendige Hintergruende (Gewitter, Polarlicht, Vulkan, Sterne)
    f:SetScript("OnUpdate", function(self, el)
        local b = self.bgDef
        if not b or not self:IsVisible() then return end
        self.t = (self.t or 0) + el
        local t = self.t
        if b.flash then
            local fl = (t % 5 < 0.12 or (t % 5 > 0.25 and t % 5 < 0.32)) and 0.55 or 0.22
            self.glow:SetAlpha(fl / 0.22)
        elseif b.flicker then
            self.glow:SetAlpha(0.8 + 0.25 * math.sin(t * 9) * math.sin(t * 3.3))
        elseif b.shift then
            local k = 0.5 + 0.5 * math.sin(t * 0.7)
            self.glow:SetVertexColor(b.glow[1] * (0.6 + 0.4 * k), b.glow[2] * (1 - 0.4 * k), b.glow[3], 0.25)
        end
        if b.stars then
            for i, s in ipairs(self.stars) do s:SetAlpha(0.35 + 0.65 * (0.5 + 0.5 * math.sin(t * (1 + i * 0.3) + i))) end
        end
    end)
    -- Szene aus einem Post aufbauen
    function f:ShowPost(p)
        self.post = p
        self:SetBg(p.bg)
        local m = self.model
        pcall(m.ClearModel, m)
        local ok, isUnitMe = false, false
        if p.rc and tonumber(p.rc) and m.SetCustomRace then
            ok = pcall(m.SetCustomRace, m, tonumber(p.rc), tonumber(p.sx) or 0)
        end
        if ns.isMe(p.by) then ok = pcall(m.SetUnit, m, "player") isUnitMe = ok end
        m:SetShown(ok)
        self.icon:SetShown(not ok)
        if not ok then
            local tc = p.cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[p.cls]
            if tc then
                self.icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
                self.icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
            end
            return
        end
        local isUnit = isUnitMe
        local function dress()
            if self.post ~= p then return end
            -- Ausruestung NUR auf dem echten eigenen Charakter (SetUnit) - auf Ersatzmodellen stuerzt WoW ab
            if isUnit then
                pcall(m.Undress, m)
                for slot, id in tostring(p.it or ""):gmatch("(%d+):(%d+)") do pcall(m.TryOn, m, "item:" .. id) end
            end
            pcall(m.SetAnimation, m, tonumber(p.pose) or 0)
            pcall(m.SetFacing, m, (tonumber(p.face) or 0) / 100)
            pcall(m.SetPortraitZoom, m, (tonumber(p.zoom) or 0) / 100)
        end
        dress()
        ns.After(0.3, dress)
    end
    -- Live-Vorschau (Editor): eigener Charakter
    function f:ShowLive(d)
        self.post = nil
        self:SetBg(d.bg)
        local m = self.model
        if not self.live then pcall(m.SetUnit, m, "player") self.live = true end
        m:Show()
        self.icon:Hide()
        pcall(m.SetAnimation, m, d.pose or 0)
        pcall(m.SetFacing, m, d.face or 0)
        pcall(m.SetPortraitZoom, m, d.zoom or 0)
    end
    f:SetBg("oase")
    return f
end

------------------------------------------------------------------------
-- Kamera: echter Screenshot (fuer dich) + Post-Editor
------------------------------------------------------------------------
local composer
local function buildComposer()
    local f = CreateFrame("Frame", "OasisInstaComposer", UIParent)
    f:SetSize(620, 440)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    K.Fill(f, C.bg)
    K.Border(f, C.line)
    ns.EscClose("OasisInstaComposer")
    local head = K.GameHead(f, L["Neuer Schnappschuss"], C.pink)
    head:SetPoint("TOPLEFT", 16, -14)
    head:SetWidth(300)
    local close = K.CloseButton(f, function() f:Hide() end, L["Schliessen (Esc)"])
    close:SetPoint("TOPRIGHT", -10, -10)
    f.shot = K.Text(f, 10, C.mint, "RIGHT")
    f.shot:SetPoint("TOPRIGHT", -44, -18)

    f.d = { pose = 0, bg = "oase", face = 0.4, zoom = 0.05, cap = "" }
    f.scene = IG.Scene(f, 250, 360)
    f.scene:SetPoint("TOPLEFT", 16, -44)
    K.Border(f.scene, C.line)
    -- Drehen mit der Maus direkt im Bild
    f.scene:EnableMouse(true)
    f.scene:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
    f.scene:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    f.scene:HookScript("OnUpdate", function(self)
        if self.dragX then
            local x = GetCursorPosition()
            f.d.face = (f.d.face + (x - self.dragX) / 90) % (math.pi * 2)
            self.dragX = x
            pcall(self.model.SetFacing, self.model, f.d.face)
        end
    end)
    local hint = K.Text(f, 10, C.dim, "CENTER")
    hint:SetPoint("TOP", f.scene, "BOTTOM", 0, -6)
    hint:SetText(L["Im Bild ziehen = drehen"])

    local X = 284
    local function label(t, y) local l = K.Text(f, 10, C.muted) l:SetPoint("TOPLEFT", X, y) l:SetText(K.Upper(t)) return l end
    label(L["Pose"], -48)
    f.poseBtns = {}
    for i, pz in ipairs(IG.POSES) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(76, 22)
        b:SetPoint("TOPLEFT", X + ((i - 1) % 4) * 80, -64 - math.floor((i - 1) / 4) * 26)
        b.bg = K.Fill(b, C.raised)
        K.Border(b, C.line)
        b.text = K.Text(b, 11, C.text, "CENTER")
        b.text:SetPoint("CENTER")
        b.text:SetText(L[pz.name])
        b:SetScript("OnClick", function() f.d.pose = pz.id f:Update() end)
        b.id = pz.id
        f.poseBtns[i] = b
    end
    label(L["Hintergrund"], -176)
    f.bgBtns = {}
    for i, bg in ipairs(IG.BGS) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(38, 26)
        b:SetPoint("TOPLEFT", X + ((i - 1) % 8) * 41, -192 - math.floor((i - 1) / 8) * 30)
        b.sw = b:CreateTexture(nil, "ARTWORK")
        b.sw:SetAllPoints()
        if not K.Gradient(b.sw, "VERTICAL", { bg.bot[1], bg.bot[2], bg.bot[3], 1 }, { bg.top[1], bg.top[2], bg.top[3], 1 }) then b.sw:SetColorTexture(bg.top[1], bg.top[2], bg.top[3], 1) end
        b.lock = K.Text(b, 12, C.text, "CENTER")
        b.lock:SetPoint("CENTER")
        K.Border(b, C.line)
        b.key = bg.key
        b:SetScript("OnClick", function() if IG.BgUnlocked(bg.key) then f.d.bg = bg.key f:Update() end end)
        b:SetScript("OnEnter", function(self)
            local lines = { L[bg.name] }
            if not IG.BgUnlocked(bg.key) then
                local r = ns.Rewards and ns.Rewards.byKey["bg:" .. bg.key]
                lines[#lines + 1] = "|cffffd24a" .. (L["Ab Oasis-Rang %d"]):format(r and r.lvl or 0) .. "|r"
            end
            K.ShowTip(self, lines)
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.bgBtns[i] = b
    end
    label(L["Zoom"], -258)
    f.zoom = K.Slider(f, 300, 0, 100, 5, function() return math.floor(f.d.zoom * 100 + 0.5) end, function(v) f.d.zoom = v / 100 f:Update() end, function(v) return v .. " %" end)
    f.zoom:SetPoint("TOPLEFT", X, -272)
    label(L["Bildunterschrift"], -306)
    f.cap = K.Input(f, 280, L["Was ist hier los? ... (Emojis gehen auch)"])
    f.cap:SetPoint("TOPLEFT", X, -322)
    f.cap:SetMaxLetters(140)
    f.emo = CreateFrame("Button", nil, f)
    f.emo:SetSize(24, 24)
    f.emo:SetPoint("LEFT", f.cap, "RIGHT", 6, 0)
    f.emo.icon = f.emo:CreateTexture(nil, "ARTWORK")
    f.emo.icon:SetAllPoints()
    f.emo.icon:SetTexture(ns.MEDIA .. "emoji\\smile")
    f.emo:SetScript("OnClick", function(self) if ns.Emoji then ns.Emoji.target = f.cap ns.Emoji.TogglePicker(self) end end)
    f.where = K.Text(f, 11, C.muted)
    f.where:SetPoint("TOPLEFT", X, -356)
    f.post = K.Button(f, L["Posten"], 140, 30, "primary", function()
        f.d.cap = f.cap:GetText() or ""
        local ok, e = pcall(IG.Publish, f.d)
        if not ok then ns.err(L["Posten"], e) return end
        f:Hide()
        pcall(IG.ShowProfile, me())
    end)
    f.post:SetPoint("BOTTOMRIGHT", -16, 16)
    f.cancel = K.Button(f, L["Abbrechen"], 100, 30, "ghost", function() f:Hide() end)
    f.cancel:SetPoint("RIGHT", f.post, "LEFT", -8, 0)
    function f:Update()
        for _, b in ipairs(self.poseBtns) do
            local on = b.id == self.d.pose
            K.SetBorderColor(b, on and C.pink or C.line)
            b.text:SetTextColor((on and C.text or C.muted)[1], (on and C.text or C.muted)[2], (on and C.text or C.muted)[3])
        end
        for _, b in ipairs(self.bgBtns) do
            local open = IG.BgUnlocked(b.key)
            b.lock:SetText(open and "" or "x")
            b.sw:SetAlpha(open and 1 or 0.3)
            K.SetBorderColor(b, b.key == self.d.bg and C.text or C.line)
        end
        self.zoom:Refresh()
        self.scene:ShowLive(self.d)
        self.where:SetText("|cffff7fa8@|r " .. (ns.safe(GetRealZoneText and GetRealZoneText()) or ""))
    end
    f:SetScript("OnShow", function(self) self.scene.live = nil self:Update() end)
    return f
end
function IG.OpenComposer(shotTaken)
    if not composer then
        local ok, res = pcall(buildComposer)
        if not ok then
            ns.err(L["Schnappschuss-Editor"], res)
            return
        end
        composer = res
    end
    local ok, e = pcall(function()
        composer.cap:SetText("")
        composer.shot:SetText(shotTaken and ("✓ " .. L["Screenshot gespeichert"]) or "")
        composer:Show()
        composer:Raise()
    end)
    if not ok then ns.err(L["Schnappschuss-Editor"], e) end
end
-- Kamera: kurz alle Oasis-Fenster ausblenden, echten Screenshot machen, dann den Editor oeffnen
function IG.Snap()
    if IG.SOON then
        K.Toast(L["Oasigram"], L["Kommt bald - wir arbeiten dran!"], C.pink, function() ns.ShowPage("insta") end)
        return
    end
    local main = ns.MainShown and ns.MainShown()
    local bar = _G.OasisMiniBar
    local barShown = bar and bar:IsShown()
    if S().instaShot ~= false and Screenshot then
        if ns.HideMain then ns.HideMain() end
        if bar then bar:Hide() end
        ns.After(0.15, function()
            pcall(Screenshot)
            ns.After(0.6, function()
                -- jeden Schritt einzeln absichern: der Editor soll auf jeden Fall aufgehen
                if barShown and bar then pcall(bar.Show, bar) end
                if main and ns.OpenMain then pcall(ns.OpenMain) end
                IG.OpenComposer(true)
            end)
        end)
    else
        IG.OpenComposer(false)
    end
end
ns.slash.foto = IG.Snap
ns.slash.photo = IG.Snap

------------------------------------------------------------------------
-- Benachrichtigungen: Likes, Kommentare, Follower
------------------------------------------------------------------------
local unread = 0
ns.Listen("STORE", function(coll, rec)
    if IG.SOON then return end
    if not rec or rec.del or ns.isMe(rec.by) or (ns.now() - (rec.ts or 0)) > 600 then return end
    ns.db.instaSeen = ns.db.instaSeen or {}
    if ns.db.instaSeen[rec.id] then return end
    local text
    if coll == "likes" and rec.owner and ns.isMe(rec.owner) then
        text = (L["%s gefaellt dein Post"]):format(ns.displayName(rec.by))
        if ns.Badges then ns.Badges.Add("instaLiked", 1) end
    elseif coll == "comments" and rec.owner and ns.isMe(rec.owner) then
        text = (L["%s hat kommentiert: %s"]):format(ns.displayName(rec.by), rec.text or "")
    elseif coll == "follows" and rec.target and ns.isMe(rec.target) then
        text = (L["%s folgt dir jetzt"]):format(ns.displayName(rec.by))
    elseif coll == "posts" and IG.IFollow(rec.by) then
        text = (L["%s hat etwas gepostet"]):format(ns.displayName(rec.by))
    end
    if not text then return end
    ns.db.instaSeen[rec.id] = true
    K.Toast(L["Oasigram"], text, C.pink, function() IG.ShowProfile(me()) end)
    if not (ns.CurrentPage and ns.CurrentPage() == "insta") then
        unread = unread + 1
        ns.SetNavBadge("insta", tostring(unread))
    end
end)
ns.Listen("STORE", function(coll)
    if coll == "posts" or coll == "likes" or coll == "comments" or coll == "follows" then ns.RefreshPage("insta") end
end)
function IG.ProfileFields(p)
    local bio = S().instaBio
    if bio and bio ~= "" then p.bio = bio:sub(1, 90) end
end

------------------------------------------------------------------------
-- Seite "Profil"
------------------------------------------------------------------------
local view = { who = nil, tab = "posts", page = 1, detail = nil }
function IG.ShowProfile(name)
    view.who = name or me()
    view.tab = "posts"
    view.page = 1
    view.detail = nil
    ns.ShowPage("insta")
    ns.RefreshPage("insta")
end

local PER = 6

local function plain(s) return s end   -- Profil 2026: kleine Beschriftungen in normaler Schreibweise
-- Glasflaeche (Profil 2026): runde, halbtransparente Flaeche + feine Kante, unabhaengig vom gewaehlten Design.
-- Ersetzt Grundfarbe, Rahmen und Design-Skin des Frames; erneuter Aufruf faerbt nur um.
local GLASS_DIR = ns.MEDIA .. "skins\\"
local function glassSlice(f, corner, edge, r, layer, sub, c, center)
    local list = {}
    local function tex()
        local x = f:CreateTexture(nil, layer, nil, sub)
        list[#list + 1] = x
        return x
    end
    for _, d in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
        local x = tex()
        if corner then x:SetTexture(GLASS_DIR .. corner) x:SetTexCoord(d[2], d[3], d[4], d[5]) else x:SetColorTexture(1, 1, 1, 1) end
        x:SetSize(r, r)
        x:SetPoint(d[1])
    end
    local function e(p1, x1, y1, p2, x2, y2, w, h, tc)
        local x = tex()
        if edge then x:SetTexture(GLASS_DIR .. edge) x:SetTexCoord(unpack(tc)) else x:SetColorTexture(1, 1, 1, 1) end
        x:SetPoint(p1, f, p1, x1, y1)
        x:SetPoint(p2, f, p2, x2, y2)
        if w then x:SetWidth(w) end
        if h then x:SetHeight(h) end
    end
    e("TOPLEFT", r, 0, "TOPRIGHT", -r, 0, nil, r, { 0, 1, 0, 1 })
    e("BOTTOMLEFT", r, 0, "BOTTOMRIGHT", -r, 0, nil, r, { 0, 1, 1, 0 })
    e("TOPLEFT", 0, -r, "BOTTOMLEFT", 0, r, r, nil, { 0, 0, 1, 0, 0, 1, 1, 1 })
    e("TOPRIGHT", 0, -r, "BOTTOMRIGHT", 0, r, r, nil, { 0, 1, 1, 1, 0, 0, 1, 0 })
    if center then
        local x = tex()
        x:SetColorTexture(1, 1, 1, 1)
        x:SetPoint("TOPLEFT", r, -r)
        x:SetPoint("BOTTOMRIGHT", -r, r)
    end
    return list
end
IG.GLASS_FILL = { 1, 1, 1, 0.04 }
IG.GLASS_LINE = { 1, 1, 1, 0.085 }
function IG.Glass(f, fill, line, r)
    if not f then return end
    if f.imgBtn then return end   -- 0.6.400: Bild-Knoepfe tragen ihr eigenes Bild - keine Glasflaeche dahinter
    -- 0.6.282: Bild-Rahmen auch um Glas-Boxen (ab 40 hoch, keine Zeilen). 0.6.284: Flaechen, die ohne Randlinie gebaut
    -- werden (z. B. Chat-Nachrichten, Linie mit Deckkraft 0), bekommen nie einen - auch nicht bei spaeteren Aufrufen
    if line and (line[4] or 1) <= 0 then f.noBoxFrame = true end
    if K.BoxFrame and not f.noBoxFrame then pcall(K.BoxFrame, f, 40) end
    fill, line = fill or IG.GLASS_FILL, line or IG.GLASS_LINE
    if not f.glassFill then
        r = r or 10
        if f.bg then f.bg:Hide() end
        if f.borders then for _, b in ipairs(f.borders) do b:Hide() end end
        for _, k in ipairs({ "skinFill", "skinLine" }) do
            if f[k] then for _, x in ipairs(f[k]) do x:Hide() end end
        end
        if f.skinBlizz and f.SetBackdrop then pcall(f.SetBackdrop, f, nil) end
        f.glassFill = glassSlice(f, "round_fill", nil, r, "BACKGROUND", 1, fill, true)
        f.glassLine = glassSlice(f, "round_line", "round_edge", r, "BORDER", 2, line)
    end
    for _, x in ipairs(f.glassFill) do x:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1) end
    for _, x in ipairs(f.glassLine) do x:SetVertexColor(line[1], line[2], line[3], line[4] or 1) end
    return f
end

-- Profil-Reiter (2026): schlanke Glasleiste, Symbol + Text, aktiver Bereich als ruhige Akzent-Pille,
-- die beim Wechsel zum neuen Reiter gleitet (zeigt, wohin man gesprungen ist)
-- Werte-Tooltip als Tabelle: Kopf "Name | Wert", Abschnitte mit Bezeichnung links / Wert rechts, Fussnote klein
-- Werte-Tooltip (2026): eigene Glaskarte statt Blizzard-Tooltip.
-- Kopf: Name klein, Wert gross, Einordnung als farbige Pille; Vergleichsleiste "du / ueblich";
-- Zusammensetzung als Zeilen (Bezeichnung links, Wert rechts); Fussnote klein. Folgt der Maus des Besitzers.
local statTip
local function strip(l) return (l:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function num(v) return tonumber((tostring(v or ""):gsub(",", "."):match("%-?%d+%.?%d*") or "")) end
function IG.StatTip(owner, lines)
    if not statTip then
        local f = CreateFrame("Frame", "OasisStatTip", UIParent)
        f:SetFrameStrata("TOOLTIP")
        f:SetSize(270, 120)
        f:SetClampedToScreen(true)
        IG.Glass(f, { 0.06, 0.065, 0.08, 0.96 }, { 1, 1, 1, 0.12 }, 12)
        f.name = K.Text(f, 11, C.muted)
        f.name:SetPoint("TOPLEFT", 16, -14)
        f.value = K.Title(f, 24, C.text)
        f.value:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -4)
        f.pill = CreateFrame("Frame", nil, f)
        f.pill:SetSize(70, 20)
        f.pill:SetPoint("TOPRIGHT", -14, -18)
        f.pill.t = K.Text(f.pill, 11, { 1, 1, 1 }, "CENTER")
        f.pill.t:SetPoint("CENTER", 0, 0)
        -- Vergleichsleiste
        f.cmpL = K.Text(f, 10, C.muted)
        f.cmpR = K.Text(f, 10, C.muted, "RIGHT")
        f.track = f:CreateTexture(nil, "ARTWORK")
        f.track:SetHeight(5)
        f.track:SetColorTexture(1, 1, 1, 0.08)
        f.fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
        f.fill:SetHeight(5)
        f.mark = f:CreateTexture(nil, "OVERLAY")
        f.mark:SetSize(2, 11)
        f.mark:SetColorTexture(1, 1, 1, 0.8)
        f.secT = K.Text(f, 10, C.dim)
        f.rows = {}
        f.foot = K.Text(f, 9, C.dim)
        f.foot:SetWordWrap(true)
        f.foot:SetJustifyH("LEFT")
        f:SetScript("OnUpdate", function(self)
            if not (self.owner and self.owner:IsVisible() and self.owner:IsMouseOver()) then self:Hide() end
        end)
        statTip = f
    end
    local f = statTip
    local W = 270
    -- Zeilen auswerten
    local title, value, rating, ratingCol, typical, foot
    local parts = {}
    for i, l in ipairs(lines) do
        local p = strip(l)
        if i == 1 then
            title, value = p:match("^(.-):%s+(.+)$")
            title = title or p
        elseif p == " " or p == "" then
        elseif p:match(":$") then
        elseif p:find("^Oasis") or #p > 70 then
            foot = p
        else
            local a, b = p:match("^(.-):%s+(.+)$")
            if a then
                local col = l:match("|c(%x%x%x%x%x%x%x%x)")
                if a:find("Einordnung") or a:find("Rating") then rating, ratingCol = b, col
                elseif a:find("blich auf Level") or a:find("Typical") or a:find("Usual") then typical = { a, b }
                else parts[#parts + 1] = { (a:gsub("^aus ", "")), b } end
            else
                foot = foot and (foot .. "  " .. p) or p
            end
        end
    end
    f.owner = owner
    f.name:SetText(title or "")
    f.value:SetText(value or "")
    -- Einordnungs-Pille in ihrer Farbe
    if rating then
        local r, g, b = 0.6, 0.6, 0.65
        if ratingCol then r, g, b = tonumber(ratingCol:sub(3, 4), 16) / 255, tonumber(ratingCol:sub(5, 6), 16) / 255, tonumber(ratingCol:sub(7, 8), 16) / 255 end
        f.pill.t:SetText(rating)
        f.pill:SetWidth(math.max(56, (f.pill.t:GetStringWidth() or 40) + 22))
        IG.Glass(f.pill, { r * 0.35, g * 0.35, b * 0.35, 0.9 }, { r, g, b, 0.7 }, 9)
        f.pill.t:SetTextColor(math.min(1, r + 0.25), math.min(1, g + 0.25), math.min(1, b + 0.25))
        f.pill:Show()
    else
        f.pill:Hide()
    end
    local y = -64
    -- Vergleich: eigener Wert gegen das Uebliche (Leiste bis 2x ueblich)
    local mine, usual = num(value), typical and num(typical[2])
    local showCmp = mine and usual and usual > 0
    for _, x in ipairs({ f.cmpL, f.cmpR, f.track, f.fill, f.mark }) do x:SetShown(showCmp and true or false) end
    if showCmp then
        f.cmpL:ClearAllPoints() f.cmpL:SetPoint("TOPLEFT", 16, y)
        f.cmpL:SetText(L["Du"] .. "  |cffffffff" .. (value or "") .. "|r")
        f.cmpR:ClearAllPoints() f.cmpR:SetPoint("TOPRIGHT", -16, y)
        f.cmpR:SetText(typical[1] .. "  |cffffffff" .. typical[2] .. "|r")
        y = y - 16
        f.track:ClearAllPoints() f.track:SetPoint("TOPLEFT", 16, y) f.track:SetWidth(W - 32)
        local ratio = math.min(1, mine / (usual * 2))
        f.fill:ClearAllPoints() f.fill:SetPoint("LEFT", f.track, "LEFT") f.fill:SetWidth(math.max(1, (W - 32) * ratio))
        local good = mine >= usual
        local c = good and C.mint or C.amber
        f.fill:SetColorTexture(c[1], c[2], c[3], 1)
        f.mark:ClearAllPoints() f.mark:SetPoint("CENTER", f.track, "LEFT", (W - 32) * 0.5, 0)
        y = y - 18
    end
    -- Zusammensetzung
    f.secT:SetShown(#parts > 0)
    if #parts > 0 then
        f.secT:ClearAllPoints() f.secT:SetPoint("TOPLEFT", 16, y)
        f.secT:SetText(L["Setzt sich zusammen aus"])
        y = y - 16
    end
    for i, pt in ipairs(parts) do
        local r = f.rows[i]
        if not r then
            r = {}
            r.l = K.Text(f, 11, C.muted)
            r.v = K.Text(f, 11, C.text, "RIGHT")
            f.rows[i] = r
        end
        r.l:ClearAllPoints() r.l:SetPoint("TOPLEFT", 16, y) r.l:SetText(pt[1]) r.l:Show()
        r.v:ClearAllPoints() r.v:SetPoint("TOPRIGHT", -16, y) r.v:SetText(pt[2]) r.v:Show()
        r.l:SetPoint("RIGHT", r.v, "LEFT", -8, 0)
        r.l:SetWordWrap(false)
        y = y - 17
    end
    for i = #parts + 1, #f.rows do f.rows[i].l:Hide() f.rows[i].v:Hide() end
    f.foot:SetShown(foot ~= nil)
    if foot then
        y = y - 4
        f.foot:ClearAllPoints() f.foot:SetPoint("TOPLEFT", 16, y) f.foot:SetWidth(W - 32)
        f.foot:SetText(foot)
        y = y - (f.foot:GetStringHeight() or 22) - 2
    end
    f:SetSize(W, math.max(80, -y + 12))
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", owner, "TOPRIGHT", 10, 0)
    f:Show()
    GameTooltip:Hide()
end
function IG.ProfileTabs(parent, items, onChange)
    local f = CreateFrame("Frame", nil, parent)
    -- 0.6.318: hoehere Leiste, aktiver Reiter mit Akzent-Unterstrich + leichtem Schein statt Pille
    local TH = 36   -- 0.6.410: schmaler
    f:SetHeight(TH)
    f.buttons = {}
    local ac = C.accent
    -- 0.6.324: keine eigene Box mehr, nur eine feine Linie unten (Entwurf)
    f.base = f:CreateTexture(nil, "BACKGROUND")
    f.base:SetColorTexture(1, 1, 1, 0.08)
    f.base:SetPoint("BOTTOMLEFT") f.base:SetPoint("BOTTOMRIGHT")
    f.base:SetHeight(1)
    f.ind = CreateFrame("Frame", nil, f)
    f.ind:SetHeight(TH - 8)
    f.ind:SetWidth(60)
    f.ind.glow = f.ind:CreateTexture(nil, "BACKGROUND")
    f.ind.glow:SetAllPoints()
    f.ind.glow:SetAlpha(0)   -- 0.6.390: kein Kasten hinter dem aktiven Reiter, nur Unterstrich + Schein
    if not K.Gradient(f.ind.glow, "VERTICAL", { ac[1], ac[2], ac[3], 0.06 }, { ac[1], ac[2], ac[3], 0 }) then f.ind.glow:SetColorTexture(ac[1], ac[2], ac[3], 0.08) end
    f.ind.line = f.ind:CreateTexture(nil, "ARTWORK")
    f.ind.line:SetColorTexture(ac[1], ac[2], ac[3], 1)
    f.ind.line:SetPoint("BOTTOMLEFT", 6, 0) f.ind.line:SetPoint("BOTTOMRIGHT", -6, 0)
    f.ind.line:SetHeight(2)
    f.ind.shine = f.ind:CreateTexture(nil, "ARTWORK", nil, -1)
    f.ind.shine:SetPoint("BOTTOMLEFT", f.ind.line, "TOPLEFT", -6, 0)
    f.ind.shine:SetPoint("BOTTOMRIGHT", f.ind.line, "TOPRIGHT", 6, 0)
    f.ind.shine:SetHeight(10)
    if not K.Gradient(f.ind.shine, "VERTICAL", { ac[1], ac[2], ac[3], 0.35 }, { ac[1], ac[2], ac[3], 0 }) then f.ind.shine:Hide() end
    -- 0.6.395: Unterstrich und Schein pulsieren sanft (aus mit "Animationen aus")
    f.ind:SetScript("OnUpdate", function(self)
        if ns.db and ns.db.settings.noAnim then self.shine:SetAlpha(1) return end
        local k = 0.65 + 0.35 * math.sin(GetTime() * 2.4)
        self.shine:SetAlpha(k)
        self.line:SetAlpha(0.8 + 0.2 * k)
    end)
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b:SetFrameLevel(f.ind:GetFrameLevel() + 2)
        b.key = it.key
        b.ico = K.Glyph(b, 16, ns.MEDIA .. "icons\\" .. (it.icon or "stats"), { 0.6, 0.6, 0.64 })
        if b.ico.SetDesaturated then b.ico:SetDesaturated(true) end   -- 0.6.390: einfarbig (farbige Grafiken wirkten bunt)
        b.label = K.Text(b, 13, { 0.6, 0.6, 0.64 }, "LEFT")
        b.label:SetText(it.text)
        b.label:SetWordWrap(false)
        b:SetScript("OnClick", function() f:Select(it.key, true) end)
        -- 0.6.395: leichter Schein beim Drueberfahren
        b.hov = b:CreateTexture(nil, "BACKGROUND")
        b.hov:SetPoint("BOTTOMLEFT", 8, 0) b.hov:SetPoint("BOTTOMRIGHT", -8, 0)
        b.hov:SetHeight(TH - 12)
        if not K.Gradient(b.hov, "VERTICAL", { 1, 1, 1, 0.06 }, { 1, 1, 1, 0 }) then b.hov:SetColorTexture(1, 1, 1, 0.03) end
        b.hov:Hide()
        b:HookScript("OnEnter", function(self) if f.value ~= self.key then self.hov:Show() end end)
        b:HookScript("OnLeave", function(self) self.hov:Hide() end)
        -- 0.6.410: Symbol waechst beim Drueberfahren, federt beim Klick (aus mit "Animationen aus")
        local function grow(to, dur)
            if (ns.db and ns.db.settings.noAnim) or not K.Tween then b.ico:SetSize(to, to) return end
            local from = b.ico:GetWidth() or 16
            K.Tween(b.ico, dur or 0.12, function(q) local v = from + (to - from) * q b.ico:SetSize(v, v) end, function() b.ico:SetSize(to, to) end)
        end
        b:HookScript("OnEnter", function() grow(19) end)
        b:HookScript("OnLeave", function() grow(16) end)
        b:HookScript("OnMouseDown", function() grow(13, 0.06) end)
        b:HookScript("OnMouseUp", function(self) grow(self:IsMouseOver() and 19 or 16, 0.14) end)
        b:SetScript("OnEnter", function(self)
            if f.value ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) self.ico:SetVertexColor(C.text[1], C.text[2], C.text[3]) end
        end)
        b:SetScript("OnLeave", function(self)
            if f.value ~= self.key then self.label:SetTextColor(0.6, 0.6, 0.64) self.ico:SetVertexColor(0.6, 0.6, 0.64) end
        end)
        f.buttons[i] = b
    end
    function f:Layout()
        local w = self:GetWidth()
        if not w or w < 50 then return end
        local n, gap, pad = #self.buttons, 2, 4
        local bw = (w - pad * 2 - gap * (n - 1)) / n
        for i, b in ipairs(self.buttons) do
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", pad + (i - 1) * (bw + gap), -4)
            b:SetSize(bw, TH - 8)
            -- Symbol + Text als Gruppe mittig; passt der Text nicht, wird er gekuerzt (nie ueber das Symbol)
            b.label:SetWidth(0)
            local textW = math.min(b.label:GetStringWidth() or 0, bw - 18 - 8 - 12)
            local x0 = math.max(6, math.floor((bw - (18 + 8 + textW)) / 2))
            b.ico:ClearAllPoints()
            b.ico:SetPoint("LEFT", b, "LEFT", x0, 0)
            b.label:ClearAllPoints()
            b.label:SetPoint("LEFT", b.ico, "RIGHT", 8, 0)
            b.label:SetWidth(textW + 1)
        end
        if self.value then self.indX = nil self:MoveInd(self.value, false) end
    end
    f:SetScript("OnSizeChanged", function(self) self:Layout() end)
    function f:Select(key, user)
        self.value = key
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            -- 0.6.369: inaktive Reiter hell (Entwurf), aktiv: Symbol in Akzentfarbe
            local c = on and C.text or { 0.6, 0.6, 0.64 }
            b.label:SetTextColor(c[1], c[2], c[3])
            local ic = on and C.accent or { 0.6, 0.6, 0.64 }
            b.ico:SetVertexColor(ic[1], ic[2], ic[3])
        end
        if user and onChange then onChange(key) end
        self:MoveInd(key, user)
    end
    function f:MoveInd(key, animate)
        local tb
        for _, b in ipairs(self.buttons) do if b.key == key then tb = b end end
        if not tb then return end
        local x1, w1 = (tb:GetLeft() or 0) - (self:GetLeft() or 0), tb:GetWidth() or 0
        local x0, w0 = self.indX or x1, self.indW or w1
        self.indX, self.indW = x1, w1
        local function put(x, w)
            self.ind:ClearAllPoints()
            self.ind:SetPoint("TOPLEFT", self, "TOPLEFT", x, -4)
            self.ind:SetWidth(math.max(20, w))
        end
        if not animate or (ns.db and ns.db.settings.noAnim) or not K.Tween then put(x1, w1) return end
        K.Tween(self.ind, 0.22, function(p)
            local e = 1 - (1 - p) * (1 - p) * (1 - p)
            put(x0 + (x1 - x0) * e, w0 + (w1 - w0) * e)
        end, function() put(x1, w1) end)
    end
    f:Select(items[1].key)
    ns.After(0, function() f:Layout() f:MoveInd(f.value, false) end)
    return f
end
ns.RegisterPage({
    key = "insta", title = "Profil", headTitle = "Charakterprofil", order = 0.6,
    sub = "Dein Charakter: Reise, Erfolge, Abenteuer und Ziele",
    build = function(p)
        p:SetScript("OnShow", function(self) self.fresh = true end)
        p.fresh = true
        -- Meine Stats (solange Oasigram noch nicht fertig ist, zeigt die Seite die eigenen Zahlen)
        local soon = CreateFrame("Frame", nil, p)
        soon:SetAllPoints()
        soon:SetFrameLevel(p:GetFrameLevel() + 50)
        soon:EnableMouse(true)
        -- deckend: darunter liegt die (noch versteckte) Oasigram-Seite
        soon.pageBg = K.Fill(soon, { 0.045, 0.045, 0.052, 1 })
        soon.pageBg:SetAlpha(0)   -- 0.6.368: keine eigene Seitenflaeche - das Fensterbild scheint durch wie auf den anderen Seiten
        -- Profil 2026: Hoehen der Kopfzeile/Reiter und Beginn der Inhalte (mit/ohne Unterreiter)
        -- 0.6.318: groesserer Kopf (170) und hoehere Reiterleiste (46) wie im Entwurf
        soon.HEAD_H, soon.NAV_Y, soon.SUB_Y, soon.TOP, soon.TOP_SUB = 150, -160, -206, -208, -238   -- 0.6.410: Reiter 36 hoch
        -- Profil + "Mein Weg" zusammengefuehrt (07.10.): sechs Bereiche oben, darunter je Bereich Unterreiter
        local MAIN = {
            { key = "vals", text = L["Werte"], icon = "stats", subs = { "stats" } },
            { key = "over", text = L["Tagebuch"], icon = "chronicle", subs = { "year", "daily" } },
            { key = "success", text = L["Erfolge"], icon = "badges", subs = { "records", "rank" } },
            { key = "adv", text = L["Abenteuer"], icon = "map", subs = { "journey", "dungeons", "mates", "deaths", "gold" } },   -- Reise gehoert jetzt zu Abenteuer
            { key = "plan", text = L["Aufgaben"], icon = "checklist", subs = { "weekly", "todo" } },   -- Ziele entfernt
            { key = "skills", text = L["Koennen"], icon = "star_on", subs = { "prof", "skills2", "weapons" } },
        }
        local SUBTEXT = { year = "Jahrbuch", daily = "Tagesziel", journey = "Reise", records = "Rekorde", stats = "Statistik",
            rank = "Rang & Belohnungen", dungeons = "Dungeons", mates = "Mitspieler", deaths = "Tode", gold = "Gold",
            goals = "Ziele", todo = "Was tun?", prof = "Berufe & Ruf", weekly = "Wochenaufgaben", skills2 = "Fertigkeiten", weapons = "Waffen" }
        -- Ansichten aus "Mein Weg" (Life.lua) - werden im Profil eingebettet
        local LIFE = { year = true, journey = true, records = true, dungeons = true, mates = true, deaths = true, gold = true, goals = true, todo = true }
        local MAIN_OF, MAIN_BY = {}, {}
        for _, m in ipairs(MAIN) do
            MAIN_BY[m.key] = m
            for _, sk in ipairs(m.subs) do MAIN_OF[sk] = m.key end
        end
        soon.lastSub = {}
        local items = {}
        for _, m in ipairs(MAIN) do items[#items + 1] = { key = m.key, text = m.text, icon = m.icon } end
        soon.tabs = IG.ProfileTabs(soon, items, function(k)
            soon:ShowTab(soon.lastSub[k] or MAIN_BY[k].subs[1], true)
        end)
        soon.tabs:SetPoint("TOPLEFT", 0, -202)
        soon.tabs:SetPoint("TOPRIGHT", 0, -202)
        -- Unterreiter je Bereich (nur wo es mehr als einen gibt)
        soon.subSeg = {}
        for _, m in ipairs(MAIN) do
            if #m.subs > 1 then
                local si = {}
                for _, sk in ipairs(m.subs) do si[#si + 1] = { key = sk, text = L[SUBTEXT[sk]] } end
                local sg = K.Segments(soon, si, function(sk) soon:ShowTab(sk, true) end, nil, { size = 12, pad = 18 })
                sg:SetPoint("TOPLEFT", 0, -254)
                sg:Hide()
                soon.subSeg[m.key] = sg
            end
        end
        local function host()
            local h = CreateFrame("Frame", nil, soon)
            h:SetPoint("TOPLEFT", 0, -254)
            h:SetPoint("BOTTOMRIGHT")
            h:Hide()
            return h
        end
        soon.rankHost = host()
        soon.profHost = host()
        soon.weapHost = host()
        soon.skillHost = host()
        soon.weeklyHost = host()
        soon.lifeHost = host()
        soon.dailyHost = host()

        -- Tagesziel (frueher auf dem Dashboard): grosse Ringe + drei Zeilen mit Leiste
        do
            local d = soon.dailyHost
            local RCOL = { { 1, 0.20, 0.36 }, { 0.62, 1, 0.12 }, { 0.10, 0.85, 1 } }
            d.panel = K.Panel(d, C.panel)
            d.panel:SetPoint("TOPLEFT", 0, 0)
            d.panel:SetPoint("RIGHT", 0, 0)
            d.panel:SetHeight(200)
            d.rings = K.ActivityRings(d.panel, 150, RCOL)
            d.rings:SetPoint("LEFT", 26, 0)
            d.head = K.Title(d.panel, 16, C.text)
            d.head:SetPoint("TOPLEFT", 200, -24)
            d.head:SetText(L["Dein Tagesziel"])
            d.pct = K.Title(d.panel, 16, C.muted, "RIGHT")
            d.pct:SetPoint("TOPRIGHT", -24, -24)
            d.rows = {}
            local LBL = { "Schritte", "XP heute", "Wochenaufgaben" }
            for i = 1, 3 do
                local r = {}
                local y = -60 - (i - 1) * 34
                r.l = K.Text(d.panel, 12, C.muted)
                r.l:SetPoint("TOPLEFT", 200, y)
                r.l:SetText(L[LBL[i]])
                r.v = K.Text(d.panel, 12, C.text, "RIGHT")
                r.v:SetPoint("TOPRIGHT", -24, y)
                r.track = d.panel:CreateTexture(nil, "ARTWORK")
                r.track:SetHeight(5)
                r.track:SetPoint("TOPLEFT", 200, y - 18)
                r.track:SetPoint("RIGHT", d.panel, "RIGHT", -24, 0)
                r.track:SetColorTexture(RCOL[i][1], RCOL[i][2], RCOL[i][3], 0.16)
                r.fill = d.panel:CreateTexture(nil, "ARTWORK", nil, 1)
                r.fill:SetHeight(5)
                r.fill:SetPoint("LEFT", r.track, "LEFT")
                r.fill:SetWidth(1)
                r.fill:SetColorTexture(RCOL[i][1], RCOL[i][2], RCOL[i][3], 1)
                d.rows[i] = r
            end
            d.msg = K.Text(d, 11, C.dim)
            d.msg:SetPoint("TOPLEFT", d.panel, "BOTTOMLEFT", 4, -10)
            d.msg:SetText(L["Schritte laufen nur zu Fuss (kein Reittier, kein Flug)."])
            local fmt = BreakUpLargeNumbers or tostring
            function d:Update(anim)
                local G = ns.GuildInfo and ns.GuildInfo.DailyGoal
                if not G then return end
                local ok, g = pcall(G)
                if not ok or not g then return end
                local sig = ("%.3f:%.3f:%.3f"):format(g.r1, g.r2, g.r3)
                if anim or self.sig ~= sig then self.sig = sig self.rings:Set({ g.r1, g.r2, g.r3 }, anim and not (ns.db and ns.db.settings.noAnim)) end
                local vals = {
                    fmt(g.steps) .. " |cff6b6b70/ " .. fmt(g.stepGoal) .. "|r",
                    g.xpGoal > 0 and (fmt(g.xp) .. " |cff6b6b70/ " .. fmt(g.xpGoal) .. "|r") or ("|cff888888" .. L["Hoechststufe"] .. "|r"),
                    g.tasks .. " |cff6b6b70/ " .. g.taskN .. "|r",
                }
                for i, r in ipairs(self.rows) do
                    r.v:SetText(vals[i])
                    local w = r.track:GetWidth() or 0
                    local ratio = ({ g.r1, g.r2, g.r3 })[i] or 0
                    if w > 2 then r.fill:SetWidth(math.max(1, w * math.min(1, ratio))) end
                end
                self.pct:SetText(math.floor((g.r1 + g.r2 + g.r3) / 3 * 100) .. " %")
                self.msg:SetText(g.full and ("|cff66db9e" .. L["Tagesziel geschafft - stark!"] .. "|r") or L["Schritte laufen nur zu Fuss (kein Reittier, kein Flug)."])
            end
            d.acc = 0
            d:SetScript("OnUpdate", function(self, el)
                self.acc = self.acc + el
                if self.acc >= 1 then self.acc = 0 self:Update(false) end
            end)
        end

        function soon:ShowTab(k, user)
            if k == "chron" then k = "journey" end
            if k == "goals" then k = "todo" end
            if not MAIN_OF[k] then k = "stats" end
            local mk = MAIN_OF[k]
            self.lastSub[mk] = k
            ns.profileTab = k
            self.tabs:Select(mk)
            local hasSub = #MAIN_BY[mk].subs > 1
            for key, sg in pairs(self.subSeg) do sg:SetShown(key == mk and hasSub) end
            if hasSub then self.subSeg[mk]:Select(k) end
            local top = hasSub and self.TOP_SUB or self.TOP
            local hosts = { stats = self.view, rank = self.rankHost, prof = self.profHost, weapons = self.weapHost, daily = self.dailyHost }
            local shown
            for key, h in pairs({ stats = self.view, rank = self.rankHost, prof = self.profHost, weapons = self.weapHost, skills2 = self.skillHost, weekly = self.weeklyHost, life = self.lifeHost, daily = self.dailyHost }) do
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", 0, top)
                h:SetPoint("BOTTOMRIGHT")
                local on = (key == "life" and LIFE[k]) or key == k
                h:SetShown(on and true or false)
                if on then shown = h end
            end
            if k == "skills2" and ns.Weapons and ns.Weapons.ShowSkills then
                local ok, e = pcall(ns.Weapons.ShowSkills, self.skillHost)
                if not ok then ns.err("Profil/Fertigkeiten", e) end
            end
            if k == "weapons" and ns.Weapons then
                local ok, e = pcall(ns.Weapons.Show, self.weapHost)
                if not ok then ns.err("Profil/Waffen", e) end
            end
            if k == "prof" and ns.ProfRep then
                local ok, e = pcall(ns.ProfRep.Show, self.profHost)
                if not ok then ns.err("Profil/Berufe", e) end
            end
            if k == "daily" then self.dailyHost:Update(user) end
            if self.StyleHosts then ns.After(0.05, function() pcall(self.StyleHosts, self) end) ns.After(0.6, function() pcall(self.StyleHosts, self) end) end
            if LIFE[k] then
                local def = ns.PageDef("life")
                if def and not self.lifeBuilt then
                    self.lifeBuilt = true
                    local ok, e = pcall(def.build, self.lifeHost)
                    if not ok then ns.err("Profil/Mein Weg", e) end
                    if self.lifeHost.seg then self.lifeHost.seg:Hide() end
                    for _, v in pairs(self.lifeHost.views or {}) do
                        v:ClearAllPoints()
                        v:SetPoint("TOPLEFT", 0, 0)
                        v:SetPoint("BOTTOMRIGHT")
                    end
                    if ns.Life then ns.Life.host = self.lifeHost end
                end
                if ns.Life then ns.Life.view = k end
                if def and def.refresh then
                    local ok, e = pcall(def.refresh, self.lifeHost)
                    if not ok then ns.err("Profil/Mein Weg", e) end
                end
            end
            if k == "rank" or k == "weekly" then
                local def = ns.PageDef("rank")
                if def and not self.rankBuilt then
                    self.rankBuilt = true
                    local ok, e = pcall(def.build, self.rankHost)
                    if not ok then ns.err("Profil/Rang", e) end
                    -- "Dein Rang" steckt jetzt in der Karte oben -> hier ausblenden, Wochenaufgaben hoch
                    local h = self.rankHost
                    if h.card then h.card:Hide() end
                    if h.week then h.week:SetParent(self.weeklyHost) h.week:ClearAllPoints() h.week:SetAllPoints(self.weeklyHost) self.weekMoved = true end   -- eigener Reiter Aufgaben > Wochenaufgaben
                    if h.week and self.StyleWeek then pcall(self.StyleWeek, self, h.week) end
                    self:PlaceCounters()
                end
                if def and def.refresh then
                    local ok, e = pcall(def.refresh, self.rankHost)
                    if not ok then ns.err("Profil/Rang", e) end
                end
            end
            if user and shown and K.FadeIn and not (ns.db and ns.db.settings.noAnim) then K.FadeIn(shown, 0) end
        end
        local hc = K.Panel(soon, C.panel)
        hc:SetPoint("TOPLEFT", 0, -38)
        hc:SetPoint("TOPRIGHT", 0, -38)
        hc:SetHeight(112)
        hc.cardBtn = K.Button(soon, L["Visitenkarte bearbeiten"], 160, 22, "ghost", function() if ns.Card then ns.Card.Edit() end end)
        hc.cardBtn:SetPoint("TOPRIGHT", soon, "TOPRIGHT", 0, -206)
        hc.cardBtn:Hide()   -- Visitenkarte jetzt per Klick auf die Charakterkarte (Portrait/Name)
        hc.glow = hc:CreateTexture(nil, "BORDER")
        hc.glow:SetAllPoints()
        hc.edge = hc:CreateTexture(nil, "ARTWORK")
        hc.edge:SetPoint("TOPLEFT") hc.edge:SetPoint("BOTTOMLEFT") hc.edge:SetWidth(3)
        soon.hc = hc
        soon.av = K.RankFrame(hc, 70, "circle")   -- 0.5.586: gemalter Rahmen ist breiter -> Portraet kleiner
        -- Klick auf die Charakterkarte (links, Portrait + Name) = Visitenkarte bearbeiten
        hc.editHit = CreateFrame("Button", nil, hc)
        hc.editHit:SetPoint("TOPLEFT", 0, 0)
        hc.editHit:SetPoint("BOTTOMLEFT", 0, 0)
        hc.editHit:SetWidth(170)
        hc.editHit:SetFrameLevel(hc:GetFrameLevel() + 20)
        hc.editHit:SetScript("OnClick", function() if ns.Card then ns.Card.Edit() end end)
        hc.editHit:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Visitenkarte"], L["Klick: Titel, Status, Lieblings-Emojis und Vitrine bearbeiten"] }) end)
        hc.editHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        soon.av:SetPoint("CENTER", hc, "LEFT", 58, 0)
        soon.face = soon.av:CreateTexture(nil, "ARTWORK", nil, 3)
        soon.face:SetSize(70, 70)
        soon.face:SetPoint("CENTER")
        pcall(soon.face.SetMask, soon.face, MASK) K.MaskSafe(soon.face)
        soon.name = K.Title(hc, 18, C.text)
        soon.name:SetPoint("TOPLEFT", 122, -16)
        soon.cls = K.Text(hc, 12, C.muted)
        soon.cls:SetPoint("LEFT", soon.name, "RIGHT", 10, 0)
        soon.rank = K.Text(hc, 12, C.amber)
        soon.rank:SetPoint("TOPLEFT", soon.name, "BOTTOMLEFT", 0, -6)
        soon.rank:SetWordWrap(false)
        soon.xpTrack = hc:CreateTexture(nil, "ARTWORK")
        soon.xpTrack:SetColorTexture(1, 1, 1, 0.07)
        soon.xpTrack:SetHeight(6)
        soon.xpTrack:SetPoint("TOPLEFT", soon.rank, "BOTTOMLEFT", 0, -10)
        soon.xpTrack:SetWidth(260)
        soon.xpFill = hc:CreateTexture(nil, "ARTWORK", nil, 1)
        soon.xpFill:SetHeight(6)
        soon.xpFill:SetPoint("LEFT", soon.xpTrack, "LEFT")
        if not K.Gradient(soon.xpFill, "HORIZONTAL", { 0.85, 0.5, 0.12, 1 }, { 1, 0.82, 0.29, 1 }) then soon.xpFill:SetColorTexture(1, 0.8, 0.3, 1) end
        soon.xpText = K.Text(hc, 10, C.muted)
        soon.xpText:SetPoint("TOPLEFT", soon.xpTrack, "BOTTOMLEFT", 0, -4)
        -- Kacheln rechts
        soon.tiles = {}
        local TILES = { { ICON .. "badges", "Abzeichen", C.amber }, { ICON .. "badges", "Oasis-XP", C.accent }, { ICON .. "badges\\chat", "Gildenchat", C.mint } }
        for i, d in ipairs(TILES) do
            local t = K.HudTile(hc, d[1], L[d[2]], d[3])
            t:SetSize(150, 66)
            t:SetPoint("RIGHT", hc, "RIGHT", -12 - (#TILES - i) * 158, 0)
            soon.tiles[i] = t
        end
        -- Name/Rang/Balken enden vor den Kacheln (sonst laufen sie darunter)
        soon.name:SetPoint("RIGHT", soon.tiles[1], "LEFT", -16, 0)
        soon.name:SetWordWrap(false)
        soon.rank:SetPoint("RIGHT", soon.tiles[1], "LEFT", -16, 0)
        soon.xpText:SetPoint("RIGHT", soon.tiles[1], "LEFT", -16, 0)
        soon.xpText:SetWordWrap(false)
        local function fitBar()
            local l, r = soon.xpTrack:GetLeft(), soon.tiles[1]:GetLeft()
            if l and r then soon.xpW = math.max(60, r - l - 16) soon.xpTrack:SetWidth(soon.xpW) end
        end
        hc:SetScript("OnSizeChanged", fitBar)
        soon.FitBar = fitBar
        -- alle Zaehler, nach Bereich gruppiert
        soon.list = K.List(soon, 36, function(l)
            local r = K.Row(l)
            r.head = K.GameHead(r, "", C.accent)
            r.head:SetPoint("LEFT", 2, -4)
            r.head:SetPoint("RIGHT", -8, -4)
            r.medal = r:CreateTexture(nil, "ARTWORK")
            r.medal:SetTexture(MASK)
            r.medal:SetSize(14, 14)
            r.medal:SetPoint("LEFT", 10, 0)
            r.name = K.Text(r, 13, C.text)
            r.name:SetPoint("TOPLEFT", 32, -5)
            r.name:SetWidth(200)
            r.desc = K.Text(r, 10, C.muted)
            r.desc:SetPoint("BOTTOMLEFT", 32, 5)
            r.desc:SetPoint("RIGHT", r, "RIGHT", -300, 0)
            r.val = K.Title(r, 14, C.text, "RIGHT")
            r.val:SetPoint("RIGHT", -210, 0)
            r.track = r:CreateTexture(nil, "ARTWORK")
            r.track:SetColorTexture(1, 1, 1, 0.07)
            r.track:SetSize(150, 5)
            r.track:SetPoint("RIGHT", -44, 0)
            r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.fill:SetHeight(5)
            r.fill:SetPoint("LEFT", r.track, "LEFT")
            r.next = K.Text(r, 10, C.dim, "RIGHT")
            r.next:SetPoint("RIGHT", -8, 0)
            return r
        end, function(r, it)
            local isHead = it.head ~= nil
            r.head:SetShown(isHead)
            for _, x in ipairs({ r.medal, r.name, r.desc, r.val, r.track, r.fill, r.next }) do x:SetShown(not isHead) end
            r.stripe:SetShown(not isHead)
            if isHead then
                r.head.text:SetText(plain(L[it.head]))
                return
            end
            local b, v, tier = it.b, it.v, it.tier
            local T = ns.Badges.TIERS
            local c = tier > 0 and T[tier].color or C.dim
            r.medal:SetVertexColor(c[1], c[2], c[3])
            r.name:SetText(L[b.name])
            r.desc:SetText(L[b.desc])
            r.val:SetText(v)
            local nextNeed = b.tiers[tier + 1]
            local prev = tier > 0 and b.tiers[tier] or 0
            local pct = nextNeed and math.max(0, math.min(1, (v - prev) / math.max(1, nextNeed - prev))) or 1
            local nc = nextNeed and T[tier + 1].color or T[#T].color
            r.fill:SetColorTexture(nc[1], nc[2], nc[3], 0.9)
            r.fill:SetWidth(math.max(1, 150 * pct))
            r.next:SetText(nextNeed and ("|cff777777/ |r" .. nextNeed) or ("|cffe8b44a" .. L["max"] .. "|r"))
        end)
        soon.list:SetPoint("TOPLEFT", hc, "BOTTOMLEFT", 0, -10)
        soon.list:SetPoint("BOTTOMRIGHT")
        ------------------------------------------------------------------
        -- Aufbau wie "Rang & Belohnungen": links Karte + Charakterwerte, rechts Zaehler
        ------------------------------------------------------------------
        local view = CreateFrame("Frame", nil, soon)
        view:SetPoint("TOPLEFT", 0, -254)
        view:SetPoint("BOTTOMRIGHT")
        soon.view = view
        local LW = 360
        -- Karte "Charakter": volle Breite oben, bleibt bei beiden Reitern sichtbar
        hc:SetParent(soon)
        hc:ClearAllPoints()
        hc:SetPoint("TOPLEFT", 0, 0)
        hc:SetPoint("TOPRIGHT", 0, 0)
        hc:SetHeight(198)
        soon.av:ClearAllPoints()
        soon.av:SetPoint("CENTER", hc, "TOPLEFT", 56, -52)
        -- Kacheln rechts in der Karte
        for i, t in ipairs(soon.tiles) do
            t:SetParent(hc)
            t:ClearAllPoints()
            t:SetSize(140, 62)
            t:SetPoint("TOPRIGHT", hc, "TOPRIGHT", -12, -14)
            t.label:SetWidth(90)
            t.label:SetWordWrap(false)
            -- nur "Abzeichen" bleibt; Oasis-XP und Gildenchat raus
            if i > 1 then t:Hide() t.Show = function() end end
        end
        soon.name:ClearAllPoints()
        soon.name:SetPoint("TOPLEFT", hc, "TOPLEFT", 112, -14)
        soon.name:SetPoint("RIGHT", soon.tiles[1], "LEFT", -16, 0)
        soon.cls:ClearAllPoints()
        soon.cls:SetPoint("TOPLEFT", soon.name, "BOTTOMLEFT", 0, -3)
        soon.cls:SetPoint("RIGHT", soon.tiles[1], "LEFT", -16, 0)
        soon.cls:SetWordWrap(false)
        soon.rank:ClearAllPoints()
        soon.rank:SetPoint("TOPLEFT", soon.cls, "BOTTOMLEFT", 0, -8)
        soon.rank:SetPoint("RIGHT", soon.tiles[1], "LEFT", -16, 0)
        soon.xpTrack:ClearAllPoints()
        soon.xpTrack:SetPoint("TOPLEFT", soon.rank, "BOTTOMLEFT", 0, -8)
        soon.xpText:ClearAllPoints()
        soon.xpText:SetPoint("TOPLEFT", soon.xpTrack, "BOTTOMLEFT", 0, -4)
        soon.xpText:SetPoint("RIGHT", soon.tiles[1], "LEFT", -16, 0)
        -- aus "Dein Rang": XP gesamt, naechste Belohnung, naechster Rahmen
        -- eine Zeile ueber die ganze Kartenbreite ganz unten
        soon.nextLine = hc:CreateTexture(nil, "ARTWORK")
        soon.nextLine:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        soon.nextLine:SetHeight(1)
        soon.nextLine:SetPoint("BOTTOMLEFT", hc, "BOTTOMLEFT", 12, 30)
        soon.nextLine:SetPoint("BOTTOMRIGHT", hc, "BOTTOMRIGHT", -12, 30)
        soon.next = K.Text(hc, 11, C.muted)
        soon.next:SetPoint("BOTTOMLEFT", hc, "BOTTOMLEFT", 14, 10)
        soon.next:SetPoint("RIGHT", hc, "RIGHT", -14, 0)
        soon.next:SetWordWrap(false)
        local function fitBar()
            local l, r = soon.xpTrack:GetLeft(), soon.tiles[1]:GetLeft()
            if l and r then soon.xpW = math.max(60, r - l - 16) soon.xpTrack:SetWidth(soon.xpW) end
        end
        soon.FitBar = fitBar
        hc:SetScript("OnSizeChanged", fitBar)

        ------------------------------------------------------------------
        -- Spiel-Stil: Wappen am Portraet, Schildchen, dicker XP-Balken, Belohnungs-Chips
        ------------------------------------------------------------------
        soon.nextLine:Hide()
        soon.next:Hide()
        soon.av:ClearAllPoints()
        soon.av:SetPoint("CENTER", hc, "LEFT", 84, 4)
        -- Buehne hinter dem Portraet: Aura, drehende Ringe, Strahlen - wird mit dem Rang immer aufwendiger
        local stage = CreateFrame("Frame", nil, hc)
        stage:SetSize(170, 170)
        stage:SetPoint("CENTER", soon.av, "CENTER")
        stage:SetFrameLevel(math.max(1, soon.av:GetFrameLevel() - 1))
        stage.aura = stage:CreateTexture(nil, "BACKGROUND")
        stage.aura:SetTexture(ns.MEDIA .. "arc")
        stage.aura:SetAllPoints()
        stage.aura:SetBlendMode("ADD")
        stage.disc = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
        stage.disc:SetTexture(MASK)
        stage.disc:SetSize(118, 118)
        stage.disc:SetPoint("CENTER")
        stage.rays = stage:CreateTexture(nil, "BACKGROUND", nil, 2)
        stage.rays:SetTexture(ns.MEDIA .. "arc")
        stage.rays:SetSize(150, 150)
        stage.rays:SetPoint("CENTER")
        stage.rays:SetBlendMode("ADD")
        soon.stage = stage
        soon.spin1 = ns.SpinRing and ns.SpinRing(hc, soon.av, 132, 0.6)
        soon.spin2 = ns.SpinRing and ns.SpinRing(hc, soon.av, 146, -0.35)
        -- Stufe = Rahmen-Index (1 Holz .. 11 Herz der Oasis)
        function soon:AvatarFx(level)
            local fi = ns.Rank and ns.Rank.FrameIndex and ns.Rank.FrameIndex(level or 1) or 1
            local fr = ns.Rank and ns.Rank.FRAMES and ns.Rank.FRAMES[fi]
            local c = fr and fr.color or { 0.6, 0.6, 0.6 }
            local st = self.stage
            st.fi, st.c = fi, c
            st.disc:SetVertexColor(c[1] * 0.35, c[2] * 0.35, c[3] * 0.35, 0.55 + 0.03 * fi)
            st.aura:SetVertexColor(c[1], c[2], c[3], math.min(0.9, 0.12 + 0.07 * fi))
            st.aura:SetShown(fi >= 2)
            st.rays:SetVertexColor(c[1], c[2], c[3], 0.5)
            st.rays:SetShown(fi >= 6)
            if self.spin1 then
                self.spin1:SetShown(fi >= 4)
                self.spin1.tex:SetVertexColor(c[1], c[2], c[3], math.min(1, 0.35 + 0.06 * fi))
            end
            if self.spin2 then
                self.spin2:SetShown(fi >= 8)
                self.spin2.tex:SetVertexColor(1, 1, 1, 0.35)
            end
            local noAnim = ns.db and ns.db.settings and ns.db.settings.noAnim
            st:SetScript("OnUpdate", (not noAnim) and function(s, el)
                s.t = (s.t or 0) + el
                local t = s.t
                -- atmen: ab Silber, schneller und staerker mit dem Rang
                local amp = s.fi >= 3 and (0.04 + 0.01 * s.fi) or 0
                local sc = 1 + amp * math.sin(t * (1.2 + 0.15 * s.fi))
                s.aura:SetSize(170 * sc, 170 * sc)
                if s.fi >= 6 then s.rays:SetRotation(t * 0.25) end
                if s.fi >= 11 then
                    local h = (t * 0.08) % 1
                    local i = math.floor(h * 6) local f = h * 6 - i
                    local q, u = 1 - f, f
                    local r, g, bb = ({ { 1, u, 0 }, { q, 1, 0 }, { 0, 1, u }, { 0, q, 1 }, { u, 0, 1 }, { 1, 0, q } })[i + 1][1], ({ { 1, u, 0 }, { q, 1, 0 }, { 0, 1, u }, { 0, q, 1 }, { u, 0, 1 }, { 1, 0, q } })[i + 1][2], ({ { 1, u, 0 }, { q, 1, 0 }, { 0, 1, u }, { 0, q, 1 }, { u, 0, 1 }, { 1, 0, q } })[i + 1][3]
                    s.aura:SetVertexColor(r, g, bb, 0.85)
                    s.rays:SetVertexColor(r, g, bb, 0.5)
                end
            end or nil)
        end
        soon:AvatarFx(1)
        soon.emb = K.RankEmblem(hc, 34)
        soon.emb:SetPoint("CENTER", soon.av, "BOTTOM", 0, 6)
        soon.emb:SetFrameLevel(soon.av:GetFrameLevel() + 10)
        soon.name:ClearAllPoints()
        soon.name:SetPoint("TOPLEFT", hc, "TOPLEFT", 172, -14)
        soon.name:SetPoint("RIGHT", soon.tiles[1], "LEFT", -16, 0)
        K.SetFontSafe(soon.name, K.FONT_HEAD, 21, "", K.FONT)
        -- Schildchen: Klasse (in Klassenfarbe) + Level
        local function pill(parent)
            local f = CreateFrame("Frame", nil, parent)
            f:SetHeight(18)
            f.bg = K.Fill(f, C.raised)
            K.Border(f, C.line)
            f.t = K.Text(f, 11, C.text, "CENTER")
            f.t:SetPoint("CENTER", 0, 0)
            function f:Set(text, c)
                self.t:SetText(text)
                self:SetWidth((self.t:GetStringWidth() or 40) + 16)
                if c then
                    self.bg:SetColorTexture(c[1] * 0.22, c[2] * 0.22, c[3] * 0.22, 1)
                    K.SetBorderColor(self, { c[1] * 0.7, c[2] * 0.7, c[3] * 0.7, 1 })
                    self.t:SetTextColor(math.min(1, c[1] + 0.2), math.min(1, c[2] + 0.2), math.min(1, c[3] + 0.2))
                end
            end
            return f
        end
        soon.clsPill = pill(hc)
        soon.clsPill:SetPoint("TOPLEFT", soon.name, "BOTTOMLEFT", 0, -6)
        soon.lvlPill = pill(hc)
        soon.lvlPill:SetPoint("LEFT", soon.clsPill, "RIGHT", 6, 0)
        soon.cls:Hide()
        -- Rang-Zeile + dicker XP-Balken
        soon.rank:ClearAllPoints()
        -- WoW-Erfahrung: Level -> naechstes, Balken (Ruhebonus hell), rechts XP und Tempo
        soon.wxp = K.Text(hc, 12, { 0.45, 0.7, 1 })
        soon.wxp:SetPoint("TOPLEFT", soon.clsPill, "BOTTOMLEFT", 0, -10)
        soon.wxpR = K.Text(hc, 11, C.muted, "RIGHT")
        soon.wxpR:SetPoint("BOTTOMRIGHT", soon.wxp, "BOTTOMRIGHT", 0, 0)
        soon.wTrack = hc:CreateTexture(nil, "ARTWORK")
        soon.wTrack:SetColorTexture(0, 0, 0, 0.55)
        soon.wTrack:SetHeight(8)
        soon.wTrack:SetPoint("TOPLEFT", soon.wxp, "BOTTOMLEFT", 0, -5)
        soon.wRest = hc:CreateTexture(nil, "ARTWORK", nil, 1)
        soon.wRest:SetPoint("LEFT", soon.wTrack, "LEFT")
        soon.wRest:SetHeight(8)
        soon.wRest:SetColorTexture(0.45, 0.7, 1, 0.3)
        soon.wFill = hc:CreateTexture(nil, "ARTWORK", nil, 2)
        soon.wFill:SetPoint("LEFT", soon.wTrack, "LEFT")
        soon.wFill:SetHeight(8)
        soon.wFill:SetColorTexture(0.25, 0.55, 1, 1)
        soon.rank:SetPoint("TOPLEFT", soon.wTrack, "BOTTOMLEFT", 0, -10)
        ns.Insta.headSoon = soon
        function soon:FillWowXP()
            local K2, L2 = ns.K, ns.L
            local lvl = UnitLevel("player") or 1
            local cur, max = UnitXP("player") or 0, UnitXPMax("player") or 1
            local rest = GetXPExhaustion and GetXPExhaustion() or 0
            local maxLvl = (GetMaxPlayerLevel and GetMaxPlayerLevel()) or 60
            local w = self.wTrack:GetWidth() or 200
            if lvl >= maxLvl then
                self.wxp:SetText(plain((L2["Level %d"]):format(lvl)) .. "  |cff888888" .. L2["Hoechststufe"] .. "|r")
                self.wxpR:SetText("")
                self.wFill:SetWidth(w) self.wRest:SetWidth(1)
                return
            end
            local pct = max > 0 and cur / max or 0
            self.wFill:SetWidth(math.max(1, w * pct))
            self.wRest:SetWidth(math.max(1, w * math.min(1, (cur + (rest or 0)) / max)))
            local fmtN = function(n) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
            -- Tempo dieser Sitzung
            local sess = ns.Insta.WowXPSession
            local tempo = ""
            if sess and sess.t0 and GetTime() - sess.t0 > 120 and sess.xp > 0 then
                local rate = sess.xp / (GetTime() - sess.t0) * 3600
                local m = math.floor((max - cur) / rate * 60)
                tempo = "  |cff66db9e" .. (L2["%s XP/Std"]):format(fmtN(math.floor(rate))) .. "  ·  " ..
                    (L2["naechstes Level in ca. %s"]):format(m < 60 and (m .. " " .. L2["Min"]) or ("%d:%02d %s"):format(math.floor(m / 60), m % 60, L2["Std"])) .. "|r"
            end
            self.wxp:SetText(plain((L2["Level %d"]):format(lvl)) .. "  |cff888888> " .. (lvl + 1) .. "|r" .. tempo)
            self.wxpR:SetText(fmtN(cur) .. " / " .. fmtN(max) .. " XP  ·  " .. math.floor(pct * 100) .. " %" ..
                ((rest or 0) > 0 and ("  |cff6199ff+" .. fmtN(rest) .. " " .. L2["Ruhe"] .. "|r") or ""))
        end
        soon.rank:SetPoint("RIGHT", soon.tiles[1], "LEFT", -70, 0)
        K.SetFontSafe(soon.rank, K.FONT_HEAD, 12, "", K.FONT)
        soon.pct = K.Title(hc, 12, C.amber, "RIGHT")
        soon.pct:SetPoint("BOTTOMRIGHT", soon.xpTrack, "TOPRIGHT", 0, 3)
        soon.xpTrack:ClearAllPoints()
        soon.xpTrack:SetPoint("TOPLEFT", soon.rank, "BOTTOMLEFT", 0, -6)
        soon.xpTrack:SetHeight(10)
        soon.xpTrack:SetColorTexture(0, 0, 0, 0.55)
        soon.xpFill:SetHeight(10)
        soon.xpBorder = CreateFrame("Frame", nil, hc)
        soon.xpBorder:SetAllPoints(soon.xpTrack)
        K.Border(soon.xpBorder, { 0.25, 0.22, 0.14, 1 })
        soon.xpShine = hc:CreateTexture(nil, "OVERLAY")
        soon.xpShine:SetPoint("TOPLEFT", soon.xpTrack, "TOPLEFT")
        soon.xpShine:SetPoint("TOPRIGHT", soon.xpTrack, "TOPRIGHT")
        soon.xpShine:SetHeight(4)
        soon.xpShine:SetColorTexture(1, 1, 1, 0.08)
        soon.xpTicks = {}
        for i = 1, 9 do
            local t = hc:CreateTexture(nil, "OVERLAY", nil, 2)
            t:SetColorTexture(0, 0, 0, 0.45)
            t:SetWidth(1)
            soon.xpTicks[i] = t
        end
        soon.xpText:ClearAllPoints()
        soon.xpText:SetPoint("TOPLEFT", soon.xpTrack, "BOTTOMLEFT", 0, -4)
        -- Belohnungs-Chips unten
        local function chip(parent, label, color)
            local f = CreateFrame("Frame", nil, parent)
            f:SetHeight(30)
            f.bg = K.Fill(f, { color[1] * 0.12, color[2] * 0.12, color[3] * 0.12, 1 })
            K.Border(f, { color[1] * 0.5, color[2] * 0.5, color[3] * 0.5, 1 })
            f.edge = f:CreateTexture(nil, "ARTWORK")
            f.edge:SetPoint("TOPLEFT") f.edge:SetPoint("BOTTOMLEFT") f.edge:SetWidth(2)
            f.edge:SetColorTexture(color[1], color[2], color[3], 1)
            f.icon = f:CreateTexture(nil, "ARTWORK")
            f.icon:SetSize(22, 22)
            f.icon:SetPoint("LEFT", 8, 0)
            f.label = K.Text(f, 9, C.dim)
            f.label:SetPoint("TOPLEFT", 36, -4)
            f.label:SetText(plain(label))
            f.value = K.Text(f, 11, C.text)
            f.value:SetPoint("BOTTOMLEFT", 36, 4)
            f.value:SetPoint("RIGHT", f, "RIGHT", -8, 0)
            f.value:SetWordWrap(false)
            return f
        end
        soon.chipR = chip(hc, L["Naechste Belohnung"], C.amber)
        soon.chipR.icon:SetTexture(ns.MEDIA .. "icons\\badges")
        soon.chipR.icon:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
        -- Tooltip: was genau die naechste Belohnung ist (bei Emojis: alle Emojis, die frei werden) + die danach
        soon.chipR:EnableMouse(true)
        soon.chipR:SetScript("OnEnter", function(self)
            local RW = ns.Rewards
            local r = ns.Rank and ns.Rank.Mine()
            local lvl = r and r.level or 1
            if not (RW and RW.LIST) then return end
            local nexts = {}
            for _, x in ipairs(RW.LIST) do if x.lvl > lvl then nexts[#nexts + 1] = x end if #nexts >= 3 then break end end
            local x = nexts[1]
            if not x then return end
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(L[x.name], 1, 0.82, 0.3)
            GameTooltip:AddLine((L["ab Rang %d"]):format(x.lvl) .. "  ·  " .. (L["noch %d Raenge"]):format(x.lvl - lvl), 0.6, 0.6, 0.6)
            if x.desc then GameTooltip:AddLine(L[x.desc], 0.9, 0.9, 0.9, true) end
            if x.kind == "emoji" and RW.EmojiLevel and ns.Emoji then
                local codes = {}
                for _, cat in ipairs(ns.Emoji.CATS or {}) do
                    if cat.custom then
                        for _, e in ipairs(cat.items or {}) do
                            if RW.EmojiLevel(e) == x.lvl and e[2] then codes[#codes + 1] = e[2] end
                        end
                    end
                end
                if #codes > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine((L["%d neue Emojis:"]):format(#codes), 0.91, 0.71, 0.29)
                    local line = {}
                    for i, c in ipairs(codes) do
                        local ok, img = pcall(ns.Emoji.Render, c)
                        line[#line + 1] = (ok and img) or c
                        if #line == 8 or i == #codes then GameTooltip:AddLine(table.concat(line, " ")) line = {} end
                    end
                end
            elseif x.kind == "theme" and x.hex then
                GameTooltip:AddLine("|cff" .. x.hex .. "|||||||||||||||||||||||||||||||||r", 1, 1, 1)
            elseif x.kind == "dice" and x.color then
                GameTooltip:AddLine(("|cff%02x%02x%02x"):format(x.color[1] * 255, x.color[2] * 255, x.color[3] * 255) .. L["Wuerfelfarbe"] .. "|r")
            end
            if #nexts > 1 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["Danach:"], 0.6, 0.6, 0.6)
                for i = 2, #nexts do GameTooltip:AddDoubleLine("  " .. L[nexts[i].name], (L["Rang %d"]):format(nexts[i].lvl), 0.85, 0.85, 0.85, 0.5, 0.5, 0.5) end
            end
            GameTooltip:Show()
        end)
        soon.chipR:SetScript("OnLeave", function() GameTooltip:Hide() end)
        soon.chipF = chip(hc, L["Naechster Rahmen"], C.accent)
        local function layoutGame()
            local W = hc:GetWidth() or 750
            if W < 100 then W = 750 end
            -- rechts: Vitrine (150) + Trennlinie (12) + Rand (14) + Luft (24)
            soon.xpW = math.max(60, W - 172 - 150 - 12 - 14 - 24)
            soon.xpTrack:SetWidth(soon.xpW)
            if soon.wTrack then
                soon.wTrack:SetWidth(soon.xpW)
                soon.wxp:SetWidth(soon.xpW)
                if soon.FillWowXP then soon:FillWowXP() end
            end
            for i, t in ipairs(soon.xpTicks) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", soon.xpTrack, "TOPLEFT", soon.xpW * i / 10, 0)
                t:SetPoint("BOTTOMLEFT", soon.xpTrack, "BOTTOMLEFT", soon.xpW * i / 10, 0)
            end
            soon.chipR:ClearAllPoints()
            soon.chipR:SetPoint("BOTTOMLEFT", hc, "BOTTOMLEFT", 172, 10)
            soon.chipR:SetWidth(soon.xpW)
            soon.chipF:Hide()
        end
        soon.FitBar = layoutGame
        hc:SetScript("OnSizeChanged", layoutGame)

        -- Abzeichen-Vitrine statt Kachel: Zahl, drei Medaillen (Bronze/Silber/Gold), duenner Balken
        soon.tiles[1]:Hide()
        soon.tiles[1].Show = function() end
        local vit = CreateFrame("Button", nil, hc)
        vit:SetSize(150, 100)
        vit:SetPoint("TOPRIGHT", hc, "TOPRIGHT", -14, -14)
        vit.sep = hc:CreateTexture(nil, "ARTWORK")
        vit.sep:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        vit.sep:SetPoint("TOPRIGHT", vit, "TOPLEFT", -12, 0)
        vit.sep:SetPoint("BOTTOMRIGHT", vit, "BOTTOMLEFT", -12, 0)
        vit.sep:SetWidth(1)
        vit.hl = vit:CreateTexture(nil, "HIGHLIGHT")
        vit.hl:SetAllPoints()
        vit.hl:SetColorTexture(1, 1, 1, 0.04)
        vit.lbl = K.Text(vit, 10, C.muted)
        vit.lbl:SetPoint("TOPLEFT", 4, -2)
        vit.lbl:SetText(plain(L["Abzeichen"]))
        vit.num = K.Title(vit, 22, C.text)
        vit.num:SetPoint("TOPLEFT", vit.lbl, "BOTTOMLEFT", 0, -4)
        vit.of = K.Text(vit, 12, C.dim)
        vit.of:SetPoint("BOTTOMLEFT", vit.num, "BOTTOMRIGHT", 4, 2)
        vit.pct = K.Text(vit, 11, C.amber, "RIGHT")
        vit.pct:SetPoint("TOPRIGHT", -4, -2)
        -- die besten Abzeichen als Symbole
        vit.icons = {}
        for i = 1, 4 do
            local b = CreateFrame("Frame", nil, vit)
            b:SetSize(30, 30)
            b:SetPoint("TOPLEFT", vit.num, "BOTTOMLEFT", (i - 1) * 36, -8)
            b.bg = K.Fill(b, { 0.06, 0.06, 0.07, 1 })
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 3, -3)
            b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
            K.Border(b, C.line)
            b:EnableMouse(true)
            b:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnMouseUp", function() ns.ShowPage("badges") end)
            vit.icons[i] = b
        end
        vit.medals = {}
        for i = 1, 3 do
            local m = CreateFrame("Frame", nil, vit)
            m:SetSize(46, 22)
            m:SetPoint("TOPLEFT", vit.num, "BOTTOMLEFT", (i - 1) * 50, -8)
            m.dot = m:CreateTexture(nil, "ARTWORK")
            m.dot:SetTexture(MASK)
            m.dot:SetSize(16, 16)
            m.dot:SetPoint("LEFT", 0, 0)
            m.ring = m:CreateTexture(nil, "BORDER")
            m.ring:SetTexture(MASK)
            m.ring:SetSize(20, 20)
            m.ring:SetPoint("CENTER", m.dot, "CENTER")
            m.ring:SetVertexColor(0, 0, 0, 0.6)
            m.n = K.Title(m, 13, C.text)
            m.n:SetPoint("LEFT", m.dot, "RIGHT", 5, 0)
            vit.medals[i] = m
            m:Hide()
        end
        vit.track = vit:CreateTexture(nil, "ARTWORK")
        vit.track:SetColorTexture(1, 1, 1, 0.07)
        vit.track:SetHeight(4)
        vit.track:SetPoint("BOTTOMLEFT", 4, 4)
        vit.track:SetPoint("BOTTOMRIGHT", -4, 4)
        vit.fill = vit:CreateTexture(nil, "OVERLAY")
        vit.fill:SetHeight(4)
        vit.fill:SetPoint("LEFT", vit.track, "LEFT")
        vit.fill:SetColorTexture(1, 0.8, 0.25, 1)
        vit:SetScript("OnClick", function() ns.ShowPage("badges") end)
        vit:SetScript("OnEnter", function(self)
            K.ShowTip(self, { L["Abzeichen"], self.tip or "", "|cff888888" .. L["Klick: alle Abzeichen"] .. "|r" })
        end)
        vit:SetScript("OnLeave", function() GameTooltip:Hide() end)
        soon.vit = vit
        local LW = 300

        -- Charakterwerte (wie im WoW-Charakterfenster)
        -- Rollen-Auswahl: wird beim ersten Befuellen gebaut (braucht soon:Options, das weiter unten steht)
        function soon:EnsureRoleSeg()
            if self.roleSeg then return end
            local bar = CreateFrame("Frame", nil, view)
            bar:SetPoint("TOPLEFT", 0, 0)
            bar:SetSize(10, 28)
            bar.btns = {}
            local x = 0
            for i, o in ipairs(self:Options()) do
                local b = CreateFrame("Button", nil, bar)
                b:SetHeight(28)
                b.bg = K.Fill(b, C.raised)
                K.Border(b, C.line)
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetSize(20, 20)
                b.icon:SetPoint("LEFT", 4, 0)
                b.icon:SetTexture(o[5] or "Interface\\Icons\\INV_Misc_QuestionMark")
                b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                b.t = K.Text(b, 12, C.muted)
                b.t:SetPoint("LEFT", b.icon, "RIGHT", 7, 0)
                b.t:SetText(L[o[2]])
                b:SetWidth((b.t:GetStringWidth() or 60) + 42)
                b:SetPoint("LEFT", x, 0)
                x = x + b:GetWidth() + 6
                b.hl = b:CreateTexture(nil, "HIGHLIGHT")
                b.hl:SetAllPoints()
                b.hl:SetColorTexture(1, 1, 1, 0.05)
                b.key = o[1]
                b:SetScript("OnClick", function()
                    ns.char.statRole = o[1]
                    bar:Select(o[1])
                    soon:FillStats()
                    soon:FillPrio()
                end)
                bar.btns[i] = b
            end
            bar:SetWidth(math.max(10, x))
            function bar:Select(key)
                for _, b in ipairs(self.btns) do
                    local on = b.key == key
                    local c = on and C.accent or C.line
                    K.SetBorderColor(b, c)
                    b.bg:SetColorTexture(on and C.accent[1] * 0.18 or C.raised[1], on and C.accent[2] * 0.18 or C.raised[2], on and C.accent[3] * 0.18 or C.raised[3], 1)
                    local tc = on and C.text or C.muted
                    b.t:SetTextColor(tc[1], tc[2], tc[3])
                    b.icon:SetDesaturated(not on)
                    b.icon:SetAlpha(on and 1 or 0.7)
                end
            end
            self.roleSeg = bar
            -- Gruppenrollen (Mehrfachauswahl): sieht die Gilde, wird mit der Blizzard-Rollenwahl abgeglichen
            if ns.Profile and ns.Profile.RoleChips then
                self.roleChips = ns.Profile.RoleChips(view, 276, function() return ns.me() end)
                self.roleChips:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, -1)
                self.roleLbl = K.Text(view, 10, C.dim, "RIGHT")
                self.roleLbl:SetPoint("RIGHT", self.roleChips, "LEFT", -10, 0)
                self.roleLbl:SetText(plain(L["Gruppenrolle"]))
                self.roleChips.onLock = function(locked)
                    -- kurz halten, sonst ueberlappt es die Spezialisierung links; Hinweis im Tooltip
                    self.roleLbl:SetText(plain(locked and L["Wunschrolle"] or L["Gruppenrolle"]))
                end
                self.roleChips:Refresh()
                ns.Listen("ROLES_CHANGED", function() if soon.roleChips then soon.roleChips:Refresh() end end)
            end
            bar:Select(self:CurrentOption()[1])
        end
        local cs = K.Panel(view, C.panel)
        cs:SetPoint("TOPLEFT", 0, -36)
        cs:SetPoint("BOTTOMLEFT")
        cs:SetPoint("BOTTOMLEFT")
        cs:SetPoint("RIGHT", view, "RIGHT", -290, 0)
        cs.head = K.GameHead(cs, L["Charakterwerte"], C.mint)
        cs.head:SetPoint("TOPLEFT", 12, -12)
        cs.head:SetPoint("RIGHT", -12, 0)
        cs.rows = {}
        for i = 1, 30 do
            local r = CreateFrame("Frame", nil, cs)
            r:SetHeight(22)

            if i % 2 == 0 then r.bg = K.Fill(r, { 1, 1, 1, 0.025 }) end
            r.l = K.Text(r, 12, C.muted)
            r.l:SetPoint("LEFT", 14, 0)
            r.v = K.Text(r, 12, C.text, "RIGHT")
            r.v:SetPoint("RIGHT", -8, 0)
            r.q = r:CreateTexture(nil, "BORDER")
            r.q:SetAllPoints()
            -- Einordnung dezent: kleine runde Markierung links statt Farbflaeche (Profil 2026)
            r.qbar = r:CreateTexture(nil, "ARTWORK")
            r.qbar:SetPoint("LEFT", 5, 0) r.qbar:SetSize(3, 12)
            if K.RoundMask then
                if r.bg then K.RoundMask(r.bg, r, 6) end
                K.RoundMask(r.q, r, 6)
                K.RoundMask(r.qbar, r.qbar, 1)
            end
            r:EnableMouse(true)
            r:SetScript("OnEnter", function(self)
                if not self.info then return end
                IG.StatTip(self, self.info)
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:HookScript("OnEnter", function(self)
                if self.toggle then K.ShowTip(self, { L["Weitere Werte"], L["Klick: auf- oder zuklappen"] }) end
            end)
            r:SetScript("OnMouseUp", function(self)
                if self.toggle then soon.showAll = not soon.showAll soon:FillStats() end
            end)
            cs.rows[i] = r
        end
        soon.cs = cs

        -- Stat-Prioritaet: was fuer Klasse + Rolle zuerst erhoeht werden sollte (Classic-Richtwerte)
        local pr = K.Panel(view, C.panel)
        pr:SetPoint("TOPLEFT", cs, "TOPRIGHT", 12, 0)
        pr:SetPoint("BOTTOMRIGHT")
        pr.head = K.GameHead(pr, L["Stat-Prioritaet"], C.amber)
        pr.head:SetPoint("TOPLEFT", 12, -12)
        pr.head:SetPoint("RIGHT", -12, 0)
        pr.rows = {}
        for i = 1, 7 do
            local r = CreateFrame("Frame", nil, pr)
            r:SetHeight(24)
            r:SetPoint("TOPLEFT", 12, -36 - (i - 1) * 26)
            r:SetPoint("RIGHT", -12, 0)
            r.bg = K.Fill(r, C.raised)
            r.num = K.Title(r, 14, C.amber, "CENTER")
            r.num:SetPoint("LEFT", 4, 0)
            r.num:SetWidth(20)
            r.name = K.Text(r, 12, C.text)
            r.name:SetPoint("LEFT", 28, 0)
            r.val = K.Text(r, 11, C.muted, "RIGHT")
            r.val:SetPoint("RIGHT", -8, 0)
            pr.rows[i] = r
        end
        -- Tipp als Hinweis-Kasten: Gluehbirne, Akzentstreifen, Stichpunkte
        pr.tipBox = CreateFrame("Frame", nil, pr)
        pr.tipBox:SetPoint("BOTTOMLEFT", 12, 12)
        pr.tipBox:SetPoint("RIGHT", pr, "RIGHT", -12, 0)
        pr.tipBox:SetHeight(42)
        -- Profil 2026: ruhige Glasflaeche mit leichtem Bernstein-Ton statt Farbblock + Streifen
        IG.Glass(pr.tipBox, { C.amber[1], C.amber[2], C.amber[3], 0.06 }, { C.amber[1], C.amber[2], C.amber[3], 0.22 }, 10)
        pr.tipIcon = pr.tipBox:CreateTexture(nil, "ARTWORK")
        pr.tipIcon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
        pr.tipIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        pr.tipIcon:SetSize(22, 22)
        pr.tipIcon:SetPoint("TOPLEFT", 12, -10)
        pr.tipHead = K.Text(pr.tipBox, 11, C.amber)
        pr.tipHead:SetPoint("LEFT", pr.tipIcon, "RIGHT", 10, 0)
        pr.tipHead:SetText(plain(L["So spielst du es"]))
        pr.tip = K.Text(pr.tipBox, 12, C.text)
        pr.tip:SetPoint("TOPLEFT", pr.tipIcon, "BOTTOMRIGHT", 10, -6)
        pr.tip:SetPoint("RIGHT", pr.tipBox, "RIGHT", -10, 0)
        pr.tip:SetWordWrap(true)
        pr.tip:SetJustifyH("LEFT")
        pr.tip:SetSpacing(3)
        -- zugeklappt nur die Kopfzeile; Klick klappt nach oben auf (ueber die Prioritaets-Zeilen)
        pr.tipBox:SetClipsChildren(true)
        pr.tipBox:SetFrameLevel(pr:GetFrameLevel() + 10)
        pr.tipBox:EnableMouse(true)
        pr.tipArrow = K.Text(pr.tipBox, 10, C.dim, "RIGHT")
        pr.tipArrow:SetPoint("RIGHT", pr.tipBox, "TOPRIGHT", -12, -21)
        pr.tipBox.open, pr.tipBox.cur = false, 42
        function pr.tipBox:Target() return self.open and ((pr.tip:GetStringHeight() or 30) + 44) or 42 end
        function pr.tipBox:Animate()
            local goal = self:Target()
            pr.tipArrow:SetText(plain(self.open and L["zuklappen"] or L["aufklappen"]) .. (self.open and "  |cffe8b44a-|r" or "  |cffe8b44a+|r"))
            -- zugeklappt: Text ausblenden (keine angeschnittene Zeile), aufgeklappt: einblenden
            if self.open then pr.tip:Show() end
            self:SetScript("OnUpdate", function(f, el)
                local d = goal - f.cur
                if math.abs(d) < 1 then
                    f.cur = goal
                    f:SetScript("OnUpdate", nil)
                    if not f.open then pr.tip:Hide() end
                else f.cur = f.cur + d * math.min(1, el * 12) end
                f:SetHeight(f.cur)
                pr.tip:SetAlpha(math.max(0, math.min(1, (f.cur - 42) / 40)))
            end)
        end
        pr.tipBox:SetScript("OnEnter", function() pr.tipArrow:SetTextColor(C.amber[1], C.amber[2], C.amber[3]) end)
        pr.tipBox:SetScript("OnLeave", function() pr.tipArrow:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end)
        pr.tip:Hide()
        pr.tipBox:SetScript("OnMouseUp", function(f) f.open = not f.open f:Animate() end)
        soon.pr = pr
        pr:SetScript("OnSizeChanged", function() if soon.FillPrio then pcall(soon.FillPrio, soon) end end)

        -- rechts: Zaehler & Abzeichen
        local rp = K.Panel(view, C.panel)
        -- sitzt im Reiter "Rang & Belohnungen" (rechts unten), wird dort beim ersten Oeffnen eingehaengt
        rp:SetParent(soon.rankHost)
        rp:ClearAllPoints()
        rp:SetPoint("TOPLEFT", soon.rankHost, "TOPLEFT", 381, -1)   -- vorlaeufig, richtig gesetzt in placeCounters
        rp:SetPoint("BOTTOMRIGHT", soon.rankHost, "BOTTOMRIGHT")
        rp.head = K.GameHead(rp, L["Zaehler & Abzeichen"], C.amber)
        rp.head:SetPoint("TOPLEFT", 12, -12)
        rp.head:SetPoint("RIGHT", -12, 0)
        local function layoutRight() do return end
            local w = rp:GetWidth() or 500
            if w < 50 then w = 500 end
            local gap = 8
            local tw = math.floor((w - 24 - gap * 2) / 3)
            for i, t in ipairs(soon.tiles) do
                t:ClearAllPoints()
                t:SetSize(tw, 62)
                t:SetPoint("TOPLEFT", rp, "TOPLEFT", 12 + (i - 1) * (tw + gap), -36)
                t.label:SetWidth(math.max(40, tw - 50))
                t.label:SetWordWrap(false)
            end
        end
        rp:SetScript("OnSizeChanged", layoutRight)
        layoutRight()
        soon.list:SetParent(rp)
        soon.list:ClearAllPoints()
        soon.list:SetPoint("TOPLEFT", rp, "TOPLEFT", 8, -36)
        soon.list:SetPoint("BOTTOMRIGHT", rp, "BOTTOMRIGHT", -6, 6)
        soon.rp = rp
        -- Belohnungen oben rechts, Zaehler & Abzeichen unten rechts
        function soon:PlaceCounters()
            local h = self.rankHost
            local H = h:GetHeight() or 480
            if H < 100 then H = 480 end
            local half = math.floor((H - 10) / 2)
            if self.weekMoved then
                -- Belohnungen links, Zaehler & Abzeichen rechts, beide volle Hoehe
                local Wd = h:GetWidth() or 700
                if Wd < 200 then Wd = 700 end
                local half2 = math.floor((Wd - 10) / 2)
                if h.rw then
                    h.rw:ClearAllPoints()
                    h.rw:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
                    h.rw:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 0)
                    h.rw:SetWidth(half2)
                end
                self.rp:ClearAllPoints()
                self.rp:SetPoint("TOPLEFT", h, "TOPLEFT", half2 + 10, 0)
                self.rp:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT")
                return
            end
            if h.rw then
                h.rw:ClearAllPoints()
                h.rw:SetPoint("TOPLEFT", h, "TOPLEFT", 381, 0)
                h.rw:SetPoint("TOPRIGHT", h, "TOPRIGHT", 0, 0)
                h.rw:SetHeight(half)
            end
            self.rp:ClearAllPoints()
            self.rp:SetPoint("TOPLEFT", h, "TOPLEFT", 381, -(half + 10))
            self.rp:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT")
        end
        soon.rankHost:SetScript("OnSizeChanged", function() soon:PlaceCounters() end)

        -- Charakterwerte lesen (alles, was der Client hergibt; fehlende Werte fallen weg)
        local function num(v) v = ns.safe(v) return tonumber(v) end
        local function fmt(n) return n and (BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(n + 0.5)) or tostring(math.floor(n + 0.5))) or nil end
        -- Einordnung (Oasis-Schaetzung): Wert im Verhaeltnis zu dem, was auf diesem Level fuer die Klasse ueblich ist.
        -- Basis = typische Werte mit Quest-Ausruestung; Faktor -> Qualitaetsfarbe wie bei Gegenstaenden.
        local MAIN = {   -- wichtige Grundwerte je Klasse (1 Staerke, 2 Beweglichkeit, 3 Ausdauer, 4 Intelligenz, 5 Willenskraft)
            WARRIOR = { [1] = true, [3] = true }, ROGUE = { [2] = true, [3] = true }, HUNTER = { [2] = true, [3] = true },
            MAGE = { [4] = true, [5] = true }, PRIEST = { [4] = true, [5] = true }, WARLOCK = { [4] = true, [3] = true },
            PALADIN = { [1] = true, [4] = true }, SHAMAN = { [1] = true, [4] = true }, DRUID = { [4] = true, [2] = true },
        }
        local ARMOR_K = { MAGE = 12, PRIEST = 12, WARLOCK = 12, ROGUE = 20, DRUID = 20, HUNTER = 30, SHAMAN = 30, WARRIOR = 42, PALADIN = 42 }
        local QUALITY = {   -- ab Faktor -> Farbe, Name
            { 2.0, { 1.00, 0.50, 0.00 }, "Legendaer" },
            { 1.6, { 0.64, 0.21, 0.93 }, "Episch" },
            { 1.25, { 0.00, 0.44, 0.87 }, "Selten" },
            { 1.0, { 0.12, 1.00, 0.00 }, "Gut" },
            { 0.8, nil, "Durchschnitt" },
            { 0, { 0.62, 0.62, 0.62 }, "Unter Durchschnitt" },
        }
        function soon.Quality(ratio)
            for _, q in ipairs(QUALITY) do if ratio >= q[1] then return q end end
            return QUALITY[#QUALITY]
        end
        -- welche Werte zaehlen fuer Klasse + Rolle (aus der Gruppensuche: Tank / Heiler / Schaden)
        local REL = {
            caster = { hp = 1, power = 1, stat3 = 1, stat4 = 1, stat5 = 1, sp = 1, scrit = 1, mp5 = 1, shit = 1, ilvl = 1 },
            healer = { hp = 1, power = 1, stat3 = 1, stat4 = 1, stat5 = 1, heal = 1, scrit = 1, mp5 = 1, ilvl = 1 },
            tank = { hp = 1, stat1 = 1, stat2 = 1, stat3 = 1, armor = 1, def = 1, dodge = 1, parry = 1, block = 1, ap = 1, hit = 1, ilvl = 1 },
            melee = { hp = 1, stat1 = 1, stat2 = 1, stat3 = 1, ap = 1, dmg = 1, speed = 1, crit = 1, hit = 1, ilvl = 1 },
            hunter = { hp = 1, power = 1, stat2 = 1, stat3 = 1, stat4 = 1, ap = 1, crit = 1, hit = 1, ilvl = 1 },
            hybrid = { hp = 1, power = 1, stat1 = 1, stat4 = 1, ap = 1, crit = 1, hit = 1, sp = 1, scrit = 1, mp5 = 1, ilvl = 1 },
        }
        -- Rollen je Klasse: Auswahl ueber den Charakterwerten (wird gemerkt)
        local OPTIONS = {
            SHAMAN = { { "enh", "Verstaerkung", "melee", "SHAMAN_hybrid", "Interface\\Icons\\Spell_Nature_LightningShield" }, { "ele", "Elementar", "caster", "SHAMAN_caster", "Interface\\Icons\\Spell_Nature_Lightning" }, { "resto", "Heiler", "healer", "SHAMAN_healer", "Interface\\Icons\\Spell_Nature_HealingWaveGreater" } },
            PALADIN = { { "ret", "Vergeltung", "melee", "PALADIN_hybrid", "Interface\\Icons\\Spell_Holy_AuraOfLight" }, { "prot", "Tank", "tank", "PALADIN_tank", "Interface\\Icons\\Spell_Holy_DevotionAura" }, { "holy", "Heiler", "healer", "PALADIN_healer", "Interface\\Icons\\Spell_Holy_HolyBolt" } },
            DRUID = { { "cat", "Katze", "melee", "DRUID_hybrid", "Interface\\Icons\\Ability_Druid_CatForm" }, { "bear", "Baer (Tank)", "tank", "DRUID_tank", "Interface\\Icons\\Ability_Racial_BearForm" }, { "bal", "Gleichgewicht", "caster", "DRUID_caster", "Interface\\Icons\\Spell_Nature_StarFall" }, { "resto", "Heiler", "healer", "DRUID_healer", "Interface\\Icons\\Spell_Nature_HealingTouch" } },
            WARRIOR = { { "dps", "Schaden", "melee", "WARRIOR_melee", "Interface\\Icons\\Ability_Warrior_SavageBlow" }, { "tank", "Tank", "tank", "WARRIOR_tank", "Interface\\Icons\\Ability_Warrior_DefensiveStance" } },
            PRIEST = { { "holy", "Heiler", "healer", "PRIEST_healer", "Interface\\Icons\\Spell_Holy_GreaterHeal" }, { "shadow", "Schatten", "caster", "PRIEST_caster", "Interface\\Icons\\Spell_Shadow_ShadowWordPain" } },
            MAGE = { { "dps", "Schaden", "caster", "MAGE", "Interface\\Icons\\Spell_Frost_FrostBolt02" } },
            WARLOCK = { { "dps", "Schaden", "caster", "WARLOCK", "Interface\\Icons\\Spell_Shadow_DeathCoil" } },
            ROGUE = { { "dps", "Schaden", "melee", "ROGUE", "Interface\\Icons\\Ability_BackStab" } },
            HUNTER = { { "dps", "Schaden", "hunter", "HUNTER", "Interface\\Icons\\Ability_Marksmanship" } },
        }
        function soon:Options()
            local _, cls = UnitClass("player")
            return OPTIONS[ns.safe(cls) or ""] or { { "dps", "Schaden", "melee", "" } }
        end
        function soon:CurrentOption()
            local opts = self:Options()
            local want = ns.char and ns.char.statRole
            for _, o in ipairs(opts) do if o[1] == want then return o end end
            -- Standard aus den Rollen der Gruppensuche
            local roles = ns.Groups and ns.Groups.MyRoles and ns.Groups.MyRoles() or {}
            for _, o in ipairs(opts) do
                if (o[3] == "healer" and roles.heal and not roles.dps) or (o[3] == "tank" and roles.tank and not roles.dps) then return o end
            end
            return opts[1]
        end
        function soon:Role()
            local o = self:CurrentOption()
            return o[3], L[o[2]]
        end

        -- Stat-Prioritaeten je Klasse/Rolle nach WoW Classic (Treffer: Nahkampf/Jaeger +9 %, Zauber +16 % gegen Bosse;
        -- Verteidigung 440 = kritsicher ab Level 60; Staerke = 2 AP bei Krieger/Paladin/Schamane/Druide)
        local PRIO = {
            MAGE = { { "sp" }, { "shit" }, { "stat4" }, { "scrit" }, { "stat5" }, tip = "Werte: Zauberschaden, dann Zaubertreffer bis +16 % (Raid-Bosse), Intelligenz, Zauber-Krit;Waffe: Stab mit Zauberschaden, dazu ein Zauberstab fuer Restmana;Rotation: Frostblitz bzw. Feuerball spammen, Hervorrufung bei leerem Mana;Leveln: Intelligenz und Willenskraft = weniger Pausen, in Gruppen Schaf (Mond) setzen" },
            WARLOCK = { { "sp" }, { "shit" }, { "stat3" }, { "stat4" }, { "scrit" }, tip = "Werte: Zauberschaden, Zaubertreffer bis +16 % (Raid), Ausdauer, Intelligenz;Waffe: Stab oder Dolch + Nebenhand mit Zauberschaden, Zauberstab fuer Restmana;Rotation: Verderbnis + Fluch, dann Schattenblitz; Aderlass statt Trinken;Tipp: Ausdauer lohnt sich doppelt (Aderlass, Leerwandler/Seelenverbindung)" },
            ROGUE = { { "hit" }, { "stat2" }, { "ap" }, { "crit" }, { "stat1" }, { "stat3" }, tip = "Werte: Treffer bis +9 %, Beweglichkeit (1 AP, ca. 29 = 1 % Krit), AP, Krit;Waffe: Kampf = schnelle Nebenhand, langsame Haupthand (Finsterer Stoss); Dolche fuer Meucheln;Rotation: Combopunkte aufbauen, Zerhaecksler oben halten, dann Ausweiden;Tipp: mit zwei Waffen verfehlen normale Schlaege oefter - Treffer ist am wichtigsten" },
            HUNTER = { { "hit" }, { "stat2" }, { "ap" }, { "crit" }, { "stat4" }, { "stat3" }, tip = "Werte: Treffer bis +9 %, Beweglichkeit (2 Distanz-AP, ca. 53 = 1 % Krit), AP, Intelligenz;Waffe: langsame Distanzwaffe (hoher Schaden pro Schuss), Nahkampfwaffe mit Werten;Rotation: Mal des Jaegers, Automatischer Schuss, Zielschuss/Mehrfachschuss dazwischen;Tipp: Begleiter fuettern und gluecklich halten, Eisfalle (Quadrat) als Kontrolle" },
            WARRIOR_melee = { { "hit" }, { "stat1" }, { "crit" }, { "stat2" }, { "ap" }, { "stat3" }, tip = "Werte: Treffer bis +9 %, Staerke (1 Punkt = 2 AP), Krit (ca. 20 Beweglichkeit = 1 %);Waffe: langsamer Zweihaender (Toedlicher Stoss, Heldenhafter Stoss wirken pro Schlag);Rotation: Wut aufbauen, Toedlicher Stoss / Blutdurst, Wirbelwind, ueberschuessige Wut in Heldenhaften Stoss;Tipp: Kampfrausch-Ruf vor dem Kampf, Hinrichten unter 20 % Leben" },
            WARRIOR_tank = { { "def" }, { "stat3" }, { "armor" }, { "hit" }, { "dodge" }, { "stat2" }, { "parry" }, tip = "Werte: Verteidigung (440 = auf 60 kritsicher gegen Bosse), Ausdauer, Ruestung, Schildblock;Waffe: Einhandwaffe + Schild, schnelle Waffe = mehr Wut;Rotation: Schildschlag/Rachsucht, Ruestung zerreissen auf das Ziel, Heldenhafter Stoss bei viel Wut;Tipp: Treffer hilft, damit Spott und Faehigkeiten nicht verfehlen" },
            PALADIN_tank = { { "def" }, { "stat3" }, { "armor" }, { "sp" }, { "block" }, tip = "Werte: Verteidigung, Ausdauer, Ruestung, dann Zauberschaden fuer mehr Bedrohung;Waffe: Einhandwaffe (gern mit Zauberschaden) + Schild;Rotation: Zorn der Gerechtigkeit an, Weihe fuer Gruppen, Heiliger Schild oben halten;Tipp: Mana ist knapp - Siegel der Weisheit oder Intelligenz mitnehmen" },
            PALADIN_healer = { { "heal" }, { "stat4" }, { "scrit" }, { "mp5" }, { "stat3" }, tip = "Werte: +Heilung, Intelligenz, Zauber-Krit (Erleuchtung gibt Mana zurueck), Mana-Reg.;Waffe: Einhandwaffe + Nebenhand/Schild mit Heilung;Heilen: Lichtblitz fuer kleinen Schaden, Heiliges Licht (niedriger Rang) fuer grosse Treffer;Tipp: Segen verteilen, Gottesschutz wenn du gezogen wirst" },
            PALADIN_hybrid = { { "stat1" }, { "crit" }, { "hit" }, { "stat2" }, { "stat4" }, { "stat3" }, tip = "Werte: Staerke (1 Punkt = 2 AP), Krit, Treffer bis +9 %;Waffe: langsamer Zweihaender - Siegel und Richturteil wirken pro Schlag;Rotation: Siegel der Rechtschaffenheit/des Befehls, Richturteil, Siegel neu setzen;Tipp: Weihe nur mit genug Mana, Segen der Macht fuer dich" },
            SHAMAN_healer = { { "heal" }, { "mp5" }, { "stat4" }, { "scrit" }, { "stat3" }, tip = "Werte: +Heilung, Mana-Reg. (MP5), Intelligenz - Willenskraft bringt wenig;Waffe: Einhandwaffe + Schild mit Heilung;Heilen: Kettenheilung fuer Gruppen, Welle der Heilung (niedriger Rang) fuer den Tank;Tipp: Manaquelle-Totem stellen, Erdschild auf den Tank" },
            SHAMAN_hybrid = { { "stat1" }, { "crit" }, { "hit" }, { "stat2" }, { "ap" }, { "stat4" }, tip = "Werte: Staerke (1 Punkt = 2 AP), Krit (loest Schlaghagel aus = schneller schlagen), Treffer bis +9 %;Waffe: langsame Zweihandwaffe - Windzorn trifft pro Schlag, also je langsamer desto mehr Schaden;Rotation: Windzorn-Waffe, Sturmschlag, Erdschock;Tipp: Totem der Staerke der Erde und Windzorn-Totem fuer die Gruppe" },
            SHAMAN_caster = { { "sp" }, { "scrit" }, { "stat4" }, { "mp5" }, { "shit" }, tip = "Werte: Zauberschaden, Zauber-Krit (Elementarfokus spart Mana), Intelligenz, Mana-Reg.;Waffe: Einhandwaffe + Schild/Nebenhand mit Zauberschaden;Rotation: Blitzschlag spammen, Kettenblitz bei Gruppen, Flammenschock;Tipp: Zaubertreffer bis +16 % im Raid, Manaquelle-Totem gegen leeres Mana" },
            DRUID_healer = { { "heal" }, { "stat4" }, { "stat5" }, { "mp5" }, { "stat3" }, tip = "Werte: +Heilung, Intelligenz, Willenskraft, Mana-Reg.;Waffe: Stab oder Einhandwaffe + Nebenhand mit Heilung;Heilen: Verjuengung und Nachwachsen vorab, Heilende Beruehrung fuer grosse Treffer;Tipp: Anregen fuer Mana, Wiedergeburt fuer gefallene Heiler" },
            DRUID_tank = { { "armor" }, { "stat3" }, { "stat2" }, { "def" }, { "stat1" }, { "hit" }, tip = "Werte: Ruestung (Baerengestalt vervielfacht sie), Ausdauer, Beweglichkeit (Ausweichen + Ruestung);Waffe: egal fuer den Schaden - nur die Werte zaehlen (Stab/Stangenwaffe mit Ausdauer);Rotation: Zermalmen, Prankenhieb fuer Gruppen, Demoralisierendes Gebruell;Tipp: Staerke fuer mehr Bedrohung, Wutanfall zum Start" },
            DRUID_hybrid = { { "stat1" }, { "stat2" }, { "crit" }, { "hit" }, { "stat3" }, tip = "Werte: Staerke (1 Punkt = 2 AP), Beweglichkeit (AP + Krit), Krit, Treffer bis +9 %;Waffe: egal fuer den Schaden - nur die Werte zaehlen;Rotation: Krallenhieb/Schreddern fuer Combopunkte, dann Wilder Biss;Tipp: Machtwandel (Gestalt neu) fuer Energie, aus dem Schleichen anspringen" },
            DRUID_caster = { { "sp" }, { "scrit" }, { "stat4" }, { "shit" }, { "mp5" }, tip = "Werte: Zauberschaden, Zauber-Krit, Intelligenz, Zaubertreffer bis +16 % im Raid;Waffe: Stab oder Einhandwaffe + Nebenhand mit Zauberschaden;Rotation: Mondfeuer + Insektenschwarm, dann Zorn oder Sternenfeuer;Tipp: Anregen fuer dich selbst, wenn das Mana knapp wird" },
            PRIEST_healer = { { "heal" }, { "stat5" }, { "stat4" }, { "mp5" }, { "stat3" }, tip = "Werte: +Heilung, Willenskraft (Meditation: Regeneration auch beim Zaubern), Intelligenz, Mana-Reg.;Waffe: Stab oder Einhandwaffe + Nebenhand mit Heilung, Zauberstab;Heilen: Erneuerung und Machtwort: Schild vorab, Grosse Heilung (niedriger Rang) fuer den Tank;Tipp: Gebet der Heilung fuer die Gruppe, Verblassen bei Aggro" },
            PRIEST_caster = { { "sp" }, { "shit" }, { "stat4" }, { "stat5" }, { "stat3" }, tip = "Werte: Zauberschaden, Zaubertreffer bis +16 % (Raid), Willenskraft fuer Mana;Waffe: Stab oder Einhandwaffe + Nebenhand mit Zauberschaden;Rotation: Schattenwort: Schmerz, Gedankenschlag, Gedankenschinden;Tipp: Schattengestalt dauerhaft an, Vampirumarmung heilt die Gruppe" },
        }
        function soon:Prio()
            local o = self:CurrentOption()
            return PRIO[o[4]]
        end
        -- Werte aus der angelegten Ausruestung: Summe je Wert + Liste der Teile
        local GEARKEY = {
            STRENGTH = "stat1", AGILITY = "stat2", STAMINA = "stat3", INTELLECT = "stat4", SPIRIT = "stat5",
            ATTACK_POWER = "ap", SPELL_DAMAGE_DONE = "sp", SPELL_POWER = "sp", SPELL_HEALING_DONE = "heal",
            POWER_REGEN0 = "mp5", MANA_REGENERATION = "mp5",
        }
        local function gearStats()
            local sum, parts = {}, {}
            if not (GetInventoryItemLink and (C_Item and C_Item.GetItemStats or GetItemStats)) then return sum, parts end
            local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
            for slot = 1, 19 do
                local link = ns.safe(GetInventoryItemLink("player", slot))
                if link then
                    local ok, st = pcall(getStats, link)
                    if ok and type(st) == "table" then
                        for k, v in pairs(st) do
                            local kk = tostring(k):gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_NAME$", "")
                            local key = GEARKEY[kk]
                            if not key then
                                local r = kk:match("^RESISTANCE(%d)")
                                if r == "0" then key = "armor" elseif r then key = "res" .. r end
                            end
                            v = tonumber(v)
                            if key and v and v ~= 0 then
                                sum[key] = (sum[key] or 0) + v
                                parts[key] = parts[key] or {}
                                table.insert(parts[key], { link = link, v = v })
                            end
                        end
                    end
                end
            end
            for _, l in pairs(parts) do table.sort(l, function(a, b) return a.v > b.v end) end
            return sum, parts
        end
        -- Tooltip-Zeilen "woraus setzt sich der Wert zusammen"
        local function gearLines(lines, G, P, key, label)
            local g = G[key] or 0
            if g ~= 0 then
                lines[#lines + 1] = (label or L["Ausruestung"]) .. ":  |cff66db9e+" .. fmt(g) .. "|r"
                for i, x in ipairs(P[key] or {}) do
                    if i > 4 then lines[#lines + 1] = "   |cff777777" .. (L["+ %d weitere"]):format(#P[key] - 4) .. "|r" break end
                    lines[#lines + 1] = "   " .. x.link .. "  |cff888888+" .. fmt(x.v) .. "|r"
                end
            end
            return g
        end
        function soon:CharStats()
            local out = {}
            local lvl = num(UnitLevel("player")) or 1
            local _, cls = UnitClass("player")
            cls = ns.safe(cls) or ""
            local curKey
            local function add(label, value, raw, expect)
                if value and value ~= "" then out[#out + 1] = { label, value, raw and expect and expect > 0 and (raw / expect) or nil, expect, key = curKey, detail = soon.detail } end
                soon.detail = nil
            end
            local function K_(k) curKey = k end
            local hp = num(UnitHealthMax("player"))
            local _, sta = UnitStat("player", 3)
            sta = num(sta) or 0
            local fromSta = sta > 20 and (20 + (sta - 20) * 10) or sta
            soon.detail = { (L["aus Ausdauer (%d)"]):format(sta) .. ":  +" .. fmt(fromSta), L["Grundwert (Klasse, Level)"] .. ":  " .. fmt((hp or 0) - fromSta),
                "|cff888888" .. L["Die ersten 20 Ausdauer geben je 1, jeder weitere Punkt 10 Gesundheit."] .. "|r" }
            K_("hp")
            add(HEALTH or L["Gesundheit"], fmt(hp), hp, 20 + 16 * lvl + 0.7 * lvl * lvl)
            local pmax = num(UnitPowerMax("player"))
            if pmax and pmax > 0 then
                local _, token = UnitPowerType("player")
                K_("power")
                add(_G[token or ""] or L["Kraft"], fmt(pmax))
            end
            local G, P = gearStats()
            local raceName = ns.safe((UnitRace("player"))) or ""
            for i = 1, 5 do
                local base0, stat, posB, negB = UnitStat("player", i)
                base0, posB, negB = num(base0) or 0, num(posB) or 0, num(negB) or 0
                local d = { (L["Grundwert (%s, Klasse, Level)"]):format(raceName) .. ":  " .. fmt(base0) }
                local g = gearLines(d, G, P, "stat" .. i)
                if posB - g > 0 then d[#d + 1] = L["Buffs & Talente"] .. ":  |cff6199ff+" .. fmt(posB - g) .. "|r" end
                if negB < 0 then d[#d + 1] = L["Abzuege"] .. ":  |cffe64040" .. fmt(negB) .. "|r" end
                soon.detail = d
                local main = MAIN[cls] and MAIN[cls][i]
                K_("stat" .. i)
                add(_G["SPELL_STAT" .. i .. "_NAME"] or ("Stat " .. i), fmt(num(stat)), main and num(stat), main and (20 + 1.8 * lvl) or nil)
            end
            local _, armor = UnitArmor("player")
            do
                local d = {}
                local g = gearLines(d, G, P, "armor")
                local _, agi = UnitStat("player", 2)
                agi = num(agi) or 0
                d[#d + 1] = (L["aus Beweglichkeit (%d x 2)"]):format(agi) .. ":  +" .. fmt(agi * 2)
                local rest = (num(armor) or 0) - g - agi * 2
                if rest > 0 then d[#d + 1] = L["Buffs, Talente, Gestalt"] .. ":  |cff6199ff+" .. fmt(rest) .. "|r" end
                soon.detail = d
            end
            K_("armor")
            add(ARMOR or L["Ruestung"], fmt(num(armor)), num(armor), (ARMOR_K[cls] or 20) * lvl)
            local base, pos, neg = UnitAttackPower("player")
            do
                local d = { L["Grundwert (aus Staerke/Beweglichkeit/Level)"] .. ":  " .. fmt(num(base) or 0) }
                gearLines(d, G, P, "ap")
                if (num(pos) or 0) - (G.ap or 0) > 0 then d[#d + 1] = L["Buffs & Talente"] .. ":  |cff6199ff+" .. fmt((num(pos) or 0) - (G.ap or 0)) .. "|r" end
                if (num(neg) or 0) < 0 then d[#d + 1] = L["Abzuege"] .. ":  |cffe64040" .. fmt(num(neg)) .. "|r" end
                soon.detail = d
            end
            K_("ap")
            if num(base) then add(ATTACK_POWER_TOOLTIP or L["Angriffskraft"], fmt(num(base) + (num(pos) or 0) + (num(neg) or 0))) end
            local lo, hi = UnitDamage("player")
            K_("dmg")
            if num(lo) and num(hi) then add(L["Waffenschaden"], fmt(num(lo)) .. " - " .. fmt(num(hi))) end
            local speed = UnitAttackSpeed and num((UnitAttackSpeed("player")))
            K_("speed")
            if speed then add(L["Angriffstempo"], ("%.2f s"):format(speed)) end
            K_("crit")
            if GetCritChance then
                local c = num(GetCritChance())
                if c then
                    local _, agi = UnitStat("player", 2)
                    agi = num(agi) or 0
                    local per = ({ ROGUE = 29, HUNTER = 53, WARRIOR = 20, PALADIN = 20, SHAMAN = 20, DRUID = 20 })[cls] or 20
                    local fromAgi = agi / per
                    soon.detail = { (L["aus Beweglichkeit: ca. %.1f %% (%d Bew. = 1 %%)"]):format(fromAgi, per),
                        (L["Grundwert, Talente, Ausruestung: ca. %.1f %%"]):format(math.max(0, c - fromAgi)) }
                    add(L["Kritische Treffer"], ("%.1f %%"):format(c), c, 6)
                end
            end
            K_("scrit")
            if GetSpellCritChance then local c = num(GetSpellCritChance(2)) if c and c > 0 then add(L["Zauber-Krit"], ("%.1f %%"):format(c)) end end
            -- Zauber: Schaden (beste Schule), Heilung, Mana-Regeneration, Treffer
            if GetSpellBonusDamage then
                local best = 0
                for school = 2, 7 do local v = num(GetSpellBonusDamage(school)) if v and v > best then best = v end end
                K_("sp")
                if best > 0 then
                    local d = {}
                    local g = gearLines(d, G, P, "sp")
                    if best - g > 0 then d[#d + 1] = L["Buffs & Talente"] .. ":  |cff6199ff+" .. fmt(best - g) .. "|r" end
                    soon.detail = d
                    add(L["Zauberschaden"], fmt(best))
                end
            end
            K_("heal")
            if GetSpellBonusHealing then
                local v = num(GetSpellBonusHealing())
                if v and v > 0 then
                    local d = {}
                    local g = gearLines(d, G, P, "heal")
                    if v - g > 0 then d[#d + 1] = L["Buffs & Talente"] .. ":  |cff6199ff+" .. fmt(v - g) .. "|r" end
                    soon.detail = d
                    add(L["Heilung"], fmt(v))
                end
            end
            if GetManaRegen and pmax and pmax > 0 then
                local base, casting = GetManaRegen()
                base, casting = num(base), num(casting)
                K_("mp5")
                if base then add(L["Mana-Reg. (5 s)"], fmt(base * 5) .. (casting and ("  |cff888888/ " .. fmt(casting * 5) .. "|r") or "")) end
            end
            -- Treffer: WoW-Wert, sonst aus den Texten der angelegten Teile ("Trefferchance um 1%")
            local gearHit, gearSpell, hitParts = 0, 0, {}
            do
                local tip = C_TooltipInfo and C_TooltipInfo.GetInventoryItem
                for slot = 1, 18 do
                    local ok, data = pcall(function() return tip and tip("player", slot) end)
                    if ok and data and data.lines then
                        for _, ln in ipairs(data.lines) do
                            local t = ns.safe(ln.leftText)
                            if t then
                                local low = t:lower()
                                local n = tonumber(low:match("treffer%a*[^%d]-(%d+)%s*%%") or low:match("chance to hit[^%d]-(%d+)%s*%%") or "")
                                if n and (low:find("treffer") or low:find("hit")) then
                                    if low:find("zauber") or low:find("spell") then gearSpell = gearSpell + n
                                    else gearHit = gearHit + n hitParts[#hitParts + 1] = "+" .. n .. " %  " .. (ns.safe(data.lines[1] and data.lines[1].leftText) or "") end
                                end
                            end
                        end
                    end
                end
            end
            K_("hit")
            do
                local v = GetHitModifier and num(GetHitModifier()) or 0
                if (v or 0) <= 0 and gearHit > 0 then v = gearHit end
                if #hitParts > 0 then soon.detail = hitParts end
                add(L["Trefferchance"], ("+%.1f %%"):format(v or 0))
            end
            K_("shit")
            do
                local v = GetSpellHitModifier and num(GetSpellHitModifier()) or 0
                if (v or 0) <= 0 and gearSpell > 0 then v = gearSpell end
                add(L["Zaubertreffer"], ("+%.1f %%"):format(v or 0))
            end
            K_("dodge")
            if GetDodgeChance then local c = num(GetDodgeChance()) if c then add(L["Ausweichen"], ("%.1f %%"):format(c)) end end
            K_("parry")
            if GetParryChance then local c = num(GetParryChance()) if c and c > 0 then add(L["Parieren"], ("%.1f %%"):format(c)) end end
            K_("block")
            if GetBlockChance then local c = num(GetBlockChance()) if c and c > 0 then add(L["Blocken"], ("%.1f %%"):format(c)) end end
            local _, avg = GetAverageItemLevel()
            -- Verteidigung (Tank) und Widerstaende
            K_("def")
            if UnitDefense then
                local b, m = UnitDefense("player")
                b, m = num(b), num(m)
                if b then add(DEFENSE or L["Verteidigung"], fmt(b + (m or 0))) end
            end
            K_("res")
            if UnitResistance then
                for school = 2, 6 do
                    local _, total = UnitResistance("player", school)
                    total = num(total)
                    local name = _G["SPELL_SCHOOL" .. school .. "_CAP"] or _G["RESISTANCE" .. school .. "_NAME"] or ("#" .. school)
                    -- Symbol wie im Charakterfenster (Blizzards Bildleiste mit 5 Widerstaenden untereinander)
                    local ICO = { [2] = { 0, 29 }, [4] = { 29, 58 }, [6] = { 58, 87 }, [3] = { 87, 116 }, [5] = { 116, 145 } }
                    local ic = ICO[school]
                    local tex = ic and ("|TInterface\\PaperDollInfoFrame\\UI-Character-ResistanceIcons:14:14:0:0:32:256:2:30:" .. ic[1] .. ":" .. ic[2] .. "|t  ") or ""
                    if total then
                        local d = {}
                        local g = gearLines(d, G, P, "res" .. school)
                        if total - g > 0 then d[#d + 1] = L["Volk, Buffs, Talente"] .. ":  |cff6199ff+" .. fmt(total - g) .. "|r" end
                        soon.detail = d
                        K_("res" .. school)
                        add(tex .. (L["%s-Widerstand"]):format(name), fmt(total))
                    end
                end
            end
            K_("ilvl")
            if num(avg) and num(avg) > 0 then add(L["Gegenstandsstufe"], ("%.1f"):format(num(avg)), num(avg), math.max(5, lvl * 0.9)) end
            return out
        end

        -- Werte eintragen: nur so viele Zeilen, wie in die Spalte passen (neu, sobald die Hoehe feststeht)
        function soon:FillStats(st)
            self:EnsureRoleSeg()
            st = st or self.lastStats
            if not st then return end
            self.lastStats = st
            -- sortieren: fuer die Rolle relevante Werte zuerst, Rest hinter einer einklappbaren Zeile
            if ns.Card then pcall(ns.Card.Record, st) end
            local roleKey, roleName = self:Role()
            local rel = REL[roleKey] or {}
            local top, rest, res, ilvlX = {}, {}, {}, nil
            for _, x in ipairs(st) do
                if (x.key or ""):find("^res%d") then res[#res + 1] = x
                elseif x.key == "ilvl" then ilvlX = x
                elseif rel[x.key or ""] then top[#top + 1] = x else rest[#rest + 1] = x end
            end
            -- Leiste oben: links Gegenstandsstufe, rechts die Widerstaende als farbige Kacheln
            local SCHOOL = {
                res2 = { 1, 0.45, 0.2, "Feuer" }, res3 = { 0.35, 0.85, 0.35, "Natur" }, res4 = { 0.4, 0.75, 1, "Frost" },
                res5 = { 0.7, 0.4, 1, "Schatten" }, res6 = { 0.95, 0.6, 1, "Arkan" },
            }
            if not self.cs.resBar then
                local rb = CreateFrame("Frame", nil, self.cs)
                rb:SetPoint("TOPLEFT", 12, -36)
                rb:SetPoint("TOPRIGHT", -12, -36)
                rb:SetHeight(30)
                rb.cells = {}
                -- Gegenstandsstufe
                local il = CreateFrame("Frame", nil, rb)
                il:SetPoint("TOPLEFT") il:SetPoint("BOTTOMLEFT")
                il:SetWidth(150)
                IG.Glass(il, IG.GLASS_FILL, IG.GLASS_LINE, 8)
                il.bar = il:CreateTexture(nil, "ARTWORK")
                il.bar:SetPoint("LEFT", 8, 0)
                il.bar:SetSize(3, 12)
                if K.RoundMask then K.RoundMask(il.bar, il.bar, 1) end
                il.lbl = K.Text(il, 11, C.muted)
                il.lbl:SetPoint("LEFT", 17, 0)
                il.val = K.Text(il, 15, C.text, "RIGHT")
                il.val:SetPoint("RIGHT", -10, 0)
                il:EnableMouse(true)
                il:SetScript("OnEnter", function(f) if f.info then K.ShowTip(f, f.info) end end)
                il:SetScript("OnLeave", function() GameTooltip:Hide() end)
                rb.il = il
                self.cs.resBar = rb
            end
            local rb = self.cs.resBar
            local il = rb.il
            if ilvlX then
                local lvl = UnitLevel("player") or 1
                local v = tonumber(ilvlX[2]) or 0
                local goal = tonumber(ilvlX[4]) or math.max(5, lvl * 0.9)
                local col = v >= goal and C.mint or (v >= goal * 0.85 and C.amber or C.red)
                il.lbl:SetText(plain(L["Gegenstandsstufe"]))
                il.val:SetText(K.hex(col) .. ilvlX[2] .. "|r")
                il.bar:SetColorTexture(col[1], col[2], col[3], 1)
                il.info = { L["Gegenstandsstufe"] .. ":  " .. ilvlX[2], ("|cff888888" .. L["gut fuer Level %d: ab %.0f"] .. "|r"):format(lvl, goal) }
                il:Show()
            else
                il:Hide()
            end
            local left = il:IsShown() and 156 or 0
            local cw = ((rb:GetWidth() > 50 and rb:GetWidth() or 600) - left - math.max(0, #res - 1) * 4) / math.max(1, #res)
            for i, x in ipairs(res) do
                local c = rb.cells[i]
                if not c then
                    -- Widerstaende: gleich grosse Glas-Pillen in einer Reihe, Schulfarbe nur als Zahl
                    c = CreateFrame("Frame", nil, rb)
                    c:SetSize(60, 30)
                    IG.Glass(c, IG.GLASS_FILL, IG.GLASS_LINE, 8)
                    c.bg = c:CreateTexture(nil, "BACKGROUND")
                    c.bg:Hide()
                    c.line = c:CreateTexture(nil, "ARTWORK")
                    c.line:Hide()
                    c.icon = K.Text(c, 12, C.text)
                    c.icon:SetPoint("LEFT", 8, 0)
                    c.name = K.Text(c, 10, C.muted)
                    c.name:SetPoint("LEFT", c.icon, "RIGHT", 4, 0)
                    c.val = K.Text(c, 14, C.text, "RIGHT")
                    c.val:SetPoint("RIGHT", -8, 0)
                    c:EnableMouse(true)
                    c:SetScript("OnEnter", function(cell) if cell.info then K.ShowTip(cell, cell.info) end end)
                    c:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    rb.cells[i] = c
                end
                local sc = SCHOOL[x.key] or { 0.8, 0.8, 0.8, "" }
                local val = tonumber((tostring(x[2]):gsub("[^%d]", ""))) or 0
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", rb, "TOPLEFT", left + (i - 1) * (cw + 4), 0)
                c:SetSize(cw, 30)
                c.icon:SetText((x[1] or ""):match("^(|T.-|t)") or "")
                c.name:SetText(cw > 95 and plain(L[sc[4]]) or "")
                c.val:SetText((val > 0 and K.hex({ math.min(1, sc[1] + 0.2), math.min(1, sc[2] + 0.2), math.min(1, sc[3] + 0.2) }) or "|cff666666") .. x[2] .. "|r")
                local info = { (x[1] or ""):gsub("^|T.-|t%s*", "") .. ":  " .. x[2] }
                for _, dl in ipairs(x.detail or {}) do info[#info + 1] = dl end
                c.info = info
                c:Show()
            end
            for i = #res + 1, #rb.cells do rb.cells[i]:Hide() end
            rb:SetShown((#res > 0 or ilvlX ~= nil) and not self.consBox)
            -- 0.6.334: mit eigener Verbrauchsgueter-Box: keine Widerstands-Reihe, Gegenstandsstufe rechts im Kopf
            if self.consBox then
                if not self.cs.ilvlTxt then
                    self.cs.ilvlTxt = K.Text(self.cs, 11, C.muted, "RIGHT")
                    self.cs.ilvlTxt:SetPoint("TOPRIGHT", self.cs, "TOPRIGHT", -14, -15)
                end
                self.cs.ilvlTxt:SetText(ilvlX and (plain(L["Gegenstandsstufe"]) .. "   " .. (il.val:GetText() or "")) or "")
            end
            self.cs.head.text:SetText(plain(L["Charakterwerte"]) .. "  |cff888888· " .. L["fuer"] .. " " .. roleName .. "|r")
            local view = {}
            for _, x in ipairs(top) do view[#view + 1] = x end
            if #rest > 0 then
                view[#view + 1] = { toggle = true, plain(L["Weitere Werte"]) .. "  |cff666666" .. #rest .. "|r",
                    "|cff888888" .. (self.showAll and L["ausblenden"] or L["einblenden"]) .. "|r" }
                if self.showAll then for _, x in ipairs(rest) do view[#view + 1] = x end end
            end
            st = view
            local h = self.cs:GetHeight() or 0
            if h < 60 then h = 300 end
            -- Werte links in einer Spalte, rechts die Einblicke (Treffer, Tempo, Upgrade, Verbrauchsgueter)
            local RH = self.consBox and 19 or 23   -- 0.6.358: Profil kompakter, alles ohne Scrollen
            local perCol = math.max(1, math.floor((h - (self.consBox and 42 or 84) - 10) / RH))   -- unten Luft (auch fuer die Klapp-Leiste)
            local fits = perCol
            if ns.Insights then pcall(ns.Insights.Fill, self, self.cs, st) end
            local W = self.cs:GetWidth() or 700
            if W < 100 then W = 700 end
            local colW = self.consBox and (W - 24 - 10) or math.floor((W - 24 - 20) / 2)
            for i, r in ipairs(self.cs.rows) do
                local col = (i - 1) >= perCol and 1 or 0
                local row = (i - 1) % perCol
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self.cs, "TOPLEFT", 12 + col * (colW + 20), (self.consBox and -40 or -80) - row * RH)
                r:SetHeight(RH - 1)
                r:SetWidth(colW)
            end
            local lvl = num(UnitLevel("player")) or 1
            -- scrollen, wenn mehr Werte als Platz (Mausrad)
            self.statOff = math.max(0, math.min(self.statOff or 0, #st - fits))
            local off = self.statOff
            if not self.cs.more then
                self.cs.more = K.Text(self.cs, 10, C.dim, "CENTER")
                self.cs.more:SetPoint("BOTTOM", self.cs, "BOTTOMLEFT", 12 + colW / 2, 4)
            end
            local below = #st - fits - off
            self.cs.more:SetText("")
            -- schlanke Scrollleiste rechts der Werte + weicher Verlauf unten, wenn noch mehr kommt
            if not self.cs.sbTrack then
                self.cs.sbTrack = self.cs:CreateTexture(nil, "ARTWORK")
                self.cs.sbTrack:SetColorTexture(1, 1, 1, 0.06)
                self.cs.sbTrack:SetWidth(3)
                self.cs.sbThumb = self.cs:CreateTexture(nil, "OVERLAY")
                self.cs.sbThumb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.85)
                self.cs.sbThumb:SetWidth(3)
                self.cs.fade = self.cs:CreateTexture(nil, "OVERLAY", nil, 2)
                self.cs.fade:SetHeight(26)
                if not K.Gradient(self.cs.fade, "VERTICAL", { C.panel[1], C.panel[2], C.panel[3], 0.95 }, { C.panel[1], C.panel[2], C.panel[3], 0 }) then self.cs.fade:SetColorTexture(0, 0, 0, 0.4) end
            end
            local trackH = fits * RH
            local scrollable = #st > fits
            self.cs.sbTrack:ClearAllPoints()
            self.cs.sbTrack:SetPoint("TOPLEFT", self.cs, "TOPLEFT", 12 + colW + 6, (self.consBox and -40 or -80))
            self.cs.sbTrack:SetHeight(trackH)
            self.cs.sbTrack:SetShown(scrollable)
            if scrollable then
                local th = math.max(14, trackH * fits / #st)
                local maxOff = math.max(1, #st - fits)
                self.cs.sbThumb:ClearAllPoints()
                self.cs.sbThumb:SetPoint("TOPLEFT", self.cs.sbTrack, "TOPLEFT", 0, -(trackH - th) * off / maxOff)
                self.cs.sbThumb:SetHeight(th)
            end
            self.cs.sbThumb:SetShown(scrollable)
            self.cs.fade:ClearAllPoints()
            self.cs.fade:SetPoint("BOTTOMLEFT", self.cs, "TOPLEFT", 12, (self.consBox and -40 or -80) - trackH)
            self.cs.fade:SetWidth(colW)
            self.cs.fade:SetShown(below > 0)
            for i, r in ipairs(self.cs.rows) do
                local x = st[i + off]
                if x and i <= fits then
                    r.toggle = x.toggle
                    -- etwas Luft vor der Klapp-Leiste "Weitere Werte"
                    if x.toggle then
                        local pt, rel, rp, px, py = r:GetPoint(1)
                        if pt then r:SetPoint(pt, rel, rp, px, py - (self.consBox and (self.showAll and 0 or 6) or 8)) end   -- 0.6.408: zugeklappt etwas Luft, ausgeklappt buendig
                    end
                    r.l:SetText(x[1])
                    r.key = x.key
                    r.v:SetText(x[2])
                    local lc = x.toggle and C.text or C.muted
                    r.l:SetTextColor(lc[1], lc[2], lc[3])
                    if x.toggle then
                        -- Klapp-Leiste: duenne Linie oben, kein Farbstreifen
                        r.q:SetColorTexture(1, 1, 1, 0.025)
                        r.qbar:SetColorTexture(0, 0, 0, 0)
                        r.v:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
                        r.l:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
                    end
                    local q = x[3] and soon.Quality(x[3])
                    r.ratio = x[3]   -- 0.6.379: Verhaeltnis zum ueblichen Wert (fuer den Fortschritt im Hintergrund)
                    local c = q and q[2]
                    if c then
                        r.q:SetColorTexture(0, 0, 0, 0)
                        r.qbar:SetColorTexture(c[1], c[2], c[3], 1)
                        r.v:SetTextColor(math.min(1, c[1] + 0.25), math.min(1, c[2] + 0.25), math.min(1, c[3] + 0.25))
                    else
                        r.q:SetColorTexture(0, 0, 0, 0)
                        r.qbar:SetColorTexture(0, 0, 0, 0)
                        r.v:SetTextColor(C.text[1], C.text[2], C.text[3])
                    end
                    local info = { x[1] .. ":  " .. x[2] }
                    if x.detail and #x.detail > 0 then
                        info[#info + 1] = "|cffe8b44a" .. L["Setzt sich zusammen aus:"] .. "|r"
                        for _, dl in ipairs(x.detail) do info[#info + 1] = dl end
                    end
                    if q then
                        info[#info + 1] = " "
                        info[#info + 1] = (L["Einordnung: %s"]):format(K.hex(c or C.text) .. L[q[3]] .. "|r")
                        info[#info + 1] = (L["Ueblich auf Level %d: ca. %s"]):format(lvl, fmt(x[4]))
                        info[#info + 1] = "|cff888888" .. L["Oasis-Schaetzung: Grundwerte der Klasse + typische Ausruestung fuer dein Level."] .. "|r"
                    end
                    if not r.goal then
                        r.goal = r:CreateTexture(nil, "OVERLAY")
                        r.goal:SetPoint("BOTTOMLEFT", 0, 0)
                        r.goal:SetHeight(2)
                        r.goalBg = r:CreateTexture(nil, "ARTWORK")
                        r.goalBg:SetPoint("BOTTOMLEFT", 0, 0)
                        r.goalBg:SetPoint("BOTTOMRIGHT", 0, 0)
                        r.goalBg:SetHeight(2)
                        r.goalBg:SetColorTexture(1, 1, 1, 0.07)
                    end
                    r.goal:Hide() r.goalBg:Hide()
                    do
                        local roleK = soon.Role and select(1, soon:Role()) or "melee"
                        local want = (roleK == "caster") and "shit" or ((roleK ~= "healer") and "hit" or nil)
                        if want and x.key == want then
                            local goal = (want == "shit") and 16 or 9
                            local hv = tonumber((tostring(x[2]):gsub(",", "."):gsub("[^%d%.]", ""))) or 0
                            local gc = hv >= goal and C.mint or (hv >= goal / 2 and C.amber or C.red)
                            r.v:SetText(x[2] .. "  |cff777777/ " .. goal .. " %|r")
                            r.goal:SetColorTexture(gc[1], gc[2], gc[3], 1)
                            r.goal:SetWidth(math.max(1, (r:GetWidth() or 200) * math.min(1, hv / goal)))
                            r.goal:Show() r.goalBg:Show()
                            info = info or {}
                        end
                    end
                    local avg, an = nil, nil
                    if ns.Card and x.key then avg, an = ns.Card.GuildAvg(x.key) end
                    if not r.cmp then
                        r.cmp = K.Text(r, 10, C.dim, "RIGHT")
                        r.cmp:SetPoint("RIGHT", r.v, "LEFT", -6, 0)
                    end
                    r.cmp:SetText("")
                    do
                        local raw = type(x[2]) == "string" and x[2]:gsub("[^%d%.,]", "") or ""
                        if raw:match("^%d+[%.,]%d%d%d") then raw = raw:gsub("[%.,]", "") else raw = raw:gsub(",", ".") end
                        local v = tonumber(raw)
                        if avg and avg > 0 and v then
                            local d = math.floor((v / avg - 1) * 100 + 0.5)
                            if d ~= 0 then r.cmp:SetText(d > 0 and ("|cff66db9e+" .. d .. "%|r") or ("|cffe06060" .. d .. "%|r")) end
                        end
                    end
                    if avg then
                        info[#info + 1] = " "
                        info[#info + 1] = "|cff6199ff" .. (L["Gilde (deine Klasse, Level +-3): Schnitt %s aus %d"]):format(avg < 100 and ("%.1f"):format(avg) or fmt(avg), an) .. "|r"
                    end
                    r.info = (#info > 1) and info or nil
                    r:Show()
                else
                    r:Hide()
                end
            end
        end
        cs:SetScript("OnSizeChanged", function() soon:FillStats() end)
        cs:EnableMouseWheel(true)
        cs:SetScript("OnMouseWheel", function(_, d)
            soon.statOff = math.max(0, (soon.statOff or 0) - d * 2)
            soon:FillStats()
        end)
        function soon:FillPrio(st)
            local pl = self:Prio()
            local byKey = {}
            for _, x in ipairs(st or self.lastStats or {}) do if x.key then byKey[x.key] = x end end
            local _, roleName = self:Role()
            self.pr.head.text:SetText(plain(L["Stat-Prioritaet"]) .. "  |cff888888· " .. roleName .. "|r")
            local LABEL = { sp = L["Zauberschaden"], shit = L["Zaubertreffer"], hit = L["Trefferchance"], crit = L["Kritische Treffer"],
                scrit = L["Zauber-Krit"], heal = L["Heilung"], mp5 = L["Mana-Reg. (5 s)"], ap = ATTACK_POWER_TOOLTIP or L["Angriffskraft"],
                armor = ARMOR or L["Ruestung"], def = DEFENSE or L["Verteidigung"], dodge = L["Ausweichen"], parry = L["Parieren"], block = L["Blocken"] }
            for i, r in ipairs(self.pr.rows) do
                local e = pl and pl[i]
                if e then
                    local k = e[1]
                    local x = byKey[k]
                    local name = LABEL[k] or (k:match("^stat(%d)$") and _G["SPELL_STAT" .. k:match("%d") .. "_NAME"]) or k
                    r.num:SetText(i)
                    r.name:SetText(name)
                    r.val:SetText(x and x[2] or "|cff555555-|r")
                    local c = i == 1 and C.amber or (i == 2 and { 0.85, 0.85, 0.9 } or { 0.8, 0.55, 0.35 })
                    r.num:SetTextColor(c[1], c[2], c[3])
                    r.bg:SetColorTexture(C.raised[1], C.raised[2], C.raised[3], i <= 3 and 1 or 0.6)
                    r:Show()
                else
                    r:Hide()
                end
            end
            local tip = pl and pl.tip and L[pl.tip] or ""
            if tip ~= "" then
                -- in Stichpunkte zerlegen (";" bzw. ". " trennt), Rolle vorne abtrennen ("Verstaerkung: ...")
                local lines = {}
                for part in (tip .. ";"):gmatch("(.-)[;]") do
                    part = part:gsub("^%s+", ""):gsub("%s+$", "")
                    -- Kennwort vorne ("Werte:", "Waffe:", ...) hervorheben
                    part = part:gsub("^([^:%s]+):", "|cffe8b44a%1:|r", 1)
                    if part ~= "" then lines[#lines + 1] = "|cffe8b44a•|r  " .. part end
                end
                self.pr.tip:SetText(table.concat(lines, "\n"))
                self.pr.tipBox:Show()
                self.pr.tipBox:Animate()
            else
                self.pr.tipBox:Hide()
            end
            -- nur so viele Prioritaets-Zeilen, wie ueber den Tipp-Kasten passen (keine Ueberlappung)
            local ph = self.pr:GetHeight() or 0
            local tipH = self.pr.tipBox:IsShown() and (42 + 20) or 12
            local maxRows = math.min(6, math.max(1, math.floor((ph - 44 - tipH) / (self.prRowH or 26))))   -- 0.6.359: bis zu 6, hoehere Zeilen
            if ph > 100 then for i, r in ipairs(self.pr.rows) do if i > maxRows then r:Hide() end end end
        end

        function soon:Update(fresh)
            local r = ns.Rank and ns.Rank.Mine()
            local _, classFile = UnitClass("player")
            classFile = ns.safe(classFile)
            local cr, cg, cb = ns.classColor(classFile)
            if not K.Gradient(hc.glow, "HORIZONTAL", { cr, cg, cb, 0.13 }, { cr, cg, cb, 0 }) then hc.glow:SetColorTexture(cr, cg, cb, 0.05) end
            if self.embers then self.embers.col = { cr, cg, cb } end
            hc.edge:SetColorTexture(cr, cg, cb, 1)
            pcall(SetPortraitTexture, self.face, "player")
            self.name:SetText(ns.colorName(ns.me() or "?", classFile))
            self.cls:SetText((ns.safe((UnitClass("player"))) or "") .. "  ·  " .. (L["Level %d"]):format(ns.safe(UnitLevel("player")) or 1))
            self.clsPill:Set(ns.safe((UnitClass("player"))) or "?", { cr, cg, cb })
            self.lvlPill:Set((L["Level %d"]):format(ns.safe(UnitLevel("player")) or 1), { 0.85, 0.85, 0.9 })
            if r then
                local key = r.frame.name .. (K.RingTier and K.RingTier(r.level) or "")
                if self.av.styleName ~= key then self.av:SetStyle(r.frame, r.level) self.av.styleName = key if self.AvatarFx then self:AvatarFx(r.level) end end
                self.rank:SetText((L["Rang %d"]):format(r.level) .. "  ·  " .. r.title)
                self.FitBar()
                self.xpFill:SetWidth(math.max(1, (self.xpW or 260) * math.min(1, r.into / math.max(1, r.need))))
                self.xpText:SetText((L["%d / %d XP bis zum naechsten Rang"]):format(r.into, r.need))
                self.pct:SetText(math.floor(r.into / math.max(1, r.need) * 100) .. " %")
                self.rank:SetText(plain((L["Rang %d"]):format(r.level)) .. "  |cffe8b44a" .. r.title .. "|r")
                self.emb:SetRank(r.level)
                -- 0.5.588: gemalter Rahmen zeigt die Rangzahl selbst im Sechseck -> Wappen nur ohne ihn
                self.emb:SetShown(not (self.av.art and self.av.art:IsShown()))
                -- naechster Rahmen: Wappen der naechsten Stufe als Vorschau
                local idx = ns.Rank.FrameIndex(r.level)
                local nf = ns.Rank.FRAMES[idx + 1]
                if nf then
                    local at = idx * 10
                    self.chipF.icon:SetTexture(ns.MEDIA .. "emblems\\tier" .. (idx + 1))
                    self.chipF.value:SetText(K.hex(nf.color) .. L[nf.name] .. "|r  |cff888888(" .. (L["Rang %d"]):format(at) .. ")|r")
                    local c = nf.color
                    self.chipF.bg:SetColorTexture(c[1] * 0.12, c[2] * 0.12, c[3] * 0.12, 1)
                    K.SetBorderColor(self.chipF, { c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, 1 })
                    self.chipF.edge:SetColorTexture(c[1], c[2], c[3], 1)
                else
                    self.chipF.icon:SetTexture(ns.MEDIA .. "emblems\\tier" .. idx)
                    self.chipF.value:SetText("|cffe8b44a" .. L["Hoechster Rahmen erreicht"] .. "|r")
                end
                -- naechste Belohnung / naechster Rahmen: Text der Rang-Seite (einmal aufbauen, versteckt)
                local def = ns.PageDef("rank")
                if def and not self.rankBuilt then
                    self.rankBuilt = true
                    pcall(def.build, self.rankHost)
                    local h = self.rankHost
                    if h.card then h.card:Hide() end
                    if h.week then h.week:SetParent(self.weeklyHost) h.week:ClearAllPoints() h.week:SetAllPoints(self.weeklyHost) self.weekMoved = true end   -- eigener Reiter Aufgaben > Wochenaufgaben
                    if h.week and self.StyleWeek then pcall(self.StyleWeek, self, h.week) end
                    self:PlaceCounters()
                end
                if def and def.refresh then pcall(def.refresh, self.rankHost) end
                local nx = self.rankHost.card and self.rankHost.card.next and self.rankHost.card.next:GetText()
                self.next:SetText(((nx or ""):gsub("\n", "   |cff555555·|r   ")))
                local first = (nx or ""):match("^([^\n]*)") or ""
                self.chipR.value:SetText((first:gsub("^[^:]*:%s*", "")))
                self.FitBar()
            end
            -- Zahlen
            local B = ns.Badges
            local mine, stats = {}, {}
            if B then mine, stats = B.Mine() end
            local earned, total = 0, 0
            for _, b in ipairs(B and B.LIST or {}) do
                total = total + #b.tiers
                earned = earned + (mine[b.id] or 0)
            end
            local chat = 0
            for _, e in ipairs(ns.db.gchat or {}) do if ns.isMe(e.s) then chat = chat + 1 end end
            -- Vitrine: Stufen gesamt + Anzahl je Medaille
            local byTier = { 0, 0, 0 }
            for _, t in pairs(mine) do if byTier[t] then byTier[t] = byTier[t] + 1 end end
            local vit = self.vit
            if fresh then K.CountUp(vit.num, earned, 0.8) else vit.num:SetText(earned) end
            vit.of:SetText("/ " .. total)
            for i, m in ipairs(vit.medals) do
                local c = B.TIERS[i].color
                m.dot:SetVertexColor(c[1], c[2], c[3])
                m.n:SetText(byTier[i])
                m.n:SetTextColor(byTier[i] > 0 and c[1] or 0.45, byTier[i] > 0 and c[2] or 0.45, byTier[i] > 0 and c[3] or 0.45)
            end
            local w = (vit.track:GetWidth() or 140)
            vit.fill:SetWidth(math.max(1, w * (total > 0 and earned / total or 0)))
            vit.pct:SetText(total > 0 and (math.floor(earned / total * 100 + 0.5) .. " %") or "")
            -- beste Abzeichen (hoechste Stufe zuerst) als Symbole
            local best = {}
            for id, tier in pairs(mine) do
                local bd = B.byId and B.byId[id]
                if bd and (tier or 0) > 0 then best[#best + 1] = { b = bd, t = tier } end
            end
            table.sort(best, function(a, b) if a.t ~= b.t then return a.t > b.t end return (a.b.id or "") < (b.b.id or "") end)
            for i, ic in ipairs(vit.icons) do
                local x = best[i]
                if x then
                    local c = B.Color(x.t)
                    local wowOk = x.b.wow and ic.icon:SetTexture(x.b.wow) ~= false
                    if not wowOk then ic.icon:SetTexture(x.b.icon) end
                    if wowOk then ic.icon:SetVertexColor(1, 1, 1) ic.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    else ic.icon:SetVertexColor(c[1], c[2], c[3]) ic.icon:SetTexCoord(0, 1, 0, 1) end
                    ic.icon:SetAlpha(1)
                    K.SetBorderColor(ic, { c[1], c[2], c[3], 0.9 })
                    ic.tip = { B.Label(x.b.id, x.t), L[x.b.desc or ""] }
                else
                    ic.icon:SetTexture(ns.MEDIA .. "icons\\badges")
                    ic.icon:SetVertexColor(0.3, 0.3, 0.32)
                    ic.icon:SetAlpha(0.4)
                    K.SetBorderColor(ic, C.line)
                    ic.tip = nil
                end
            end
            vit.tip = (L["%d Bronze, %d Silber, %d Gold"]):format(byTier[1], byTier[2], byTier[3])
            self.tiles[2]:Set(r and r.xp or 0, nil, nil, fresh)
            self.tiles[3]:Set(chat, L["Nachrichten"], nil, fresh)
            -- Liste
            local rows = {}
            for _, cat in ipairs(B and B.CATS or {}) do
                if cat.key ~= "insta" then
                    local first = true
                    for _, b in ipairs(B.LIST) do
                        if b.cat == cat.key and b.stat then
                            if first then rows[#rows + 1] = { head = cat.name } first = false end
                            rows[#rows + 1] = { b = b, v = tonumber(stats[b.stat]) or 0, tier = mine[b.id] or 0 }
                        end
                    end
                end
            end
            self.list:SetData(rows)
            -- Charakterwerte
            local st = self:CharStats()
            self:FillStats(st)
            self:FillPrio(st)
        end
        ------------------------------------------------------------------
        -- Profil 2026: kompakte Glas-Kopfzeile + schlanke Reiterleiste -> deutlich mehr Platz fuer Inhalte
        -- Kopf (112): Portraet | Name, Klasse, Level | Level- und Rang-Leiste | Belohnung + Abzeichen
        -- darunter Reiter (34) und ggf. Unterreiter (24); Inhalt ab 164 bzw. 194 px (vorher 254 / 288)
        ------------------------------------------------------------------
        do
            local PH, X1, X2, RW = soon.HEAD_H, 140, 300, 0   -- 0.6.373: Karten rechts entfallen, Leisten bekommen die Breite
            local ac = C.accent
            hc:ClearAllPoints()
            hc:SetPoint("TOPLEFT", 0, 0)
            hc:SetPoint("TOPRIGHT", 0, 0)
            hc:SetHeight(PH)
            IG.Glass(hc, IG.GLASS_FILL, IG.GLASS_LINE, 14)
            hc.edge:Hide()
            -- leichter Verlauf in der Klassenfarbe (Farbe setzt soon:Update) - innerhalb der runden Ecken
            hc.glow:ClearAllPoints()
            hc.glow:SetPoint("TOPLEFT", 3, -3)
            hc.glow:SetPoint("BOTTOMRIGHT", -3, 3)
            hc.glow:Hide()   -- 0.6.333: kein Klassenfarben-Verlauf mehr (wirkte rosa)
            -- Glut: kleine Funken in der Klassenfarbe steigen langsam auf (vor allem links ums Portraet)
            local em = CreateFrame("Frame", nil, hc)
            em:SetPoint("TOPLEFT", 3, -3)
            em:SetPoint("BOTTOMRIGHT", -3, 3)
            em:SetClipsChildren(true)
            -- ueber den Feldern (sonst verdeckt), faengt keine Klicks ab
            em:SetFrameLevel(hc:GetFrameLevel() + 14)
            em:EnableMouse(false)
            em.p = {}
            for i = 1, 26 do
                local t = em:CreateTexture(nil, "ARTWORK")
                t:SetTexture(ns.MEDIA .. "ember")
                t:SetBlendMode("ADD")
                t:Hide()
                em.p[i] = { t = t, life = math.random() * 4 }   -- versetzt starten (0.5.513: positiv, sonst nie sichtbar)
            end
            em.col = { 1, 0.6, 0.3 }
            em:SetScript("OnUpdate", function(self, el)
                if ns.db and ns.db.settings.noAnim then
                    for _, q in ipairs(self.p) do q.t:Hide() end
                    return
                end
                local w, h = self:GetWidth(), self:GetHeight()
                if not w or w < 20 then return end
                local c = self.col
                for _, q in ipairs(self.p) do
                    q.life = q.life - el
                    if q.life <= 0 then
                        if true then
                            -- neu: meist links (Portraet), selten weiter rechts
                            q.max = 3 + math.random() * 4
                            q.life = q.max
                            local spread = (math.random() < 0.45) and 0.3 or 1
                            q.x0 = math.random() * w * spread
                            q.y = -4 - math.random() * 6
                            q.vy = 6 + math.random() * 12
                            q.ph = math.random() * 6.28
                            q.sz = 3 + math.random() * 4
                            q.t:SetSize(q.sz, q.sz)
                            q.t:Show()
                        else
                            q.t:Hide()
                        end
                    end
                    if q.max and q.life > 0 then
                        q.y = q.y + q.vy * el
                        local k = 1 - q.life / q.max
                        local x = q.x0 + math.sin(q.ph + k * 5) * 6
                        q.t:ClearAllPoints()
                        q.t:SetPoint("CENTER", self, "BOTTOMLEFT", x, q.y)
                        -- Klassenfarbe, zur Glut hin etwas waermer; ein- und ausblenden
                        q.t:SetVertexColor(math.min(1, c[1] * 0.8 + 0.25), c[2] * 0.75 + 0.1, c[3] * 0.6)
                        q.t:SetAlpha(math.sin(k * math.pi) * 0.75)
                        if q.y > h + 4 then q.life = 0 end
                    end
                end
            end)
            soon.embers = em
            -- Portraet: der Rangrahmen bleibt (er zeigt den Rang); Aura, Strahlen und Drehringe entfallen
            local AS = 0.92   -- 0.6.374: Profilbadge kleiner
            soon.av:SetScale(AS)
            soon.av:ClearAllPoints()
            soon.av:SetPoint("CENTER", hc, "LEFT", 66 / AS, 0)
            soon.stage:Hide()
            function soon:AvatarFx()
                self.stage:Hide()
                if self.spin1 then self.spin1:Hide() end
                if self.spin2 then self.spin2:Hide() end
            end
            soon:AvatarFx()
            soon.emb:SetScale(1.0)
            soon.emb:ClearAllPoints()
            soon.emb:SetPoint("CENTER", soon.av, "BOTTOM", 0, 5)   -- 0.6.387: minimal hoeher
            hc.editHit:SetWidth(X2 - 16)
            -- Name gross, darunter Klasse/Level als Pillen, Hinweis Visitenkarte
            soon.name:ClearAllPoints()
            soon.name:SetPoint("TOPLEFT", hc, "TOPLEFT", X1, -26)
            soon.name:SetWidth(X2 - X1 - 16)
            K.SetFontSafe(soon.name, K.FONT_HEAD, 28, "", K.FONT)
            soon.clsPill:ClearAllPoints()
            soon.clsPill:SetPoint("TOPLEFT", soon.name, "BOTTOMLEFT", 0, -12)
            for _, pl in ipairs({ soon.clsPill, soon.lvlPill }) do
                pl:SetHeight(28)
                if pl.t then K.SetFontSafe(pl.t, K.FONT, 13, "", K.FONT) end
                IG.Glass(pl, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.12 }, 10)
                local set = pl.Set
                function pl:Set(text, c)
                    set(self, text, c)
                    self:SetWidth((self.t:GetStringWidth() or 40) + 40)
                    if c then IG.Glass(self, { c[1], c[2], c[3], 0.16 }, { c[1], c[2], c[3], 0.7 }) end
                end
            end
            soon.cardHint = K.Text(hc, 11, C.dim)
            soon.cardHint:SetPoint("TOPLEFT", soon.clsPill, "BOTTOMLEFT", 2, -14)
            soon.cardHint:SetWidth(X2 - X1 - 16)
            soon.cardHint:SetText(L["Klick: Visitenkarte bearbeiten"])
            -- Leisten: oben Level (Klassenfarbe), unten Oasis-Rang (Akzentfarbe), beide schmal und rund
            soon.wxp:ClearAllPoints()
            soon.wxp:SetPoint("TOPLEFT", hc, "TOPLEFT", X2, -22)
            soon.wxp:SetTextColor(C.text[1], C.text[2], C.text[3])
            K.SetFontSafe(soon.wxp, K.FONT, 14, "", K.FONT)
            soon.wTrack:ClearAllPoints()
            soon.wTrack:SetPoint("TOPLEFT", soon.wxp, "BOTTOMLEFT", 0, -8)
            soon.wxpR:ClearAllPoints()
            soon.wxpR:SetPoint("TOPLEFT", soon.wTrack, "BOTTOMLEFT", 0, -7)
            soon.wxpR:SetJustifyH("LEFT")
            -- Oasis-Rang gross in Gold, Leiste in Gold/Orange
            soon.rank:ClearAllPoints()
            soon.rank:SetPoint("TOPLEFT", hc, "TOPLEFT", X2, -84)
            K.SetFontSafe(soon.rank, K.FONT_HEAD, 18, "", K.FONT)
            soon.rank:SetTextColor(C.amber[1], C.amber[2], C.amber[3])
            soon.pct:ClearAllPoints()
            soon.pct:SetPoint("BOTTOMRIGHT", soon.xpTrack, "TOPRIGHT", 0, 8)
            soon.pct:SetTextColor(C.text[1], C.text[2], C.text[3])
            soon.xpTrack:ClearAllPoints()
            soon.xpTrack:SetPoint("TOPLEFT", soon.rank, "BOTTOMLEFT", 0, -8)
            soon.xpText:ClearAllPoints()
            soon.xpText:SetPoint("TOPLEFT", soon.xpTrack, "BOTTOMLEFT", 0, -7)
            for _, t in ipairs({ soon.wTrack, soon.wRest, soon.wFill, soon.xpTrack, soon.xpFill }) do t:SetHeight(8) end
            soon.wTrack:SetColorTexture(1, 1, 1, 0.07)
            soon.xpTrack:SetColorTexture(1, 1, 1, 0.07)
            local am, og = C.amber, { 1, 0.55, 0.2, 1 }
            if not K.Gradient(soon.xpFill, "HORIZONTAL", { am[1], am[2], am[3], 1 }, og) then soon.xpFill:SetColorTexture(am[1], am[2], am[3], 1) end
            if K.RoundMask then
                for _, t in ipairs({ soon.wTrack, soon.wRest, soon.wFill, soon.xpTrack, soon.xpFill }) do K.RoundMask(t, t, 3) end
            end
            soon.xpBorder:Hide()
            soon.xpShine:Hide()
            for _, t in ipairs(soon.xpTicks) do t:Hide() end
            -- rechts: naechste Belohnung + Abzeichen als zwei Glaskarten
            local cr = soon.chipR
            cr:ClearAllPoints()
            cr:SetPoint("TOPRIGHT", hc, "TOPRIGHT", -12, -14)
            cr:SetSize(RW, 56)
            cr.edge:Hide()
            -- 0.6.333: schlichte Karte (feine graue Kante) statt Box-Rahmen
            for _, x in ipairs({ cr, soon.vit }) do
                x.noBoxFrame = true
                if x.boxFrame then x.boxFrame:Hide() if x.boxFrame.fit then x.boxFrame.fit() end end
            end
            IG.Glass(cr, { 0.06, 0.06, 0.07, 0.85 }, { 1, 1, 1, 0.12 }, 8)
            cr.icon:ClearAllPoints()
            cr.icon:SetSize(22, 22)
            cr.icon:SetPoint("LEFT", 12, 0)
            cr.label:ClearAllPoints()
            cr.label:SetPoint("TOPLEFT", 44, -11)
            cr.label:SetText(L["Naechste Belohnung"])
            cr.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
            cr.value:ClearAllPoints()
            cr.value:SetPoint("BOTTOMLEFT", 44, 10)
            cr.value:SetPoint("RIGHT", cr, "RIGHT", -12, 0)
            K.SetFontSafe(cr.value, K.FONT_HEAD, 13, "", K.FONT)
            soon.chipF:Hide()
            local vit = soon.vit
            -- 0.6.373: "Naechste Belohnung" und "Abzeichen" entfallen im Kopf
            cr:Hide() cr.Show = function() end
            vit:Hide() vit.Show = function() end
            vit:ClearAllPoints()
            vit:SetPoint("TOPRIGHT", hc, "TOPRIGHT", -12, -78)
            vit:SetSize(RW, 58)
            vit.sep:Hide()
            IG.Glass(vit, { 0.06, 0.06, 0.07, 0.85 }, { 1, 1, 1, 0.12 }, 8)
            vit.lbl:ClearAllPoints()
            vit.lbl:SetPoint("TOPLEFT", 12, -10)
            vit.lbl:SetText(L["Abzeichen"])
            vit.num:ClearAllPoints()
            vit.num:SetPoint("TOPLEFT", vit.lbl, "BOTTOMLEFT", 0, -4)
            K.SetFontSafe(vit.num, K.FONT_HEAD, 18, "", K.FONT)
            vit.pct:ClearAllPoints()
            vit.pct:SetPoint("LEFT", vit.lbl, "RIGHT", 8, 0)   -- 0.6.360: neben der Ueberschrift (stiess sonst an die Abzeichen)
            vit.pct:SetJustifyH("LEFT")
            vit.pct:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
            for i, b in ipairs(vit.icons) do
                b:ClearAllPoints()
                b:SetSize(20, 20)
                b:SetPoint("RIGHT", vit, "RIGHT", -8 - (#vit.icons - i) * 23, 0)
                b.icon:ClearAllPoints()
                b.icon:SetPoint("TOPLEFT", 3, -3)
                b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
                -- jedes Abzeichen in einem eigenen kleinen Rahmen
                if not b.box then b.box = CreateFrame("Frame", nil, b) b.box:SetAllPoints() b.box:SetFrameLevel(b:GetFrameLevel()) IG.Glass(b.box, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.1 }, 4) end
            end
            vit.track:ClearAllPoints()
            vit.track:SetPoint("BOTTOMLEFT", 14, 8)
            vit.track:SetPoint("BOTTOMRIGHT", vit, "BOTTOMRIGHT", -(8 + #vit.icons * 23 + 6), 8)
            vit.track:SetHeight(3)
            vit.fill:SetHeight(3)
            -- Breiten an die Fensterbreite anpassen
            local function layoutHead()
                local W = hc:GetWidth() or 0
                if W < 200 then W = 751 end
                local bw = math.min(430, math.max(120, W - X2 - 12 - RW - 20))   -- 0.6.374: nicht ueber die ganze Breite strecken
                soon.xpW = bw
                soon.xpTrack:SetWidth(bw)
                soon.wTrack:SetWidth(bw)
                soon.wxp:SetWidth(bw)
                soon.wxpR:SetWidth(bw)
                soon.xpText:SetWidth(bw)
                soon.rank:SetWidth(math.max(60, bw - 50))
                if soon.FillWowXP then soon:FillWowXP() end
            end
            soon.FitBar = layoutHead
            hc:SetScript("OnSizeChanged", layoutHead)
            layoutHead()
            -- Reiterleiste + Unterreiter
            soon.tabs:ClearAllPoints()
            soon.tabs:SetPoint("TOPLEFT", 0, soon.NAV_Y)
            soon.tabs:SetPoint("TOPRIGHT", 0, soon.NAV_Y)
            for _, sg in pairs(soon.subSeg) do
                sg:ClearAllPoints()
                sg:SetPoint("TOPLEFT", 6, soon.SUB_Y)
            end
            -- Inhaltsflaechen im selben Glas
            IG.Glass(cs, IG.GLASS_FILL, IG.GLASS_LINE, 12)
            IG.Glass(pr, IG.GLASS_FILL, IG.GLASS_LINE, 12)
            if K.RoundMask then for _, r in ipairs(pr.rows) do K.RoundMask(r.bg, r, 6) end end
            if soon.dailyHost.panel then IG.Glass(soon.dailyHost.panel, IG.GLASS_FILL, IG.GLASS_LINE, 12) end
            -- Rollenwahl (wird spaeter gebaut): Glasknoepfe, aktive Rolle in Akzentfarbe
            local ensureRole = soon.EnsureRoleSeg
            function soon:EnsureRoleSeg()
                local had = self.roleSeg
                ensureRole(self)
                local bar = self.roleSeg
                if had or not bar then return end
                -- 0.6.318: einzelne umrandete Knoepfe (wie im Entwurf); der aktive in Akzentfarbe
                local CLEAR = { 1, 1, 1, 0 }
                local OFF_F, OFF_L = { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.16 }
                local x = 0
                for _, b in ipairs(bar.btns) do
                    b:SetHeight(26)
                    b:ClearAllPoints()
                    b:SetPoint("LEFT", x, 0)
                    x = x + (b:GetWidth() or 60) + 8
                    IG.Glass(b, OFF_F, OFF_L, 6)
                    if b.hl and K.RoundMask then K.RoundMask(b.hl, b, 6) end
                end
                bar:SetWidth(math.max(1, x - 8))
                bar:SetHeight(26)
                IG.Glass(bar, CLEAR, CLEAR, 10)
                local sel = bar.Select
                function bar:Select(key)
                    sel(self, key)
                    for _, b in ipairs(self.btns) do
                        local on = b.key == key
                        IG.Glass(b, on and { ac[1], ac[2], ac[3], 0.18 } or OFF_F, on and { ac[1], ac[2], ac[3], 0.9 } or OFF_L)
                    end
                end
                local ok, cur = pcall(self.CurrentOption, self)
                if ok and cur then bar:Select(cur[1]) end
                -- Wunsch-/Gruppenrolle: ebenfalls Pillen; gewaehlte Rollen dezent in Rollenfarbe
                local rc = self.roleChips
                if rc and rc.chips then
                    rc:SetHeight(30)
                    rc:ClearAllPoints()
                    rc:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)
                    IG.Glass(rc, CLEAR, CLEAR, 10)
                    local cw = ((rc:GetWidth() or 276) - 8 * (#rc.chips - 1)) / #rc.chips
                    for i, b in ipairs(rc.chips) do
                        b:ClearAllPoints()
                        b:SetSize(cw, 30)
                        b:SetPoint("LEFT", (i - 1) * (cw + 8), 0)
                        IG.Glass(b, OFF_F, OFF_L, 6)
                    end
                    local refresh = rc.Refresh
                    function rc:Refresh()
                        refresh(self)
                        local RC = ns.Profile and ns.Profile.ROLE_COLORS or {}
                        for _, b in ipairs(self.chips) do
                            local on = (b.icon:GetAlpha() or 0) > 0.5
                            local c = RC[b.role] or ac
                            IG.Glass(b, on and { c[1], c[2], c[3], 0.18 } or OFF_F, on and { c[1], c[2], c[3], 0.9 } or OFF_L)
                        end
                    end
                    rc:Refresh()
                end
            end
            -- Klassenfarbe als zweite Farbe (Kopf-Toenung, Level-Leiste); Leisten fuellen sich beim Oeffnen
            local baseUpdate = soon.Update
            function soon:Update(fresh)
                baseUpdate(self, fresh)
                local _, cf = UnitClass("player")
                local r, g, b = ns.classColor(ns.safe(cf))
                r, g, b = r or 0.6, g or 0.6, b or 0.6
                IG.Glass(hc, { 0.6 + r * 0.4, 0.6 + g * 0.4, 0.6 + b * 0.4, 0.05 }, { r, g, b, 0.22 })
                self.wFill:SetColorTexture(r, g, b, 1)
                self.wRest:SetColorTexture(r, g, b, 0.28)
                if fresh and K.Tween and not (ns.db and ns.db.settings.noAnim) then
                    for _, t in ipairs({ self.xpFill, self.wRest, self.wFill }) do
                        local goal = t:GetWidth() or 1
                        if goal > 2 then
                            t:SetWidth(1)
                            K.Tween(t, 0.7, function(p)
                                local e = 1 - (1 - p) * (1 - p) * (1 - p)
                                t:SetWidth(math.max(1, goal * e))
                            end, function() t:SetWidth(goal) end, 0.05)
                        end
                    end
                end
            end
        end
        ------------------------------------------------------------------
        -- 0.6.319: Profil nach Entwurf 2 - Kopfbild, Klasse/Level als Text, Werte-Kacheln + Spezialisierungs-Kasten
        ------------------------------------------------------------------
        do
            -- Kopfbild rechts (Gildenmodul), nach links in den Kopf auslaufend
            if ns.GuildPack then
                hc.art = hc:CreateTexture(nil, "BACKGROUND", nil, 1)
                -- 0.6.321: "Dunkle Oase bei Nacht" ueber die ganze Karte, dezent
                hc.art:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\profile_bg")
                hc.art:SetTexCoord(0, 1, 0.1 * 356 / 512, 0.9 * 356 / 512)
                hc.art:SetPoint("TOPRIGHT", -2, -2) hc.art:SetPoint("BOTTOMRIGHT", -2, 2)
                hc.art:SetPoint("LEFT", hc, "LEFT", 2, 0)
                hc.art:SetAlpha(0.2)
                hc.artFade = hc:CreateTexture(nil, "BACKGROUND", nil, 2)
                hc.artFade:SetPoint("TOPLEFT", hc.art, "TOPLEFT") hc.artFade:SetPoint("BOTTOMLEFT", hc.art, "BOTTOMLEFT")
                hc.artFade:SetWidth(260)
                local bg = C.bg
                if not K.Gradient(hc.artFade, "HORIZONTAL", { bg[1], bg[2], bg[3], 1 }, { bg[1], bg[2], bg[3], 0 }) then hc.artFade:Hide() end
                if K.RoundMask then pcall(K.RoundMask, hc.art, hc, 14) end
            end
            -- 0.6.329: dunkle Klassenfarbe als Grund (setzt soon:Update), feines Punktraster und Abschattung von links
            hc.dots = hc:CreateTexture(nil, "BACKGROUND", nil, 3)
            hc.dots:SetPoint("TOPLEFT", 3, -3) hc.dots:SetPoint("BOTTOMRIGHT", -3, 3)
            hc.dots:SetTexture(ns.MEDIA .. "dots", "REPEAT", "REPEAT")
            hc.dots:SetHorizTile(true) hc.dots:SetVertTile(true)
            hc.dots:SetAlpha(0.07)
            hc.shadeL = hc:CreateTexture(nil, "BACKGROUND", nil, 4)
            hc.shadeL:SetPoint("TOPLEFT", 3, -3) hc.shadeL:SetPoint("BOTTOMLEFT", 3, 3)
            hc.shadeL:SetWidth(420)
            if not K.Gradient(hc.shadeL, "HORIZONTAL", { 0, 0, 0, 0.55 }, { 0, 0, 0, 0 }) then hc.shadeL:Hide() end
            if K.RoundMask then pcall(K.RoundMask, hc.dots, hc, 14) pcall(K.RoundMask, hc.shadeL, hc, 14, { "tl", "bl" }) end
            -- Klasse | Level als schlichter Text statt Pillen
            for _, pl in ipairs({ soon.clsPill, soon.lvlPill }) do
                local set = pl.Set
                function pl:Set(text, c)
                    set(self, text, c)
                    IG.Glass(self, { 1, 1, 1, 0 }, { 1, 1, 1, 0 })
                    if self.t then
                        K.SetFontSafe(self.t, K.FONT, 16, "", K.FONT)
                        self.t:SetTextColor(C.text[1], C.text[2], C.text[3])
                        self:SetWidth((self.t:GetStringWidth() or 40) + 4)
                        self.t:ClearAllPoints() self.t:SetPoint("LEFT", 0, 0)
                    end
                end
            end
            soon.lvlPill:ClearAllPoints()
            soon.lvlPill:SetPoint("LEFT", soon.clsPill, "RIGHT", 24, 0)
            soon.clsSep = hc:CreateTexture(nil, "ARTWORK")
            soon.clsSep:SetColorTexture(1, 1, 1, 0.3)
            soon.clsSep:SetSize(1, 16)
            soon.clsSep:SetPoint("LEFT", soon.clsPill, "RIGHT", 12, 0)

            -- 0.6.359: Stat-Prioritaet wie im Entwurf - Rangzahl im Kaestchen, Name, Farbleiste, Wert
            local PRIO_COL = { { 0.93, 0.27, 0.32 }, { 0.86, 0.42, 0.66 }, { 0.86, 0.42, 0.66 }, { 0.55, 0.42, 0.88 }, { 0.55, 0.42, 0.88 }, { 0.55, 0.42, 0.88 } }
            soon.prRowH = 40
            for i, r in ipairs(pr.rows) do
                r:SetHeight(34)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", pr, "TOPLEFT", 12, -44 - (i - 1) * 40)
                r:SetPoint("RIGHT", pr, "RIGHT", -12, 0)
                r.bg:SetColorTexture(1, 1, 1, 0.025)
                r.box = r:CreateTexture(nil, "ARTWORK")
                r.box:SetColorTexture(1, 1, 1, 0.05)
                r.box:SetSize(28, 26)
                r.box:SetPoint("LEFT", 4, 0)
                r.num:ClearAllPoints()
                r.num:SetPoint("CENTER", r.box, "CENTER", 0, 0)
                K.SetFontSafe(r.num, K.FONT_HEAD, 15, "", K.FONT)
                r.name:ClearAllPoints()
                r.name:SetPoint("LEFT", r.box, "RIGHT", 14, 0)
                K.SetFontSafe(r.name, K.FONT, 12, "", K.FONT)
                r.name:SetJustifyH("LEFT")
                r.val:ClearAllPoints()
                r.val:SetPoint("RIGHT", r, "RIGHT", -10, 0)
                K.SetFontSafe(r.val, K.FONT, 13, "", K.FONT)
                r.track = r:CreateTexture(nil, "ARTWORK")
                r.track:SetColorTexture(1, 1, 1, 0.07)
                r.track:SetHeight(9)
                r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
                r.fill:SetHeight(9)
                r.fill:SetPoint("LEFT", r.track, "LEFT")
                if K.RoundMask then pcall(K.RoundMask, r.track, r.track, 3) pcall(K.RoundMask, r.fill, r.fill, 3) pcall(K.RoundMask, r.box, r.box, 4) end
            end
            -- Schimmer: alle paar Sekunden laeuft ein heller Streif ueber die gefuellten Teile
            for _, r in ipairs(pr.rows) do
                r.sheen = r:CreateTexture(nil, "ARTWORK", nil, 2)
                r.sheen:SetBlendMode("ADD")
                r.sheen:SetSize(30, 12)
                r.sheen:SetTexture(ns.MEDIA .. "ember")   -- 0.6.375: weich, Helligkeit ueber die Farbe
                r.sheen:Hide()
                -- 0.6.394: feine schraege Streifen laufen dauerhaft ueber den gefuellten Teil
                r.stripe = r:CreateTexture(nil, "ARTWORK", nil, 3)
                r.stripe:SetTexture(ns.MEDIA .. "stripes", "REPEAT", "REPEAT")
                r.stripe:SetHorizTile(true)
                r.stripe:SetAllPoints(r.fill)
            end
            local shT = 0
            pr:HookScript("OnUpdate", function(_, el)
                if ns.db and ns.db.settings.noAnim then return end
                -- 0.6.385: dauerhaft - der Schimmer laeuft ohne Pause, die Balken atmen sanft
                shT = (shT + (el or 0)) % 2.4
                local p = shT / 2.4
                local br = 0.88 + 0.12 * math.sin(GetTime() * 2.2)
                local off = -(GetTime() * 0.6) % 1
                for i, r in ipairs(pr.rows) do
                    local fw = r.fill and r.fill:GetWidth() or 0
                    local q = (p - (i - 1) * 0.08) % 1
                    if r.fill and r.fillCol then local fc = r.fillCol r.fill:SetVertexColor(fc[1] * br, fc[2] * br, fc[3] * br, 1) end
                    if r.stripe and r.fill then
                        local fwS = r.fill:GetWidth() or 1
                        r.stripe:SetTexCoord(off, off + fwS / 16, 0, (r.fill:GetHeight() or 9) / 16)
                        r.stripe:SetShown(r:IsShown() and fwS > 6)
                    end
                    if false and r:IsShown() and fw > 30 then   -- 0.6.407: weisser Lichtfleck entfernt
                        r.sheen:ClearAllPoints()
                        r.sheen:SetPoint("LEFT", r.fill, "LEFT", q * (fw - 24), 0)
                        local kk = math.sin(q * math.pi) * 0.6
                        r.sheen:SetVertexColor(kk, kk, kk, 1)
                        r.sheen:Show()
                    else
                        r.sheen:Hide()
                    end
                end
            end)
            soon:HookScript("OnShow", function() soon.prFresh = true end)
            -- 0.6.373: Ziel je Wert (fuer Stat-Prioritaet und Charakterwerte)
            function soon.GoalOf(k)
                local lvl = num(UnitLevel("player")) or 1
                if k == "hit" then return 9, "%" end
                if k == "shit" then return 16, "%" end
                if k == "crit" or k == "scrit" then return 5 + lvl * 0.15, "%" end
                if k == "dodge" or k == "parry" or k == "block" then return 5 + lvl * 0.1, "%" end
                if k and k:match("^stat%d$") then return lvl * 3 + 20 end
                if k == "ap" then return lvl * 8 + 40 end
                if k == "sp" or k == "heal" then return math.max(10, lvl * 3) end
                if k == "armor" then return lvl * 50 end
                if k == "def" then return lvl * 5 end
                if k == "mp5" then return math.max(2, lvl * 0.3) end
                if k == "hp" then return lvl * 30 + 60 end
                return nil
            end
            -- Charakterwerte: dezenter Fortschritt als Verlauf hinter jeder Zeile (Laenge = Anteil am Ziel)
            local fillStats = soon.FillStats
            function soon:FillStats(...)
                fillStats(self, ...)
                local ac = C.accent
                for _, r in ipairs(self.cs.rows) do
                    if not r.prog then
                        r.prog = r:CreateTexture(nil, "BORDER", nil, 1)
                        r.prog:SetPoint("TOPLEFT") r.prog:SetPoint("BOTTOMLEFT")
                    end
                    -- 0.6.379: dieselbe Einordnung wie der Tooltip (Verhaeltnis zum ueblichen Wert fuers Level)
                    local g = r:IsShown() and not r.toggle and (r.ratio and 1 or soon.GoalOf(r.key))
                    if g and g > 0 then
                        local tx = strip(r.v:GetText() or ""):gsub(",", ".")
                        local v = math.abs(tonumber(tx:match("%-?%d+%.?%d*") or "") or 0)
                        local w = (r:GetWidth() or 0)
                        if w < 20 then w = 300 end
                        local q = r.ratio or (v / g)
                        if r.ratio then v = 1 end
                        r.prog:SetWidth(math.max(1, w * math.min(1, q)))
                        -- 0.6.375: Farbe nach Qualitaet - weiss, gruen, blau, episch, legendaer
                        local qq = soon.Quality and soon.Quality(q)
                        local qc = (qq and qq[2]) or { 1, 1, 1 }   -- Durchschnitt = weiss
                        if not K.Gradient(r.prog, "HORIZONTAL", { qc[1], qc[2], qc[3], 0.18 }, { qc[1], qc[2], qc[3], 0.02 }) then r.prog:SetColorTexture(qc[1], qc[2], qc[3], 0.08) end
                        r.prog:SetShown(v > 0)
                    else
                        r.prog:Hide()
                    end
                end
            end
            local fillPrio = soon.FillPrio
            function soon:FillPrio(st)
                -- 0.6.360: immer 6 Zeilen - Zeilenabstand richtet sich nach der Hoehe der Box
                local ph = self.pr:GetHeight() or 0
                local step = ph > 100 and math.max(26, math.min(40, math.floor((ph - 52) / 6))) or 40
                self.prRowH = step
                for i, r in ipairs(self.pr.rows) do
                    r:SetHeight(step - 5)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", self.pr, "TOPLEFT", 12, -44 - (i - 1) * step)
                    r:SetPoint("RIGHT", self.pr, "RIGHT", -12, 0)
                end
                fillPrio(self, st)
                -- 0.6.363: Leisten gegen ein Ziel je Wert (voll = Ziel erreicht); Trefferchance gegen die Grenze,
                -- alles andere gegen einen Richtwert fuer das eigene Level
                local lvl = num(UnitLevel("player")) or 1
                local pl = self:Prio()
                local goalOf = soon.GoalOf
                local function goalOfOld(k)
                    if k == "hit" then return 9, "%" end
                    if k == "shit" then return 16, "%" end
                    if k == "crit" or k == "scrit" then return 5 + lvl * 0.15, "%" end
                    if k == "dodge" or k == "parry" or k == "block" then return 5 + lvl * 0.1, "%" end
                    if k and k:match("^stat%d$") then return lvl * 3 + 20 end
                    if k == "ap" then return lvl * 8 + 40 end
                    if k == "sp" or k == "heal" then return math.max(10, lvl * 3) end
                    if k == "armor" then return lvl * 50 end
                    if k == "def" then return lvl * 5 end
                    if k == "mp5" then return math.max(2, lvl * 0.3) end
                    return nil
                end
                local vals, goals = {}, {}
                for i, r in ipairs(self.pr.rows) do
                    -- 0.6.368: eigene Zahlerkennung - hier gilt eine lokale num (nur ganze Zahlen), "6.9 %" wurde 0
                    local tx = strip(r.val:GetText() or ""):gsub(",", ".")
                    vals[i] = math.abs(tonumber(tx:match("%-?%d+%.?%d*") or "") or 0)
                    local k = pl and pl[i] and pl[i][1]
                    local g, unit = goalOf(k)
                    goals[i] = g
                    r:EnableMouse(true)
                    r.goalTip = g and { r.name:GetText() or "", (L["Ziel fuer Level %d: %s"]):format(lvl, (unit == "%") and (("%.1f %%"):format(g)) or tostring(math.floor(g + 0.5))) } or nil
                    if not r.goalHooked then
                        r.goalHooked = true
                        r:SetScript("OnEnter", function(self) if self.goalTip then K.ShowTip(self, self.goalTip) end end)
                        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    end
                end
                for i, r in ipairs(self.pr.rows) do
                    -- 0.6.371: eine Breite fuer alle Zeilen (aus der Box), sonst begann Zeile 1 woanders
                    local W = (self.pr:GetWidth() or 0) - 24
                    if W < 50 then W = 300 end
                    r.track:ClearAllPoints()
                    -- Leiste rechts vom Namen; Name endet davor (wird sonst gekuerzt statt ueberlagert)
                    r.track:SetPoint("LEFT", r, "LEFT", W * 0.5, 0)
                    r.track:SetWidth(W * 0.32)
                    r.name:SetPoint("RIGHT", r, "LEFT", W * 0.5 - 10, 0)
                    r.name:SetWordWrap(false)
                    -- 0.6.409: Farbe nach Zielerfuellung statt nach Platz: rot < 50 %, orange < 80 %, gelb < 100 %, gruen ab 100 %
                    local qf = goals[i] and goals[i] > 0 and vals[i] / goals[i] or 0
                    local c = (qf >= 1 and { 0.30, 0.85, 0.45 }) or (qf >= 0.8 and { 0.95, 0.82, 0.30 }) or (qf >= 0.5 and { 0.98, 0.58, 0.22 }) or { 0.93, 0.30, 0.32 }
                    -- 0.6.407: Verlauf von dunkler zu heller statt Einfarbig + Atmen
                    if not K.Gradient(r.fill, "HORIZONTAL", { c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 1 }, { math.min(1, c[1] * 1.1), math.min(1, c[2] * 1.1), math.min(1, c[3] * 1.1), 1 }) then
                        r.fill:SetColorTexture(c[1], c[2], c[3], 1)
                    end
                    r.fillCol = nil
                    local q = goals[i] and goals[i] > 0 and vals[i] / goals[i] or 0
                    r.diag = { vals[i], goals[i], q, W }
                    -- 0.6.372: Balken wachsen beim Oeffnen und bei Aenderung von links auf ihren Wert (gestaffelt)
                    local goalW = math.max(1, W * 0.32 * math.max(0.04, math.min(1, q)))
                    local noAnim = ns.db and ns.db.settings.noAnim
                    if noAnim or not K.Tween or (r.barW and math.abs(r.barW - goalW) < 0.5 and not self.prFresh) then
                        r.fill:SetWidth(goalW)
                    else
                        r.fill:SetWidth(1)
                        local fillTex = r.fill
                        K.Tween(fillTex, 0.7, function(t)
                            local e = 1 - (1 - t) ^ 3
                            fillTex:SetWidth(math.max(1, goalW * e))
                        end, function() fillTex:SetWidth(goalW) end, 0.06 * (i - 1))
                    end
                    r.barW = goalW
                    r.num:SetTextColor(C.amber[1], C.amber[2], C.amber[3])
                    r.val:SetTextColor(C.text[1], C.text[2], C.text[3])
                    r.bg:SetColorTexture(1, 1, 1, 0.025)
                end
                self.prFresh = nil
            end
            -- 0.6.367: Diagnose fuer den Profil-Kopf/Werte (/oa profildiag) - schreibt die echten Werte in den Chat
            ns.slash.profildiag = function()
                local pb = soon.pageBg
                if pb then
                    local r, g, b, a = pb:GetVertexColor()
                    ns.print(("Seitenflaeche: shown=%s alpha=%.2f vc=%.2f,%.2f,%.2f,%.2f layer=%s soonAlpha=%.2f soonEff=%.2f level=%s strata=%s"):format(
                        tostring(pb:IsShown()), pb:GetAlpha() or -1, r or -1, g or -1, b or -1, a or -1, tostring(pb:GetDrawLayer()), soon:GetAlpha() or -1,
                        soon.GetEffectiveAlpha and soon:GetEffectiveAlpha() or -1, tostring(soon:GetFrameLevel()), tostring(soon:GetFrameStrata())))
                    -- Test: 5 s knallgruen - wird es gruen, ist es diese Flaeche

                end
                for i, r in ipairs(pr.rows) do
                    if r:IsShown() then
                        local d = r.diag or {}
                        ns.print(("Prio %d %s | text=%q wert=%s ziel=%s q=%s W=%s fill=%s"):format(i, tostring(r.name:GetText()), tostring(r.val:GetText()),
                            tostring(d[1]), tostring(d[2]), tostring(d[3]), tostring(d[4]), tostring(r.fill and r.fill:GetWidth())))
                    end
                end
            end
            -- 0.6.354: "So spielst du es" entfaellt im Profil
            if pr.tipBox then
                pr.tipBox:Hide()
                pr.tipBox.Show = function() end
                pr.tipBox.SetShown = function() end
            end
            -- obere Reihe der Werte-Ansicht: drei Kacheln links, Spezialisierung/Wunschrolle rechts
            local ROW = 78   -- 0.6.353: feste Abstaende (Beschriftung 10, Zahl +7, Leiste 10 vom Rand)
            cs:ClearAllPoints()
            -- 0.6.330: Verbrauchsgueter als eigene Box unter den Charakterwerten (2x2), Werte einspaltig
            local cb = CreateFrame("Frame", nil, view)
            -- 0.6.355: rechts unter der Stat-Prioritaet
            cb:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
            cb:SetPoint("LEFT", view, "CENTER", 6, 0)
            cb:SetHeight(124)
            IG.Glass(cb, IG.GLASS_FILL, IG.GLASS_LINE, 12)
            soon.consBox = cb
            -- 0.6.356: Verbrauchsgueter im Profil entfernt (Box bleibt unsichtbar, haelt nur die Einblicke)
            cb:Hide()
            cb.Show = function() end
            cs:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -(ROW + 12))
            cs:SetPoint("BOTTOMLEFT", view, "BOTTOMLEFT", 0, 0)
            cs:SetPoint("RIGHT", view, "CENTER", -6, 0)
            -- Stat-Prioritaet rechts oben, endet ueber den Verbrauchsguetern
            pr:ClearAllPoints()
            pr:SetPoint("TOPLEFT", cs, "TOPRIGHT", 12, 0)
            pr:SetPoint("RIGHT", view, "RIGHT", 0, 0)
            pr:SetPoint("BOTTOM", view, "BOTTOM", 0, 0)
            if cs.SetClipsChildren then cs:SetClipsChildren(true) end   -- Verbrauchsgueter liefen unten heraus
            local tiles = CreateFrame("Frame", nil, view)
            tiles:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
            tiles:SetPoint("RIGHT", view, "RIGHT", -162, 0)   -- 0.6.349: Kasten rechts nur noch Spezialisierung (~150), Kacheln bekommen den Rest   -- 0.6.326: halbe Breite, Kasten rechts bekommt die andere Haelfte
            tiles:SetHeight(ROW)
            soon.statTiles = tiles   -- soon.tiles ist schon belegt (Abzeichen-Kacheln)
            local DEF = {
                { key = "hp", label = "Gesundheit", icon = "heart", col = { 0.95, 0.3, 0.32 } },
                { key = "ap", label = "Angriffskraft", icon = "role_dps", col = { 0.95, 0.72, 0.38 } },
                { key = "crit", label = "Kritische Treffer", icon = "star_on", col = { 0.55, 0.45, 0.95 } },
            }
            tiles.t = {}
            for i, d in ipairs(DEF) do
                local t = CreateFrame("Frame", nil, tiles)
                IG.Glass(t, IG.GLASS_FILL, IG.GLASS_LINE, 10)
                -- 0.6.326: schlichte Symbole in der Wertfarbe (Entwurf)
                -- 0.6.355: Symbol im dezenten Farbkreis, mittig zu Beschriftung und Zahl
                t.disc = t:CreateTexture(nil, "ARTWORK")
                t.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                t.disc:SetSize(36, 36)
                t.disc:SetPoint("CENTER", t, "TOPLEFT", 32, -34)
                t.disc:SetVertexColor(d.col[1], d.col[2], d.col[3], 0.14)
                t.icon = K.Glyph(t, 18, ns.MEDIA .. "icons\\" .. d.icon, d.col)
                t.icon:SetPoint("CENTER", t.disc, "CENTER")
                t.lbl = K.Text(t, 11, C.muted)
                t.lbl:SetPoint("TOPLEFT", t, "TOPLEFT", 60, -12)
                t.lbl:SetPoint("RIGHT", t, "RIGHT", -8, 0)
                t.lbl:SetWordWrap(false)
                t.lbl:SetText(L[d.label])
                t.val = K.Title(t, 23, C.text)
                t.val:SetPoint("TOPLEFT", t.lbl, "BOTTOMLEFT", 0, -5)
                t.track = t:CreateTexture(nil, "ARTWORK")
                t.track:SetColorTexture(1, 1, 1, 0.08)
                t.track:SetHeight(5)
                t.track:SetPoint("BOTTOMLEFT", 16, 11) t.track:SetPoint("BOTTOMRIGHT", -16, 11)
                t.fill = t:CreateTexture(nil, "ARTWORK", nil, 1)
                t.fill:SetColorTexture(d.col[1], d.col[2], d.col[3], 1)
                t.fill:SetHeight(5)
                t.fill:SetPoint("LEFT", t.track, "LEFT")
                t.fill:SetWidth(1)
                if K.RoundMask then pcall(K.RoundMask, t.track, t.track, 3) pcall(K.RoundMask, t.fill, t.fill, 3) end
                t.def = d
                tiles.t[i] = t
            end
            local function layoutTiles()
                local W = tiles:GetWidth() or 0
                if W < 60 then return end
                local tw = (W - 2 * 10) / 3
                for i, t in ipairs(tiles.t) do
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", tiles, "TOPLEFT", (i - 1) * (tw + 10), 0)
                    t:SetSize(tw, ROW)
                end
            end
            tiles:SetScript("OnSizeChanged", layoutTiles)
            -- Werte: Live-Abfrage (nie im Kampf rechnen - Werte koennen dort geheim sein)
            function soon:FillTiles()
                if InCombatLockdown and InCombatLockdown() then return end
                local lvl = num(UnitLevel("player")) or 1
                local hp = num(ns.safe(UnitHealthMax("player"))) or 0
                local b, pos, neg = UnitAttackPower("player")
                local ap = (num(ns.safe(b)) or 0) + (num(ns.safe(pos)) or 0) + (num(ns.safe(neg)) or 0)
                local crit = num(ns.safe(GetCritChance and GetCritChance())) or 0
                -- 0.6.409: Balken = Anteil am Richtwert fuer das eigene Level (dieselben Ziele wie die Stat-Prioritaet)
                local G = soon.GoalOf or function() return nil end
                local gHp, gAp, gCr = G("hp") or (lvl * 30 + 60), G("ap") or (lvl * 8 + 40), G("crit") or (5 + lvl * 0.15)
                local vals = {
                    { tostring(hp), hp, gHp, false },
                    { tostring(ap), ap, gAp, false },
                    { (("%.1f %%"):format(crit):gsub("%.", ",")), crit, gCr, true },
                }
                for i, t in ipairs(tiles.t) do
                    local v = vals[i]
                    t.val:SetText(v[1])
                    local q = v[3] > 0 and v[2] / v[3] or 0
                    local w = t.track:GetWidth() or 0
                    if w > 2 then t.fill:SetWidth(math.max(1, w * math.max(0, math.min(1, q)))) end
                    local goalTxt = v[4] and (("%.1f %%"):format(v[3]):gsub("%.", ",")) or tostring(math.floor(v[3] + 0.5))
                    t.tip = { L[t.def.label] .. ":  " .. v[1],
                        (L["Balken: %d %% vom Richtwert fuer Level %d (%s)"]):format(math.floor(math.min(9.99, q) * 100 + 0.5), lvl, goalTxt),
                        "|cff888888" .. L["Voll = Richtwert erreicht. Grobe Oasis-Schaetzung, kein Spielwert."] .. "|r" }
                    if not t.tipHooked then
                        t.tipHooked = true
                        t:EnableMouse(true)
                        t:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
                        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
                    end
                end
            end
            -- Kasten rechts: Spezialisierung + Wunschrolle
            local rb = CreateFrame("Frame", nil, view)
            rb:SetPoint("TOPLEFT", tiles, "TOPRIGHT", 12, 0)
            rb:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)
            rb:SetHeight(ROW)
            IG.Glass(rb, IG.GLASS_FILL, IG.GLASS_LINE, 10)
            rb.l1 = K.Text(rb, 11, C.muted)
            rb.l1:SetPoint("TOPLEFT", 12, -6)
            rb.l1:SetText(L["Spezialisierung"])
            rb.l2 = K.Text(rb, 11, C.muted)
            rb.l2:SetText(L["Wunschrolle"])
            soon.roleBox = rb
            local ensure2 = soon.EnsureRoleSeg
            function soon:EnsureRoleSeg()
                ensure2(self)
                local bar = self.roleSeg
                if not bar or bar.inBox then return end
                bar.inBox = true
                -- 0.6.344: nebeneinander, beide in natuerlicher Groesse; nur wenn es nicht passt, gemeinsam verkleinern.
                -- Wird bei jeder Groessenaenderung neu gerechnet (beim Bauen war der Kasten noch 0 breit).
                -- 0.6.349: Wunschrolle gehoert zu den Gruppen - im Profil nicht mehr zeigen
                if self.roleChips then self.roleChips:Hide() self.roleChips.Show = function() end end
                rb.l2:Hide()
                local rc = nil
                local function layout()
                    local inner = (rb:GetWidth() or 0) - 24
                    if inner < 120 then return end
                    local cwList, cwTotal = {}, 0
                    if rc and rc.chips then
                        for i, b in ipairs(rc.chips) do
                            -- 0.6.348: nur Symbol (Name steht im Tooltip)
                            if b.label then b.label:Hide() end
                            if b.icon then b.icon:ClearAllPoints() b.icon:SetPoint("CENTER") end
                            local w = 30
                            cwList[i] = w
                            cwTotal = cwTotal + w + (i > 1 and 6 or 0)
                        end
                    end
                    -- 0.6.349: Spezialisierung ebenfalls nur als Symbole (Name im Tooltip)
                    local bx = 0
                    for _, b in ipairs(bar.btns or {}) do
                        if b.t then b.t:Hide() end
                        if b.icon then
                            b.icon:ClearAllPoints() b.icon:SetPoint("CENTER")
                            b.icon:SetSize(18, 18)   -- 0.6.350: Luft zum Rand
                            if K.RoundMask and not b.iconMasked then b.iconMasked = true pcall(K.RoundMask, b.icon, b.icon, 4) end
                        end
                        b:SetSize(30, 30)
                        b:ClearAllPoints()
                        b:SetPoint("LEFT", bar, "LEFT", bx, 0)
                        bx = bx + 30 + 6
                        if not b.tipHooked then
                            b.tipHooked = true
                            b:HookScript("OnEnter", function(self) if self.t then K.ShowTip(self, { self.t:GetText() or "" }) end end)
                            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
                        end
                    end
                    bar:SetWidth(math.max(1, bx - 6))
                    bar:SetScale(1)
                    local bw = bar:GetWidth() or 200
                    local sc = math.min(1, inner / math.max(1, bw + 24 + cwTotal))
                    bar:SetScale(sc)
                    bar:ClearAllPoints()
                    -- 0.6.373: mittig im Kasten (waagrecht und unter der Ueberschrift)
                    local bh = (rb:GetHeight() or 78)
                    local xL = 12 + math.max(0, (inner - bw * sc) / 2)
                    local yT = 22 + math.max(0, ((bh - 22) - 30 * sc) / 2)
                    bar:SetPoint("TOPLEFT", rb, "TOPLEFT", xL / sc, -yT / sc)
                    if rc then
                        rc:SetScale(sc)
                        rc:ClearAllPoints()
                        rc:SetWidth(math.max(1, cwTotal))
                        rc:SetHeight(26)
                        rc:SetPoint("TOPRIGHT", rb, "TOPRIGHT", -12 / sc, -24 / sc)
                        local x = 0
                        for i, b in ipairs(rc.chips or {}) do
                            b:ClearAllPoints()
                            b:SetSize(cwList[i], 26)
                            b:SetPoint("LEFT", rc, "LEFT", x, 0)
                            x = x + cwList[i] + 6
                        end
                        rb.l2:ClearAllPoints()
                        -- Ueberschrift auf einer Hoehe mit "Spezialisierung"
                        rb.l2:SetPoint("LEFT", rc, "LEFT", 0, 0)
                        rb.l2:SetPoint("TOP", rb, "TOP", 0, -6)
                    end
                end
                rb:HookScript("OnSizeChanged", function() pcall(layout) end)
                pcall(layout)
                -- 0.6.379: Spezialisierung im Kopf unter "Klasse | Level", ohne Kasten; Kacheln bekommen die volle Breite
                bar:SetParent(hc)
                bar:SetFrameLevel(hc:GetFrameLevel() + 20)
                bar:SetScale(1)
                bar:ClearAllPoints()
                bar:SetPoint("TOPLEFT", self.clsPill, "BOTTOMLEFT", 0, -12)
                rb:Hide()
                rb.Show = function() end
                if self.statTiles then self.statTiles:SetPoint("RIGHT", view, "RIGHT", 0, 0) end
                if self.roleLbl then
                    self.roleLbl:ClearAllPoints()
                    self.roleLbl:Hide()
                    self.roleLbl:SetPoint("TOPLEFT", rb, "TOPLEFT", 12, -62)
                    self.roleLbl:SetJustifyH("LEFT")
                    K.SetFontSafe(self.roleLbl, K.FONT, 11, "", K.FONT)
                end
            end
            -- 0.6.322: Ring ums Portraet; 0.6.329: zeigt den Fortschritt im Oasis-Rang (Gold), ab 12 Uhr im Uhrzeigersinn
            -- 0.6.342: Rang-Ring = voller Goldring (einfache Textur, sicher sichtbar) + dunkle Cooldown-Flaeche ueber
            -- dem noch fehlenden Teil. Eigener Frame am Kopf, Ebene immer ueber dem Portraet.
            local am = C.amber
            local lr = CreateFrame("Frame", nil, hc)
            lr:SetPoint("CENTER", soon.av, "CENTER", 0, 0)
            lr.gold = lr:CreateTexture(nil, "ARTWORK")
            lr.gold:SetAllPoints()
            lr.gold:SetTexture(ns.MEDIA .. "level_ring")
            lr.gold:SetVertexColor(am[1], am[2], am[3], 1)
            local okCd, cd = pcall(CreateFrame, "Cooldown", nil, lr)
            if okCd and cd and cd.SetSwipeTexture then
                cd:SetAllPoints()
                cd:SetSwipeTexture(ns.MEDIA .. "level_ring")
                cd:SetSwipeColor(0.07, 0.07, 0.08, 0.92)
                if cd.SetDrawEdge then cd:SetDrawEdge(false) end
                if cd.SetDrawBling then cd:SetDrawBling(false) end
                if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
                cd.noCooldownCount = true
                -- 0.6.343: dieser Client zeichnet ohne Umkehr den abgelaufenen Teil -> umkehren = Rest abdecken
                if cd.SetReverse then cd:SetReverse(true) end
                lr.cd = cd
            end
            soon.levelRing = lr
            function soon:FillRing()
                local sc = self.av:GetEffectiveScale() / math.max(0.01, lr:GetEffectiveScale())
                local d = ((self.av.size or 70) + 20) * sc
                lr:SetSize(d, d)
                local base = math.min(9000, self.av:GetFrameLevel() + 20)
                lr:SetFrameLevel(base)
                if lr.cd then lr.cd:SetFrameLevel(base + 1) end
                lr:Show()
                -- Zahl im Sechseck liegt auf dem Ring: Wappen darueber zeigen
                if self.emb then
                    self.emb:SetFrameLevel(base + 6)
                    self.emb:Show()
                end
                -- 0.6.403: eigene Zahlerkennung (hier gilt eine lokale num, die "97 %" nicht liest)
                local pt = tostring(self.pct and self.pct:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub(",", ".")
                local frac = (tonumber(pt:match("%d+%.?%d*") or "") or 0) / 100
                frac = math.max(0, math.min(1, frac))
                -- fast leer: kein Gold, nur blasse Spur (die Cooldown-Flaeche zeigt bei ~0 kein verlaessliches Bild)
                lr.gold:SetVertexColor(am[1], am[2], am[3], frac < 0.01 and 0.15 or 1)
                if lr.cd then
                    -- abgelaufen = Fortschritt, die dunkle Flaeche deckt den Rest ab
                    if frac >= 0.999 or frac < 0.01 then lr.cd:Hide() else
                        lr.cd:Show()
                        local D = 1000
                        lr.cd:SetCooldown(GetTime() - frac * D, D)
                        if lr.cd.Pause then pcall(lr.cd.Pause, lr.cd) end
                    end
                end
            end
            hc:HookScript("OnShow", function() ns.After(0.05, function() pcall(soon.FillRing, soon) end) end)
            -- Rang geaendert (Aufstieg, neue XP): Kopf samt Ring neu fuellen
            ns.Listen("RANK", function() if soon:IsVisible() then pcall(soon.Update, soon) end end)
            -- 0.6.324: Stift vor "Visitenkarte bearbeiten", Pfeil in der Belohnungskarte
            soon.cardPen = hc:CreateTexture(nil, "ARTWORK")
            soon.cardPen:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
            soon.cardPen:SetSize(14, 14)
            soon.cardPen:SetVertexColor(C.muted[1], C.muted[2], C.muted[3])
            soon.cardPen:SetPoint("TOPLEFT", soon.clsPill, "BOTTOMLEFT", 0, -14)
            soon.cardHint:ClearAllPoints()
            soon.cardHint:SetPoint("LEFT", soon.cardPen, "RIGHT", 6, 0)
            soon.cardHint:SetText(L["Visitenkarte bearbeiten"])
            -- 0.6.340: Hinweis entfaellt (Klick auf Portraet/Name oeffnet die Visitenkarte weiterhin)
            soon.cardHint:Hide() soon.cardHint.Show = function() end
            soon.cardPen:Hide()
            if soon.chipR then
                soon.chipR.chev = K.Text(soon.chipR, 16, C.muted, "RIGHT")
                soon.chipR.chev:SetPoint("RIGHT", -12, 0)
                soon.chipR.chev:SetText(">")
                soon.chipR.value:SetPoint("RIGHT", soon.chipR, "RIGHT", -28, 0)
            end
            -- 0.6.341: keine roten Box-Rahmen im Profil (Entwurf) - nur Glas mit feiner Kante
            local function noFrame(x)
                if not x then return end
                x.noBoxFrame = true
                if x.boxFrame then x.boxFrame:Hide() if x.boxFrame.fit then x.boxFrame.fit() end end
            end
            -- 0.6.361: die Boxen tragen wieder den Oasis-Bildrahmen; nur die kleinen Karten im Kopf bleiben schlicht
            local function withFrame(x)
                if not x then return end
                x.noBoxFrame = nil
                if not x.boxFrame and K.BoxFrame then pcall(K.BoxFrame, x, 40) end
                if x.boxFrame then
                    x.boxFrame:Show()
                    if x.boxFrame.fit then x.boxFrame.fit() end
                    -- 0.6.364: auf der Profil-Seite schwarze Rahmen (Linie dunkel, kein rotes Leuchten)
                    x.boxFrame.tint = { 0.05, 0.05, 0.06 }
                    for _, g in ipairs(x.boxFrame.glows or {}) do g:SetVertexColor(0.05, 0.05, 0.06, 1) end
                    for _, pc in ipairs(x.boxFrame.pieces or {}) do pc:SetDesaturated(true) pc:SetVertexColor(0.22, 0.22, 0.24, 1) end
                end
            end
            -- 0.6.365: alte Panel-Flaeche unter dem Glas ausblenden (zweiter Hintergrund)
            for _, x in ipairs({ cs, pr }) do
                if x.bg then x.bg:SetAlpha(0) end
                for _, t in ipairs(x.skinFill or {}) do t:SetAlpha(0) end
                for _, t in ipairs(x.skinLine or {}) do t:SetAlpha(0) end
                for _, t in ipairs(x.borders or {}) do t:SetAlpha(0) end
            end
            -- 0.6.375: Box-Flaechen deckender (vorher sehr durchsichtig)
            local BOXFILL, BOXLINE = { 0.055, 0.055, 0.065, 0.85 }, { 1, 1, 1, 0.08 }
            function soon:SolidBoxes()
                for _, x in ipairs({ self.cs, self.pr, self.roleBox }) do if x then IG.Glass(x, BOXFILL, BOXLINE) end end
                for _, t in ipairs((self.statTiles and self.statTiles.t) or {}) do IG.Glass(t, BOXFILL, BOXLINE) end
            end
            function soon:NoFrames()
                for _, x in ipairs({ self.chipR, self.vit, self.consBox }) do noFrame(x) end
                for _, x in ipairs({ hc, self.cs, self.pr, self.roleBox }) do withFrame(x) end
                for _, t in ipairs((self.statTiles and self.statTiles.t) or {}) do withFrame(t) end
            end
            -- 0.6.396: alle Profil-Reiter im Look der Werte-Seite - jede umrahmte Box darin bekommt schwarzen
            -- Rahmen und eine deckende dunkle Glasflaeche (Erfolge, Abenteuer, Aufgaben, Koennen ...)
            local styled = setmetatable({}, { __mode = "k" })
            function soon:StyleHosts()
                local function walk(f, depth)
                    if not f or depth > 4 then return end
                    for _, ch in ipairs({ f:GetChildren() }) do
                        if ch.boxFrame and not styled[ch] and not ch.noBoxFrame then
                            styled[ch] = true
                            if K.DarkBoxFrame then pcall(K.DarkBoxFrame, ch) end
                            if (ch:GetWidth() or 0) > 120 and (ch:GetHeight() or 0) > 50 then pcall(IG.Glass, ch, BOXFILL, BOXLINE) end
                        end
                        walk(ch, depth + 1)
                    end
                end
                for _, h in ipairs({ self.rankHost, self.profHost, self.weapHost, self.skillHost, self.weeklyHost, self.lifeHost, self.dailyHost }) do
                    if h and h:IsShown() then walk(h, 1) end
                end
            end
            -- 0.6.399: Wochenaufgaben im Stil der Werte-Seite (Glas, gerundete Zeilen, Haken im Farbkreis, dicker Balken)
            function soon:StyleWeek(week)
                if week.styled then return end
                week.styled = true
                pcall(IG.Glass, week, BOXFILL, BOXLINE)
                if K.DarkBoxFrame then pcall(K.DarkBoxFrame, week) end
                local mint = C.mint
                for i, r in ipairs(week.rows or {}) do
                    r:SetHeight(58)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", week, "TOPLEFT", 14, -44 - (i - 1) * 66)
                    r:SetPoint("RIGHT", week, "RIGHT", -14, 0)
                    if r.bg then r.bg:SetColorTexture(1, 1, 1, 0.03) if K.RoundMask then pcall(K.RoundMask, r.bg, r, 8) end end
                    -- Haken im Farbkreis
                    r.disc = r:CreateTexture(nil, "BORDER")
                    r.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                    r.disc:SetSize(32, 32)
                    r.disc:SetPoint("LEFT", 12, 0)
                    r.disc:SetVertexColor(mint[1], mint[2], mint[3], 0.12)
                    r.check:ClearAllPoints()
                    r.check:SetPoint("CENTER", r.disc, "CENTER")
                    r.check:SetSize(14, 14)
                    r.text:ClearAllPoints()
                    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 56, -12)
                    r.text:SetPoint("RIGHT", r, "RIGHT", -90, 0)
                    K.SetFontSafe(r.text, K.FONT, 13, "", K.FONT)
                    r.xp:ClearAllPoints()
                    r.xp:SetPoint("TOPRIGHT", r, "TOPRIGHT", -14, -12)
                    K.SetFontSafe(r.xp, K.FONT_HEAD, 14, "", K.FONT)
                    r.track:ClearAllPoints()
                    r.track:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 56, 13)
                    r.track:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -70, 13)
                    r.track:SetHeight(8)
                    r.fill:SetHeight(8)
                    if not K.Gradient(r.fill, "HORIZONTAL", { mint[1] * 0.7, mint[2] * 0.7, mint[3] * 0.7, 1 }, { mint[1], mint[2], mint[3], 1 }) then r.fill:SetColorTexture(mint[1], mint[2], mint[3], 1) end
                    if K.RoundMask then pcall(K.RoundMask, r.track, r.track, 4) pcall(K.RoundMask, r.fill, r.fill, 4) end
                    r.prog:ClearAllPoints()
                    r.prog:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -14, 9)
                    K.SetFontSafe(r.prog, K.FONT, 11, "", K.FONT)
                end
                if week.bonus then week.bonus:ClearAllPoints() week.bonus:SetPoint("TOPLEFT", week, "TOPLEFT", 16, -44 - 3 * 66 - 6) end
                if week.x2 then week.x2:ClearAllPoints() week.x2:SetPoint("TOPLEFT", week.bonus, "BOTTOMLEFT", 0, -8) end
            end
            local up2 = soon.Update
            function soon:Update(fresh)
                pcall(self.NoFrames, self)
                pcall(self.SolidBoxes, self)
                up2(self, fresh)
                -- Name in Weiss (Entwurf), Rang: "Rang N" in Gold, Titel hell
                local _, cfx = UnitClass("player")
                local cr2, cg2, cb2 = ns.classColor(ns.safe(cfx))
                cr2, cg2, cb2 = cr2 or 0.6, cg2 or 0.6, cb2 or 0.6
                IG.Glass(hc, { cr2 * 0.06 + 0.025, cg2 * 0.06 + 0.025, cb2 * 0.06 + 0.03, 0.97 }, { 1, 1, 1, 0.08 })   -- 0.6.332: viel dunkler
                if self.xpW then self.rank:SetWidth(self.xpW) end
                local me = ns.me and ns.me() or ""
                self.name:SetText(ns.displayName and ns.displayName(me) or (me:match("^[^-]+") or me))
                self.name:SetTextColor(1, 1, 1)
                local rt = (self.rank:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                local head, rest = rt:match("^(.-)%s%s+[·%s]*(.+)$")
                -- Rang-Wappen vor "Rang N" (0.6.335)
                if not self.rankIco then
                    self.rankIco = hc:CreateTexture(nil, "ARTWORK")
                    self.rankIco:SetSize(18, 18)
                    self.rankIco:SetPoint("RIGHT", self.rank, "LEFT", -6, 0)
                    self.rank:ClearAllPoints()
                    self.rank:SetPoint("TOPLEFT", hc, "TOPLEFT", 300 + 24, -84)
                    -- Leiste bleibt in der Spalte (haengt sonst am verschobenen Text)
                    self.xpTrack:ClearAllPoints()
                    self.xpTrack:SetPoint("TOPLEFT", hc, "TOPLEFT", 300, -110)
                end
                local rl = tonumber((rt:match("(%d+)")))
                if rl and ns.Rank and ns.Rank.FrameIndex then
                    local okI, idx = pcall(ns.Rank.FrameIndex, rl)
                    if okI and idx then self.rankIco:SetTexture(ns.MEDIA .. "emblems\\tier" .. idx) end
                end
                if head and rest then
                    K.SetFontSafe(self.rank, K.FONT_HEAD, 15, "", K.FONT)
                    self.rank:SetText(head .. "   |cffe6e6e6" .. rest .. "|r")
                end
                pcall(self.FillTiles, self)
                pcall(self.FillRing, self)
            end
        end
        p.soon = soon
        -- links: Profilkarte
        local left = K.Panel(p, C.panel)
        left:SetPoint("TOPLEFT")
        left:SetPoint("BOTTOMLEFT")
        left:SetWidth(250)
        left.glow = left:CreateTexture(nil, "BORDER")
        left.glow:SetPoint("TOPLEFT") left.glow:SetPoint("TOPRIGHT") left.glow:SetHeight(160)
        p.left = left
        p.av = K.RankFrame(left, 64, "circle")
        p.av:SetPoint("TOP", 0, -12)
        p.face = p.av:CreateTexture(nil, "OVERLAY", nil, 1)
        p.face:SetSize(64, 64)
        p.face:SetPoint("CENTER")
        p.name = K.Title(left, 17, C.text, "CENTER")
        p.name:SetPoint("TOP", 0, -126)
        p.name:SetWidth(230)
        p.title = K.Text(left, 11, C.amber, "CENTER")
        p.title:SetPoint("TOP", p.name, "BOTTOM", 0, -3)
        p.title:SetWidth(230)
        -- Zahlen: Posts / Follower / Folgt
        p.stats = {}
        for i, lab in ipairs({ "Posts", "Follower", "Folgt" }) do
            local s = CreateFrame("Button", nil, left)
            s:SetSize(74, 40)
            s:SetPoint("TOP", (i - 2) * 78, -160)
            s.n = K.Title(s, 17, C.text, "CENTER")
            s.n:SetPoint("TOP", 0, 0)
            s.l = K.Text(s, 9, C.muted, "CENTER")
            s.l:SetPoint("BOTTOM", 0, 2)
            s.l:SetText(K.Upper(L[lab]))
            s:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
            s:SetScript("OnLeave", function() GameTooltip:Hide() end)
            p.stats[i] = s
        end
        p.likes = K.Text(left, 11, C.pink, "CENTER")
        p.likes:SetPoint("TOP", 0, -206)
        p.bio = K.Text(left, 12, C.text, "CENTER")
        p.bio:SetPoint("TOP", 0, -230)
        p.bio:SetWidth(220)
        p.bio:SetWordWrap(true)
        p.bioEdit = K.Input(left, 220, L["Kurz ueber dich ..."])
        p.bioEdit:SetPoint("TOP", 0, -228)
        p.bioEdit:SetMaxLetters(90)
        p.bioEdit:Hide()
        p.bioEdit:SetScript("OnEnterPressed", function(self)
            S().instaBio = self:GetText()
            self:Hide()
            p.bio:Show()
            if ns.Radar then ns.Radar.SendHello() end
            ns.RefreshPage("insta")
        end)
        p.bioBtn = CreateFrame("Button", nil, left)
        p.bioBtn:SetPoint("TOPLEFT", p.bio, "TOPLEFT", -6, 4)
        p.bioBtn:SetPoint("BOTTOMRIGHT", p.bio, "BOTTOMRIGHT", 6, -4)
        p.bioBtn:SetScript("OnClick", function()
            if view.who and not ns.isMe(view.who) then return end
            p.bio:Hide()
            p.bioEdit:SetText(S().instaBio or "")
            p.bioEdit:Show()
            p.bioEdit:SetFocus()
        end)
        p.bioBtn:SetScript("OnEnter", function(self) if not view.who or ns.isMe(view.who) then K.ShowTip(self, L["Klick: Bio bearbeiten"]) end end)
        p.bioBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        p.action = K.Button(left, "", 200, 30, "primary", function()
            if not view.who or ns.isMe(view.who) then IG.Snap() else IG.ToggleFollow(view.who) end
        end)
        p.action:SetPoint("TOP", 0, -292)
        p.back = K.Button(left, L["Zu meinem Profil"], 200, 24, "ghost", function() IG.ShowProfile(me()) end)
        p.back:SetPoint("TOP", p.action, "BOTTOM", 0, -6)
        -- beliebte Profile
        local ph = K.GameHead(left, L["Beliebt in der Gilde"], C.pink)
        ph:SetPoint("TOPLEFT", 12, -364)
        ph:SetPoint("RIGHT", -12, 0)
        p.pop = {}
        for i = 1, 5 do
            local r = CreateFrame("Button", nil, left)
            r:SetHeight(22)
            r:SetPoint("TOPLEFT", 12, -388 - (i - 1) * 24)
            r:SetPoint("RIGHT", -12, 0)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT") r.hl:SetAllPoints() r.hl:SetColorTexture(1, 1, 1, 0.05)
            r.name = K.Text(r, 12, C.text)
            r.name:SetPoint("LEFT", 4, 0)
            r.val = K.Text(r, 11, C.pink, "RIGHT")
            r.val:SetPoint("RIGHT", -4, 0)
            r:SetScript("OnClick", function(self) if self.who then IG.ShowProfile(self.who) end end)
            p.pop[i] = r
        end

        -- rechts: Reiter + Raster
        local right = CreateFrame("Frame", nil, p)
        right:SetPoint("TOPLEFT", 262, 0)
        right:SetPoint("BOTTOMRIGHT")
        p.right = right
        p.seg = K.Segments(right, {
            { key = "posts", text = L["Posts"] }, { key = "feed", text = L["Feed"] }, { key = "all", text = L["Entdecken"] },
        }, function(k) view.tab = k view.page = 1 view.detail = nil ns.RefreshPage("insta") end)
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.pager = K.Text(right, 11, C.muted, "RIGHT")
        p.pager:SetPoint("TOPRIGHT", -60, -6)
        p.prev = K.Button(right, "<", 26, 24, "ghost", function() view.page = math.max(1, view.page - 1) ns.RefreshPage("insta") end)
        p.prev:SetPoint("TOPRIGHT", -30, 0)
        p.next = K.Button(right, ">", 26, 24, "ghost", function() view.page = view.page + 1 ns.RefreshPage("insta") end)
        p.next:SetPoint("TOPRIGHT", 0, 0)
        p.tiles = {}
        for i = 1, PER do
            local t = CreateFrame("Button", nil, right)
            t:SetSize(150, 190)
            t.scene = IG.Scene(t, 150, 190)
            t.scene:SetPoint("TOPLEFT")
            t.scene.model:EnableMouse(false)
            K.Border(t, C.line)
            t.cap = K.Text(t, 11, C.text)
            t.cap:SetPoint("BOTTOMLEFT", 8, 24)
            t.cap:SetPoint("RIGHT", -8, 0)
            t.cap:SetWordWrap(false)
            t.who = K.Text(t, 10, C.muted)
            t.who:SetPoint("BOTTOMLEFT", 8, 8)
            t.heart = K.Text(t, 11, C.pink, "RIGHT")
            t.heart:SetPoint("BOTTOMRIGHT", -8, 8)
            t.hl = t:CreateTexture(nil, "HIGHLIGHT") t.hl:SetAllPoints() t.hl:SetColorTexture(1, 1, 1, 0.05)
            t:SetScript("OnClick", function(self) if self.post then view.detail = self.post.id ns.RefreshPage("insta") end end)
            t:SetScript("OnDoubleClick", function(self) if self.post then IG.ToggleLike(self.post) end end)
            t.del = CreateFrame("Button", nil, t)
            t.del:SetSize(22, 22)
            t.del:SetPoint("TOPRIGHT", -4, -4)
            t.del:SetFrameLevel(t.scene.model:GetFrameLevel() + 5)
            t.del.bg = t.del:CreateTexture(nil, "BACKGROUND")
            t.del.bg:SetAllPoints()
            t.del.bg:SetColorTexture(0, 0, 0, 0.6)
            t.del.x = K.Text(t.del, 13, C.text, "CENTER")
            t.del.x:SetPoint("CENTER", 0, 1)
            t.del.x:SetText("x")
            t.del:SetScript("OnClick", function(self) if t.post then IG.ArmDelete(self, t.post) end end)
            t.del:SetScript("OnEnter", function(self) K.ShowTip(self, L["Post loeschen"]) end)
            t.del:SetScript("OnLeave", function() GameTooltip:Hide() end)
            t.del:Hide()
            p.tiles[i] = t
        end
        right:SetScript("OnSizeChanged", function(self, w, h)
            local tw = math.floor(((w or 480) - 20) / 3)
            local th = math.floor(((h or 540) - 36 - 10) / 2)
            for i, t in ipairs(p.tiles) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", ((i - 1) % 3) * (tw + 10), -36 - math.floor((i - 1) / 3) * (th + 10))
                t:SetSize(tw, th)
                t.scene:SetSize(tw, th)
            end
        end)
        p.empty = K.Text(right, 13, C.muted, "CENTER")
        p.empty:SetPoint("CENTER", 0, 0)
        p.empty:SetWidth(360)
        p.empty:SetWordWrap(true)

        -- Detailansicht (ueber dem Raster)
        local d = K.Panel(right, C.panel)
        d:SetPoint("TOPLEFT", 0, -36)
        d:SetPoint("BOTTOMRIGHT")
        d:SetFrameLevel(right:GetFrameLevel() + 20)
        d:EnableMouse(true)
        d:Hide()
        p.detail = d
        d.scene = IG.Scene(d, 240, 330)
        d.scene:SetPoint("TOPLEFT", 10, -10)
        K.Border(d.scene, C.line)
        d.close = K.CloseButton(d, function() view.detail = nil ns.RefreshPage("insta") end, L["Schliessen (Esc)"])
        d.close:SetPoint("TOPRIGHT", -8, -8)
        local DX = 262
        d.who = K.Title(d, 14, C.text)
        d.who:SetPoint("TOPLEFT", DX, -14)
        d.whoBtn = CreateFrame("Button", nil, d)
        d.whoBtn:SetAllPoints(d.who)
        d.whoBtn:SetScript("OnClick", function() if d.post then IG.ShowProfile(d.post.by) end end)
        d.where = K.Text(d, 10, C.muted)
        d.where:SetPoint("TOPLEFT", d.who, "BOTTOMLEFT", 0, -3)
        d.cap = K.Text(d, 13, C.text)
        d.cap:SetPoint("TOPLEFT", DX, -56)
        d.cap:SetPoint("RIGHT", -14, 0)
        d.cap:SetWordWrap(true)
        d.like = CreateFrame("Button", nil, d)
        d.like:SetSize(30, 30)
        d.like:SetPoint("TOPLEFT", DX - 4, -104)
        d.like.icon = d.like:CreateTexture(nil, "ARTWORK")
        d.like.icon:SetAllPoints()
        d.like.icon:SetTexture(ICON .. "heart")
        d.like:SetScript("OnClick", function(self)
            if not d.post then return end
            IG.ToggleLike(d.post)
            -- kleiner "Pop"
            K.Tween(self, 0.35, function(q) local s = 30 + 10 * math.sin(q * math.pi) self:SetSize(s, s) end, function() self:SetSize(30, 30) end)
        end)
        d.likes = K.Text(d, 12, C.text)
        d.likes:SetPoint("LEFT", d.like, "RIGHT", 8, 0)
        d.likesBtn = CreateFrame("Button", nil, d)
        d.likesBtn:SetAllPoints(d.likes)
        d.likesBtn:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
        d.likesBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        d.del = K.Button(d, L["Loeschen"], 80, 22, "danger", function(self)
            if d.post then IG.ArmDelete(d.del, d.post, function() view.detail = nil ns.RefreshPage("insta") end) end
        end)
        d.del:SetPoint("TOPRIGHT", -40, -108)
        local ch = K.GameHead(d, L["Kommentare"], C.pink)
        ch:SetPoint("TOPLEFT", DX, -148)
        ch:SetPoint("RIGHT", -14, 0)
        d.ch = ch
        d.comments = {}
        for i = 1, 6 do
            local c = K.Text(d, 11, C.text)
            c:SetPoint("TOPLEFT", DX, -172 - (i - 1) * 22)
            c:SetPoint("RIGHT", -14, 0)
            c:SetWordWrap(false)
            d.comments[i] = c
        end
        d.input = K.Input(d, 200, L["Kommentieren ..."])
        d.input:SetPoint("BOTTOMLEFT", DX, 12)
        d.input:SetPoint("RIGHT", -14, 0)
        d.input:SetMaxLetters(120)
        d.input:SetScript("OnEnterPressed", function(self)
            if d.post then IG.Comment(d.post, self:GetText()) end
            self:SetText("")
        end)
    end,
    refresh = function(p)
        p.soon:SetShown(IG.SOON and true or false)
        -- 0.5.653: alte Profilansicht (linke Karte mit Portrait-Kreis ...) schimmerte hinter der neuen Karte durch -> ausblenden
        if IG.SOON then
            for _, c in ipairs({ p:GetChildren() }) do
                if c ~= p.soon and c:IsShown() then
                    c:Hide()
                    p.oldHidden = p.oldHidden or {}
                    p.oldHidden[c] = true
                end
            end
        elseif p.oldHidden then
            for c in pairs(p.oldHidden) do c:Show() end
            p.oldHidden = nil
        end
        if IG.SOON then
            p.soon:Update(p.fresh)
            p.soon:ShowTab(ns.profileTab or "stats")
            if p.fresh then K.FadeIn(p.soon, 0) end
            p.fresh = false
            return
        end
        local fresh = p.fresh
        local who = view.who or me()
        local mine = ns.isMe(who)
        if mine then unread = 0 ns.SetNavBadge("insta", nil) end
        -- Profilkarte
        local R = ns.Radar
        local cls = R and R.ClassOf(who)
        local cr, cg, cb = ns.classColor(cls)
        if not K.Gradient(p.left.glow, "VERTICAL", { cr or 1, cg or 1, cb or 1, 0 }, { cr or 1, cg or 1, cb or 1, 0.14 }) then p.left.glow:SetColorTexture(cr or 1, cg or 1, cb or 1, 0.04) end
        local lvl, verified = nil, true
        if ns.Rank then lvl, verified = ns.Rank.Of(who) end
        local st = lvl and ns.Rank.Frame(lvl) or { name = "-", color = { cr or 0.6, cg or 0.6, cb or 0.6 }, width = 2 }
        local key = st.name .. tostring(lvl and K.RingTier and K.RingTier(lvl) or "")
        if p.av.styleName ~= key then p.av:SetStyle(st, lvl) p.av.styleName = key end
        if mine and SetPortraitTexture then
            pcall(SetPortraitTexture, p.face, "player")
            p.face:SetTexCoord(0, 1, 0, 1)
        else
            local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
            p.face:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            if tc then p.face:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
        end
        if p.face.SetMask and not p.masked then p.masked = pcall(p.face.SetMask, p.face, MASK) end K.MaskSafe(p.face)
        p.name:SetText(ns.colorName(who, cls))
        p.title:SetText(lvl and ((L["Rang %d"]):format(lvl) .. "  ·  " .. ns.Rank.Title(lvl) .. (verified and "" or ("  |cffe69a4a(" .. L["ungeprueft"] .. ")|r"))) or L["ohne Oasis-Rang"])
        local posts = IG.PostsBy(who)
        local fol, fing = IG.Followers(who), IG.Following(who)
        local vals = { #posts, #fol, #fing }
        local tips = { nil, fol, fing }
        for i, s in ipairs(p.stats) do
            if fresh then K.CountUp(s.n, vals[i], 0.7) else s.n:SetText(vals[i]) end
            local names = {}
            for _, n in ipairs(tips[i] or {}) do names[#names + 1] = ns.displayName(n) end
            s.tip = (#names > 0) and { L[({ "Posts", "Follower", "Folgt" })[i]], table.concat(names, ", ") } or nil
        end
        p.likes:SetText("|T" .. ICON .. "heart:12:12:0:0:64:64:0:64:0:64:255:127:168|t  " .. (L["%d Likes insgesamt"]):format(IG.LikesReceived(who)))
        local bio = mine and (S().instaBio or "") or (ns.db.members[who] and ns.db.members[who].bio or "")
        p.bio:SetText(bio ~= "" and bio or ("|cff666666" .. (mine and L["Klick: Bio schreiben"] or L["Noch keine Bio."]) .. "|r"))
        if mine then
            p.action:SetLabel("|T" .. ICON .. "camera:14:14|t  " .. L["Neuer Schnappschuss"])
        else
            p.action:SetLabel(IG.IFollow(who) and L["Entfolgen"] or ("+ " .. L["Folgen"]))
        end
        p.back:SetShown(not mine)
        -- beliebt: meiste Follower
        local cnt = {}
        for _, f in ipairs(Store.List("follows")) do local k = ns.short(f.target) cnt[k] = { n = ((cnt[k] and cnt[k].n) or 0) + 1, who = f.target } end
        for _, po in ipairs(Store.List("posts")) do local k = ns.short(po.by) cnt[k] = cnt[k] or { n = 0, who = po.by } end
        local top = {}
        for _, v in pairs(cnt) do top[#top + 1] = v end
        table.sort(top, function(a, b) if a.n ~= b.n then return a.n > b.n end return ns.short(a.who) < ns.short(b.who) end)
        for i, r in ipairs(p.pop) do
            local t = top[i]
            if t then
                r.who = t.who
                r.name:SetText(ns.Radar.Colored(t.who))
                r.val:SetText((L["%d Follower"]):format(t.n))
                r:Show()
            else
                r:Hide()
            end
        end
        -- Raster
        p.seg:Select(view.tab)
        local list = view.tab == "feed" and IG.Feed() or (view.tab == "all" and IG.AllPosts() or posts)
        local pages = math.max(1, math.ceil(#list / PER))
        view.page = math.min(view.page, pages)
        p.pager:SetText(view.page .. " / " .. pages)
        p.prev:SetShown(pages > 1) p.next:SetShown(pages > 1) p.pager:SetShown(pages > 1)
        for i, t in ipairs(p.tiles) do
            local po = list[(view.page - 1) * PER + i]
            if po then
                t.post = po
                if t.scene.post ~= po then t.scene:ShowPost(po) end
                t.cap:SetText(po.cap or "")
                t.who:SetText(ns.Radar.Colored(po.by) .. "  |cff666666" .. ns.ago(po.ts) .. "|r")
                local nl = #IG.Likes(po)
                t.heart:SetText((IG.Liked(po) and "|cffff7fa8♥|r " or "♡ ") .. nl)
                t.del:SetShown(ns.isMe(po.by))
                t:Show()
                if fresh then K.FadeIn(t, i * 0.06) end
            else
                t.post = nil
                t:Hide()
            end
        end
        p.empty:SetShown(#list == 0)
        p.empty:SetText(view.tab == "feed" and L["Noch nichts im Feed. Folge Leuten aus der Gilde - ihre Posts landen dann hier."]
            or (mine and view.tab == "posts" and L["Noch keine Posts. Klick auf 'Neuer Schnappschuss' oder auf die Kamera in der Oasis-Leiste!"]
            or L["Hier gibt es noch nichts zu sehen."]))
        -- Detail
        local dp = view.detail and Store.Get("posts", view.detail)
        local d = p.detail
        if dp and not dp.del then
            d.post = dp
            if d.scene.post ~= dp then d.scene:ShowPost(dp) end
            d.who:SetText(ns.Radar.Colored(dp.by))
            d.where:SetText("|cffff7fa8@|r " .. (dp.zone ~= "" and dp.zone or "?") .. "  ·  " .. ns.ago(dp.ts))
            d.cap:SetText(ns.Emoji and ns.Emoji.Render(dp.cap or "") or (dp.cap or ""))
            local likes = IG.Likes(dp)
            local liked = IG.Liked(dp)
            d.like.icon:SetVertexColor(liked and 1 or 0.5, liked and 0.5 or 0.5, liked and 0.66 or 0.55)
            d.likes:SetText((L["%d Likes"]):format(#likes))
            local names = {}
            for _, l in ipairs(likes) do names[#names + 1] = ns.displayName(l.by) end
            d.likesBtn.tip = #names > 0 and { L["Gefaellt:"], table.concat(names, ", ") } or nil
            d.del:SetShown(ns.isMe(dp.by))
            local cm = IG.Comments(dp)
            d.ch:SetCount(#cm > 0 and #cm or nil)
            for i, c in ipairs(d.comments) do
                local x = cm[#cm - #d.comments + i] or (#cm < #d.comments and cm[i]) or nil
                if #cm <= #d.comments then x = cm[i] end
                c:SetText(x and (ns.Radar.Colored(x.by) .. "  " .. (ns.Emoji and ns.Emoji.Render(x.text) or x.text)) or "")
            end
            if not d:IsShown() then d:Show() K.FadeIn(d, 0) end
        else
            d:Hide()
        end
        p.fresh = false
    end,
})
ns.slash.profil = function() IG.ShowProfile(me()) end

------------------------------------------------------------------------
-- Ausruestungs-Check im Blizzard-Charakterfenster: Gegenstandsstufe je Feld (in Qualitaetsfarbe),
-- schwaechstes Teil rot markiert, Oasis-Leiste mit Durchschnitt + "Upgrades finden".
-- Nur eigene Elemente auf den Feldern - Blizzards Knoepfe selbst werden nicht veraendert.
------------------------------------------------------------------------
local GEAR_SLOTS = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged" }
local gearMarks = {}
local function itemLevelOf(link)
    if not link then return nil end
    local lvl
    if C_Item and C_Item.GetDetailedItemLevelInfo then lvl = C_Item.GetDetailedItemLevelInfo(link) end
    if not lvl and GetDetailedItemLevelInfo then lvl = GetDetailedItemLevelInfo(link) end
    if not lvl then lvl = select(4, C_Item.GetItemInfo(link)) end
    return tonumber(ns.safe(lvl))
end
local function markFor(slotName)
    if gearMarks[slotName] then return gearMarks[slotName] end
    local btn = _G["Character" .. slotName .. "Slot"]
    if not btn then return nil end
    local m = CreateFrame("Frame", nil, btn)
    m:SetAllPoints()
    m:SetFrameLevel(btn:GetFrameLevel() + 5)
    m:EnableMouse(false)
    m.lvl = m:CreateFontString(nil, "OVERLAY")
    K.SetFontSafe(m.lvl, K.FONT_HEAD, 13, "THICKOUTLINE", K.FONT)
    m.lvl:SetAlpha(1)
    -- oben links wie in den Taschen - unten rechts wirkt es wie eine Stapelzahl
    m.lvl:SetPoint("TOPLEFT", 1, -1)
    m.weak = m:CreateTexture(nil, "OVERLAY")
    m.weak:SetPoint("TOPLEFT", -1, 1)
    m.weak:SetPoint("BOTTOMRIGHT", 1, -1)
    m.weak:SetColorTexture(1, 0.15, 0.15, 0)
    m.weakTag = m:CreateTexture(nil, "OVERLAY", nil, 2)
    m.weakTag:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    m.weakTag:SetSize(10, 10)
    m.weakTag:SetAlpha(0.7)
    m.weakTag:SetPoint("BOTTOMRIGHT", -1, 1)
    gearMarks[slotName] = m
    return m
end
local gearBar
local function updateGear()
    if not (PaperDollFrame and PaperDollFrame:IsVisible()) then return end
    local sum, n, weakest, weakLvl = 0, 0, nil, nil
    for _, slot in ipairs(GEAR_SLOTS) do
        local m = markFor(slot)
        if m then
            local id = GetInventorySlotInfo(slot .. "Slot")
            local link = id and ns.safe(GetInventoryItemLink("player", id))
            local lvl = itemLevelOf(link)
            m.weak:SetColorTexture(1, 0.15, 0.15, 0)
            m.weakTag:Hide()
            if lvl then
                -- 0.5.849: Farbe = Seltenheit des Teils (grau/weiss/gruen/blau/lila/orange) wie in den Taschen, fett und voll deckend
                local q = ns.safe(select(3, C_Item.GetItemInfo(link)))
                if type(q) ~= "number" and C_Item.GetItemQualityByID then q = ns.safe(C_Item.GetItemQualityByID(link)) end
                -- Rueckfall: Seltenheit aus dem Farbcode des Links ("|cnIQ3:" in Forever)
                if type(q) ~= "number" and type(link) == "string" then q = tonumber(link:match("|cnIQ(%d):")) end
                if type(q) ~= "number" then q = 1 end
                -- feste Farbtabelle: GetItemQualityColor gibt es in diesem Client nicht (darum blieben die Zahlen weiss)
                local QC = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.55, 1 },
                    [4] = { 0.78, 0.35, 1 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 } }
                local qc = QC[q] or QC[1]
                local r, g, b = qc[1], qc[2], qc[3]
                m.lvl:SetText(lvl)
                m.lvl:SetTextColor(r, g, b)
                m.lvl:SetAlpha(1)
                sum, n = sum + lvl, n + 1
                if not weakLvl or lvl < weakLvl then weakest, weakLvl = m, lvl end
            else
                m.lvl:SetText("")
            end
        end
    end
    if weakest and n >= 4 then
        weakest.weakTag:Show()
    end
    if gearBar then
        local avg = n > 0 and sum / n or 0
        local lvl = ns.safe(UnitLevel("player")) or 1
        local c = avg >= lvl * 0.9 and C.mint or (avg >= lvl * 0.7 and C.amber or C.red)
        gearBar.t:SetText(("|cff888888Oasis|r   " .. L["Gegenstandsstufe"] .. ": " .. K.hex(c) .. "%.1f|r   |cff888888" .. L["schwaechstes Teil: %s"] .. "|r"):format(avg, weakLvl and tostring(weakLvl) or "-"))
        gearBar:SetWidth(math.max(320, (gearBar.t:GetStringWidth() or 200) + 140))
    end
end
local function setupCharFrame()
    if gearBar or not PaperDollFrame then return end
    gearBar = CreateFrame("Frame", nil, PaperDollFrame)
    gearBar:SetSize(300, 24)
    gearBar:SetPoint("TOP", PaperDollFrame, "BOTTOM", 0, 2)
    if CharacterFrame then gearBar:SetPoint("TOP", CharacterFrame, "BOTTOM", 0, 0) end
    gearBar.bg = K.Fill(gearBar, { 0.04, 0.04, 0.05, 0.92 })
    K.Border(gearBar, C.line)
    gearBar.t = K.Text(gearBar, 11, C.text)
    gearBar.t:SetPoint("LEFT", 10, 0)
    gearBar.btn = K.Button(gearBar, L["Upgrades finden"], 110, 18, "primary", function()
        if ns.Upgrades then ns.Upgrades.Toggle(gearBar) end
    end)
    gearBar.btn:SetPoint("RIGHT", -4, 0)
    gearBar.btn:SetScript("OnEnter", function(self)
        K.ShowTip(self, { L["Upgrades finden"], L["Zeigt Beute aus Dungeons deines Levelbereichs, die besser ist als dein angelegtes Teil."] })
    end)
    gearBar.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    gearBar:SetScript("OnSizeChanged", nil)
    PaperDollFrame:HookScript("OnShow", function() ns.After(0.05, updateGear) end)
    -- Breite an den Text anpassen
    gearBar:SetScript("OnUpdate", function(self)
        self:SetWidth(math.max(300, (self.t:GetStringWidth() or 200) + 140))
        self:SetScript("OnUpdate", nil)
    end)
end
ns.Listen("LOGIN", function() pcall(setupCharFrame) end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.After(0.2, updateGear) end)
ns.On("GET_ITEM_INFO_RECEIVED", function() if PaperDollFrame and PaperDollFrame:IsVisible() then updateGear() end end)

------------------------------------------------------------------------
-- Upgrade-Finder: Dungeon-Beute (Levelbereich) mit hoeherer Gegenstandsstufe als das angelegte Teil
------------------------------------------------------------------------
do
    local U = {}
    ns.Upgrades = U
    local LOC = {
        INVTYPE_HEAD = { "Head" }, INVTYPE_NECK = { "Neck" }, INVTYPE_SHOULDER = { "Shoulder" }, INVTYPE_CLOAK = { "Back" },
        INVTYPE_CHEST = { "Chest" }, INVTYPE_ROBE = { "Chest" }, INVTYPE_WRIST = { "Wrist" }, INVTYPE_HAND = { "Hands" },
        INVTYPE_WAIST = { "Waist" }, INVTYPE_LEGS = { "Legs" }, INVTYPE_FEET = { "Feet" },
        INVTYPE_FINGER = { "Finger0", "Finger1" }, INVTYPE_TRINKET = { "Trinket0", "Trinket1" },
        INVTYPE_WEAPON = { "MainHand" }, INVTYPE_WEAPONMAINHAND = { "MainHand" }, INVTYPE_2HWEAPON = { "MainHand" },
        INVTYPE_WEAPONOFFHAND = { "SecondaryHand" }, INVTYPE_SHIELD = { "SecondaryHand" }, INVTYPE_HOLDABLE = { "SecondaryHand" },
        INVTYPE_RANGED = { "Ranged" }, INVTYPE_RANGEDRIGHT = { "Ranged" }, INVTYPE_THROWN = { "Ranged" }, INVTYPE_RELIC = { "Ranged" },
    }
    -- Ruestungsklasse (1 Stoff .. 4 Platte) und Waffen je Klasse
    local ARMOR = { WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2, PRIEST = 1, MAGE = 1, WARLOCK = 1 }
    local WEAP = {
        WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 }, PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
        HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 }, ROGUE = { 2, 3, 4, 7, 13, 15, 16, 18 },
        PRIEST = { 4, 10, 15, 19 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 }, MAGE = { 7, 10, 15, 19 },
        WARLOCK = { 7, 10, 15, 19 }, DRUID = { 4, 5, 6, 10, 13, 15 },
    }
    local SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
    local function usable(cls, lvl, classID, sub)
        if classID == 4 then
            if sub == 6 then return SHIELD[cls] end
            if sub == 0 or not sub then return true end
            if sub > 4 then return false end
            local max = ARMOR[cls] or 1
            if lvl < 40 and (cls == "WARRIOR" or cls == "PALADIN") then max = 3 end
            if lvl < 40 and (cls == "HUNTER" or cls == "SHAMAN") then max = 2 end
            return sub <= max
        elseif classID == 2 then
            return tContains(WEAP[cls] or {}, sub)
        end
        return false
    end
    local function equippedLink(slot)
        local id = GetInventorySlotInfo(slot .. "Slot")
        return id and ns.safe(GetInventoryItemLink("player", id))
    end
    local function equipped(slot)
        local link = equippedLink(slot)
        return link and (itemLevelOf(link) or 0) or 0
    end
    -- Wert eines Items fuer die gewaehlte Spezialisierung (Profil -> Meine Stats): Gewichte je Wert
    local W = {
        melee = { STRENGTH = 2, AGILITY = 1.6, ATTACK_POWER = 1, CRIT_RATING = 14, HIT_RATING = 14, STAMINA = 0.3, DAMAGE_PER_SECOND = 9 },
        hunter = { AGILITY = 2, ATTACK_POWER = 1, RANGED_ATTACK_POWER = 1, INTELLECT = 0.4, CRIT_RATING = 14, HIT_RATING = 14, STAMINA = 0.3, DAMAGE_PER_SECOND = 6 },
        tank = { STAMINA = 1.6, DEFENSE_SKILL_RATING = 2, AGILITY = 1, STRENGTH = 1, DODGE_RATING = 12, PARRY_RATING = 12, BLOCK_RATING = 6, ARMOR = 0.08, DAMAGE_PER_SECOND = 2 },
        caster = { INTELLECT = 1, SPELL_POWER = 1.4, SPELL_DAMAGE_DONE = 1.4, SPIRIT = 0.4, STAMINA = 0.3, SPELL_CRIT_RATING = 12, SPELL_HIT_RATING = 12, MANA_REGENERATION = 1.5 },
        healer = { INTELLECT = 1, SPELL_HEALING_DONE = 1.2, SPELL_POWER = 1, SPIRIT = 0.6, MANA_REGENERATION = 2, STAMINA = 0.3, SPELL_CRIT_RATING = 8 },
    }
    local function myRole()
        local s = ns.Insta and ns.Insta.headSoon
        if s and s.Role then local ok, r = pcall(s.Role, s) if ok and r then return r end end
        local _, c = UnitClass("player")
        return ({ MAGE = "caster", WARLOCK = "caster", PRIEST = "healer", HUNTER = "hunter" })[c or ""] or "melee"
    end
    local function scoreOf(link, role)
        if not link then return 0 end
        local getStats = (C_Item and C_Item.GetItemStats) or GetItemStats
        if not getStats then return 0 end
        local ok, st = pcall(getStats, link)
        if not ok or type(st) ~= "table" then return 0 end
        local w = W[role] or W.melee
        local sum = 0
        for k, v in pairs(st) do
            local key = tostring(k):gsub("^ITEM_MOD_", ""):gsub("_SHORT$", ""):gsub("_NAME$", "")
            if key == "RESISTANCE0" then key = "ARMOR" end
            local wv = w[key]
            if wv and tonumber(v) then sum = sum + tonumber(v) * wv end
        end
        return sum
    end
    U.ScoreOf, U.MyRole = scoreOf, myRole

    function U.Find()
        local out, pending = {}, 0
        local stats = { total = 0, dungeons = 0 }   -- 0.5.938: fuer Ladeanzeige und "warum nichts gefunden"
        local lvl = ns.safe(UnitLevel("player")) or 1
        local cls = select(2, UnitClass("player"))
        local de = GetLocale and GetLocale() == "deDE"
        local seen = {}
        for _, d in ipairs(ns.DungeonData or {}) do
            local lo, hi = d.lo or 0, d.hi or d.lo or 0
            if d.lo and d.status ~= "closed" and lo <= lvl + 4 and hi >= lvl - 4 then
                stats.dungeons = stats.dungeons + 1
                for _, b in ipairs(d.bosses or {}) do
                    for _, it in ipairs(b.loot or {}) do
                        local id = it[1]
                        if id and not seen[id] then
                            seen[id] = true
                            stats.total = stats.total + 1
                            local name, link, q, ilvl, minL, _, _, _, loc, tex, _, classID, sub = C_Item.GetItemInfo(id)
                            if not name then
                                pending = pending + 1
                                if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
                            else
                                local slots = LOC[loc or ""]
                                if slots and (minL or 0) > lvl and usable(cls, lvl, classID, sub) and (not stats.nextLvl or minL < stats.nextLvl) then
                                    stats.nextLvl = minL   -- tragbar, aber erst spaeter
                                end
                                if slots and (minL or 0) <= lvl and usable(cls, lvl, classID, sub)
                                    and not (ns.Upgrade and ns.Upgrade.Unlearned and ns.Upgrade.Unlearned(link)) then   -- 0.5.942: nichts Ungelerntes vorschlagen
                                    -- nach Werten fuer die eigene Spezialisierung vergleichen (nicht nur Gegenstandsstufe)
                                    local role = myRole()
                                    local cur, curScore = math.huge, math.huge
                                    for _, sl in ipairs(slots) do
                                        local sc = scoreOf(equippedLink(sl), role)
                                        if sc < curScore then curScore, cur = sc, equipped(sl) end
                                    end
                                    local newScore = scoreOf(link, role)
                                    local gain = math.floor(newScore - curScore + 0.5)
                                    if gain >= 1 then
                                        out[#out + 1] = { link = link, tex = tex, gain = gain, ilvl = ilvl, minL = minL or 0,
                                            src = (de and d.de or d.name) .. "  ·  " .. (b.name or "?"), key = d.key, cur = cur,
                                            dungeon = (de and d.de or d.name), boss = b.name, lo = d.lo, hi = d.hi, q = q,
                                            slot = (slots[1]:gsub("%d$", "")) }
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        table.sort(out, function(a, b) if a.gain ~= b.gain then return a.gain > b.gain end return a.ilvl > b.ilvl end)
        return out, pending, stats
    end

    local SLOTS = {
        { "Head", "Kopf" }, { "Neck", "Hals" }, { "Shoulder", "Schultern" }, { "Back", "Ruecken" }, { "Chest", "Brust" },
        { "Wrist", "Handgelenke" }, { "Hands", "Haende" }, { "Waist", "Taille" }, { "Legs", "Beine" }, { "Feet", "Fuesse" },
        { "Finger", "Ringe" }, { "Trinket", "Schmuck" }, { "MainHand", "Waffenhand" }, { "SecondaryHand", "Nebenhand" }, { "Ranged", "Distanz" },
    }
    local f
    local function build()
        f = CreateFrame("Frame", "OasisUpgrades", CharacterFrame or UIParent)
        f:SetSize(360, 482)   -- 0.6.193: breiter fuer die Fundort-Zeile
        if CharacterFrame then f:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", -30, -12) else f:SetPoint("CENTER") end
        f:SetFrameStrata("HIGH")
        f:EnableMouse(true)
        K.Fill(f, { 0.04, 0.04, 0.05, 0.97 })
        K.Border(f, C.line)
        local hd = K.GameHead(f, L["Beste Upgrades je Platz"], C.amber)
        hd:SetPoint("TOPLEFT", 12, -10) hd:SetPoint("RIGHT", -36, 0)
        local close = K.CloseButton(f, function() f:Hide() end, L["Schliessen (Esc)"])
        close:SetPoint("TOPRIGHT", -6, -6)
        -- 0.6.193: Plaetze mit Upgrade als zweizeilige Karte (Symbol mit Qualitaetsrahmen, Name, darunter Fundort
        -- Dungeon · Boss in Gold, rechts Gewinn als Plakette); leere Plaetze als schmale gedimmte Zeile. Hoehe passt sich an.
        f.rows = {}
        for i, sl in ipairs(SLOTS) do
            local r = CreateFrame("Button", nil, f)
            r:SetHeight(20)
            r:SetPoint("LEFT", f, "LEFT", 8, 0)
            r:SetPoint("RIGHT", f, "RIGHT", -8, 0)
            r.bg = r:CreateTexture(nil, "BACKGROUND")
            r.bg:SetPoint("TOPLEFT", 0, -2) r.bg:SetPoint("BOTTOMRIGHT", 0, 2)
            r.bg:SetColorTexture(1, 1, 1, 0.045)
            r.edge = r:CreateTexture(nil, "ARTWORK")
            r.edge:SetPoint("TOPLEFT", r.bg, "TOPLEFT") r.edge:SetPoint("BOTTOMLEFT", r.bg, "BOTTOMLEFT")
            r.edge:SetWidth(2)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints(r.bg) r.hl:SetColorTexture(1, 1, 1, 0.06)
            r.slot = K.Text(r, 9, C.dim)
            r.slot:SetPoint("LEFT", 10, 0)
            r.slot:SetWidth(68)
            r.slot:SetText(K.Upper(L[sl[2]]))
            r.iconBox = CreateFrame("Frame", nil, r)
            r.iconBox:SetSize(30, 30)
            r.iconBox:SetPoint("LEFT", 80, 0)
            r.iconBox.bg = r.iconBox:CreateTexture(nil, "BACKGROUND")
            r.iconBox.bg:SetAllPoints() r.iconBox.bg:SetColorTexture(0, 0, 0, 0.6)
            K.Border(r.iconBox, C.line)
            r.icon = r.iconBox:CreateTexture(nil, "ARTWORK")
            r.icon:SetPoint("TOPLEFT", 2, -2) r.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.pill = r:CreateTexture(nil, "ARTWORK")
            r.pill:SetSize(40, 18)
            r.pill:SetPoint("RIGHT", -8, 0)
            r.pill:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.14)
            r.gain = K.Text(r, 11, C.mint, "CENTER")
            r.gain:SetPoint("CENTER", r.pill)
            r.name = K.Text(r, 11, C.text)
            r.name:SetPoint("TOPLEFT", r.iconBox, "TOPRIGHT", 8, -1)
            r.name:SetPoint("RIGHT", r.pill, "LEFT", -8, 0)
            r.name:SetWordWrap(false)
            r.src = K.Text(r, 9, { 0.9, 0.72, 0.38 })
            r.src:SetPoint("BOTTOMLEFT", r.iconBox, "BOTTOMRIGHT", 8, 2)
            r.src:SetPoint("RIGHT", r.pill, "LEFT", -8, 0)
            r.src:SetWordWrap(false)
            r.empty = K.Text(r, 10, { 0.4, 0.4, 0.42 })
            r.empty:SetPoint("LEFT", 80, 0)
            r.empty:SetText(L["kein besseres Teil"])
            r.key = sl[1]
            r:SetScript("OnEnter", function(self)
                if not self.item then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, self.item.link)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(self.item.src, 0.9, 0.72, 0.38)
                if self.item.lo then GameTooltip:AddLine((L["Dungeon fuer Level %d-%d"]):format(self.item.lo, self.item.hi or self.item.lo), 0.6, 0.6, 0.6) end
                GameTooltip:AddLine((L["+%d Punkte fuer deine Spezialisierung"]):format(self.item.gain), 0.4, 0.86, 0.62)
                GameTooltip:AddLine(L["Shift-Klick: verlinken"], 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self)
                if self.item and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.item.link) end
            end)
            function r:SetFull(on)
                self:SetHeight(on and 42 or 20)
                self.bg:SetShown(on) self.edge:SetShown(on) self.iconBox:SetShown(on) self.pill:SetShown(on)
                self.gain:SetShown(on) self.name:SetShown(on) self.src:SetShown(on) self.empty:SetShown(not on)
                self.slot:SetTextColor(on and 0.75 or 0.4, on and 0.75 or 0.4, on and 0.78 or 0.42)
            end
            r:SetFull(false)
            f.rows[i] = r
        end
        -- Fusszeile: eigener Bereich unter den Plaetzen (Spezialisierung, Anzahl, Hinweis)
        f.footBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        f.footBg:SetPoint("BOTTOMLEFT", 1, 1)
        f.footBg:SetPoint("BOTTOMRIGHT", -1, 1)
        f.footBg:SetHeight(52)
        f.footBg:SetColorTexture(1, 1, 1, 0.03)
        f.footLine = f:CreateTexture(nil, "ARTWORK")
        f.footLine:SetPoint("BOTTOMLEFT", 1, 53)
        f.footLine:SetPoint("BOTTOMRIGHT", -1, 53)
        f.footLine:SetHeight(1)
        f.footLine:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        f.footRole = K.Text(f, 11, C.amber)
        f.footRole:SetPoint("BOTTOMLEFT", 12, 30)
        f.footCount = K.Text(f, 11, C.mint, "RIGHT")
        f.footCount:SetPoint("BOTTOMRIGHT", -12, 30)
        f.foot = K.Text(f, 10, C.dim)
        f.foot:SetPoint("BOTTOMLEFT", 12, 12)
        f.foot:SetPoint("RIGHT", f, "RIGHT", -12, 0)
        f.foot:SetWordWrap(false)
        -- 0.5.938: Ladeanzeige, solange der Client die Gegenstaende noch nachlaedt (und kurz beim Oeffnen, damit man die Suche sieht)
        local ld = CreateFrame("Frame", nil, f)
        ld:SetPoint("TOPLEFT", 1, -32)
        ld:SetPoint("BOTTOMRIGHT", -1, 54)
        ld:SetFrameLevel(f:GetFrameLevel() + 10)
        ld:EnableMouse(true)
        K.Fill(ld, { 0.04, 0.04, 0.05, 1 })
        ld.t = K.Text(ld, 13, C.text, "CENTER")
        ld.t:SetPoint("CENTER", 0, 26)
        ld.track = ld:CreateTexture(nil, "ARTWORK")
        ld.track:SetSize(220, 4)
        ld.track:SetPoint("CENTER", 0, 0)
        ld.track:SetColorTexture(1, 1, 1, 0.08)
        ld.fill = ld:CreateTexture(nil, "OVERLAY")
        ld.fill:SetHeight(4)
        ld.fill:SetPoint("LEFT", ld.track, "LEFT", 0, 0)
        ld.fill:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 1)
        ld.sub = K.Text(ld, 11, C.dim, "CENTER")
        ld.sub:SetPoint("CENTER", 0, -22)
        ld.shown, ld.goal = 0, 0
        ld:SetScript("OnUpdate", function(self, el)
            -- Balken gleitet zum Ziel; Punkte hinter dem Text wandern
            self.shown = self.shown + (self.goal - self.shown) * math.min(1, el * 8)
            self.fill:SetWidth(math.max(1, 220 * self.shown))
            self.dots = ((self.dots or 0) + el * 3) % 4
            self.t:SetText(L["Durchsuche Dungeon-Beute"] .. string.rep(".", math.floor(self.dots)))
        end)
        ld:Hide()
        f.load = ld
        ns.EscClose("OasisUpgrades")
    end
    function U.Refresh()
        if not (f and f:IsShown()) then return end
        local list, pending, stats = U.Find()
        stats = stats or { total = 0, dungeons = 0 }
        -- Ladeanzeige: bis alles geladen ist, mindestens 0,6 s nach dem Oeffnen, hoechstens 8 s (manche Nummern liefert der Client nie)
        local now = GetTime()
        f.loadStart = f.loadStart or now
        local waited = now - f.loadStart
        local loading = (pending > 0 and waited < 8) or waited < 0.6
        if f.load then
            f.load.goal = stats.total > 0 and ((stats.total - pending) / stats.total) or 1
            f.load.sub:SetText((L["%d von %d Gegenstaenden geladen"]):format(stats.total - pending, stats.total))
            f.load:SetShown(loading)
        end
        local best = {}
        for _, x in ipairs(list) do if not best[x.slot] then best[x.slot] = x end end   -- Liste ist nach Gewinn sortiert
        local n = 0
        for _, r in ipairs(f.rows) do
            local x = best[r.key]
            r.item = x
            if x then
                n = n + 1
                r.icon:SetTexture(x.tex)
                r.icon:SetAlpha(1)
                r.name:SetText(x.link)
                r.gain:SetText("+" .. x.gain)
                r.src:SetText((x.dungeon or "?") .. "  |cff8a8a90·|r  " .. (x.boss or "?"))
                local qr, qg, qb = 0.6, 0.6, 0.6
                if x.q and GetItemQualityColor then local ok, a1, a2, a3 = pcall(GetItemQualityColor, x.q) if ok and a1 then qr, qg, qb = a1, a2, a3 end end
                K.SetBorderColor(r.iconBox, { qr, qg, qb, 0.9 })
                r.edge:SetColorTexture(qr, qg, qb, 0.9)
                r:SetFull(true)
            else
                r.icon:SetTexture(nil)
                r.gain:SetText("")
                r:SetFull(false)
            end
        end
        -- Zeilen untereinander (Karten hoeher), Fensterhoehe passt sich an
        local y = -36
        for _, r in ipairs(f.rows) do
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", f, "TOPLEFT", 8, y)
            r:SetPoint("RIGHT", f, "RIGHT", -8, 0)
            y = y - r:GetHeight()
        end
        f:SetHeight(-y + 62)
        local roleName
        do
            local hs = ns.Insta and ns.Insta.headSoon
            if hs and hs.Role then local ok, _, rn = pcall(hs.Role, hs) if ok and rn then roleName = rn end end
        end
        local lv = UnitLevel("player") or 1
        f.footRole:SetText(K.Upper(L["Bewertet fuer"]) .. "  |cffffffff" .. (roleName or L["deine Klasse"]) .. "|r")
        f.footCount:SetText(loading and ("|cff888888" .. L["Lade Gegenstaende ..."] .. "|r") or (L["%d Upgrades"]):format(n))
        if loading then
            f.foot:SetText((L["Aus Dungeons fuer Level %d-%d  ·  nur was du tragen kannst"]):format(math.max(1, lv - 4), lv + 4))
        elseif n == 0 and stats.nextLvl then
            f.foot:SetText("|cffe8b44a" .. (L["Nichts Besseres fuer deine Stufe - die naechsten Teile gibt es ab Stufe %d."]):format(stats.nextLvl) .. "|r")
        else
            f.foot:SetText((L["%d Gegenstaende aus %d Dungeons geprueft (Level %d-%d)  ·  nur was du tragen kannst"]):format(stats.total, stats.dungeons, math.max(1, lv - 4), lv + 4))
        end
        if loading then ns.After(pending > 0 and 0.5 or 0.2, U.Refresh) end
    end
    function U.Toggle()
        if not f then build() end
        if f:IsShown() then f:Hide() return end
        f.loadStart = nil   -- jedes Oeffnen sucht neu und zeigt die Ladeanzeige
        if f.load then f.load.shown = 0 end
        f:Show()
        U.Refresh()
    end
    ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.After(0.3, U.Refresh) end)
end


------------------------------------------------------------------------
-- Profil-Reiter "Berufe & Ruf"
------------------------------------------------------------------------
do
    local L, K, C = ns.L, ns.K, ns.K.C
    local PR = {}
    ns.ProfRep = PR
    -- Classic-Ausbildungsstufen: Maximalstufe, Name, benoetigtes Level
    local TIERS = { { 75, "Lehrling", 1 }, { 150, "Geselle", 10 }, { 225, "Experte", 20 }, { 300, "Fachmann", 35 } }
    local STAND = { "Hasserfuellt", "Feindselig", "Unfreundlich", "Neutral", "Freundlich", "Wohlwollend", "Respektvoll", "Ehrfuerchtig" }
    local SCOL = { { 0.8, 0.13, 0.13 }, { 0.8, 0.3, 0.13 }, { 0.75, 0.4, 0.15 }, { 0.9, 0.8, 0.2 },
        { 0, 0.6, 0.1 }, { 0, 0.7, 0.3 }, { 0, 0.7, 0.6 }, { 0, 0.8, 0.8 } }

    local function parse(raw)
        local out = {}
        for part in tostring(raw or ""):gmatch("[^+]+") do
            local n, r = part:match("^([^/]+)/(%d+)")
            if n then out[n] = tonumber(r) end
        end
        return out
    end
    -- Gildenvergleich: wer hat den Beruf noch, wer ist am hoechsten
    local function guildFor(name)
        local cnt, best, bestN = 0, 0, nil
        for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
            if not ns.isMe(m.name) then
                local pr = ns.db.members and ns.db.members[m.name]
                local r = parse(pr and pr.profs or (ns.db.guildProfs and ns.db.guildProfs[m.name]))[name]
                if r then
                    cnt = cnt + 1
                    if r > best then best, bestN = r, m.name end
                end
            end
        end
        return cnt, best, bestN
    end

    local function reps()
        local out = {}
        -- neue Schnittstelle (C_Reputation), sonst die alte
        local CR = C_Reputation
        if CR and CR.GetNumFactions and CR.GetFactionDataByIndex then
            local n = CR.GetNumFactions() or 0
            -- eingeklappte Gruppen kurz aufklappen, sonst fehlen deren Fraktionen
            if CR.ExpandAllFactionHeaders then pcall(CR.ExpandAllFactionHeaders) n = CR.GetNumFactions() or n end
            for i = 1, n do
                local ok, f = pcall(CR.GetFactionDataByIndex, i)
                if ok and type(f) == "table" and f.name and (not f.isHeader or f.isHeaderWithRep) then
                    local lo, hi, v = f.currentReactionThreshold or 0, f.nextReactionThreshold or 0, f.currentStanding or 0
                    out[#out + 1] = { name = f.name, st = f.reaction or 4, p = (hi > lo) and (v - lo) / (hi - lo) or 1,
                        cur = v - lo, max = hi - lo }
                end
            end
            if #out > 0 then
                table.sort(out, function(a, b) if a.st ~= b.st then return a.st > b.st end return a.p > b.p end)
                return out
            end
        end
        local n = GetNumFactions and GetNumFactions() or 0
        if ExpandAllFactionHeaders then pcall(ExpandAllFactionHeaders) n = GetNumFactions() or n end
        for i = 1, n do
            local ok, name, _, standing, bMin, bMax, val, _, _, isHeader, _, hasRep = pcall(GetFactionInfo, i)
            if ok and name and (not isHeader or hasRep) and standing and bMin and bMax and val then
                out[#out + 1] = { name = name, st = standing, p = (bMax > bMin) and (val - bMin) / (bMax - bMin) or 1,
                    cur = val - bMin, max = bMax - bMin }
            end
        end
        table.sort(out, function(a, b) if a.st ~= b.st then return a.st > b.st end return a.p > b.p end)
        return out
    end

    -- 0.6.401: Koennen im Stil der Werte-Seite - gerundete Zeilen und Leisten
    local function roundBar(bar, r)
        for _, rg in ipairs({ bar:GetRegions() }) do
            if rg.GetObjectType and rg:GetObjectType() == "Texture" and K.RoundMask then pcall(K.RoundMask, rg, bar, r or 4) end
        end
    end
    local function rowBg(row)
        local t = row:CreateTexture(nil, "BACKGROUND")
        t:SetPoint("TOPLEFT", -8, 6) t:SetPoint("BOTTOMRIGHT", 8, -4)
        t:SetColorTexture(1, 1, 1, 0.03)
        if K.RoundMask then pcall(K.RoundMask, t, row, 8) end
        return t
    end
    function PR.Build(h)
        local left = K.Panel(h, C.panel)
        left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT") left:SetPoint("RIGHT", h, "CENTER", -6, 0)
        local hd = K.GameHead(left, L["Berufe"], C.amber)
        hd:SetPoint("TOPLEFT", 12, -12) hd:SetPoint("RIGHT", -12, 0)
        h.profRows = {}
        for i = 1, 6 do
            local r = CreateFrame("Frame", nil, left)
            r:SetPoint("TOPLEFT", 22, -48 - (i - 1) * 70)
            r:SetPoint("RIGHT", -22, 0)
            r:SetHeight(56)
            r.bgx = rowBg(r)
            -- Symbol im Farbkreis
            r.disc = r:CreateTexture(nil, "BORDER")
            r.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            r.disc:SetSize(34, 34)
            r.disc:SetPoint("LEFT", 0, 0)
            r.disc:SetVertexColor(C.amber[1], C.amber[2], C.amber[3], 0.14)
            r.ico = K.Glyph(r, 18, ns.MEDIA .. "icons\\crafting", C.amber)
            r.ico:SetPoint("CENTER", r.disc, "CENTER")
            r.n = K.Text(r, 13, C.text)
            r.n:SetPoint("TOPLEFT", 46, -2)
            r.v = K.Title(r, 15, C.amber, "RIGHT")
            r.v:SetPoint("TOPRIGHT", 0, -1)
            r.bar = K.Bar(r, 320, 9)
            r.bar:SetPoint("TOPLEFT", 46, -22) r.bar:SetPoint("RIGHT", 0, 0)
            if not K.Gradient(r.bar.fill, "HORIZONTAL", { 0.95, 0.72, 0.38, 1 }, { 1, 0.5, 0.18, 1 }) then r.bar.fill:SetColorTexture(1, 0.6, 0.25, 1) end
            roundBar(r.bar, 4)
            r.hint = K.Text(r, 10, C.dim)
            r.hint:SetPoint("TOPLEFT", 46, -38) r.hint:SetPoint("RIGHT", 0, 0)
            r.hint:SetJustifyH("LEFT")
            r:EnableMouse(true)
            r:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            h.profRows[i] = r
        end
        h.profEmpty = K.Text(left, 11, C.dim)
        h.profEmpty:SetPoint("TOPLEFT", 14, -44)
        h.profEmpty:SetText(L["Noch keine Berufe gelernt."])

        local right = K.Panel(h, C.panel)
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0) right:SetPoint("BOTTOMRIGHT")
        local hr = K.GameHead(right, L["Ruf"], C.accent)
        hr:SetPoint("TOPLEFT", 12, -12) hr:SetPoint("RIGHT", -12, 0)
        h.repList = K.List(right, 42, function(l)
            local r = CreateFrame("Frame", nil, l)
            r.bgx = r:CreateTexture(nil, "BACKGROUND")
            r.bgx:SetPoint("TOPLEFT", -6, 2) r.bgx:SetPoint("BOTTOMRIGHT", 6, 4)
            r.bgx:SetColorTexture(1, 1, 1, 0.03)
            if K.RoundMask then pcall(K.RoundMask, r.bgx, r, 6) end
            r.n = K.Text(r, 12, C.text)
            r.n:SetPoint("TOPLEFT", 4, -4)
            r.s = K.Text(r, 11, C.muted, "RIGHT")
            r.s:SetPoint("TOPRIGHT", -4, -4)
            r.bar = K.Bar(r, 100, 7)
            r.bar:SetPoint("TOPLEFT", 4, -22) r.bar:SetPoint("RIGHT", -4, 0)
            roundBar(r.bar, 3)
            return r
        end, function(r, x)
            r.n:SetText(x.name)
            local c = SCOL[x.st] or C.muted
            r.s:SetText(K.hex(c) .. L[STAND[x.st] or "Neutral"] .. "|r  |cff888888" .. x.cur .. "/" .. x.max .. "|r")
            r.bar.fill:SetColorTexture(c[1], c[2], c[3], 1)
            r.bar:Set(x.p)
        end)
        h.repList:SetPoint("TOPLEFT", 18, -42)
        h.repList:SetPoint("BOTTOMRIGHT", -8, 10)
        h.repList.empty:SetText(L["Noch keine Fraktionen entdeckt."])
    end

    function PR.Show(h)
        if not h.built then h.built = true PR.Build(h) end
        local list = {}
        if ns.Radar and ns.Radar.myProfessions then
            local ok, l = pcall(ns.Radar.myProfessions)
            if ok and type(l) == "table" then list = l end
        end
        local lvl = UnitLevel("player") or 1
        for i, r in ipairs(h.profRows) do
            local x = list[i]
            r:SetShown(x ~= nil)
            if x then
                local rank, max = tonumber(x.rank) or 0, tonumber(x.max) or 0
                r.n:SetText(x.name)
                r.v:SetText(rank .. " / " .. max)
                r.bar:Set(max > 0 and rank / max or 0)
                local hint
                if max > 0 and max < 300 and rank >= max - 5 then
                    local nextT
                    for _, t in ipairs(TIERS) do if t[1] > max then nextT = t break end end
                    if nextT then
                        hint = lvl >= nextT[3] and ("|cffe8b44a" .. (L["Bald am Limit - beim Lehrer %s lernen"]):format(L[nextT[2]]) .. "|r")
                            or (L["Limit erreicht - %s ab Level %d"]):format(L[nextT[2]], nextT[3])
                    end
                end
                local cnt, best, bestN = guildFor(x.name)
                local g = cnt > 0 and (L["Gilde: %d weitere, bester %s (%d)"]):format(cnt, ns.displayName(bestN), best) or L["Niemand sonst in der Gilde"]
                r.hint:SetText(hint and (hint .. "  |cff666666-|r  " .. g) or g)
                local tip = { x.name, (L["Stufe %d von %d"]):format(rank, max),
                    cnt > 0 and (L["%d Gildenmitglieder haben diesen Beruf"]):format(cnt) or L["Niemand sonst in der Gilde"] }
                if cnt > 0 and rank > best then tip[#tip + 1] = "|cff66db9e" .. L["Du bist der beste in der Gilde!"] .. "|r" end
                r.tip = tip
            end
        end
        h.profEmpty:SetShown(#list == 0)
        h.repList:SetData(reps())
    end
end


------------------------------------------------------------------------
-- Profil-Reiter "Chronik": Deine Woche (Spielzeit je Tag) + Meilensteine
------------------------------------------------------------------------
do
    local L, K, C = ns.L, ns.K, ns.K.C
    local CH = {}
    ns.Chron = CH
    local DAYS = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }

    local function dayKey(ts) return date("%Y-%m-%d", ts) end
    -- Spielzeit mitzaehlen: jede Minute +60 s auf den heutigen Tag
    local function tick()
        local c = ns.char
        if not c then return end
        c.play = c.play or {}
        local k = dayKey(time())
        c.play[k] = (c.play[k] or 0) + 60
        -- alte Tage (> 60) aufraeumen
        local cut = dayKey(time() - 60 * 86400)
        for d in pairs(c.play) do if d < cut then c.play[d] = nil end end
    end
    -- weitere Meilensteine (Berufsstufen, erster Start mit Oasis)
    function CH.Add(key, text, icon)
        local c = ns.char
        if not c then return end
        c.chron = c.chron or {}
        if c.chron[key] then return end
        c.chron[key] = { ts = time(), t = text, i = icon }
    end
    local function checkProfs()
        if not (ns.Radar and ns.Radar.myProfessions) then return end
        local ok, list = pcall(ns.Radar.myProfessions)
        if not ok or type(list) ~= "table" then return end
        for _, x in ipairs(list) do
            local r = tonumber(x.rank) or 0
            for _, step in ipairs({ 75, 150, 225, 300 }) do
                if r >= step then CH.Add("prof:" .. x.name .. ":" .. step, { "%s: Stufe %d erreicht", x.name, step }, "Interface\\Icons\\Trade_BlackSmithing") end
            end
        end
    end
    ns.On("PLAYER_ENTERING_WORLD", function()
        if CH.ticker then return end
        CH.ticker = C_Timer.NewTicker(60, tick)
        CH.Add("oasis", { "Mit Oasis unterwegs" }, "Interface\\Icons\\INV_Misc_Gem_Pearl_04")
        C_Timer.After(10, function() pcall(checkProfs) end)
    end)
    ns.On("SKILL_LINES_CHANGED", function() pcall(checkProfs) end)

    -- Schrittlaenge beim Rennen (die Spielfigur rennt ~6,4 m/s -> ca. 4 Schritte pro Sekunde)
    CH.STRIDE = 1.6
    -- gelaufene Strecke (Meter je Tag): jede Sekunde Abstand zur letzten Position, Spruenge (Portale) ignorieren
    local lastX, lastY, lastInst
    C_Timer.NewTicker(1, function()
        local c = ns.char
        if not c or not UnitPosition then return end
        local ok, y, x, _, inst = pcall(UnitPosition, "player")
        if not ok or not x then lastX = nil return end
        if (UnitOnTaxi and UnitOnTaxi("player")) or (IsMounted and IsMounted()) or (UnitInVehicle and UnitInVehicle("player")) or UnitIsDeadOrGhost("player") or inst ~= lastInst or not lastX then
            lastX, lastY, lastInst = x, y, inst
            return
        end
        local d = math.sqrt((x - lastX) ^ 2 + (y - lastY) ^ 2)   -- Yards
        lastX, lastY = x, y
        if d > 0.3 and d < 40 then
            c.walk = c.walk or {}
            local k = dayKey(time())
            local before = c.walk[k] or 0
            c.walk[k] = before + d * 0.9144
            -- Abzeichen: jeder volle Kilometer; Tagesziel 10.000 Schritte (ca. 7,5 km)
            c.walkAcc = (c.walkAcc or 0) + d * 0.9144
            if c.walkAcc >= 1000 and ns.Badges then
                c.walkAcc = c.walkAcc - 1000
                ns.Badges.Add("walkKm", 1)
            end
            if before < 10000 * CH.STRIDE and c.walk[k] >= 10000 * CH.STRIDE and ns.Badges then
                ns.Badges.Add("stepGoal", 1)
                K.Toast(L["Tagesziel erreicht!"], L["10.000 Schritte heute"], C.mint)
            end
            local h = CH.liveH
            if h and h.mini and h.mini[1] and h:IsVisible() then pcall(CH.UpdateWalk, h) end
        end
    end)
    -- Schritte/km in den Kacheln (auch live aus dem Sekunden-Takt)
    function CH.UpdateWalk(h)
        local c = ns.char or {}
        local walk = c.walk or {}
        local now = time()
        local wd = (tonumber(date("%w", now)) + 6) % 7
        local today = walk[dayKey(now)] or 0
        local wk = 0
        for i = 0, wd do wk = wk + (walk[dayKey(now - i * 86400)] or 0) end
        local function steps(m) local n = math.floor(m / CH.STRIDE) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
        h.mini[1].v:SetText(steps(today) .. "  |cff888888" .. ("%.1f"):format(today / 1000) .. " km|r")
        h.mini[2].v:SetText(steps(wk) .. "  |cff888888" .. ("%.1f"):format(wk / 1000) .. " km|r")
        if h.rings then
            local sT, sW = math.floor(today / CH.STRIDE), math.floor(wk / CH.STRIDE)
            local days = 0
            local play = c.play or {}
            for i = 0, wd do if (play[dayKey(now - i * 86400)] or 0) > 0 then days = days + 1 end end
            local R = h.ringCol
            local function hx(c2, s) return ("|cff%02x%02x%02x%s|r"):format(c2[1] * 255, c2[2] * 255, c2[3] * 255, s) end
            h.ringTxt[1]:SetText(hx(R[1], steps(today) .. "/10.000") .. " |cff888888" .. K.Upper(L["Schritte heute"]) .. "  " .. ("%.1f"):format(today / 1000) .. " km|r")
            h.ringTxt[2]:SetText(hx(R[2], steps(wk) .. "/70.000") .. " |cff888888" .. K.Upper(L["Schritte Woche"]) .. "  " .. ("%.1f"):format(wk / 1000) .. " km|r")
            h.ringTxt[3]:SetText(hx(R[3], days .. "/7") .. " |cff888888" .. K.Upper(L["Aktive Tage"]) .. "|r")
            local first = not h.ringsShown
            h.ringsShown = true
            h.rings:Set({ sT / 10000, sW / 70000, days / 7 }, first)
        end
    end

    local function fmtH(sec)
        local m = math.floor((sec or 0) / 60)
        if m < 60 then return m .. " min" end
        return ("%d:%02d h"):format(math.floor(m / 60), m % 60)
    end

    local MONTHS = { "Januar", "Februar", "Maerz", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" }
    -- eigene Symbole je Art (nur Oasis-Texturen bzw. bewaehrte)
    local KIND = {
        level = { ns.MEDIA .. "icons\\badges\\quester", C.amber, "Level" },
        level10 = { ns.MEDIA .. "icons\\badges\\first10", C.amber, "Level" },
        prof = { ns.MEDIA .. "icons\\crafting", C.blue, "Beruf" },
        oasis = { ns.MEDIA .. "logo64", C.accent, "Oasis" },
        badge = { ns.MEDIA .. "icons\\badges", C.violet or C.blue, "Abzeichen" },
        boss = { ns.MEDIA .. "icons\\dungeons", C.red, "Boss" },
        loot = { ns.MEDIA .. "icons\\raid", C.mint, "Beute" },
        legacy = { ns.MEDIA .. "icons\\legacy", C.amber, "Legacy" },
        dr = { ns.MEDIA .. "icons\\deathroll", C.pink, "Deathroll" },
        other = { ns.MEDIA .. "icons\\chronicle", C.muted, "Ereignis" },
    }
    local function tile(parent, label, color)
        local t = CreateFrame("Frame", nil, parent)
        t:SetHeight(46)
        t.bg = K.Fill(t, C.raised)
        t.top = t:CreateTexture(nil, "ARTWORK")
        t.top:SetPoint("TOPLEFT") t.top:SetPoint("TOPRIGHT") t.top:SetHeight(2)
        t.top:SetColorTexture(color[1], color[2], color[3], 0.9)
        t.v = K.Title(t, 14, C.text)
        t.v:SetPoint("RIGHT", t, "RIGHT", -6, 0)
        t.v:SetWordWrap(false)
        t.v:SetPoint("TOPLEFT", 10, -8)
        t.l = K.Text(t, 9, C.muted)
        t.l:SetPoint("BOTTOMLEFT", 10, 7)
        t.l:SetText(K.Upper(L[label]))
        return t
    end

    function CH.Build(h)
        local left = K.Panel(h, C.panel)
        left:SetPoint("TOPLEFT") left:SetPoint("BOTTOMLEFT") left:SetWidth(370)
        local hd = K.GameHead(left, L["Deine Woche"], C.accent)
        hd:SetPoint("TOPLEFT", 12, -12) hd:SetPoint("RIGHT", -12, 0)
        h.range = K.Text(left, 10, C.dim, "RIGHT")
        h.range:SetPoint("TOPRIGHT", -12, -15)
        h.sum = K.Title(left, 24, C.text)
        h.sum:SetPoint("TOPLEFT", 12, -40)
        h.delta = K.Text(left, 11, C.mint)
        h.delta:SetPoint("BOTTOMLEFT", h.sum, "BOTTOMRIGHT", 10, 4)
        h.sumL = K.Text(left, 10, C.dim)
        h.sumL:SetPoint("TOPLEFT", 12, -68)
        -- Kennzahlen
        h.tiles = { tile(left, "Schnitt pro Tag", C.blue), tile(left, "Bester Tag", C.amber), tile(left, "Serie", C.mint) }
        for i, t in ipairs(h.tiles) do
            t:SetPoint("TOPLEFT", 12 + (i - 1) * 117, -88)
            t:SetWidth(111)
            t:SetHeight(42)
        end
        -- Balken je Tag (Verlauf), Schnitt als Linie
        h.bars = {}
        local chartTop, chartH = -152, 40   -- Platz ueber dem Diagramm fuer die Stunden-Zahl am hoechsten Balken
        h.chartH = chartH
        for i = 1, 7 do
            local b = CreateFrame("Frame", nil, left)
            b:SetSize(30, chartH)
            b:SetPoint("TOPLEFT", 16 + (i - 1) * 40, chartTop)
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            b.bg:SetColorTexture(1, 1, 1, 0.035)
            b.fill = b:CreateTexture(nil, "ARTWORK")
            b.fill:SetPoint("BOTTOMLEFT") b.fill:SetPoint("BOTTOMRIGHT")
            if not K.Gradient(b.fill, "VERTICAL", { C.accent[1] * 0.45, C.accent[2] * 0.45, C.accent[3] * 0.45, 0.9 }, { C.accent[1], C.accent[2], C.accent[3], 1 }) then
                b.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.85)
            end
            b.cap = b:CreateTexture(nil, "OVERLAY")
            b.cap:SetHeight(2)
            b.cap:SetPoint("BOTTOMLEFT", b.fill, "TOPLEFT") b.cap:SetPoint("BOTTOMRIGHT", b.fill, "TOPRIGHT")
            b.cap:SetColorTexture(1, 1, 1, 0.5)
            b.day = K.Text(b, 11, C.muted, "CENTER")
            b.day:SetPoint("TOP", b, "BOTTOM", 0, -4)
            b.val = K.Text(b, 9, C.dim, "CENTER")
            b.val:SetPoint("BOTTOM", b.fill, "TOP", 0, 3)
            b.today = b:CreateTexture(nil, "OVERLAY")
            b.today:SetPoint("TOPLEFT", b.day, "BOTTOMLEFT", 4, -2) b.today:SetPoint("TOPRIGHT", b.day, "BOTTOMRIGHT", -4, -2)
            b.today:SetHeight(2)
            b.today:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            b:EnableMouse(true)
            b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(1, 1, 1, 0.07) if self.tip then K.ShowTip(self, self.tip) end end)
            b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.035) GameTooltip:Hide() end)
            h.bars[i] = b
        end
        h.avg = left:CreateTexture(nil, "OVERLAY")
        h.avg:SetHeight(1)
        h.avg:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 0.7)
        h.avgL = K.Text(left, 9, C.amber, "LEFT")
        h.avgL:SetSpacing(1)
        -- letzte 4 Wochen
        local h4 = K.Text(left, 10, C.dim)
        h4:SetPoint("TOPLEFT", 12, chartTop - chartH - 30)
        h4:SetText(K.Upper(L["Letzte 4 Wochen"]))
        h.weeks = {}
        for i = 1, 4 do
            local w = CreateFrame("Frame", nil, left)
            w:SetSize(80, 24)
            w:SetPoint("TOPLEFT", 12 + (i - 1) * 88, chartTop - chartH - 44)
            w.track = w:CreateTexture(nil, "BACKGROUND")
            w.track:SetPoint("BOTTOMLEFT") w.track:SetPoint("BOTTOMRIGHT") w.track:SetHeight(4)
            w.track:SetColorTexture(1, 1, 1, 0.06)
            w.fill = w:CreateTexture(nil, "ARTWORK")
            w.fill:SetPoint("BOTTOMLEFT") w.fill:SetHeight(4)
            w.v = K.Text(w, 12, C.text)
            w.v:SetPoint("TOPLEFT", 0, 0)
            w.l = K.Text(w, 9, C.dim, "RIGHT")
            w.l:SetPoint("TOPRIGHT", 0, -2)
            h.weeks[i] = w
        end
        h.walkHead = K.Text(left, 10, C.dim)
        -- feste Reihenfolge von oben (nicht vom unteren Rand aus, sonst ueberlappt es bei kleinem Fenster)
        local wy = chartTop - chartH - 80
        h.walkHead:SetPoint("TOPLEFT", 12, wy)
        h.walkHead:SetText(K.Upper(L["Zu Fuss unterwegs"]))
        h.walk = K.Title(left, 13, C.text)
        h.walk:SetPoint("TOPLEFT", 12, wy - 15)
        h.walk:SetPoint("RIGHT", -12, 0)
        h.walk:SetWordWrap(false)
        h.stats = K.Text(left, 11, C.muted)
        h.stats:SetPoint("TOPLEFT", 12, wy - 33)
        h.stats:SetPoint("RIGHT", -12, 0)
        h.stats:SetJustifyH("LEFT")
        h.stats:SetSpacing(4)
        h.walkHead:Hide() h.walk:Hide() h.stats:Hide()

        -- kleine Kennzahl-Kachel (Wert gross, Beschriftung klein, farbige Kante)
        local function mini(parent, x, y, w, color, label)
            local m = CreateFrame("Frame", nil, parent)
            m:SetSize(w, 38)
            m:SetPoint("TOPLEFT", x, y)
            m.bg = K.Fill(m, C.raised)
            m.edge = m:CreateTexture(nil, "ARTWORK")
            m.edge:SetPoint("TOPLEFT") m.edge:SetPoint("BOTTOMLEFT") m.edge:SetWidth(2)
            m.edge:SetColorTexture(color[1], color[2], color[3], 1)
            m.v = K.Title(m, 13, C.text)
            m.v:SetPoint("TOPLEFT", 10, -5)
            m.v:SetPoint("RIGHT", -6, 0)
            m.v:SetWordWrap(false)
            m.l = K.Text(m, 9, C.muted)
            m.l:SetPoint("BOTTOMLEFT", 10, 5)
            m.l:SetPoint("RIGHT", -6, 0)
            m.l:SetWordWrap(false)
            m.l:SetText(K.Upper(L[label]))
            m:EnableMouse(true)
            m:SetScript("OnEnter", function(self) self.bg:SetColorTexture(C.raised[1] + 0.04, C.raised[2] + 0.04, C.raised[3] + 0.04, 1) if self.tip then K.ShowTip(self, self.tip) end end)
            m:SetScript("OnLeave", function(self) self.bg:SetColorTexture(C.raised[1], C.raised[2], C.raised[3], C.raised[4] or 1) GameTooltip:Hide() end)
            return m
        end
        h.mini = {}
        h.mini[3] = mini(left, 12, wy + 4, 170, C.amber, "Aktive Tage")
        h.mini[4] = mini(left, 188, wy + 4, 170, C.accent, "Level-Ups diese Woche")

        -- rechts: Zeitleiste mit Monaten
        local right = K.Panel(h, C.panel)
        right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0) right:SetPoint("BOTTOMRIGHT")
        local hw = K.GameHead(right, L["Zu Fuss unterwegs"], C.mint)
        hw:SetPoint("TOPLEFT", 12, -12) hw:SetPoint("RIGHT", -12, 0)
        -- Smartwatch-Ringe: aussen Schritte heute (10.000), Mitte Schritte Woche (70.000), innen aktive Tage (7)
        h.walkBox = CreateFrame("Frame", nil, right)
        h.walkBox:SetPoint("TOPLEFT", 12, -38) h.walkBox:SetPoint("TOPRIGHT", -12, -38) h.walkBox:SetHeight(72)
        h.ringCol = { { 1, 0.20, 0.36 }, { 0.62, 1, 0.12 }, { 0.10, 0.85, 1 } }
        h.rings = K.ActivityRings(h.walkBox, 70, h.ringCol)
        h.rings:SetPoint("LEFT", 2, 0)
        h.ringTxt = {}
        for i = 1, 3 do
            local fs = K.Text(h.walkBox, 12, C.text, nil, K.FONT_HEAD)
            fs:SetPoint("TOPLEFT", 86, -6 - (i - 1) * 20)
            fs:SetPoint("RIGHT", 0, 0)
            fs:SetWordWrap(false)
            h.ringTxt[i] = fs
        end
        -- alte Kacheln bleiben als unsichtbare Platzhalter (Werte-Code schreibt weiter hinein)
        h.mini[1] = mini(h.walkBox, 0, 0, 10, C.mint, "Schritte heute") h.mini[1]:Hide()
        h.mini[2] = mini(h.walkBox, 0, 0, 10, C.blue, "Schritte Woche") h.mini[2]:Hide()
        -- Meilensteine: kleiner, ruhiger
        local hr = K.Text(right, 10, C.dim)
        hr:SetPoint("TOPLEFT", 12, -126)
        hr:SetText(K.Upper(L["Meilensteine"]))
        h.count = K.Text(right, 10, C.dim, "RIGHT")
        h.count:SetPoint("TOPRIGHT", -12, -126)
        local sepM = right:CreateTexture(nil, "ARTWORK")
        sepM:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
        sepM:SetHeight(1)
        sepM:SetPoint("TOPLEFT", 12, -118) sepM:SetPoint("TOPRIGHT", -12, -118)
        h.line = right:CreateTexture(nil, "BACKGROUND")
        h.line:SetColorTexture(1, 1, 1, 0.05)
        h.line:SetWidth(1)
        h.line:SetPoint("TOPLEFT", 25, -144)
        h.line:SetPoint("BOTTOMLEFT", 25, 10)
        h.list = K.List(right, 36, function(l)
            local r = CreateFrame("Frame", nil, l)
            r.month = K.Text(r, 10, C.dim)
            r.month:SetPoint("LEFT", 36, 0)
            r.dot = r:CreateTexture(nil, "ARTWORK")
            r.dot:SetTexture(ns.MEDIA .. "dot")
            r.dot:SetSize(22, 22)
            r.dot:SetPoint("LEFT", 2, 0)
            r.ic = r:CreateTexture(nil, "OVERLAY")
            r.ic:SetSize(12, 12)
            r.ic:SetPoint("CENTER", r.dot, "CENTER")
            r.t = K.Text(r, 11, { 0.85, 0.85, 0.88, 1 })
            r.t:SetPoint("TOPLEFT", 36, -4)
            r.t:SetPoint("RIGHT", -10, 0)
            r.t:SetWordWrap(false)
            r.d = K.Text(r, 9, C.dim)
            r.d:SetPoint("TOPLEFT", r.t, "BOTTOMLEFT", 0, -2)
            r.tag = K.Text(r, 9, C.muted, "RIGHT")
            r.tag:SetPoint("TOP", r.d, "TOP", 0, 0)
            r.tag:SetPoint("RIGHT", r, "RIGHT", -10, 0)
            return r
        end, function(r, x)
            if x.month then
                r.month:SetText(K.Upper(x.month))
                r.month:Show()
                r.dot:Hide() r.ic:Hide() r.t:Hide() r.d:Hide() r.tag:Hide()
                return
            end
            r.month:Hide()
            r.dot:Show() r.ic:Show() r.t:Show() r.d:Show() r.tag:Show()
            local k = KIND[x.kind] or KIND.other
            r.dot:SetVertexColor(k[2][1] * 0.22, k[2][2] * 0.22, k[2][3] * 0.22)
            r.ic:SetTexture(k[1])
            r.ic:SetVertexColor(k[2][1], k[2][2], k[2][3])
            if x.kind == "oasis" then r.ic:SetVertexColor(1, 1, 1) end
            r.t:SetText(x.text)
            r.d:SetText(date("%d.%m.%Y  %H:%M", x.ts) .. "  ·  " .. ns.ago(x.ts))
            r.tag:SetText(K.hex({ k[2][1] * 0.75, k[2][2] * 0.75, k[2][3] * 0.75 }) .. K.Upper(L[k[3]]) .. "|r")
        end)
        h.list:SetPoint("TOPLEFT", 12, -138)
        h.list:SetPoint("BOTTOMRIGHT", -8, 10)
        h.list.empty:SetText(L["Noch keine Meilensteine. Level auf, lern Berufe - hier entsteht deine Geschichte."])
    end

    function CH.Show(h)
        if not h.built then h.built = true CH.Build(h) end
        local c = ns.char or {}
        local play = c.play or {}
        local now = time()
        local wd = (tonumber(date("%w", now)) + 6) % 7   -- 0 = Montag
        local total, maxV, days, best, bestD = 0, 1, 0, 0, nil
        local vals = {}
        for i = 1, 7 do
            local ts = now - (wd - (i - 1)) * 86400
            local v = (i - 1 <= wd) and (play[dayKey(ts)] or 0) or 0
            vals[i] = { v = v, ts = ts, future = i - 1 > wd }
            total = total + v
            if v > maxV then maxV = v end
            if v > 0 then days = days + 1 end
            if v > best then best, bestD = v, i end
        end
        local function weekTotal(back)
            local s = 0
            for i = 0, 6 do s = s + (play[dayKey(now - (wd + 7 * back - i) * 86400)] or 0) end
            return s
        end
        local last = weekTotal(1)
        h.range:SetText(date("%d.%m.", vals[1].ts) .. " - " .. date("%d.%m.", vals[7].ts))
        h.sum:SetText(fmtH(total))
        local diff = total - last
        if last > 0 then
            h.delta:SetText((diff >= 0 and "|cff66db9e+" or "|cffe64040-") .. fmtH(math.abs(diff)) .. "|r  |cff777777" .. L["zur Vorwoche"] .. "|r")
        else
            h.delta:SetText("")
        end
        h.sumL:SetText(L["gespielt diese Woche (mit Oasis gemessen)"])
        -- Serie: Tage am Stueck bis heute (oder gestern)
        local streak, d = 0, 0
        if (play[dayKey(now)] or 0) == 0 then d = 1 end
        while (play[dayKey(now - d * 86400)] or 0) > 0 and streak < 60 do streak = streak + 1 d = d + 1 end
        h.tiles[1].v:SetText(days > 0 and fmtH(total / days) or "-")
        h.tiles[2].v:SetText(bestD and (L[DAYS[bestD]] .. " |cff888888" .. fmtH(best) .. "|r") or "-")
        h.tiles[3].v:SetText(streak > 0 and ((L["%d Tage"]):format(streak)) or "-")
        -- Balken + Schnittlinie
        local avg = days > 0 and total / days or 0
        for i, b in ipairs(h.bars) do
            local x = vals[i]
            local hgt = math.max(1, (h.chartH - 2) * x.v / maxV)
            b.fill:SetHeight(hgt)
            b.fill:SetShown(x.v > 0)
            b.cap:SetShown(x.v > 0)
            b.fill:SetAlpha(i - 1 == wd and 1 or 0.75)
            b.day:SetText(L[DAYS[i]])
            local dc = (i - 1 == wd) and C.text or (x.future and C.dim or C.muted)
            b.day:SetTextColor(dc[1], dc[2], dc[3])
            b.today:SetShown(i - 1 == wd)
            b.val:SetText(x.v > 0 and fmtH(x.v) or "")
            b.tip = { (ns.weekday and ns.weekday(x.ts) or "") .. date("  %d.%m.%Y", x.ts), x.future and L["noch nicht"] or fmtH(x.v) }
        end
        if avg > 0 then
            local y = (h.chartH - 2) * avg / maxV
            h.avg:ClearAllPoints()
            h.avg:SetPoint("BOTTOMLEFT", h.bars[1], "BOTTOMLEFT", -4, y)
            h.avg:SetPoint("BOTTOMRIGHT", h.bars[7], "BOTTOMRIGHT", 6, y)
            h.avgL:ClearAllPoints()
            h.avgL:SetPoint("LEFT", h.avg, "RIGHT", 6, 0)
            h.avgL:SetText(L["Schnitt"] .. "\n" .. fmtH(avg))
            h.avg:Show() h.avgL:Show()
        else
            h.avg:Hide() h.avgL:Hide()
        end
        -- letzte 4 Wochen (diese zuerst)
        local wk, wmax = {}, 1
        for i = 1, 4 do wk[i] = weekTotal(i - 1) if wk[i] > wmax then wmax = wk[i] end end
        for i, w in ipairs(h.weeks) do
            w.v:SetText(wk[i] > 0 and fmtH(wk[i]) or "-")
            w.l:SetText(i == 1 and L["diese"] or (L["vor %d"]):format(i - 1))
            local col = i == 1 and C.accent or C.muted
            w.fill:SetColorTexture(col[1], col[2], col[3], 0.9)
            w.fill:SetWidth(math.max(1, 80 * wk[i] / wmax))
        end
        -- Level diese Woche
        local weekStart = now - wd * 86400 - (tonumber(date("%H", now)) * 3600 + tonumber(date("%M", now)) * 60)
        local lv = 0
        for _, ts in pairs(c.milestones or {}) do if tonumber(ts) and tonumber(ts) >= weekStart then lv = lv + 1 end end
        h.stats:SetText((L["Aktive Tage: %d von 7"]):format(days) .. "    ·    " .. (L["Level-Ups diese Woche: %d"]):format(lv))
        if h.mini and h.mini[3] then
            h.mini[3].v:SetText(days .. " |cff888888/ 7|r")
            h.mini[4].v:SetText(tostring(lv))
        end
        -- Schritte (ca. 0,75 m pro Schritt) und Kilometer: heute / diese Woche
        local walk = c.walk or {}
        local today = walk[dayKey(now)] or 0
        local wk = 0
        for i = 0, wd do wk = wk + (walk[dayKey(now - i * 86400)] or 0) end
        local function steps(m) local n = math.floor(m / CH.STRIDE) return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n) end
        CH.liveH = h
        if h.mini and h.mini[1] then CH.UpdateWalk(h) end
        h.walk:SetText((L["Heute %s Schritte"]):format(steps(today)) .. "  |cff888888(" .. ("%.1f"):format(today / 1000) .. " km)|r     "
            .. (L["Woche %s Schritte"]):format(steps(wk)) .. "  |cff888888(" .. ("%.1f"):format(wk / 1000) .. " km)|r")

        -- Zeitleiste: Level, Berufe, Oasis + eigene Chronik-Eintraege (Abzeichen, Bosse, Beute, Legacy, Deathroll)
        local items = {}
        for lvl, ts in pairs(c.milestones or {}) do
            local n = tonumber(lvl)
            if n and tonumber(ts) then
                items[#items + 1] = { ts = tonumber(ts), text = (L["Level %d erreicht"]):format(n), kind = (n % 10 == 0) and "level10" or "level" }
            end
        end
        for key, m in pairs(c.chron or {}) do
            local t = m.t
            local text = type(t) == "table" and (L[t[1]]):format(select(2, unpack(t))) or tostring(t)
            items[#items + 1] = { ts = m.ts, text = text, kind = tostring(key):find("^prof:") and "prof" or (key == "oasis" and "oasis" or "other") }
        end
        if ns.Store and ns.Chronicle and ns.Chronicle.Text then
            for _, e in ipairs(ns.Store.List("chronicle", function(r) return r.who and ns.isMe(r.who) end)) do
                local kind = e.kind
                if kind ~= "level" and kind ~= "guild" then
                    local ok, txt = pcall(ns.Chronicle.Text, e)
                    if ok and txt and txt ~= "" then
                        local item = ns.Chronicle.Item and select(2, pcall(ns.Chronicle.Item, e))
                        items[#items + 1] = { ts = e.ts or 0, text = (txt:gsub(":$", "")) .. (type(item) == "string" and (" " .. item) or ""),
                            kind = KIND[kind] and kind or (tostring(kind):find("^dr") and "dr" or "other") }
                    end
                end
            end
        end
        table.sort(items, function(a, b) return a.ts > b.ts end)
        -- Monats-Ueberschriften einfuegen
        local out, lastM = {}, nil
        for _, x in ipairs(items) do
            local m = date("%Y-%m", x.ts)
            if m ~= lastM then
                out[#out + 1] = { month = L[MONTHS[tonumber(date("%m", x.ts))]] .. " " .. date("%Y", x.ts) }
                lastM = m
            end
            out[#out + 1] = x
        end
        h.count:SetText(#items > 0 and (L["%d Eintraege"]):format(#items) or "")
        h.list:SetData(out)
    end
end


------------------------------------------------------------------------
-- Visitenkarte (Titel, Status, Lieblings-Emojis), Vitrinen-Abzeichen neben dem Namen,
-- Gildenvergleich der Charakterwerte
------------------------------------------------------------------------
do
    local L, K, C = ns.L, ns.K, ns.K.C
    local Card = {}
    ns.Card = Card

    local function mine()
        local c = ns.char
        if not c then return {} end
        c.card = c.card or {}
        return c.card
    end
    -- Daten eines Spielers (eigene aus ns.char, fremde aus dem geteilten Profil)
    function Card.Of(name)
        if not name then return {} end
        if ns.isMe(name) then
            local m = mine()
            return { t = m.t, s = m.s, e = m.e, sb = m.sb }
        end
        local p = ns.db.members and ns.db.members[name]
        if not p and ns.Radar and ns.Radar.AliasOf then
            local a = ns.Radar.AliasOf(name)
            p = a and ns.db.members[a]
        end
        if not p then return {} end
        return { t = p.ct, s = p.cs, e = p.ce, sb = p.sb }
    end

    -- Vitrine: bis zu 3 Abzeichen; ohne Auswahl die drei hoechsten
    function Card.Showcase(name)
        local d = Card.Of(name)
        local ids = {}
        if d.sb and d.sb ~= "" then
            for id in tostring(d.sb):gmatch("[^,]+") do ids[#ids + 1] = id end
        end
        return ids
    end
    function Card.NameBadges(name, size)
        if not ns.Badges then return "" end
        local ids = Card.Showcase(name)
        if #ids == 0 then return "" end
        local have = ns.Badges.Of(name)
        local t = {}
        size = size or 12
        for _, id in ipairs(ids) do
            local b, tier = ns.Badges.byId[id], have[id]
            if b and tier then
                local c = ns.Badges.Color(tier)
                t[#t + 1] = ("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(b.icon, size, size,
                    math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
            end
        end
        return #t > 0 and (" " .. table.concat(t, "")) or ""
    end

    -- eigene Charakterwerte merken (Rohzahlen) -> werden im Profil geteilt
    function Card.Record(st)
        local c = ns.char
        if not c or type(st) ~= "table" then return end
        local out = {}
        for _, x in ipairs(st) do
            if x.key and type(x[2]) == "string" then
                local raw = x[2]:gsub("[^%d%.,]", "")
                if raw:match("^%d+[%.,]%d%d%d") then raw = raw:gsub("[%.,]", "") else raw = raw:gsub(",", ".") end
                local v = tonumber(raw)
                if v then out[#out + 1] = x.key .. ":" .. v end
            end
        end
        c.statStr = table.concat(out, ",")
    end
    local function decode(s)
        local t = {}
        for k, v in tostring(s or ""):gmatch("([%w_]+):([%d%.]+)") do t[k] = tonumber(v) end
        return t
    end
    -- Gildenschnitt fuer einen Wert: gleiche Klasse, Level +-3
    function Card.GuildAvg(key)
        local R = ns.Radar
        if not (R and R.roster and key) then return end
        local myCls = select(2, UnitClass("player"))
        local lvl = UnitLevel("player") or 1
        local sum, n = 0, 0
        for _, m in ipairs(R.roster) do
            if not ns.isMe(m.name) and m.class == myCls and math.abs((m.level or 0) - lvl) <= 3 then
                local p = ns.db.members[m.name] or (m.aname and ns.db.members[m.aname])
                local v = p and decode(p.cst)[key]
                if v then sum, n = sum + v, n + 1 end
            end
        end
        if n == 0 then return end
        return sum / n, n
    end

    -- im Profil teilen
    local base = IG.ProfileFields
    IG.ProfileFields = function(p)
        base(p)
        local m = mine()
        if m.t and m.t ~= "" then p.ct = m.t:sub(1, 24) end
        if m.s and m.s ~= "" then p.cs = m.s:sub(1, 60) end
        if m.e and m.e ~= "" then p.ce = m.e:sub(1, 40) end
        if m.sb and m.sb ~= "" then p.sb = m.sb end
        if ns.char and ns.char.statStr and ns.char.statStr ~= "" then p.cst = ns.char.statStr end
    end

    -- Bearbeiten-Dialog
    local dlg
    local function build()
        local f = CreateFrame("Frame", "OasisCardEdit", UIParent)
        f:SetSize(420, 330)
        f:SetPoint("CENTER")
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        K.Fill(f, C.bg)
        K.Border(f, C.line)
        ns.EscClose("OasisCardEdit")
        local hd = K.GameHead(f, L["Visitenkarte"], C.accent)
        hd:SetPoint("TOPLEFT", 14, -14) hd:SetPoint("RIGHT", -40, 0)
        local close = K.CloseButton(f, function() f:Hide() end, L["Schliessen (Esc)"])
        close:SetPoint("TOPRIGHT", -8, -8)
        local function field(label, y, maxL, ph)
            local l = K.Text(f, 11, C.muted)
            l:SetPoint("TOPLEFT", 16, y)
            l:SetText(label)
            local e = K.Input(f, 388, ph)
            e:SetPoint("TOPLEFT", 16, y - 16)
            e:SetMaxLetters(maxL)
            return e
        end
        f.t = field(L["Titel"], -44, 24, L["z.B. Der Unaufhaltsame"])
        f.s = field(L["Status"], -94, 60, L["z.B. Suche Gruppe fuer Uldaman"])
        f.e = field(L["Lieblings-Emojis"], -144, 40, L["z.B. :) <3 xD"])
        if ns.Emoji and ns.Emoji.AttachHotkey then ns.Emoji.AttachHotkey(f.e, function() return f.e end) end
        local bl = K.Text(f, 11, C.muted)
        bl:SetPoint("TOPLEFT", 16, -196)
        bl:SetText(L["Vitrine: bis zu 3 Abzeichen neben deinem Namen (anklicken)"])
        f.badges = {}
        f.sel = {}
        local save = K.Button(f, L["Speichern"], 110, 26, "primary", function()
            local m = mine()
            m.t, m.s, m.e = f.t:GetText(), f.s:GetText(), f.e:GetText()
            local sb = {}
            for _, id in ipairs(f.sel) do sb[#sb + 1] = id end
            m.sb = table.concat(sb, ",")
            f:Hide()
            if ns.Radar and ns.Radar.SendHello then pcall(ns.Radar.SendHello) end
            ns.RefreshPage("insta")
            ns.RefreshPage("chat")
        end)
        save:SetPoint("BOTTOMRIGHT", -14, 14)
        return f
    end
    local function fillBadges(f)
        for _, b in ipairs(f.badges) do b:Hide() end
        local list = {}
        for id, tier in pairs(ns.Badges and ns.Badges.Mine(true) or {}) do
            if ns.Badges.byId[id] then list[#list + 1] = { id = id, tier = tier } end
        end
        table.sort(list, function(a, b) if a.tier ~= b.tier then return a.tier > b.tier end return a.id < b.id end)
        local function paint()
            for _, b in ipairs(f.badges) do
                local on = tContains(f.sel, b.id)
                b.icon:SetDesaturated(not on)
                b.icon:SetAlpha(on and 1 or 0.45)
                K.SetBorderColor(b, on and C.accent or C.line)
            end
        end
        for i, x in ipairs(list) do
            if i > 20 then break end
            local b = f.badges[i]
            if not b then
                b = CreateFrame("Button", nil, f)
                b:SetSize(32, 32)
                b:SetPoint("TOPLEFT", 16 + ((i - 1) % 10) * 38, -214 - math.floor((i - 1) / 10) * 38)
                b.icon = b:CreateTexture(nil, "ARTWORK")
                b.icon:SetPoint("TOPLEFT", 2, -2) b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
                K.Border(b, C.line)
                b:SetScript("OnEnter", function(self) K.ShowTip(self, { ns.Badges.Label(self.id, self.tier) }) end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                f.badges[i] = b
            end
            b.id, b.tier = x.id, x.tier
            local bd = ns.Badges.byId[x.id]
            b.icon:SetTexture(bd.icon)
            local c = ns.Badges.Color(x.tier)
            b.icon:SetVertexColor(c[1], c[2], c[3])
            b:SetScript("OnClick", function(self)
                for j, id in ipairs(f.sel) do if id == self.id then table.remove(f.sel, j) paint() return end end
                if #f.sel >= 3 then table.remove(f.sel, 1) end
                f.sel[#f.sel + 1] = self.id
                paint()
            end)
            b:Show()
        end
        paint()
    end
    function Card.Edit()
        dlg = dlg or build()
        local m = mine()
        dlg.t:SetText(m.t or "")
        dlg.s:SetText(m.s or "")
        dlg.e:SetText(m.e or "")
        wipe(dlg.sel)
        for id in tostring(m.sb or ""):gmatch("[^,]+") do dlg.sel[#dlg.sel + 1] = id end
        fillBadges(dlg)
        dlg:Show()
    end

    -- Anzeige in der Profilkarte (Titel, Status, Emojis, Vitrine)
    local function render(txt)
        if ns.Emoji and ns.Emoji.Render then
            local ok, r = pcall(ns.Emoji.Render, txt)
            if ok and r then return r end
        end
        return txt
    end
    C_Timer.After(0, function()
        if not (ns.Profile and ns.Profile.Show) then return end
        hooksecurefunc(ns.Profile, "Show", function(name)
            local f = _G.OasisProfileCard
            if not f or not name then return end
            local d = Card.Of(name)
            local nm = f.name:GetText() or ""
            f.name:SetText(nm .. Card.NameBadges(name, 16))
            if not f.cardLine then
                f.cardLine = K.Text(f, 11, C.text)
                f.cardLine:SetPoint("LEFT", f.pill, "RIGHT", 10, 0)
                f.cardLine:SetPoint("RIGHT", f, "RIGHT", -18, 0)
                f.cardLine:SetJustifyH("LEFT")
                f.cardLine:SetWordWrap(false)
            end
            local parts = {}
            if d.t and d.t ~= "" then parts[#parts + 1] = "|cffe8b44a" .. d.t .. "|r" end
            if d.s and d.s ~= "" then parts[#parts + 1] = "|cffcccccc\"" .. d.s .. "\"|r" end
            if d.e and d.e ~= "" then parts[#parts + 1] = render(d.e) end
            f.cardLine:SetText(table.concat(parts, "  "))
        end)
    end)
end


------------------------------------------------------------------------
-- Einblicke rechts neben den Charakterwerten: Treffer-Ziel, Level-Tempo, Upgrade-Tipp, Verbrauchsgueter
------------------------------------------------------------------------
do
    local L, K, C = ns.L, ns.K, ns.K.C
    local IN = {}
    ns.Insights = IN

    -- Level-Tempo: XP dieser Sitzung mitschreiben
    local sess = { t0 = nil, xp = 0, last = nil, lastMax = nil }
    local function xpTick()
        local cur, max = UnitXP("player"), UnitXPMax("player")
        if not sess.t0 then sess.t0, sess.last, sess.lastMax = GetTime(), cur, max return end
        local d = cur - (sess.last or cur)
        if d < 0 then d = d + (sess.lastMax or 0) end   -- Levelaufstieg
        if d > 0 then sess.xp = sess.xp + d end
        sess.last, sess.lastMax = cur, max
    end
    ns.On("PLAYER_XP_UPDATE", xpTick)
    ns.Listen("LOGIN", function() ns.After(2, xpTick) end)
    local function fmtTime(sec)
        local m = math.floor(sec / 60)
        if m < 60 then return m .. " " .. L["Min"] end
        return ("%d:%02d %s"):format(math.floor(m / 60), m % 60, L["Std"])
    end

    -- Verbrauchsgueter je Rolle (Classic-Item-IDs); angezeigt wird das beste, das man schon benutzen kann
    local G = {
        str = { 2454, 3391, 9206 }, agi = { 2457, 3390, 8949, 9187, 13452 }, int = { 3383, 9179 }, sp = { 9155, 13454 },
        def = { 5997, 3389, 8951 }, fort = { 3825 }, mana = { 20007 }, stone = { 2862, 2863, 2871, 7964, 12404 },
        weight = { 3239, 3240, 3241, 7965, 12643 }, wizoil = { 20744, 20746, 20750, 20749 }, manaoil = { 20745, 20747, 20748 },
    }
    local ROLE = { melee = { "str", "agi", "stone", "weight" }, tank = { "def", "fort", "str", "stone" }, caster = { "int", "sp", "wizoil" },
        healer = { "int", "manaoil", "mana" }, hunter = { "agi", "int", "stone" } }
    local function bestOf(list, lvl)
        local best, pending = nil, false
        for _, id in ipairs(list) do
            local name, link, _, _, minL, _, _, _, _, tex = C_Item.GetItemInfo(id)
            if not name then
                pending = true
                if C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
            elseif (minL or 0) <= lvl then
                best = { id = id, link = link, tex = tex, minL = minL or 0 }
            end
        end
        return best, pending
    end
    local function craftersOf(id)
        if not (ns.Crafting and ns.Crafting.Index) then return 0 end
        for _, e in ipairs(ns.Crafting.Index()) do
            if e.itemID == id then return #(ns.Crafting.CraftersOf(e) or {}) end
        end
        return 0
    end

    local function section(host, title, color, y)
        local h = K.GameHead(host, title, color)
        h.text:SetText(title)   -- normale Schreibweise (Profil 2026)
        h:SetPoint("TOPLEFT", 0, y)
        h:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        return h
    end
    local function bar(host, y)
        local b = CreateFrame("Frame", nil, host)
        b:SetPoint("TOPLEFT", 0, y)
        b:SetPoint("RIGHT", host, "RIGHT", 0, 0)
        b:SetHeight(6)
        K.Fill(b, { 1, 1, 1, 0.07 })
        b.fill = b:CreateTexture(nil, "ARTWORK")
        b.fill:SetPoint("LEFT")
        b.fill:SetHeight(6)
        return b
    end

    local function build(soon, cs)
        local f = CreateFrame("Frame", nil, cs)
        soon.ins = f
        -- 1) Treffer-Ziel
        f.h1 = section(f, L["Treffer-Ziel"], C.red, 0)
        f.hitBar = bar(f, -24)
        f.hitTxt = K.Text(f, 11, C.muted)
        f.hitTxt:SetPoint("TOPLEFT", 0, -34)
        -- 2) Level-Tempo
        f.h2 = section(f, L["Level-Tempo"], C.mint, -58)
        f.tempo = K.Text(f, 11, C.text)
        f.tempo:SetPoint("TOPLEFT", 0, -80)
        f.tempo:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        f.tempo:SetJustifyH("LEFT")
        f.tempo:SetSpacing(3)
        -- 3) Upgrade-Tipp
        f.h3 = section(f, L["Upgrade-Tipp"], C.amber, -124)
        f.up = CreateFrame("Button", nil, f)
        f.up:SetPoint("TOPLEFT", 0, -146)
        f.up:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        f.up:SetHeight(30)
        f.up.icon = f.up:CreateTexture(nil, "ARTWORK")
        f.up.icon:SetSize(26, 26)
        f.up.icon:SetPoint("LEFT")
        f.up.name = K.Text(f.up, 11, C.text)
        f.up.name:SetPoint("TOPLEFT", f.up.icon, "TOPRIGHT", 6, 0)
        f.up.name:SetPoint("RIGHT", f.up, "RIGHT", 0, 0)
        f.up.name:SetWordWrap(false)
        f.up.sub = K.Text(f.up, 10, C.dim)
        f.up.sub:SetPoint("BOTTOMLEFT", f.up.icon, "BOTTOMRIGHT", 6, 0)
        f.up.sub:SetPoint("RIGHT", f.up, "RIGHT", 0, 0)
        f.up.sub:SetWordWrap(false)
        f.up:SetScript("OnEnter", function(self)
            if self.link then GameTooltip:SetOwner(self, "ANCHOR_RIGHT") pcall(GameTooltip.SetHyperlink, GameTooltip, self.link) GameTooltip:Show() end
        end)
        f.up:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.up:SetScript("OnClick", function(self)
            if self.link and IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link) end
        end)
        -- 4) Verbrauchsgueter
        f.h4 = section(f, L["Verbrauchsgueter"], C.blue, 0)
        f.h2:Hide() f.tempo:Hide()
        f.h1:Hide() f.hitBar:Hide() f.hitTxt:Hide()
        f.cons = {}
        for i = 1, 4 do
            local b = CreateFrame("Button", nil, f)
            -- Profil 2026: Glaszeile, Name darf zweizeilig umbrechen (nicht mehr abgeschnitten)
            b:SetPoint("TOPLEFT", 0, -28 - (i - 1) * 42)
            b:SetPoint("RIGHT", f, "RIGHT", 0, 0)
            b:SetHeight(38)
            IG.Glass(b, IG.GLASS_FILL, IG.GLASS_LINE, 8)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT")
            b.hl:SetAllPoints()
            b.hl:SetColorTexture(1, 1, 1, 0.04)
            if K.RoundMask then K.RoundMask(b.hl, b, 8) end
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(24, 24)
            b.icon:SetPoint("LEFT", 7, 0)
            b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if K.RoundMask then K.RoundMask(b.icon, b.icon, 4) end
            b.name = K.Text(b, 11, C.text)
            b.name:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
            b.name:SetPoint("RIGHT", b, "RIGHT", -8, 0)
            b.name:SetJustifyH("LEFT")
            b.name:SetWordWrap(true)
            if b.name.SetMaxLines then b.name:SetMaxLines(2) end
            b.who = K.Text(b, 10, C.mint, "RIGHT")
            b.who:SetPoint("RIGHT", -10, 0)
            b:SetScript("OnEnter", function(self)
                if not self.link then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
                if (self.n or 0) > 0 then GameTooltip:AddLine((L["%d in der Gilde koennen es herstellen"]):format(self.n), 0.4, 0.86, 0.62) end
                GameTooltip:AddLine(L["Klick: in der Handwerks-Boerse suchen"], 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            b:SetScript("OnClick", function(self)
                if not self.link then return end
                if IsModifiedClick("CHATLINK") then ChatEdit_InsertLink(self.link) return end
                -- Handwerks-Boerse: wer kann das herstellen?
                local name = self.link:match("%[(.-)%]")
                if ns.Crafting and ns.Crafting.ShowItem then ns.Crafting.ShowItem(name) end
            end)
            f.cons[i] = b
        end
        f.foot = K.Text(f, 9, C.dim)
        f.foot:SetPoint("BOTTOMLEFT", 0, 0)
        f.foot:SetPoint("RIGHT", f, "RIGHT", 0, 0)
        f.foot:SetJustifyH("LEFT")
        f.foot:SetWordWrap(true)
        f.foot:SetText("")
        f.foot:Hide()
        f.h3:Hide() f.up:Hide()
    end

    function IN.Fill(soon, cs, st)
        if not soon.ins then build(soon, cs) end
        local f = soon.ins
        local W = cs:GetWidth() or 700
        if W < 100 then W = 700 end
        local colW = math.floor((W - 24 - 20) / 2)
        f:ClearAllPoints()
        if soon.consBox then
            -- 0.6.330: eigene Box unter den Charakterwerten, Verbrauchsgueter 2x2
            local cb = soon.consBox
            if f:GetParent() ~= cb then f:SetParent(cb) f:SetFrameLevel(cb:GetFrameLevel() + 2) end
            f:SetPoint("TOPLEFT", cb, "TOPLEFT", 14, -12)
            f:SetPoint("BOTTOMRIGHT", cb, "BOTTOMRIGHT", -14, 10)
            local fw = (cb:GetWidth() or 360) - 28
            if fw < 100 then fw = 330 end
            local bw = (fw - 10) / 2
            for i, b in ipairs(f.cons) do
                local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", f, "TOPLEFT", col * (bw + 10), -26 - row * 40)
                b:SetSize(bw, 36)
            end
        else
            f:SetPoint("TOPLEFT", cs, "TOPLEFT", 12 + colW + 28, -80)
            f:SetPoint("BOTTOMRIGHT", cs, "BOTTOMRIGHT", -12, 10)
        end
        local roleKey = soon.Role and select(1, soon:Role()) or "melee"
        local lvl = UnitLevel("player") or 1

        -- 1) Treffer: Nahkampf/Jaeger/Tank 9 %, Zauber 16 %; Heiler braucht keinen
        local byKey = {}
        for _, x in ipairs(soon.lastStats or {}) do if x.key then byKey[x.key] = x end end
        local caster = roleKey == "caster"
        local x = byKey[caster and "shit" or "hit"]
        local raw = x and type(x[2]) == "string" and tonumber((x[2]:gsub(",", "."):gsub("[^%d%.]", ""))) or 0
        local goal = caster and 16 or 9
        local c = raw >= goal and C.mint or (raw >= goal / 2 and C.amber or C.red)
        if roleKey == "healer" then
            f.hitBar.fill:SetWidth(1) f.hitBar.fill:SetColorTexture(0, 0, 0, 0)
            f.hitTxt:SetText("|cff777777" .. L["fuer Heiler nicht noetig"] .. "|r")
        else
            f.hitBar.fill:SetColorTexture(c[1], c[2], c[3], 1)
            f.hitBar.fill:SetWidth(math.max(1, (f.hitBar:GetWidth() or 200) * math.min(1, raw / goal)))
            f.hitTxt:SetText((L["%.1f %% von %d %%"]):format(raw, goal) .. (raw >= goal and ("  |cff66db9e" .. L["Erreicht!"] .. "|r") or ""))
        end

        -- 2) Level-Tempo
        local cur, max = UnitXP("player"), UnitXPMax("player")
        local rest = GetXPExhaustion and GetXPExhaustion() or 0
        local lines = {}
        local el = sess.t0 and (GetTime() - sess.t0) or 0
        if el > 120 and sess.xp > 0 then
            local rate = sess.xp / el * 3600
            lines[#lines + 1] = (L["%s XP/Std"]):format(BreakUpLargeNumbers and BreakUpLargeNumbers(math.floor(rate)) or math.floor(rate))
            lines[#lines + 1] = (L["naechstes Level in ca. %s"]):format(fmtTime((max - cur) / rate * 3600))
        else
            lines[#lines + 1] = "|cff777777" .. L["noch zu wenig Daten"] .. "|r"
        end
        if rest and rest > 0 then lines[#lines + 1] = "|cff6199ff" .. (L["Ruhebonus: %s XP"]):format(BreakUpLargeNumbers and BreakUpLargeNumbers(rest) or rest) .. "|r" end
        f.tempo:SetText(table.concat(lines, "\n"))

        -- 3) Upgrade-Tipp: jetzt im Charakterfenster ("Upgrades finden")
        local up = nil
        local u = up and up[1]
        if u then
            f.up.link = u.link
            f.up.icon:SetTexture(u.tex)
            f.up.name:SetText(u.link .. "  |cff66db9e+" .. u.gain .. "|r")
            f.up.sub:SetText(u.src)
        else
            f.up.link = nil
            f.up.icon:SetTexture(nil)
            f.up.name:SetText("|cff777777" .. L["Alles angelegt ist gut fuer dein Level."] .. "|r")
            f.up.sub:SetText("")
        end

        -- 4) Verbrauchsgueter
        local groups = ROLE[roleKey] or ROLE.melee
        local anyPending = false
        for i, b in ipairs(f.cons) do
            local g = groups[i]
            local best, pending = nil, false
            if g then best, pending = bestOf(G[g], lvl) end
            anyPending = anyPending or pending
            if best then
                b.link = best.link
                b.icon:SetTexture(best.tex)
                -- Link ohne eckige Klammern anzeigen (spart Platz), Klick/Tooltip nutzen weiter den echten Link
                b.name:SetText((tostring(best.link or ""):gsub("|h%[(.-)%]|h", "|h%1|h")))
                b.n = craftersOf(best.id)
                b.who:SetText(b.n > 0 and (b.n .. " " .. L["Gilde"]) or "")
                b.name:SetPoint("RIGHT", b, "RIGHT", b.n > 0 and -((b.who:GetStringWidth() or 40) + 18) or -8, 0)
                b:Show()
            else
                b:Hide()
            end
        end
        if anyPending and not IN.retry then
            IN.retry = true
            ns.After(1.5, function() IN.retry = false if soon.FillStats then soon:FillStats() end end)
        end
    end
end


------------------------------------------------------------------------
-- Profilkopf: WoW-Erfahrung + Level-Tempo
------------------------------------------------------------------------
do
    local sess = { t0 = nil, xp = 0, last = nil, lastMax = nil }
    local function tick()
        local cur, max = UnitXP("player"), UnitXPMax("player")
        if not sess.t0 then sess.t0, sess.last, sess.lastMax = GetTime(), cur, max return end
        local d = cur - (sess.last or cur)
        if d < 0 then d = d + (sess.lastMax or 0) end
        if d > 0 then sess.xp = sess.xp + d end
        sess.last, sess.lastMax = cur, max
    end
    ns.On("PLAYER_XP_UPDATE", function() tick() if ns.Insta and ns.Insta.headSoon then ns.Insta.headSoon:FillWowXP() end end)
    ns.Listen("LOGIN", function() ns.After(2, tick) end)
    ns.Insta.WowXPSession = sess
end

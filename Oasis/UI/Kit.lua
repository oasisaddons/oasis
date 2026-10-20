-- Oasis - UI toolkit
-- Calm, dark surfaces, one accent color (Oasis violet), WoW font for headings.
local ADDON, ns = ...
local L = ns.L
local K = {}
ns.K = K

K.FONT = "Fonts\\ARIALN.TTF"
K.FONT_HEAD = "Fonts\\FRIZQT__.TTF"

-- Fonts: WoW's own + bundled (Media\fonts, SIL OFL - see LICENSE-FONTS.txt)
-- ui = suitable as body text (readable even when small)
local MF = "Interface\\AddOns\\Oasis\\Media\\fonts\\"
K.FONTS = {
    { key = "arialn", text = "Arial Narrow", path = "Fonts\\ARIALN.TTF", ui = true },
    { key = "friz", text = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF", ui = true },
    { key = "2002", text = "2002", path = "Fonts\\2002.TTF", ui = true },
    { key = "morpheus", text = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { key = "skurri", text = "Skurri", path = "Fonts\\SKURRI.TTF" },
    { key = "teko", text = "Teko", path = MF .. "Teko.ttf", ui = true },
    { key = "antonio", text = "Antonio", path = MF .. "Antonio.ttf", ui = true },
    { key = "antoniobold", text = "Antonio Bold", path = MF .. "AntonioBold.ttf" },
    { key = "inter", text = "Inter", path = MF .. "Inter.ttf", ui = true, cyr = true },
    { key = "ptsans", text = "PT Sans Narrow", path = MF .. "PTSansNarrow.ttf", ui = true, cyr = true },
    { key = "ptsansbold", text = "PT Sans Narrow Bold", path = MF .. "PTSansNarrowBold.ttf", cyr = true },
    { key = "russo", text = "Russo One", path = MF .. "RussoOne.ttf", cyr = true },
    { key = "bebas", text = "Bebas Neue", path = MF .. "BebasNeue.ttf" },
    { key = "cinzel", text = "Cinzel", path = MF .. "Cinzel.ttf" },
    { key = "cinzeldeco", text = "Cinzel Decorative", path = MF .. "CinzelDecorative.ttf" },
    { key = "marcellus", text = "Marcellus SC", path = MF .. "MarcellusSC.ttf" },
    { key = "orbitron", text = "Orbitron", path = MF .. "Orbitron.ttf", noext = true },
    { key = "blackops", text = "Black Ops One", path = MF .. "BlackOpsOne.ttf" },
    { key = "uncial", text = "Uncial Antiqua", path = MF .. "UncialAntiqua.ttf" },
    { key = "medieval", text = "MedievalSharp", path = MF .. "MedievalSharp.ttf" },
    { key = "metamorphous", text = "Metamorphous", path = MF .. "Metamorphous.ttf" },
    { key = "almendra", text = "Almendra", path = MF .. "Almendra.ttf", noext = true },
    { key = "fraktur", text = "Unifraktur", path = MF .. "UnifrakturMaguntia.ttf", noext = true },
    { key = "germania", text = "Germania One", path = MF .. "GermaniaOne.ttf", noext = true },
    { key = "pirata", text = "Pirata One", path = MF .. "PirataOne.ttf" },
    { key = "rocker", text = "New Rocker", path = MF .. "NewRocker.ttf" },
    { key = "creepster", text = "Creepster", path = MF .. "Creepster.ttf", noext = true },
    { key = "bangers", text = "Bangers", path = MF .. "Bangers.ttf" },
    { key = "shojumaru", text = "Shojumaru", path = MF .. "Shojumaru.ttf" },
    { key = "potta", text = "Potta One", path = MF .. "PottaOne.ttf" },
    { key = "stick", text = "Stick", path = MF .. "Stick.ttf", noext = true },
    -- only for Chinese/Korean/Japanese (reduced to the Oasis texts), not in the selection lists
    -- noext = without Polish letters (Latin Extended-A): for Polish PT Sans is used
    { key = "notosc", text = "Noto Sans SC", path = MF .. "NotoSansSC.ttf", hidden = true, cyr = true },
    { key = "notokr", text = "Noto Sans KR", path = MF .. "NotoSansKR.ttf", hidden = true, cyr = true },
    { key = "nototc", text = "Noto Sans TC", path = MF .. "NotoSansTC.ttf", hidden = true, cyr = true },
    { key = "notojp", text = "Noto Sans JP", path = MF .. "NotoSansJP.ttf", hidden = true, cyr = true },
}
-- fonts for selection lists (without the reduced CJK fonts)
function K.PickFonts(filter)
    local out = {}
    for _, f in ipairs(K.FONTS) do
        if not f.hidden and (not filter or filter(f)) then out[#out + 1] = f end
    end
    return out
end
K.fontByKey = {}
for _, f in ipairs(K.FONTS) do K.fontByKey[f.key] = f end

-- PRELOAD fonts (0.5.479): WoW only properly picks up a custom font file if it was already
-- used during the loading screen - otherwise the text stays empty the first time or
-- a different font appears, only correct after /reload ("Inter not at startup",
-- "some fonts show nothing at all"). So use each font once here while loading.
do
    local pre = CreateFrame("Frame", nil, UIParent)
    pre:SetSize(1, 1)
    -- 0.5.647: ON the screen (bottom left), almost transparent - off-screen WoW draws nothing and doesn't load the
    -- font -> on first start a fallback font appeared. Gone again after the loading screen.
    pre:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    pre:SetAlpha(0.01)
    K.preloadFrame = pre
    K.preload = {}
    for _, f in ipairs(K.FONTS) do
        if not f.hidden then
            local fs = pre:CreateFontString(nil, "OVERLAY")
            fs:SetPoint("TOPLEFT")
            if pcall(fs.SetFont, fs, f.path, 12, "") and fs:GetFont() then
                fs:SetText("Oasis ÄÖÜ äöü ß 0123")
                K.preload[f.key] = fs
            end
        end
    end
end

-- after the loading screen reassign all Oasis texts once with their font
-- (catches texts created before preloading that stayed empty/wrong)
function K.RefreshFonts()
    if K.RecalcFontScale then pcall(K.RecalcFontScale) end
    for obj in pairs(K._fontObjs or {}) do
        local ok, path, size, flags = pcall(obj.GetFont, obj)
        if ok and path and size then
            -- 0.5.603: briefly switch to a Blizzard font first, then back - WoW ignores setting the same font again,
            -- then the fallback font from the first start stayed
            if path ~= STANDARD_TEXT_FONT then pcall(obj.SetFont, obj, STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags or "") end
            pcall(obj.SetFont, obj, path, size, flags or "")
            if obj.GetText and obj.SetText then
                local t = obj:GetText()
                if t and t ~= "" then pcall(obj.SetText, obj, t) end
            end
        end
    end
end

-- Font matching the text: if the text has characters the font can't do (Cyrillic, Korean,
-- Chinese/Japanese), fall back to a font that has them (e.g. guild names in the logo)
K.fontByPath = {}
for _, f in ipairs(K.FONTS) do K.fontByPath[f.path] = f end
function K.FontFor(path, text)
    text = text or ""
    local f = K.fontByPath[path]
    if text:find("[\208\209][\128-\191]") then
        if not (f and f.cyr) then return K.fontByKey.ptsansbold.path end
    elseif text:find("[\234-\237][\128-\191][\128-\191]") then
        return "Fonts\\2002.TTF"                 -- Hangul (Blizzard font with Korean)
    elseif text:find("[\227-\233][\128-\191][\128-\191]") then
        return "Fonts\\ARHei.ttf"                -- Chinese/Japanese; if missing, SetFontSafe catches it
    end
    return path
end
function K.FontPath(key, fallback)
    local f = key and K.fontByKey[key]
    return f and f.path or fallback or K.FONT
end

-- apply personal fonts; languages with Cyrillic script need matching fonts
function K.ApplyUserFonts()
    local s = ns.db and ns.db.settings
    if not s then return end
    -- one font for everything
    local b = K.fontByKey[s.uiFont or "inter"]
    local h = b
    local lang = ns.langByKey and ns.langByKey[ns.lang]
    if lang and lang.cjk then
        b, h = K.fontByKey[lang.cjk], K.fontByKey[lang.cjk]
    elseif lang and lang.cyr then
        if not (b and b.cyr) then b = K.fontByKey.ptsans end
        if not (h and h.cyr) then h = K.fontByKey.ptsansbold end
    elseif lang and lang.ext then
        if b and b.noext then b = K.fontByKey.ptsans h = b end
    end
    K.SetFonts(b and b.path or "Fonts\\ARIALN.TTF", h and h.path or "Fonts\\FRIZQT__.TTF")
end

-- set font; if the file is missing, the FontString stays without font -> fallback font
function K.SetFontSafe(fs, path, size, flags, fallback)
    local ok = pcall(fs.SetFont, fs, path, size, flags or "")
    if not ok or not fs:GetFont() then fs:SetFont(fallback or "Fonts\\FRIZQT__.TTF", size, flags or "") end
end

-- fit text exactly to a width: choose the font size so it is w pixels wide
function K.FitText(fs, path, text, w, minSize, maxSize, fallback)
    local size = 20
    -- font first, then text: SetText on a FontString without a font throws an error in WoW
    for _ = 1, 4 do
        K.SetFontSafe(fs, path, size, "", fallback or K.FONT_HEAD)
        fs:SetText(text or "")
        local sw = fs:GetStringWidth() or 0
        if sw <= 0 then break end
        local n = math.max(minSize or 8, math.min(maxSize or 60, size * w / sw))
        if math.abs(n - size) < 0.3 then break end
        size = n
    end
    return size
end

-- uppercase including umlauts (string.upper only knows ASCII)
local UPPER = { ["ä"] = "Ä", ["ö"] = "Ö", ["ü"] = "Ü", ["é"] = "É", ["è"] = "È", ["à"] = "À", ["ç"] = "Ç", ["ñ"] = "Ñ",
    ["ã"] = "Ã", ["õ"] = "Õ", ["ê"] = "Ê", ["á"] = "Á", ["í"] = "Í", ["ó"] = "Ó", ["ú"] = "Ú", ["ò"] = "Ò", ["ì"] = "Ì", ["ù"] = "Ù",
    ["â"] = "Â", ["î"] = "Î", ["ô"] = "Ô", ["û"] = "Û", ["ë"] = "Ë", ["ï"] = "Ï", ["œ"] = "Œ", ["æ"] = "Æ", ["ÿ"] = "Ÿ", ["ё"] = "Ё" }
function K.Upper(s)
    s = tostring(s or ""):upper()
    for lo, up in pairs(UPPER) do s = s:gsub(lo, up) end
    -- Cyrillic: lowercase а-я (U+0430-044F) -> А-Я
    s = s:gsub("\208([\176-\191])", function(c) return "\208" .. string.char(c:byte() - 32) end)
    s = s:gsub("\209([\128-\143])", function(c) return "\208" .. string.char(c:byte() + 32) end)
    return s
end

-- letter-spaced font: distribute letters individually so the text is exactly w pixels wide
function K.Tracked(parent, size, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(size + 4)
    f.chars = {}
    f.size, f.color = size, color or C.muted
    function f:Set(text, w, font, size)
        self.text, self.w, self.font = text, w, font
        if size then self.size = size self:SetHeight(size + 4) end
        self:SetWidth(w)
        local list = {}
        for ch in tostring(text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do list[#list + 1] = ch end
        for i, ch in ipairs(list) do
            local fs = self.chars[i]
            if not fs then
                fs = self:CreateFontString(nil, "OVERLAY")
                fs:SetShadowColor(0, 0, 0, 0.6)
                fs:SetShadowOffset(1, -1)
                self.chars[i] = fs
            end
            K.SetFontSafe(fs, font or K.FONT, self.size, "", K.FONT)
            fs:SetTextColor(self.color[1], self.color[2], self.color[3], self.color[4] or 1)
            fs:SetText(ch)
            fs:Show()
        end
        for i = #list + 1, #self.chars do self.chars[i]:Hide() end
        self:Layout(#list)
    end
    -- choose the size so the letters without spacing fill w (at most maxSize),
    -- even spacing fills the rest of the width
    function f:Fit(text, w, font, maxSize)
        self:Set(text, w, font, 20)
        local n, total = 0, 0
        for _, fs in ipairs(self.chars) do
            if fs:IsShown() then n = n + 1 total = total + (fs:GetStringWidth() or 0) end
        end
        local size = 20
        if total > 0 then size = math.max(8, math.min(maxSize or 60, 20 * w / total)) end
        self:Set(text, w, font, size)
        return size
    end
    function f:Layout(n)
        n = n or 0
        if n == 0 then return end
        local total = 0
        for i = 1, n do total = total + (self.chars[i]:GetStringWidth() or 0) end
        local gap = n > 1 and math.max(0, (self.w - total) / (n - 1)) or 0
        local x = 0
        for i = 1, n do
            local fs = self.chars[i]
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", self, "LEFT", x, 0)
            x = x + (fs:GetStringWidth() or 0) + gap
        end
        -- font may only load on first use -> measure again
        local text = self.text
        ns.After(0.3, function() if self.text == text then self:Relayout() end end)
    end
    function f:Relayout()
        local n = 0
        for _, fs in ipairs(self.chars) do if fs:IsShown() then n = n + 1 end end
        local total = 0
        for i = 1, n do total = total + (self.chars[i]:GetStringWidth() or 0) end
        local gap = n > 1 and math.max(0, (self.w - total) / (n - 1)) or 0
        local x = 0
        for i = 1, n do
            self.chars[i]:ClearAllPoints()
            self.chars[i]:SetPoint("LEFT", self, "LEFT", x, 0)
            x = x + (self.chars[i]:GetStringWidth() or 0) + gap
        end
    end
    return f
end

-- swap the UI font live. Every Oasis text remembers its role when created
-- ("body" / "head"); if both fonts are the same, the role can no longer be read from the path.
local fontObjs = setmetatable({}, { __mode = "k" })
K._fontObjs = fontObjs   -- for K.RefreshFonts
-- width compensation: wide fonts are set slightly smaller so texts stay as wide
-- as with the narrow default font (otherwise they overlap in fixed layouts)
K.fontScale = { body = 1, head = 1 }
local REF_TEXT = "Gildenzentrale Einstellungen Abzeichen Handwerks-Boerse 12345"
local REF_FONT = "Fonts\\ARIALN.TTF"
local measure
local function widthOf(path)
    if not measure then
        measure = UIParent:CreateFontString(nil, "BACKGROUND")
        measure:Hide()
    end
    local ok = pcall(measure.SetFont, measure, path, 20, "")
    if not ok or not measure:GetFont() then return nil end
    measure:SetText(REF_TEXT)
    local w = measure:GetStringWidth()
    return (w and w > 0) and w or nil
end
function K.FontScaleFor(path)
    local ref, w = widthOf(REF_FONT), widthOf(path)
    if not ref or not w then return 1 end
    return math.max(0.72, math.min(1, ref / w))
end
local function track(obj, role) fontObjs[obj] = role or "body" end
local function norm(p) return (tostring(p or ""):lower():gsub("/", "\\")) end
function K.SetFonts(body, head)
    local oldBody, oldHead = K.FONT, K.FONT_HEAD
    body, head = body or oldBody, head or oldHead
    if body == oldBody and head == oldHead then return end
    K.FONT, K.FONT_HEAD = body, head
    local oldScale = K.fontScale
    K.fontScale = { body = K.FontScaleFor(body), head = K.FontScaleFor(head) }
    local ob, oh = norm(oldBody), norm(oldHead)
    for obj, role in pairs(fontObjs) do
        local ok, path, size, flags = pcall(obj.GetFont, obj)
        if ok and size then
            local p = norm(path)
            local r
            -- path unique? (modules sometimes set K.FONT_HEAD to a body font afterwards)
            if ob ~= oh and p == oh then r = "head"
            elseif ob ~= oh and p == ob then r = "body"
            elseif p == ob or p == oh then r = role
            end
            if r then
                -- calculate the base size back from the previous scaling
                local base = size / (oldScale[r] or 1)
                local sc = K.fontScale[r] or 1
                pcall(obj.SetFont, obj, r == "head" and head or body, math.max(6, base * sc), flags or "")
            end
        end
    end
    if K.ReCenterAll then K.ReCenterAll() end
end
-- 0.5.799: re-measure width compensation. Right after a fresh game start the custom font file is often not loaded yet at the first
-- measurement (ApplyUserFonts) -> compensation stayed 1, all texts too large/cut off, only correct after /reload.
function K.RecalcFontScale()
    local old = K.fontScale
    local new = { body = K.FontScaleFor(K.FONT), head = K.FontScaleFor(K.FONT_HEAD) }
    if math.abs(new.body - old.body) < 0.01 and math.abs(new.head - old.head) < 0.01 then return false end
    K.fontScale = new
    local nb, nh = norm(K.FONT), norm(K.FONT_HEAD)
    for obj, role in pairs(fontObjs) do
        local ok, path, size, flags = pcall(obj.GetFont, obj)
        if ok and path and size then
            local p = norm(path)
            local r
            if nb ~= nh and p == nh then r = "head"
            elseif nb ~= nh and p == nb then r = "body"
            elseif p == nb or p == nh then r = role
            end
            if r then pcall(obj.SetFont, obj, path, math.max(6, size / (old[r] or 1) * (new[r] or 1)), flags or "") end
        end
    end
    if K.ReCenterAll then K.ReCenterAll() end
    return true
end

K.C = {
    bg      = { 0.035, 0.035, 0.038, 0.97 },
    side    = { 0.020, 0.020, 0.022, 1 },
    panel   = { 0.075, 0.075, 0.080, 1 },
    raised  = { 0.110, 0.110, 0.118, 1 },
    field   = { 0.028, 0.028, 0.030, 1 },
    line    = { 0.190, 0.190, 0.200, 1 },
    text    = { 0.940, 0.940, 0.940, 1 },
    muted   = { 0.640, 0.640, 0.660, 1 },
    dim     = { 0.420, 0.420, 0.440, 1 },
    accent  = { 1.000, 0.071, 0.000, 1 },   -- #ff1200
    accent2 = { 0.700, 0.050, 0.000, 1 },
    -- Data colors (roles, status, quality)
    blue    = { 0.380, 0.600, 1.000, 1 },
    violet  = { 1.000, 0.071, 0.000, 1 },
    pink    = { 1.000, 0.470, 0.220, 1 },
    mint    = { 0.400, 0.860, 0.620, 1 },
    amber   = { 0.980, 0.760, 0.340, 1 },
    red     = { 0.900, 0.250, 0.280, 1 },
}
local C = K.C
C.panel2 = C.raised
C.hover = { 0.140, 0.140, 0.150, 1 }

function K.hex(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
-- Live preview (color picker): surfaces/texts/icons remember their palette color (table from K.C,
-- changed IN PLACE on design switch) -> K.LiveRecolor recolors everything without rebuilding the window
local liveTex = setmetatable({}, { __mode = "k" })
local liveFs = setmetatable({}, { __mode = "k" })
local liveGlyph = setmetatable({}, { __mode = "k" })
local function col(t, c, a)
    liveTex[t] = { c, a }
    -- surface of a skinned frame: pass color on to the design border
    if t.skinOwner and K.SkinFill then K.SkinFill(t.skinOwner, c, a) return end
    t:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1)
end
-- Show truncated texts ("...") fully as tooltip on hover - for all K.Text/K.Title.
-- A light tick (0.2 s) checks only while the Oasis window is open.
local truncTip = CreateFrame("Frame")
local truncOwner
-- own flag instead of a field on GameTooltip (don't write to the Blizzard tooltip)
local tipTrunc = false
if GameTooltip then GameTooltip:HookScript("OnHide", function() tipTrunc = false end) end
truncTip.t = 0
truncTip:SetScript("OnUpdate", function(self, el)
    self.t = self.t + el
    if self.t < 0.2 then return end
    self.t = 0
    local m = ns.MainFrame and ns.MainFrame()
    if not (m and m:IsShown()) then return end
    -- Performance 0.5.482: liveFs contains thousands of texts (WoW never frees widgets). Only once per second pick out the
    -- visible truncated ones, then in the 0.2 s tick check only those few for "mouse over".
    -- mouse not over the window: don't search at all.
    local over = m:IsMouseOver()
    local hit
    if over then
        self.scan = (self.scan or 0) + 1
        if not self.cand or self.scan >= 5 then
            self.scan = 0
            local cand = {}
            for fs in pairs(liveFs) do
                if fs.IsTruncated and fs:IsVisible() and fs:IsTruncated() then cand[#cand + 1] = fs end
            end
            self.cand = cand
        end
        for _, fs in ipairs(self.cand) do
            if fs:IsVisible() and fs:IsMouseOver() then hit = fs break end
        end
    else
        self.cand = nil
    end
    if hit then
        if truncOwner == hit then return end
        if GameTooltip:IsShown() and not tipTrunc then return end   -- own tooltip takes precedence
        truncOwner = hit
        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        tipTrunc = true
        GameTooltip:SetText(hit:GetText() or "", 1, 1, 1, 1, true)
        GameTooltip:Show()
    elseif truncOwner then
        truncOwner = nil
        if tipTrunc then tipTrunc = false GameTooltip:Hide() end
    end
end)

function K.LiveRecolor()
    for t, v in pairs(liveTex) do
        if t.skinOwner and K.SkinFill then pcall(K.SkinFill, t.skinOwner, v[1], v[2])
        else pcall(t.SetColorTexture, t, v[1][1], v[1][2], v[1][3], v[2] or v[1][4] or 1) end
    end
    for fs, c in pairs(liveFs) do pcall(fs.SetTextColor, fs, c[1], c[2], c[3], c[4] or 1) end
    for g, c in pairs(liveGlyph) do pcall(g.SetVertexColor, g, c[1], c[2], c[3]) end
    -- window + bar (gradient) with new palette
    local m = ns.MainFrame and ns.MainFrame()
    if m and K.StyleWindow then pcall(K.StyleWindow, m) end
end

------------------------------------------------------------------------
-- Basic building blocks
------------------------------------------------------------------------
function K.Fill(frame, c, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    col(t, c)
    return t
end

function K.Border(frame, c, size)
    c = c or C.line
    size = size or 1
    frame.borders = frame.borders or {}
    local function edge(p1, p2, w, h)
        local t = frame:CreateTexture(nil, "BORDER")
        col(t, c)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        frame.borders[#frame.borders + 1] = t
    end
    edge("TOPLEFT", "TOPRIGHT", nil, size)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, size)
    edge("TOPLEFT", "BOTTOMLEFT", size, nil)
    edge("TOPRIGHT", "BOTTOMRIGHT", size, nil)
end
function K.SetBorderColor(frame, c, a)
    if frame.skinLine and K.SkinLine then K.SkinLine(frame, c, a) return end
    if frame.skinBlizz then return end
    if not frame.borders then return end
    for _, t in ipairs(frame.borders) do col(t, c, a) end
end

-- thin divider
function K.Divider(parent, c)
    local t = parent:CreateTexture(nil, "ARTWORK")
    col(t, c or C.line)
    t:SetHeight(1)
    return t
end

function K.Text(parent, size, color, justify, font, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    local role = (font == nil or font == K.FONT) and "body" or "head"
    fs:SetFont(font or K.FONT, (size or 13) * (K.fontScale[role] or 1), "")

    local c = color or C.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    liveFs[fs] = c
    fs:SetJustifyH(justify or "LEFT")
    fs:SetShadowColor(0, 0, 0, 0.6)
    fs:SetShadowOffset(1, -1)
    fs:SetWordWrap(false)
    track(fs, (font == nil or font == K.FONT) and "body" or "head")
    -- foreign scripts (Korean, Chinese, Cyrillic) automatically with a matching font
    local orig = fs.SetText
    fs.SetText = function(self, t, ...)
        if type(t) == "string" and ns.FixItemLinks then t = ns.FixItemLinks(t) end
        if type(t) == "string" and t:find("[\208-\211\225-\239]") then
            t = t:gsub("\227\133\164", " "):gsub("\239\190\160", " "):gsub("\225\133[\159\160]", " "):gsub("\226\128[\139-\143]", "")
            K.SetNameFont(self, t)
        elseif self.cjkFont then
            K.SetNameFont(self, "")
        end
        return orig(self, t, ...)
    end
    return fs
end
function K.Title(parent, size, color, justify)
    local fs = K.Text(parent, size or 14, color or C.text, justify, K.FONT_HEAD)
    track(fs, "head")
    return fs
end

-- place numbers exactly centered in a field (level boxes, counter pills, crests ...).
-- WoW centers the line box, not the digits: depending on the font, digits sit higher/lower
-- (measured with fontTools, fraction of line height, + = digits sit too high). Additionally
-- the shadow (1,-1) shifts the glyphs half a pixel to the bottom right.
local NUM_DY = {
    almendra = -0.052, bangers = 0.014, bebasneue = 0.042, blackopsone = 0.028, cinzel = 0.028,
    cinzeldecorative = -0.009, creepster = -0.007, germaniaone = 0.001, marcellussc = -0.016,
    medievalsharp = 0.062, metamorphous = -0.031, newrocker = 0.017, notosanskr = -0.047,
    notosanssc = -0.047, orbitron = -0.019, ptsansnarrow = -0.016, ptsansnarrowbold = -0.016,
    pirataone = 0.022, pottaone = -0.045, russoone = 0.022, shojumaru = 0.014, stick = -0.06,
    teko = 0.053, uncialantiqua = -0.051, unifrakturmaguntia = 0.08, arialn = -0.008,
    frizqt__ = -0.16,   -- Friz Quadrata (Blizzard default): digits sit visibly too low (measured in game)
}
local centered = setmetatable({}, { __mode = "k" })
local function placeNum(fs)
    local a = centered[fs]
    if not a then return end
    local path, size = fs:GetFont()
    local key = tostring(path or ""):lower():match("([^\\/]+)%.[ot]tf$") or ""
    local off = NUM_DY[key] or 0
    local lh = fs:GetLineHeight() or size or 12
    local dy = -off * lh
    local sx, sy = fs:GetShadowOffset()
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", a.rel, a.rp, a.x - (sx or 0) / 2, a.y + dy - (sy or 0) / 2)
end
function K.CenterNum(fs, rel, rp, x, y)
    if type(rp) == "number" then rp, x, y = "CENTER", rp, x end
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    centered[fs] = { rel = rel or fs:GetParent(), rp = rp or "CENTER", x = x or 0, y = y or 0 }
    placeNum(fs)
end
K.ReCenterNum = placeNum
function K.ReCenterAll() for fs in pairs(centered) do placeNum(fs) end end

function K.Panel(parent, c, withBorder)
    local f = CreateFrame("Frame", nil, parent)
    f.bg = K.Fill(f, c or C.panel)
    if withBorder ~= false then
        K.Border(f, C.line)
        if K.ApplySkin then K.ApplySkin(f, "panel", c or C.panel) end
    end
    return f
end

-- Section heading
function K.Header(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(18)
    f.text = K.Title(f, 12, C.text)
    f.text:SetPoint("LEFT", 0, 0)
    f.text:SetText(text)
    local hc = K.HeadColor and K.HeadColor()
    if hc then f.text:SetTextColor(hc[1], hc[2], hc[3]) end
    return f
end

-- WoW icon, edge slightly cropped
function K.Icon(parent, size, path)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if path then t:SetTexture(path) end
    return t
end

------------------------------------------------------------------------
-- Buttons: "primary" (filled), "ghost" (outline), "danger"
------------------------------------------------------------------------
-- UI clicks from the chosen UI sound pack (ns.Sound.UI_PACKS): button, tab, switch - can be turned off
function K.UiSound(key)
    local s = ns.db and ns.db.settings
    if not s or s.sound == false or s.uiSounds == false or not (ns.Sound and ns.Sound.PlayChoice) then return end
    local now = GetTime()
    if K._uiLast and now - K._uiLast < 0.06 then return end
    local vol = K.UiVolume()
    if vol <= 0 then return end
    K._uiLast = now
    pcall(ns.Sound.PlayChoice, key, vol)
end
-- volume of click sounds (steps of 5 %, see Sound.VOL_MAX): own slider settings.uiVol, otherwise 70 % of the sound volume
function K.UiVolume()
    local s = ns.db and ns.db.settings
    local v = s and tonumber(s.uiVol)
    if v then return math.max(0, math.min(40, math.floor(v))) end
    return math.max(1, math.floor(((s and tonumber(s.soundVol)) or 7) * 0.7 + 0.5))
end
-- buttons that play their own sound (tabs, switches, chips ...) - flags as weak table
local ownSound = setmetatable({}, { __mode = "k" })
K.OwnSound = ownSound
local function genericClick(self)
    if not ownSound[self] and self:GetScript("OnClick") then K.UiSound("ui_click") end
end
-- all clickable Oasis buttons under f get a click sound (PreClick, runs before OnClick).
-- Own frames only; protected ones and buttons with their own PreClick stay untouched.
local soundified = setmetatable({}, { __mode = "k" })
local function soundify(f, depth)
    if depth > 40 or not f.GetChildren then return end
    for _, c in ipairs({ f:GetChildren() }) do
        if not soundified[c] and not (c.IsForbidden and c:IsForbidden()) and not (c.IsProtected and c:IsProtected()) then
            if c.IsObjectType and c:IsObjectType("Button") and not c:GetScript("PreClick") then
                soundified[c] = true
                c:SetScript("PreClick", genericClick)
            elseif c.IsObjectType and c:IsObjectType("EditBox") then
                soundified[c] = true
                c:HookScript("OnEditFocusGained", function() K.UiSound("ui_select") end)
            end
        end
        soundify(c, depth + 1)
    end
end
function K.SoundifyTree(f)
    if f then pcall(soundify, f, 0) end
end
function K.Button(parent, text, w, h, style, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 110, h or 24)
    b.style = style or "ghost"
    local base = (style == "primary") and C.accent2 or C.raised
    b.bg = K.Fill(b, base)
    K.Border(b, style == "primary" and C.accent2 or C.line)
    b.label = K.Text(b, 12, (style == "danger") and C.red or C.text, "CENTER")
    b.label:SetPoint("CENTER", 0, 0)
    b.label:SetText(text or "")
    b:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        if self.style == "primary" then col(self.bg, C.accent)
        elseif self.style == "danger" then col(self.bg, C.red, 0.18)
        else col(self.bg, C.hover) K.SetBorderColor(self, C.accent2) end
    end)
    b:SetScript("OnLeave", function(self)
        col(self.bg, base)
        K.SetBorderColor(self, self.style == "primary" and C.accent2 or C.line)
    end)
    b:SetScript("OnMouseDown", function(self) if self:IsEnabled() then self.label:SetPoint("CENTER", 0, -1) end end)
    b:SetScript("OnMouseUp", function(self) self.label:SetPoint("CENTER", 0, 0) end)
    -- sound before every click (PreClick stays even if OnClick is set again later)
    b:SetScript("PreClick", function(self) if self:GetScript("OnClick") and not ownSound[self] then K.UiSound(self.style == "primary" and "ui_confirm" or "ui_click") end end)
    if onClick then b:SetScript("OnClick", onClick) end
    function b:SetLabel(t) self.label:SetText(t) end
    if K.SkinButton then K.SkinButton(b, base) end
    -- Glas 2026: main button in full accent color + bright gloss on top (all buttons)
    local th = K.CurrentTheme and K.CurrentTheme()
    if th and th.orbs then
        if style == "primary" then
            base = C.accent
            col(b.bg, base)
            if b.skinFill then K.SkinFill(b, base) end
        end
        b.sheen = b:CreateTexture(nil, "ARTWORK", nil, 1)
        b.sheen:SetPoint("TOPLEFT", 2, -1) b.sheen:SetPoint("TOPRIGHT", -2, -1)
        b.sheen:SetHeight(math.max(4, math.floor((h or 24) / 2)))
        if not K.Gradient(b.sheen, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, style == "primary" and 0.16 or 0.06 }) then b.sheen:Hide() end
        if style == "primary" then
            b:SetScript("OnEnter", function(self)
                if not self:IsEnabled() then return end
                local a = C.accent
                col(self.bg, { math.min(1, a[1] * 1.15 + 0.06), math.min(1, a[2] * 1.15 + 0.06), math.min(1, a[3] * 1.15 + 0.06), 1 })
            end)
            b:SetScript("OnLeave", function(self) col(self.bg, C.accent) end)
        end
    end
    function b:SetEnabledState(on)
        self:SetEnabled(on)
        self:SetAlpha(on and 1 or 0.45)
    end
    -- 0.6.400: image button - hide all own surfaces except the image (gloss, old fill, border were visible behind it)
    if b.imgBtn then
        local keep = {}
        for _, list in pairs(b.imgBtn) do for _, t in ipairs(list) do keep[t] = true end end
        for _, rg in ipairs({ b:GetRegions() }) do
            if rg.GetObjectType and rg:GetObjectType() == "Texture" and not keep[rg] then   -- 0.6.424: also HIGHLIGHT (dark surface on hover)
                rg:SetAlpha(0)
                -- 0.6.418: reparent into a hidden frame - otherwise hover/design switch made the surface visible again
                K.imgBtnTrash = K.imgBtnTrash or CreateFrame("Frame")
                K.imgBtnTrash:Hide()
                pcall(rg.SetParent, rg, K.imgBtnTrash)
            end
        end
    end
    return b
end

-- close cross from two lines
-- arrow = true: up arrow (collapse) instead of cross
function K.CloseButton(parent, onClick, tip, arrow)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local lines = {}
    for i, rot in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local t = b:CreateTexture(nil, "ARTWORK")
        if arrow then
            t:SetSize(9, 1.5)
            t:SetPoint("CENTER", i == 1 and -3 or 3, 1)
        else
            t:SetSize(13, 1.5)
            t:SetPoint("CENTER")
        end
        col(t, C.muted)
        t:SetRotation(rot)
        lines[i] = t
    end
    b:SetScript("OnEnter", function(self)
        for _, t in ipairs(lines) do col(t, C.text) end
        local t = type(tip) == "function" and tip() or tip   -- text may depend on settings
        if t then K.ShowTip(self, t) end
    end)
    b:SetScript("OnLeave", function()
        for _, t in ipairs(lines) do col(t, C.muted) end
        GameTooltip:Hide()
    end)
    b:SetScript("PreClick", function(self) if self:GetScript("OnClick") then K.UiSound("ui_close") end end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- small text button ("+"), "x" becomes the cross
-- dropdown: button with arrow, click opens a list
-- items() returns { { key, text }, ... }; key == nil means "All"
local menu
local function menuFrame()
    if menu then return menu end
    menu = CreateFrame("Frame", "OasisDropMenu", UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    K.Fill(menu, C.raised)
    K.Border(menu, C.line)
    menu.rows = {}
    -- click outside closes
    menu.catcher = CreateFrame("Button", nil, UIParent)
    menu.catcher:SetAllPoints(UIParent)
    menu.catcher:SetFrameStrata("FULLSCREEN")
    menu.catcher:SetScript("OnClick", function() menu:Hide() end)
    menu.catcher:Hide()
    menu:SetScript("OnHide", function() menu.catcher:Hide() end)
    menu:Hide()
    return menu
end
-- menu on a button/row: items = { { text, fn, disabled, checked }, ... }, title optional
function K.ShowMenu(owner, items, title, minWidth)
    local m = menuFrame()
    if m:IsShown() and m.owner == owner then m:Hide() return end
    m.owner = owner
    for _, r in ipairs(m.rows) do r:Hide() end
    local list = {}
    if title then list[1] = { text = title, header = true } end
    for _, it in ipairs(items) do list[#list + 1] = it end
    local maxW = 0
    -- icons: if an entry has "icon", all rows get an icon column (text aligned)
    local anyIcon, anyChecked = false, false
    for _, it in ipairs(list) do
        if it.icon then anyIcon = true end
        if it.checked and not it.header then anyChecked = true end
    end
    for i, it in ipairs(list) do
        local r = m.rows[i]
        if not r then
            r = CreateFrame("Button", nil, m)
            r:SetHeight(20)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0.06)
            -- selected entry (0.5.920): tinted surface + thin accent edge on the left, like the active nav item
            r.sel = r:CreateTexture(nil, "BACKGROUND")
            r.sel:SetAllPoints()
            r.selBar = r:CreateTexture(nil, "ARTWORK")
            r.selBar:SetPoint("TOPLEFT")
            r.selBar:SetPoint("BOTTOMLEFT")
            r.selBar:SetWidth(2)
            r.text = K.Text(r, 12, C.text)
            r.text:SetPoint("LEFT", 10, 0)
            r.ic = r:CreateTexture(nil, "ARTWORK")
            r.ic:SetSize(14, 14)
            r.ic:SetPoint("LEFT", 9, 0)
            m.rows[i] = r
        end
        local pad = (anyIcon and not it.header) and 30 or 10
        r.text:ClearAllPoints()
        r.text:SetPoint("LEFT", pad, 0)
        if it.icon and not it.header then
            r.ic:SetTexture(it.icon)
            local ic = it.disabled and C.dim or (it.iconColor or C.muted)
            r.ic:SetVertexColor(ic[1], ic[2], ic[3], it.disabled and 0.6 or 1)
            r.ic:Show()
        else
            r.ic:Hide()
        end
        r.idx = i
        -- if the menu has a selection, the other entries recede slightly
        local c = (it.header and C.dim) or (it.disabled and C.dim) or ((anyChecked and not it.checked) and C.muted) or C.text
        r.text:SetTextColor(c[1], c[2], c[3])
        K.SetFontSafe(r.text, it.font or K.FONT, 12, "", K.FONT)
        r.text:SetText(it.text)
        local on = it.checked and not it.header
        r.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.14)
        r.selBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
        r.sel:SetShown(on and true or false)
        r.selBar:SetShown(on and true or false)
        maxW = math.max(maxW, r.text:GetStringWidth() + pad + 14)
        r:EnableMouse(not it.header and not it.disabled)
        r:SetScript("OnClick", function()
            K.UiSound("ui_select")
            m:Hide()
            if it.fn then it.fn() end
        end)
        r:Show()
    end
    -- 0.6.476: long menus scroll (mouse wheel) instead of sticking out of the screen; always within the visible area
    local screenH = (UIParent and UIParent:GetHeight()) or 768
    local vis = math.max(5, math.min(#list, math.floor((screenH * 0.7 - 8) / 20)))
    m.nList, m.vis, m.off = #list, vis, 0
    function m:Place()
        for i, r in ipairs(self.rows) do
            if r.idx and i <= self.nList then
                local on = i > self.off and i <= self.off + self.vis
                r:SetShown(on)
                if on then
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", 1, -4 - (i - 1 - self.off) * 20)
                    r:SetPoint("RIGHT", self, "RIGHT", -1, 0)
                end
            end
        end
        if self.more then self.more:SetShown(self.off + self.vis < self.nList) end
    end
    if not m.wheelSet then
        m.wheelSet = true
        m:EnableMouseWheel(true)
        m:SetScript("OnMouseWheel", function(self, d)
            local mx = math.max(0, self.nList - self.vis)
            self.off = math.max(0, math.min(mx, self.off - d * 3))
            self:Place()
        end)
        m.more = K.Text(m, 10, C.dim, "CENTER")
        m.more:SetPoint("BOTTOM", 0, 1)
        m.more:SetText("v")
        if m.SetClampedToScreen then m:SetClampedToScreen(true) end
    end
    for i = #list + 1, #m.rows do m.rows[i].idx = nil end
    m:Place()
    m:SetSize(math.max(minWidth or 150, maxW), vis * 20 + 8 + ((#list > vis) and 8 or 0))
    m:ClearAllPoints()
    if owner.isDropdown or not GetCursorPosition then
        m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    else
        local x, y = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale()
        m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / sc + 4, y / sc - 4)
    end
    m.catcher:Show()
    m:Show()
end

function K.Dropdown(parent, w, label, items, getValue, onPick)
    local b = K.Button(parent, "", w, 24, "ghost")
    b.isDropdown = true
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 10, 0)
    b.label:SetPoint("RIGHT", -20, 0)
    b.label:SetJustifyH("LEFT")
    b.arrow = K.Text(b, 10, C.dim, "RIGHT")
    b.arrow:SetPoint("RIGHT", -8, 0)
    b.arrow:SetText("v")
    function b:Update()
        local v, text = getValue(), L["All"]
        for _, it in ipairs(items()) do if it.key == v then text = it.text end end
        self.label:SetText((v ~= nil and K.hex(C.accent) or "|cffa3a3a8") .. label .. ":|r " .. text)
        K.SetBorderColor(self, v ~= nil and C.accent2 or C.line)
    end
    b:SetScript("OnClick", function(self)
        local cur = getValue()
        local list = { { text = L["All"], checked = cur == nil, fn = function() onPick(nil) self:Update() end } }
        for _, it in ipairs(items()) do
            list[#list + 1] = { text = it.text, checked = it.key == cur, fn = function() onPick(it.key) self:Update() end }
        end
        K.ShowMenu(self, list, nil, w)
    end)
    b:Update()
    return b
end

-- monochrome icon (Media\\icons), tinted instead of a WoW icon
function K.Glyph(parent, size, path, color)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    if path then t:SetTexture(path) end
    color = color or C.muted
    t:SetVertexColor(color[1], color[2], color[3])
    liveGlyph[t] = color
    return t
end
function K.IconButton(parent, glyph, size, onClick, tip)
    if glyph == "X" or glyph == "x" then
        local b = K.CloseButton(parent, onClick, tip)
        b:SetSize(size or 18, size or 18)
        return b
    end
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 20, size or 20)
    b.label = K.Text(b, (size or 20) - 4, C.muted, "CENTER")
    b.label:SetPoint("CENTER")
    b.label:SetText(glyph)
    b:SetScript("OnEnter", function(self)
        self.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        if tip then K.ShowTip(self, tip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        GameTooltip:Hide()
    end)
    b:SetScript("PreClick", function(self) if self:GetScript("OnClick") and not ownSound[self] then K.UiSound("ui_click") end end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end
-- button plays a sound itself (listen/preview): no click sound before it (0.5.662)
function K.NoUiSound(b) if b then ownSound[b] = true end return b end

------------------------------------------------------------------------
-- tabs (filter), width adapts to the text
------------------------------------------------------------------------
-- opts (optional): { size = font size, pad = padding }
function K.Segments(parent, items, onChange, w, opts)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(24)
    f.buttons = {}
    local x = 0
    local size, pad = opts and opts.size or 13, opts and opts.pad or 22
    for _, it in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b.label = K.Text(b, size, C.muted, "CENTER")
        b.label:SetPoint("CENTER", 0, 1)
        b.label:SetText(it.text)
        local bw = math.max(opts and 36 or 48, b.label:GetStringWidth() + pad)
        b:SetSize(bw, 24)
        b:SetPoint("LEFT", x, 0)
        x = x + bw + 2
        b.under = b:CreateTexture(nil, "ARTWORK")
        col(b.under, C.accent)
        b.under:SetPoint("BOTTOMLEFT", 6, 0)
        b.under:SetPoint("BOTTOMRIGHT", -6, 0)
        b.under:SetHeight(2)
        b.key = it.key
        ownSound[b] = true
        b:SetScript("OnClick", function() K.UiSound("ui_select") f:Select(it.key, true) end)
        b:SetScript("OnEnter", function(self) if f.value ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end end)
        b:SetScript("OnLeave", function(self) if f.value ~= self.key then self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end end)
        f.buttons[#f.buttons + 1] = b
    end
    f:SetWidth(x)
    -- 0.6.536: fit into maxW - visible buttons only, shrink spacing first, then font (guild leadership stuck out on the right)
    function f:Fit(maxW)
        if not maxW or maxW <= 0 then return end
        local vis = {}
        for _, b in ipairs(self.buttons) do if b:IsShown() then vis[#vis + 1] = b end end
        local function total(sz, pd)
            local t = 0
            for _, b in ipairs(vis) do if not b.face then b.face, _, b.fflags = b.label:GetFont() end if b.face then b.label:SetFont(b.face, sz, b.fflags or "") end t = t + math.max(30, b.label:GetStringWidth() + pd) + 2 end
            return t
        end
        local sz, pd = size, pad
        while total(sz, pd) > maxW and pd > 10 do pd = pd - 2 end
        while total(sz, pd) > maxW and sz > 10 do sz = sz - 1 end
        local xx = 0
        for _, b in ipairs(vis) do
            local bw = math.max(30, b.label:GetStringWidth() + pd)
            b:SetWidth(bw) b:ClearAllPoints() b:SetPoint("LEFT", xx, 0)
            xx = xx + bw + 2
        end
        self:SetWidth(xx)
    end
    function f:Select(key, user)
        self.value = key
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            b.under:SetShown(on)
            local c = on and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3])
        end
        if user and onChange then onChange(key) end
        if user then K.TabAnim(self, key) end
        if user and K.OnSaved then pcall(K.OnSaved) end
    end
    f:Select(items[1].key)
    return f
end

------------------------------------------------------------------------
-- Edit box
------------------------------------------------------------------------
function K.Input(parent, w, placeholder, onChange)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w or 180, 24)
    e:SetAutoFocus(false)
    e:SetFont(K.FONT, 13, "")
    track(e)
    e:SetTextColor(C.text[1], C.text[2], C.text[3])
    e:SetTextInsets(7, 7, 0, 0)
    e.bg = K.Fill(e, C.field)
    K.Border(e, C.line)
    if K.ApplySkin then K.ApplySkin(e, "field", C.field) end
    e.ph = K.Text(e, 13, C.dim)
    e.ph:SetPoint("LEFT", 7, 0)
    e.ph:SetPoint("RIGHT", -7, 0)
    e.ph:SetText(placeholder or "")
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if self.onEnter then self.onEnter(self:GetText()) end
    end)
    e:SetScript("OnEditFocusGained", function(self) K.SetBorderColor(self, C.accent2) end)
    e:SetScript("OnEditFocusLost", function(self) K.SetBorderColor(self, C.line) end)
    e:SetScript("OnTextChanged", function(self, user)
        self.ph:SetShown(self:GetText() == "")
        if user and onChange then onChange(self:GetText()) end
    end)
    return e
end

-- small field label
function K.Label(parent, text)
    local fs = K.Text(parent, 11, C.muted)
    fs:SetText(text)
    return fs
end

------------------------------------------------------------------------
-- Switch
------------------------------------------------------------------------
-- round rail (pill) from two circles + middle piece; :SetColor(r, g, b, a) - 0.5.556
local PILL_CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
function K.Pill(parent, w, h, layer)
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(w, h)
    layer = layer or "ARTWORK"
    p.l = p:CreateTexture(nil, layer) p.l:SetTexture(PILL_CIRCLE) p.l:SetSize(h, h) p.l:SetPoint("LEFT")
    p.r = p:CreateTexture(nil, layer) p.r:SetTexture(PILL_CIRCLE) p.r:SetSize(h, h) p.r:SetPoint("RIGHT")
    p.m = p:CreateTexture(nil, layer) p.m:SetTexture("Interface\\Buttons\\WHITE8X8")
    p.m:SetPoint("TOPLEFT", h / 2, 0) p.m:SetPoint("BOTTOMRIGHT", -h / 2, 0)
    function p:SetColor(r, g, b, a)
        for _, t in ipairs({ self.l, self.r, self.m }) do t:SetVertexColor(r, g, b, a or 1) end
    end
    return p
end
function K.KnobCircle(parent, size)
    local t = parent:CreateTexture(nil, "OVERLAY", nil, 2)
    t:SetTexture(PILL_CIRCLE)
    t:SetSize(size, size)
    return t
end
function K.Toggle(parent, label, getter, setter, desc)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(380, desc and 38 or 24)
    local track = CreateFrame("Frame", nil, f)
    track:SetSize(30, 16)
    track:SetPoint("TOPLEFT", 0, -3)
    -- Classic: Blizzard checkbox instead of slide switch
    local sk = K.Skin and K.Skin("toggle")
    local round = not (sk and sk.check)
    local knob
    if round then
        -- 0.5.556: round switch (pill + circle knob), slides smoothly
        track.pill = K.Pill(track, 30, 16)
        track.pill:SetAllPoints()
        knob = K.KnobCircle(track.pill, 12)   -- on the pill, otherwise the pill lies above it
    else
        track.bg = K.Fill(track, C.field)
        K.Border(track, C.line)
        knob = track:CreateTexture(nil, "OVERLAY")
        knob:SetSize(10, 10)
        if K.ApplySkin then K.ApplySkin(track, "toggle", C.field) end
    end
    if sk and sk.check then
        track:SetAlpha(0)
        f.cb = f:CreateTexture(nil, "ARTWORK")
        f.cb:SetTexture("Interface\\Buttons\\UI-CheckBox-Up")
        f.cb:SetSize(24, 24)
        f.cb:SetPoint("TOPLEFT", track, "TOPLEFT", 0, 4)
        f.cbCheck = f:CreateTexture(nil, "OVERLAY")
        f.cbCheck:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        f.cbCheck:SetAllPoints(f.cb)
        f.cbHl = f:CreateTexture(nil, "HIGHLIGHT")
        f.cbHl:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        f.cbHl:SetBlendMode("ADD")
        f.cbHl:SetAllPoints(f.cb)
    end
    f.lbl = K.Text(f, 13, C.text)
    f.lbl:SetPoint("TOPLEFT", track, "TOPRIGHT", 10, -1)
    f.lbl:SetText(label)
    if desc then
        f.desc = K.Text(f, 11, C.muted)
        f.desc:SetPoint("TOPLEFT", f.lbl, "BOTTOMLEFT", 0, -3)
        f.desc:SetText(desc)
    end
    function f:Refresh()
        local v = getter()
        if round then
            local c = v and C.accent2 or { 0.22, 0.22, 0.25 }
            track.pill:SetColor(c[1], c[2], c[3], 1)
            local kc = v and { 1, 1, 1 } or { 0.62, 0.62, 0.66 }
            knob:SetVertexColor(kc[1], kc[2], kc[3], 1)
            local want = v and 1 or 0
            local from = self.kpos or want
            self.kpos = want
            local function place(q) knob:ClearAllPoints() knob:SetPoint("CENTER", track, "LEFT", 8 + 14 * q, 0) end
            if from ~= want and K.Tween and not (ns.db and ns.db.settings.noAnim) then
                K.Tween(knob, 0.14, function(t) place(from + (want - from) * t) end)
            else
                place(want)
            end
        else
            col(track.bg, v and C.accent2 or C.field)
            K.SetBorderColor(track, v and C.accent2 or C.line)
            col(knob, v and C.text or C.muted)
            knob:ClearAllPoints()
            knob:SetPoint(v and "RIGHT" or "LEFT", v and -3 or 3, 0)
        end
        if self.cbCheck then self.cbCheck:SetShown(v and true or false) end
    end
    ownSound[f] = true
    f:SetScript("OnClick", function(self)
        K.UiSound("ui_toggle")
        setter(not getter())
        self:Refresh()
        if K.OnSaved then pcall(K.OnSaved) end
        -- 0.5.563: small joy when toggling
        if round and K.Tween and not (ns.db and ns.db.settings.noAnim) then
            local on = getter() and true or false
            if on then
                if not self.rip then
                    self.rip = track:CreateTexture(nil, "BACKGROUND")
                    self.rip:SetTexture(PILL_CIRCLE)
                end
                local r = self.rip
                r:ClearAllPoints()
                r:SetPoint("CENTER", track, "LEFT", 22, 0)
                r:SetVertexColor(C.accent2[1], C.accent2[2], C.accent2[3])
                r:Show()
                K.Tween(r, 0.42, function(q)
                    local e = 1 - (1 - q) * (1 - q)
                    r:SetSize(12 + 26 * e, 12 + 26 * e)
                    r:SetAlpha(0.45 * (1 - q))
                end, function() r:Hide() end)
            end
            local a, t = on and C.accent2 or C.muted, C.text
            K.Tween(self.lbl, 0.5, function(q)
                self.lbl:SetTextColor(a[1] + (t[1] - a[1]) * q, a[2] + (t[2] - a[2]) * q, a[3] + (t[3] - a[3]) * q)
            end)
        end
    end)
    -- button grows slightly on hover
    if round then
        f:HookScript("OnEnter", function() if K.Tween and not (ns.db and ns.db.settings.noAnim) then K.Tween(knob, 0.1, function(q) knob:SetSize(12 + 2 * q, 12 + 2 * q) end) end end)
        f:HookScript("OnLeave", function() knob:SetSize(12, 12) end)
    end
    f:Refresh()
    return f
end

-- 0.5.563: equalizer - n bars, dance while active() is true, otherwise a quiet wave
function K.Equalizer(parent, n, w, h, color, active)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f.bars = {}
    local gap = 2
    local bw = math.max(1, (w - gap * (n - 1)) / n)
    for i = 1, n do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetColorTexture(color[1], color[2], color[3], 1)
        t:SetWidth(bw)
        t:SetPoint("BOTTOMLEFT", (i - 1) * (bw + gap), 0)
        t:SetHeight(2)
        f.bars[i] = t
        t.ph = i * 0.9 + math.random() * 2
        t.cur = 2
    end
    f.acc = 0
    f:SetScript("OnUpdate", function(self, el)
        self.acc = self.acc + el
        if self.acc < 0.033 then return end
        local dt = self.acc
        self.acc = 0
        local now = GetTime()
        local on = active and active() or false
        for i, t in ipairs(self.bars) do
            local want
            if on then
                want = h * (0.25 + 0.75 * math.abs(math.sin(now * (5 + i % 4) + t.ph)) * (0.55 + 0.45 * math.random()))
                t:SetAlpha(1)
            else
                want = 2 + (h * 0.14) * (0.5 + 0.5 * math.sin(now * 1.6 + i * 0.55))
                t:SetAlpha(0.55)
            end
            t.cur = t.cur + (want - t.cur) * math.min(1, dt * 14)
            t:SetHeight(math.max(1, t.cur))
        end
    end)
    return f
end

-- chip: on/off with color dot (e.g. roles)
function K.Chip(parent, text, color, getter, setter, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 76, 24)
    b.bg = K.Fill(b, C.raised)
    K.Border(b, C.line)
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetSize(6, 6)
    b.mark:SetPoint("LEFT", 8, 0)
    col(b.mark, color)
    b.label = K.Text(b, 12, C.muted, "LEFT")
    b.label:SetPoint("LEFT", 20, 0)
    b.label:SetText(text)
    function b:Refresh()
        local on = getter()
        col(self.bg, on and { color[1] * 0.25, color[2] * 0.25, color[3] * 0.25 } or C.raised)
        K.SetBorderColor(self, on and color or C.line)
        self.mark:SetAlpha(on and 1 or 0.35)
        local c = on and C.text or C.muted
        self.label:SetTextColor(c[1], c[2], c[3])
    end
    ownSound[b] = true
    b:SetScript("OnClick", function(self)
        K.UiSound("ui_toggle")
        setter(not getter())
        self:Refresh()
        if K.OnSaved then pcall(K.OnSaved) end
    end)
    b:Refresh()
    return b
end

------------------------------------------------------------------------
-- slider: getter/setter, min/max/step, fmt(v) for display, onRelease optional
------------------------------------------------------------------------
function K.Slider(parent, w, minV, maxV, step, getter, setter, fmt, onRelease)
    local f = CreateFrame("Button", nil, parent)
    f:SetSize(w or 180, 20)
    local track = f:CreateTexture(nil, "ARTWORK")
    col(track, C.field)
    track:SetHeight(4)
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", -46, 0)
    local fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
    col(fill, C.accent2)
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT")
    local knob = f:CreateTexture(nil, "OVERLAY")
    col(knob, C.text)
    knob:SetSize(8, 14)
    f.value = K.Text(f, 12, C.muted, "RIGHT")
    f.value:SetPoint("RIGHT", 0, 0)
    f.value:SetWidth(42)
    local function clamp(v)
        v = math.floor((v - minV) / step + 0.5) * step + minV
        return math.max(minV, math.min(maxV, v))
    end
    function f:Refresh()
        local v = getter() or minV
        local p = (maxV > minV) and (v - minV) / (maxV - minV) or 0
        local tw = math.max(1, track:GetWidth() or ((w or 180) - 46))
        fill:SetWidth(math.max(0.01, tw * p))
        fill:SetShown(p > 0)
        knob:ClearAllPoints()
        knob:SetPoint("CENTER", track, "LEFT", tw * p, 0)
        self.value:SetText(fmt and fmt(v) or tostring(v))
    end
    local function fromCursor()
        local x = GetCursorPosition() / f:GetEffectiveScale()
        local left = track:GetLeft() or 0
        local tw = math.max(1, track:GetWidth())
        local v = clamp(minV + (x - left) / tw * (maxV - minV))
        if v ~= getter() then setter(v) end
        f:Refresh()
    end
    f:SetScript("OnMouseDown", function(self)
        fromCursor()
        self:SetScript("OnUpdate", fromCursor)
    end)
    ownSound[f] = true
    f:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        if not onRelease then K.UiSound("ui_select") end   -- with onRelease usually a preview plays
        if onRelease then onRelease(getter()) end
        if K.OnSaved then pcall(K.OnSaved) end
    end)
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, d)
        setter(clamp((getter() or minV) + d * step))
        self:Refresh()
        if onRelease then onRelease(getter()) end
        if K.OnSaved then pcall(K.OnSaved) end
    end)
    f:SetScript("OnEnter", function() col(knob, C.accent) end)
    f:SetScript("OnLeave", function() col(knob, C.text) end)
    f:SetScript("OnSizeChanged", function(self) self:Refresh() end)
    f:Refresh()
    return f
end

-- color swatch (click selects), shows border when active
function K.Swatch(parent, c, size, onClick, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 20, size or 20)
    b.fill = b:CreateTexture(nil, "ARTWORK")
    b.fill:SetPoint("TOPLEFT", 3, -3)
    b.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    col(b.fill, c)
    K.Border(b, C.line)
    function b:SetColor(nc) col(self.fill, nc) end
    function b:SetActive(on) K.SetBorderColor(self, on and C.text or C.line) end
    b:SetScript("OnClick", function(self) if onClick then onClick(self) end end)
    if tip then
        b:SetScript("OnEnter", function(self) K.ShowTip(self, tip) end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

-- open WoW color picker (color wheel); onChange(hex) on every change, on cancel with the initial value
function K.OpenColorPicker(startHex, onChange, onCancel)
    local CPF = ColorPickerFrame
    if not CPF then return false end
    local c = K.FromHex(startHex) or C.accent
    local function current()
        local r, g, b = CPF:GetColorRGB()
        return K.ToHex({ r, g, b })
    end
    local function cancel() if onCancel then onCancel() else onChange(startHex or "") end end
    -- while the picker is open: only recolor live, rebuild only on close (otherwise everything twitches)
    K.pickerOpen = true
    if not CPF.oasisHooked then
        CPF.oasisHooked = true
        CPF:HookScript("OnHide", function()
            if not K.pickerOpen then return end
            K.pickerOpen = false
            if K.onPickerClosed then pcall(K.onPickerClosed) end
        end)
    end
    if CPF.SetupColorPickerAndShow then
        CPF:SetupColorPickerAndShow({
            r = c[1], g = c[2], b = c[3], hasOpacity = false,
            swatchFunc = function() onChange(current()) end,
            cancelFunc = cancel,
        })
    else
        CPF.hasOpacity = false
        CPF.previousValues = { c[1], c[2], c[3] }
        CPF.func = function() onChange(current()) end
        CPF.cancelFunc = cancel
        CPF:SetColorRGB(c[1], c[2], c[3])
        CPF:Hide()
        CPF:Show()
    end
    return true
end

-- "Color picker" button with color preview
-- getRaw (optional): stored value returned on "Cancel" (e.g. "" = same as the guild);
-- if getRaw returns a FUNCTION, it is called on cancel (e.g. restores several settings)
function K.ColorPickButton(parent, getHex, onChange, label, getRaw)
    local b = K.Button(parent, label or L["Color picker …"], 120, 24, "ghost", function(_, btn)
        if btn == "RightButton" then return end   -- right-click = own special function (e.g. reset)
        local raw
        if getRaw then raw = getRaw() else raw = getHex() end
        K.OpenColorPicker(getHex(), onChange, function()
            if type(raw) == "function" then raw() else onChange(raw) end
        end)
    end)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 26, 0)
    b.prev = b:CreateTexture(nil, "ARTWORK")
    b.prev:SetSize(12, 12)
    b.prev:SetPoint("LEFT", 8, 0)
    function b:Update()
        local c = K.FromHex(getHex()) or C.accent
        self.prev:SetColorTexture(c[1], c[2], c[3], 1)
    end
    b:Update()
    return b
end

------------------------------------------------------------------------
-- activity rings like on a smartwatch: three thick rings with progress (cooldown swipe on
-- ring texture), dark track, glowing cap at the end, above 100 % the ring keeps going (second lap brighter)
-- K.ActivityRings(parent, size, colors) -> f; f:Set({r1, r2, r3}, animated)
------------------------------------------------------------------------
local RING_TEX = { "ring_a", "ring_b", "ring_c" }
local RING_SCALE = { 1, 0.74, 0.48 }
function K.ActivityRings(parent, size, colors)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.rings = {}
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\ember")
    f.glow:SetBlendMode("ADD")
    f.glow:SetSize(size * 1.5, size * 1.5)
    f.glow:SetPoint("CENTER")
    f.glow:SetAlpha(0)
    local canSwipe = CreateFrame and pcall(function()
        local t = CreateFrame("Cooldown", nil, f)
        if not (t.SetSwipeTexture and t.SetCooldown) then error("x") end
        t:Hide()
    end)
    for i = 1, 3 do
        local c = colors[i]
        local s = math.floor(size * RING_SCALE[i] + 0.5)
        local path = ns.MEDIA .. RING_TEX[i]
        local r = { c = c, size = s }
        r.track = f:CreateTexture(nil, "BORDER")
        r.track:SetTexture(path)
        r.track:SetSize(s, s)
        r.track:SetPoint("CENTER")
        r.track:SetVertexColor(c[1], c[2], c[3], 0.16)   -- subtle track in ring color instead of a dark disc
        if canSwipe then
            local cd = CreateFrame("Cooldown", nil, f)
            cd:SetSize(s, s)
            cd:SetPoint("CENTER")
            cd:SetSwipeTexture(path)
            cd:SetSwipeColor(c[1], c[2], c[3], 1)
            if cd.SetDrawEdge then cd:SetDrawEdge(false) end
            if cd.SetDrawBling then cd:SetDrawBling(false) end
            if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
            if cd.SetReverse then cd:SetReverse(true) end
            cd.noCooldownCount = true
            cd:SetFrameLevel(f:GetFrameLevel() + i)
            r.cd = cd
            -- second lap (> 100 %): brighter, lies on top
            local cd2 = CreateFrame("Cooldown", nil, f)
            cd2:SetSize(s, s)
            cd2:SetPoint("CENTER")
            cd2:SetSwipeTexture(path)
            cd2:SetSwipeColor(math.min(1, c[1] + 0.35), math.min(1, c[2] + 0.35), math.min(1, c[3] + 0.35), 1)
            if cd2.SetDrawEdge then cd2:SetDrawEdge(false) end
            if cd2.SetDrawBling then cd2:SetDrawBling(false) end
            if cd2.SetHideCountdownNumbers then cd2:SetHideCountdownNumbers(true) end
            if cd2.SetReverse then cd2:SetReverse(true) end
            cd2.noCooldownCount = true
            cd2:SetFrameLevel(f:GetFrameLevel() + i + 3)
            r.cd2 = cd2
        else
            -- fallback without swipe: ring simply brighter per progress
            r.fill = f:CreateTexture(nil, "ARTWORK")
            r.fill:SetTexture(path)
            r.fill:SetSize(s, s)
            r.fill:SetPoint("CENTER")
        end
        -- cap at the end (glowing dot)
        r.cap = CreateFrame("Frame", nil, f)
        r.cap:SetSize(1, 1)
        r.cap:SetFrameLevel(f:GetFrameLevel() + 8)
        r.capT = r.cap:CreateTexture(nil, "OVERLAY")
        r.capT:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        local thick = math.max(4, math.floor(s * ({ 29, 39, 60 })[i] / 256 + 0.5))
        r.capT:SetSize(thick, thick)
        r.capT:SetPoint("CENTER")
        r.capT:SetVertexColor(math.min(1, c[1] + 0.25), math.min(1, c[2] + 0.25), math.min(1, c[3] + 0.25), 1)
        r.radius = s / 2 - thick / 2
        f.rings[i] = r
    end
    local D = 1000
    local function setRing(r, v)
        v = math.max(0, v or 0)
        local first, second = math.min(1, v), math.max(0, math.min(1, v - 1))
        if r.cd then
            local now = GetTime()
            if first <= 0.001 then r.cd:Hide() else
                r.cd:Show()
                r.cd:SetCooldown(now - first * D, D)
                if r.cd.Pause then r.cd:Pause() end
            end
            if second <= 0.001 then r.cd2:Hide() else
                r.cd2:Show()
                r.cd2:SetCooldown(now - second * D, D)
                if r.cd2.Pause then r.cd2:Pause() end
            end
        elseif r.fill then
            r.fill:SetVertexColor(r.c[1], r.c[2], r.c[3], 0.25 + 0.75 * first)
        end
        local a = (v % 1 == 0 and v > 0) and 0 or (v % 1) * 2 * math.pi
        if v >= 1 and v % 1 == 0 then a = 0 end
        r.cap:ClearAllPoints()
        r.cap:SetPoint("CENTER", f, "CENTER", r.radius * math.sin(a), r.radius * math.cos(a))
        r.cap:SetShown(v > 0.02)
    end
    function f:Set(vals, anim)
        self.vals = vals
        local full = (vals[1] or 0) >= 1 and (vals[2] or 0) >= 1 and (vals[3] or 0) >= 1
        self.glow:SetVertexColor(colors[1][1], colors[1][2], colors[1][3])
        self.glow:SetAlpha(full and 0.35 or 0)
        local noAnim = ns.db and ns.db.settings and ns.db.settings.noAnim
        if anim and not noAnim and K.Tween then
            K.Tween(self, 1.1, function(q)
                local e = 1 - (1 - q) ^ 3
                for i, r in ipairs(self.rings) do setRing(r, (vals[i] or 0) * e) end
            end, function() for i, r in ipairs(self.rings) do setRing(r, vals[i] or 0) end end)
        else
            for i, r in ipairs(self.rings) do setRing(r, vals[i] or 0) end
        end
    end
    -- swipe state only stays paused while visible; set again when shown again
    f:SetScript("OnShow", function(self) if self.vals then self:Set(self.vals, false) end end)
    return f
end

-- arrow up/down in the edit box: recall recently sent texts.
-- getList() returns the list NEWEST FIRST. OnArrowPressed doesn't fire in every client -> additionally
-- OnKeyDown (double trigger within 50 ms is ignored).
function K.InputHistory(eb, getList)
    if not eb then return end
    if eb.SetAltArrowKeyMode then pcall(eb.SetAltArrowKeyMode, eb, false) end
    local function step(self, key)
        if key ~= "UP" and key ~= "DOWN" then return end
        local now = GetTime()
        if self.histAt and now - self.histAt < 0.05 then return end
        self.histAt = now
        local list = getList() or {}
        if #list == 0 then return end
        if key == "UP" then
            self.histIdx = math.min(#list, (self.histIdx or 0) + 1)
        else
            self.histIdx = (self.histIdx or 1) - 1
            if self.histIdx < 1 then self.histIdx = nil self:SetText("") return end
        end
        self:SetText(list[self.histIdx] or "")
        self:SetCursorPosition(#(self:GetText() or ""))
    end
    eb:HookScript("OnArrowPressed", step)
    eb:HookScript("OnKeyDown", step)
    eb:HookScript("OnEscapePressed", function(self) self.histIdx = nil end)
    eb:HookScript("OnEditFocusLost", function(self) self.histIdx = nil end)
end

-- badge "raid leader only": small plaque with crown + tooltip saying who that is and where to set it.
-- small = crown only (for tight spots)
function K.LeadTag(parent, small)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(16)
    f.bg = K.Fill(f, { C.amber[1] * 0.18, C.amber[2] * 0.18, C.amber[3] * 0.18, 0.95 })
    K.Border(f, { C.amber[1] * 0.6, C.amber[2] * 0.6, C.amber[3] * 0.6, 1 })
    f.ic = K.Glyph(f, 11, ns.MEDIA .. "icons\\admin", C.amber)
    f.ic:SetPoint("LEFT", 4, 0)
    f.t = K.Text(f, 9, C.amber)
    f.t:SetPoint("LEFT", f.ic, "RIGHT", 3, 0)
    f.t:SetText(small and "" or K.Upper(L["Raid leaders"]))
    f:SetWidth(small and 19 or (f.t:GetStringWidth() + 24))
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local ok = ns.Admin and ns.Admin.IsRaidLead and ns.Admin.IsRaidLead()
        K.ShowTip(self, { L["Raid leader only"],
            L["Raid leaders and assistants are set by the guild leadership (crown > modules > Raids & Loot). In a running raid the raid leader and assistants count too."],
            ok and ("|cff66db9e" .. L["You have these rights."] .. "|r") or ("|cffe8b44a" .. L["You don't have these rights - view only."] .. "|r") })
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return f
end

------------------------------------------------------------------------
-- Locks: areas/buttons normal members may not use stay visible,
-- are dimmed and say who may. The permission check in the logic stays unchanged.
------------------------------------------------------------------------
local LOCK_ICON = "Interface\\PetBattles\\PetBattle-LockIcon"
local FROST_TEX = "Interface\\AddOns\\Oasis\\Media\\frost"   -- noise tile for frosted glass (K.Lock)
local BLUR_TEX = { "Interface\\AddOns\\Oasis\\Media\\blurpage", "Interface\\AddOns\\Oasis\\Media\\blurpage2" }  -- blurred page mock-ups
local locks = setmetatable({}, { __mode = "k" })
local lockBtns = setmetatable({}, { __mode = "k" })
-- predefined reasons (title, subline)
K.LOCK_WHO = {
    raidlead = { "Raid leaders only" },
    raidassist = { "Raid leaders & raid assistants only" },
    officer = { "Officers only" },
    lead = { "Guild leadership and officers only" },
    grouplead = { "Group leader and assistants only" },
    rank = { "Your guild rank can't do this" },
}
local function lockAllowed(check)
    -- developers see locked pages open only in test mode (otherwise locked like everyone: the developer
    -- switch is account-wide, on alts without rights the page was open but empty - 08.10.)
    if ns.Admin and ns.Admin.TestMode and ns.Admin.TestMode() then return true end
    if not check then return false end
    local ok, r = pcall(check)
    return ok and r and true or false
end
local function lockTexts(who, text, sub)
    local d = who and K.LOCK_WHO[who]
    return text or (d and L[d[1]]) or L["Guild leadership and officers only"], sub or (d and d[2] and L[d[2]]) or nil
end
-- K.Lock(frame, { check = fn -> allowed?, who = "raidlead"|"officer"|"lead"|..., text = , sub = , compact = true,
--                 top = px (lock starts here, header/tabs above stay sharp), keep = { frames that stay visible } })
function K.Lock(frame, opts)
    opts = opts or {}
    local o = CreateFrame("Frame", nil, frame)
    if opts.top then
        o:SetPoint("TOPLEFT", 0, -opts.top)
        o:SetPoint("BOTTOMRIGHT")
    else
        o:SetAllPoints(frame)
    end
    o.keep = {}
    for _, k in ipairs(opts.keep or {}) do o.keep[k] = true end
    o:SetFrameLevel((frame:GetFrameLevel() or 1) + 60)
    o:EnableMouse(true)
    if o.EnableMouseWheel then o:EnableMouseWheel(true) end
    o:SetScript("OnMouseWheel", function() end)
    o:SetScript("OnMouseDown", function() end)
    -- "Blurred": WoW can't blur -> the real content is hidden (SetLocked, alpha 0)
    -- and instead a pre-rendered, heavily blurred page mock-up is shown (Media\\blurpage*.tga),
    -- aspect ratio via TexCoord crop, slightly accent-tinted, vignette at the edges
    local bc = C.bg or { 0.07, 0.07, 0.08 }
    o.bg = o:CreateTexture(nil, "BACKGROUND")
    o.bg:SetAllPoints()
    o.bg:SetColorTexture(bc[1], bc[2], bc[3], 1)
    -- variant per page deterministic (name/rights key/text)
    local key = (frame.GetName and frame:GetName()) or opts.variant or ((opts.who or "") .. (opts.text or ""))
    local hsum = 0
    for i = 1, #key do hsum = hsum + key:byte(i) * i end
    o.seed = hsum
    o.blur = o:CreateTexture(nil, "BACKGROUND", nil, 1)
    o.blur:SetAllPoints()
    o.blur:SetTexture(hsum % 2 == 0 and BLUR_TEX[1] or BLUR_TEX[2])
    o.blur:SetAlpha(opts.compact and 0.85 or 1)
    o.tint = o:CreateTexture(nil, "BACKGROUND", nil, 2)
    o.tint:SetAllPoints()
    local ac = C.accent or { 1, 0.07, 0 }
    o.tint:SetColorTexture(ac[1], ac[2], ac[3], 0.035)
    o.veils = {}
    local nz = o:CreateTexture(nil, "BACKGROUND", nil, 3)
    nz:SetAllPoints()
    if not pcall(nz.SetTexture, nz, FROST_TEX, "REPEAT", "REPEAT") then nz:SetTexture(FROST_TEX) end
    if nz.SetHorizTile then pcall(nz.SetHorizTile, nz, true) pcall(nz.SetVertTile, nz, true) end
    nz:SetAlpha(0.03)
    nz.off = 0.37
    o.veils[1] = nz
    -- vignette: four soft edge gradients to dark
    o.vig = {}
    local va = opts.compact and 0.45 or 0.6
    local dk = { bc[1] * 0.5, bc[2] * 0.5, bc[3] * 0.5 }
    for i, s in ipairs({ { "TOPLEFT", "TOPRIGHT", "VERTICAL", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", "VERTICAL", true },
                         { "TOPLEFT", "BOTTOMLEFT", "HORIZONTAL", true }, { "TOPRIGHT", "BOTTOMRIGHT", "HORIZONTAL", false } }) do
        local t = o:CreateTexture(nil, "BORDER")
        t:SetPoint(s[1]) t:SetPoint(s[2])
        t.horiz = s[3] == "HORIZONTAL"
        t:SetColorTexture(1, 1, 1, 1)
        -- gradient: min = left/bottom, max = right/top
        local edgeMin = s[4]
        local c0 = { dk[1], dk[2], dk[3], edgeMin and va or 0 }
        local c1 = { dk[1], dk[2], dk[3], edgeMin and 0 or va }
        if not K.Gradient(t, s[3], c0, c1) then t:SetColorTexture(dk[1], dk[2], dk[3], va * 0.3) end
        o.vig[i] = t
    end
    -- card (large locks only): shadow, accent top edge, lock in accent color with soft glow.
    -- IMPORTANT: lock/texts are attached to the card (an own frame would otherwise lie ABOVE o's regions and dim them)
    local ac2 = C.accent or { 1, 0.07, 0 }
    local holder = o
    if not opts.compact then
        o.card = CreateFrame("Frame", nil, o)
        o.card:SetSize(400, 140)
        o.card:SetPoint("CENTER", 0, 0)
        o.card.shadow = {}
        for i, s in ipairs({ 14, 9, 5, 2 }) do
            local t = o.card:CreateTexture(nil, "BACKGROUND", nil, -8 + i)
            t:SetPoint("TOPLEFT", -s, s - 4) t:SetPoint("BOTTOMRIGHT", s, -s - 6)
            t:SetColorTexture(0, 0, 0, 0.10 + i * 0.03)
            o.card.shadow[i] = t
        end
        o.card.bg = o.card:CreateTexture(nil, "BACKGROUND", nil, 0)
        o.card.bg:SetAllPoints()
        o.card.bg:SetColorTexture(bc[1] * 1.4, bc[2] * 1.4, bc[3] * 1.5, 0.96)
        o.card.sheen = o.card:CreateTexture(nil, "BACKGROUND", nil, 1)
        o.card.sheen:SetPoint("TOPLEFT") o.card.sheen:SetPoint("TOPRIGHT")
        o.card.sheen:SetHeight(50)
        if not K.Gradient(o.card.sheen, "VERTICAL", { ac2[1], ac2[2], ac2[3], 0 }, { ac2[1], ac2[2], ac2[3], 0.10 }) then o.card.sheen:Hide() end
        if K.Border then K.Border(o.card, { 1, 1, 1, 0.12 }) end
        o.card.edge = o.card:CreateTexture(nil, "BORDER")
        o.card.edge:SetPoint("TOPLEFT", 3, 0) o.card.edge:SetPoint("TOPRIGHT", -3, 0)
        o.card.edge:SetHeight(2)
        o.card.edge:SetColorTexture(ac2[1], ac2[2], ac2[3], 1)
        -- "rounded": pull back corner pixels
        for _, p in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
            local t = o.card:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetSize(2, 2) t:SetPoint(p)
            t:SetColorTexture(bc[1], bc[2], bc[3], 0.85)
        end
        holder = o.card
        -- glow behind the lock (gentle pulse, off with noAnim)
        o.glowTex = o.card:CreateTexture(nil, "ARTWORK", nil, 0)
        o.glowTex:SetSize(78, 78)
        o.glowTex:SetTexture("Interface\\AddOns\\Oasis\\Media\\shine")
        o.glowTex:SetVertexColor(ac2[1], ac2[2], ac2[3])
        o.glowTex:SetAlpha(0.35)
        if o.glowTex.SetBlendMode then o.glowTex:SetBlendMode("ADD") end
    end
    o.ic = holder:CreateTexture(nil, "ARTWORK", nil, 2)
    o.ic:SetSize(opts.compact and 18 or 34, opts.compact and 18 or 34)
    o.ic:SetTexture(opts.icon or LOCK_ICON)
    o.ic:SetDesaturated(true)
    if opts.compact then o.ic:SetVertexColor(1, 1, 1)
    else o.ic:SetVertexColor(math.min(1, ac2[1] + 0.15), math.min(1, ac2[2] + 0.25), math.min(1, ac2[3] + 0.2)) end
    -- contrast: title white and large, subline bright
    o.t = K.Text(holder, opts.compact and 11 or 17, { 1, 1, 1, 1 }, "CENTER")
    o.s = K.Text(holder, opts.compact and 9 or 12, { 0.80, 0.82, 0.86, 1 }, "CENTER")
    for _, fs in ipairs({ o.t, o.s }) do
        if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) fs:SetShadowColor(0, 0, 0, 0.9) end
        fs:SetWordWrap(true)
        if fs.SetAlpha then fs:SetAlpha(1) end
    end
    if opts.compact then
        o.ic:SetPoint("BOTTOM", o, "CENTER", 0, 4)
        o.t:SetPoint("TOP", o.ic, "BOTTOM", 0, -6)
    else
        o.ic:SetPoint("TOP", o.card, "TOP", 0, -18)
        o.glowTex:SetPoint("CENTER", o.ic, "CENTER", 0, 0)
        o.t:SetPoint("TOP", o.ic, "BOTTOM", 0, -10)
    end
    o.t:SetWidth(opts.compact and 60 or 360)
    o.s:SetPoint("TOP", o.t, "BOTTOM", 0, -6)
    o.s:SetWidth(opts.compact and 60 or 360)
    -- pulse: glow breathes slowly
    if o.glowTex and o.glowTex.CreateAnimationGroup then
        pcall(function()
            local ag = o.glowTex:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local a = ag:CreateAnimation("Alpha")
            a:SetFromAlpha(0.18) a:SetToAlpha(0.5) a:SetDuration(1.6)
            if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
            o.pulse = ag
        end)
    end
    function o:FitCard()
        if not self.card then return end
        local h = 18 + 34 + 10 + (self.t:GetStringHeight() or 20) + 6 + (self.s:GetStringHeight() or 0) + 20
        self.card:SetHeight(math.max(120, h))
    end
    o:SetScript("OnSizeChanged", function(self, w, h)
        local tw = math.max(40, math.min(opts.compact and 60 or 360, (w or 0) - (opts.compact and 16 or 60)))
        self.t:SetWidth(tw) self.s:SetWidth(tw)
        if self.card then self.card:SetWidth(math.min(400, math.max(160, (w or 400) - 24))) self:FitCard() end
        w, h = math.max(1, w or 1), math.max(1, h or 1)
        -- tile noise instead of stretching (128px tile)
        for _, t in ipairs(self.veils) do
            t:SetTexCoord(t.off, t.off + w / 128, t.off * 0.6, t.off * 0.6 + h / 128)
        end
        -- blur mock-up: crop with matching aspect ratio (don't distort);
        -- small areas show a crop from the middle/table, large ones the whole page
        local cw, ch = 1, 1
        if w >= h then ch = h / w else cw = w / h end
        local sc = (opts.compact or math.max(w, h) < 256) and math.max(0.35, math.max(w, h) / 512) or 1
        cw, ch = math.min(1, cw * sc), math.min(1, ch * sc)
        local fx, fy = ((self.seed or 0) % 7) / 6, ((self.seed or 0) % 5) / 4
        if sc < 1 then fy = 0.35 + fy * 0.5 end
        local x0, y0 = (1 - cw) * fx, (1 - ch) * fy
        self.blur:SetTexCoord(x0, x0 + cw, y0, y0 + ch)
        local vs = math.max(4, math.floor(math.min(w, h) * 0.18))
        for _, t in ipairs(self.vig) do if t.horiz then t:SetWidth(vs) else t:SetHeight(vs) end end
    end)
    o.check, o.opts = opts.check, opts
    function o:SetTexts(text, sub)
        local t, s = lockTexts(self.opts.who, text, sub)
        self.t:SetText(t)
        self.s:SetText((not self.opts.compact and s) or "")
        self:FitCard()
    end
    o:SetTexts(opts.text, opts.sub)
    -- compact: subline as tooltip
    o:SetScript("OnEnter", function(self)
        local t, s = lockTexts(self.opts.who, self.opts.text, self.opts.sub)
        K.ShowTip(self, s and { t, s } or t)
    end)
    o:SetScript("OnLeave", function() GameTooltip:Hide() end)
    function o:SetLocked(on, instant)
        on = on and true or false
        if self.locked == on and not instant then return end
        self.locked = on
        -- hide real content below (only siblings in the same frame, not locks themselves);
        -- the blur mock-up replaces it, on unlock the old alpha comes back
        local host = self:GetParent()
        if host and host.GetChildren then
            for _, c in ipairs({ host:GetChildren() }) do
                if c ~= self and not locks[c] and not self.keep[c] and c.SetAlpha and not (c.IsProtected and c:IsProtected()) then
                    if on then c.oasisLockA = c.oasisLockA or c:GetAlpha() or 1 c:SetAlpha(0)
                    elseif c.oasisLockA then c:SetAlpha(c.oasisLockA) c.oasisLockA = nil end
                end
            end
        end
        local still = ns.db and ns.db.settings.noAnim
        if self.pulse then
            if on and not still then pcall(self.pulse.Play, self.pulse) else pcall(self.pulse.Stop, self.pulse) end
        end
        if on then
            self:Show()
            -- always override running tweens (e.g. half fade-out), otherwise alpha gets stuck
            if instant or still then self:SetAlpha(1) K.Tween(self, 0.01, function() self:SetAlpha(1) end)
            else self:SetAlpha(0) K.Tween(self, 0.2, function(p) self:SetAlpha(p) end, function() self:SetAlpha(1) end) end
        elseif instant or still or not self:IsShown() then
            K.Tween(self, 0.01, function() end)
            self:SetAlpha(1)
            self:Hide()
        else
            K.Tween(self, 0.2, function(p) self:SetAlpha(1 - p) end, function() if not self.locked then self:Hide() end end)
        end
    end
    function o:Update(instant) self:SetLocked(not lockAllowed(self.check), instant) end
    frame:HookScript("OnShow", function() o:Update(true) end)
    locks[o] = true
    o.locked = nil
    o:Update(true)
    return o
end
-- lock button: gray, without effect, tooltip with reason. reason = text or key from K.LOCK_WHO
function K.LockButton(btn, checkFn, reason)
    if not btn then return end
    btn.lockCheck, btn.lockReason = checkFn, reason
    if not btn.lockWrapped then
        btn.lockWrapped = true
        btn.lockIc = btn:CreateTexture(nil, "OVERLAY")
        btn.lockIc:SetTexture(LOCK_ICON)
        btn.lockIc:SetSize(12, 12)
        btn.lockIc:SetPoint("RIGHT", -4, 0)
        btn.lockIc:Hide()
        local origSet = btn.SetEnabledState
        btn.SetEnabledState = function(self, on)
            self.wantOn = on
            local ok = not self.locked and on
            if origSet then origSet(self, ok) else self:SetEnabled(ok) self:SetAlpha(ok and 1 or 0.45) end
        end
        local click = btn:GetScript("OnClick")
        if click then btn:SetScript("OnClick", function(self, ...) if self.locked then return end return click(self, ...) end) end
        btn:HookScript("OnEnter", function(self)
            if not self.locked then return end
            local r = self.lockReason
            local t, s = lockTexts(type(r) == "string" and K.LOCK_WHO[r] and r or nil, (type(r) == "string" and not K.LOCK_WHO[r]) and r or nil)
            K.ShowTip(self, s and { t, s } or t)
        end)
        btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
        btn:HookScript("OnShow", function(self) K.UpdateLockButton(self) end)
    end
    lockBtns[btn] = true
    K.UpdateLockButton(btn)
    return btn
end
function K.UpdateLockButton(btn)
    if not btn or not btn.lockWrapped then return end
    local locked = not lockAllowed(btn.lockCheck)
    btn.locked = locked
    btn:SetEnabled(not locked and btn.wantOn ~= false)
    btn:SetAlpha(locked and 0.45 or ((btn.wantOn == false) and 0.45 or 1))
    btn.lockIc:SetShown(locked)
    for _, r in ipairs({ btn.ic, btn.icon, btn.glyph }) do if r and r.SetDesaturated then r:SetDesaturated(locked) end end
end
-- recheck all locks (rights have changed)
function K.RefreshLocks()
    for o in pairs(locks) do if o:GetParent() and o:GetParent():IsShown() then o:Update() end end
    for b in pairs(lockBtns) do K.UpdateLockButton(b) end
end
do
    local pending
    local function soon()
        if pending then return end
        pending = true
        ns.After(0.2, function() pending = false K.RefreshLocks() end)
    end
    for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE", "PARTY_LEADER_CHANGED" }) do ns.On(ev, soon) end
    ns.Listen("BRAND", soon)
end

-- "ff1200" <-> { r, g, b }
function K.FromHex(hex, fallback)
    hex = tostring(hex or ""):gsub("^#", ""):gsub("^|c", "")
    if #hex == 8 then hex = hex:sub(3) end
    if not hex:match("^%x%x%x%x%x%x$") then return fallback end
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255, 1 }
end
function K.ToHex(c) return ("%02x%02x%02x"):format(c[1] * 255 + 0.5, c[2] * 255 + 0.5, c[3] * 255 + 0.5) end

------------------------------------------------------------------------
-- virtual list with thin scrollbar
-- createRow(list, i) -> row ; updateRow(row, item, index)
------------------------------------------------------------------------
-- 0.5.625: is a list currently being scrolled? (expensive decorative animations pause meanwhile)
local listBusyAt = 0
function ns.ListBusy() return GetTime() - listBusyAt < 0.25 end
function K.List(parent, rowH, createRow, updateRow)
    local f = CreateFrame("Frame", nil, parent)
    f:SetClipsChildren(true)
    f.rowH = rowH
    f.rows, f.data, f.offset = {}, {}, 0
    f:EnableMouseWheel(true)

    local thumb = f:CreateTexture(nil, "OVERLAY")
    col(thumb, C.line)
    thumb:SetWidth(3)
    f.thumb = thumb

    f.empty = K.Text(f, 13, C.dim, "CENTER")
    f.empty:SetPoint("TOP", 0, -30)
    f.empty:SetPoint("LEFT", 20, 0)
    f.empty:SetPoint("RIGHT", -20, 0)
    f.empty:SetWordWrap(true)

    function f:Visible() return math.max(1, math.floor(self:GetHeight() / self.rowH)) end
    -- 0.5.618: smooth scrolling - pos = position in rows (with fractions), rows are shifted pixel-exactly
    -- by the remainder; offset (whole rows) is kept for callers that set it directly
    f.pos, f.target = 0, 0
    local function maxPos(self)
        local h = self:GetHeight() or 0
        return math.max(0, #self.data - h / self.rowH)
    end
    local function place(self)
        local frac = (self.pos - self.offset) * self.rowH
        local h = self:GetHeight() or 0
        for i, row in ipairs(self.rows) do
            local y = (i - 1) * self.rowH - frac
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -y)
            row:SetPoint("RIGHT", self, "RIGHT", -8, 0)
            if row.item and y >= h then row:Hide() elseif row.item then row:Show() end
        end
        local mp = maxPos(self)
        if mp > 0 then
            local th = math.max(20, h * h / (#self.data * self.rowH))
            thumb:SetHeight(th)
            thumb:ClearAllPoints()
            thumb:SetPoint("TOPRIGHT", 0, -((h - th) * math.min(1, self.pos / mp)))
            thumb:Show()
        else
            thumb:Hide()
        end
    end
    function f:Refresh(scrollOnly)
        -- offset set from outside (e.g. reset to 0): take over the position
        if self.offset ~= math.floor(self.pos) then self.pos, self.target = self.offset, self.offset end
        local mp = maxPos(self)
        if self.pos > mp then self.pos = mp end
        if self.target > mp then self.target = mp end
        if self.pos < 0 then self.pos = 0 end
        if self.target < 0 then self.target = 0 end
        self.offset = math.floor(self.pos)
        local vis = self:Visible()
        -- 0.5.620 only while scrolling: pass rows along instead of redrawing all (only newly visible ones are filled)
        if scrollOnly and #self.rows >= vis + 2 then
            local byIdx, free, order = {}, {}, {}
            for i = 1, vis + 2 do
                local r = self.rows[i]
                if r.item and r.index and not byIdx[r.index] then byIdx[r.index] = r else free[#free + 1] = r end
            end
            for i = 1, vis + 2 do
                local idx = self.offset + i
                local r = byIdx[idx]
                if r then byIdx[idx] = nil order[i] = r end
            end
            for _, r in pairs(byIdx) do free[#free + 1] = r end
            for i = 1, vis + 2 do
                if not order[i] then
                    local r = table.remove(free)
                    order[i] = r
                    local idx = self.offset + i
                    local item = self.data[idx]
                    if item then
                        r.item, r.index = item, idx
                        if r.stripe then r.stripe:SetShown(idx % 2 == 0) end
                        r:Show()
                        local t1 = ns.prof and debugprofilestop()
                        local ok, e = pcall(updateRow, r, item, idx)
                        if t1 and ns.prof then ns.prof.add(updateRow, "Listenzeile neu", debugprofilestop() - t1) end
                        if not ok then ns.err(L["List"], e) end
                    else
                        r.item, r.index = nil, nil
                        r:Hide()
                    end
                end
            end
            for i = 1, vis + 2 do self.rows[i] = order[i] end
            place(self)
            return
        end
        for i = 1, vis + 2 do
            local row = self.rows[i]
            if not row then
                row = createRow(self, i)
                row:SetHeight(self.rowH - 1)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * self.rowH)
                row:SetPoint("RIGHT", self, "RIGHT", -8, 0)
                self.rows[i] = row
            end
            local idx = self.offset + i
            local item = self.data[idx]
            if item then
                row.item, row.index = item, idx
                if row.stripe then row.stripe:SetShown(idx % 2 == 0) end
                row:Show()
                local ok, e = pcall(updateRow, row, item, idx)
                if not ok then ns.err(L["List"], e) end
            else
                row.item = nil
                row:Hide()
            end
        end
        for i = vis + 3, #self.rows do self.rows[i]:Hide() self.rows[i].item = nil end
        place(self)
        self.empty:SetShown(#self.data == 0)
    end
    function f:SetData(d)
        self.data = d or {}
        self:Refresh()
    end
    local function step(self, el)
        listBusyAt = GetTime()
        local t0 = ns.prof and debugprofilestop()
        local d = self.target - self.pos
        if math.abs(d) < 0.01 then
            self.pos = self.target
            self:SetScript("OnUpdate", nil)
        else
            self.pos = self.pos + d * math.min(1, el * 16)
        end
        if math.floor(self.pos) ~= self.offset then
            self.offset = math.floor(self.pos)
            self:Refresh(true)
        else
            place(self)
        end
        if t0 and ns.prof then ns.prof.add(updateRow, "Liste scrollen (je Bild)", debugprofilestop() - t0) end
    end
    f:SetScript("OnMouseWheel", function(self, delta)
        local mp = maxPos(self)
        self.target = math.max(0, math.min(mp, self.target - delta * 3))
        if ns.db and ns.db.settings.noAnim then
            self.pos = self.target
            self.offset = math.floor(self.pos)
            self:Refresh()
            return
        end
        self:SetScript("OnUpdate", step)
    end)
    f:SetScript("OnSizeChanged", function(self) self:Refresh() end)
    return f
end

-- default row
function K.Row(list)
    local r = CreateFrame("Button", nil, list)
    r.stripe = r:CreateTexture(nil, "BACKGROUND")
    r.stripe:SetAllPoints()
    r.stripe:SetColorTexture(1, 1, 1, 0.022)
    -- hover: brighten row clearly + accent bar on the left, so you can read row by row
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.08)
    -- no colored bar on the left on hover (brighten only)
    r.sel = r:CreateTexture(nil, "ARTWORK")
    col(r.sel, C.accent)
    r.sel:SetPoint("TOPLEFT")
    r.sel:SetPoint("BOTTOMLEFT")
    r.sel:SetWidth(2)
    r.sel:Hide()
    r.cols = {}
    function r:Col(key, x, w, size, color, justify)
        local fs = K.Text(self, size or 13, color, justify)
        fs:SetPoint("LEFT", x, 0)
        if w then fs:SetWidth(w) end
        self.cols[key] = fs
        return fs
    end
    return r
end

------------------------------------------------------------------------
-- key figure
------------------------------------------------------------------------
function K.StatCard(parent, label)
    local f = K.Panel(parent, C.panel)
    f:SetSize(150, 54)
    f.value = K.Title(f, 19, C.text)
    f.value:SetPoint("TOPLEFT", 12, -9)
    f.label = K.Text(f, 11, C.muted)
    f.label:SetPoint("BOTTOMLEFT", 12, 8)
    f.label:SetText(label)
    function f:Set(v) self.value:SetText(v) end
    return f
end

-- badge
function K.Badge(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(60, size or 17)
    f.bg = K.Fill(f, C.raised)
    f.text = K.Text(f, 11, C.text, "CENTER")
    f.text:SetPoint("CENTER", 0, 0)
    function f:Set(text, c)
        self.text:SetText(text)
        col(self.bg, { c[1] * 0.28, c[2] * 0.28, c[3] * 0.28 })
        self.text:SetTextColor(c[1] * 0.5 + 0.5, c[2] * 0.5 + 0.5, c[3] * 0.5 + 0.5)
        self:SetWidth(math.max(40, self.text:GetStringWidth() + 14))
    end
    return f
end

-- progress bar
function K.Bar(parent, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w or 100, h or 4)
    K.Fill(f, C.field)
    f.fill = f:CreateTexture(nil, "ARTWORK")
    col(f.fill, C.accent2)
    f.fill:SetPoint("TOPLEFT")
    f.fill:SetPoint("BOTTOMLEFT")
    -- 0.6.274: design with its own bar (skin "bar" = { track, fill }): track and fill as graphics
    local sb = K.Skin and K.Skin("bar")
    if sb and sb.track and sb.fill then
        for _, r in ipairs({ f:GetRegions() }) do if r ~= f.fill and r.SetColorTexture and r:GetDrawLayer() == "BACKGROUND" then r:Hide() end end
        local tr = f:CreateTexture(nil, "BACKGROUND", nil, 1)
        tr:SetAllPoints()
        tr:SetTexture(sb.track)
        f.skinTrack = tr
        f.fill:SetTexture(sb.fill)
        f.fill:SetVertexColor(1, 1, 1, 1)
    end
    function f:Set(p)
        p = math.max(0, math.min(1, p or 0))
        self.fill:SetWidth(math.max(0.01, self:GetWidth() * p))
        self.fill:SetShown(p > 0)
    end
    return f
end

------------------------------------------------------------------------
-- Tooltips
------------------------------------------------------------------------
function K.ShowTip(owner, lines, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    if type(lines) == "string" then
        GameTooltip:SetText(lines, 1, 1, 1, 1, true)
    else
        for i, l in ipairs(lines) do
            if i == 1 then GameTooltip:SetText(l, 1, 1, 1) else GameTooltip:AddLine(l, 0.8, 0.79, 0.86, true) end
        end
    end
    GameTooltip:Show()
end
function K.ItemTip(owner, link)
    if not link then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if ok then GameTooltip:Show() else GameTooltip:Hide() end
end

------------------------------------------------------------------------
-- notices (top center, stacking)
------------------------------------------------------------------------
local toastPool, toastActive = {}, {}
-- anchor of the notices: default top center; custom position = center of the first notice (settings.toastPos)
local toastAnchor
local function anchorFrame()
    if not toastAnchor then
        toastAnchor = CreateFrame("Frame", "OasisToastAnchor", UIParent)
        toastAnchor:SetSize(330, 50)
    end
    local pos = ns.db and ns.db.settings.toastPos
    toastAnchor:ClearAllPoints()
    if pos and pos.x then
        toastAnchor:SetPoint("CENTER", UIParent, "CENTER", pos.x, pos.y)
    else
        toastAnchor:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
    return toastAnchor, pos and pos.y and pos.y < 0   -- lower half: stack upwards
end
local function layoutToasts()
    local a, up = anchorFrame()
    local s = (ns.db and ns.db.settings.toastScale) or 1
    -- other frames in the stack (e.g. online popup) take the first slots
    local slot = 0
    for _, x in ipairs(K.toastExtra or {}) do
        if x:IsShown() then
            x:SetScale(s)
            x:ClearAllPoints()
            x:SetPoint("CENTER", a, "CENTER", 0, (up and 1 or -1) * slot * 68)
            slot = slot + 1
        end
    end
    -- spacing by actual height (long notices are taller)
    local off, prevH = slot * 68, nil
    for i, t in ipairs(toastActive) do
        t:SetScale(s)
        t:ClearAllPoints()
        local h = t:GetHeight() or 56
        if prevH then off = off + prevH / 2 + h / 2 + 6 end
        -- the first notice sits exactly where the sample notice was dropped
        t:SetPoint("CENTER", a, "CENTER", 0, (up and 1 or -1) * off)
        prevH = h
    end
end
K.LayoutToasts = layoutToasts

-- set notice position with the mouse: drag the sample notice
local mover
function K.ToastMover(onDone)
    if not mover then
        mover = CreateFrame("Frame", "OasisToastMover", UIParent)
        mover:SetSize(330, 50)
        mover:SetFrameStrata("FULLSCREEN_DIALOG")
        mover:SetMovable(true)
        mover:SetClampedToScreen(true)
        mover:EnableMouse(true)
        mover:RegisterForDrag("LeftButton")
        mover.bg = K.Fill(mover, C.panel)
        K.Border(mover, C.accent, 2)
        mover.title = K.Title(mover, 12, C.text)
        mover.title:SetPoint("TOPLEFT", 12, -9)
        mover.text = K.Text(mover, 11, C.muted)
        mover.text:SetPoint("TOPLEFT", mover.title, "BOTTOMLEFT", 0, -5)
        mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
        mover:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        local function close(accept)
            if accept then
                local x, y = mover:GetCenter()
                local ux, uy = UIParent:GetCenter()
                local s = mover:GetScale()
                ns.db.settings.toastPos = { x = math.floor(x * s - ux + 0.5), y = math.floor(y * s - uy + 0.5) }
            else
                ns.db.settings.toastPos = mover.prevPos
            end
            mover.closing = true
            mover:Hide()
            mover.closing = nil
            layoutToasts()
            if mover.onDone then mover.onDone() end
        end
        -- Apply / Cancel directly below the sample notice (move along when dragging)
        mover.ok = K.Button(mover, L["Apply"], 120, 24, "primary", function() close(true) end)
        mover.ok:SetPoint("TOPRIGHT", mover, "BOTTOMRIGHT", 0, -6)
        mover.cancel = K.Button(mover, L["Cancel"], 100, 24, "ghost", function() close(false) end)
        mover.cancel:SetPoint("RIGHT", mover.ok, "LEFT", -6, 0)
        -- Esc = Cancel
        ns.EscClose("OasisToastMover")
        mover:HookScript("OnHide", function(self)   -- hook: SetScript would remove the Esc hook
            if not self.closing then ns.db.settings.toastPos = self.prevPos layoutToasts() if self.onDone then self.onDone() end end
        end)
    end
    mover.onDone = onDone
    mover.prevPos = ns.db.settings.toastPos
    mover.title:SetText(L["Notification position"])
    mover.text:SetText(L["Drag it to the spot you want"])
    local s = (ns.db and ns.db.settings.toastScale) or 1
    mover:SetScale(s)
    local a = anchorFrame()
    local x, y = a:GetCenter()
    local ux, uy = UIParent:GetCenter()
    mover:ClearAllPoints()
    mover:SetPoint("CENTER", UIParent, "CENTER", ((x or ux) - ux) / s, ((y or uy) - uy) / s)
    mover:Show()
end
function K.Toast(title, text, color, onClick, sound, validUntil)
    -- notices often show foreign texts (names, titles, notes): sanitize and truncate centrally
    if ns.CleanText then
        if type(title) == "string" then title = ns.CleanText(title, 300) end
        if type(text) == "string" then text = ns.CleanText(text, 800) end
    end
    local event = sound or (ns.Sound and ns.Sound.TakeNext()) or "toast"
    if validUntil and ns.now() > validUntil then return end
    -- 0.6.405: the same notice (title + text) at most once per minute - no spamming
    K.toastSeen = K.toastSeen or {}
    local sig = tostring(title) .. "|" .. tostring(text)
    local nowT = (GetTime and GetTime()) or (ns.now and ns.now()) or 0
    if K.toastSeen[sig] and nowT - K.toastSeen[sig] < 60 then return end
    K.toastSeen[sig] = nowT
    if ns.db and not ns.db.settings.toasts then return end
    if ns.demoLoading then return end
    -- individual notice kinds turned off (Settings > Notices)
    local off = ns.db and ns.db.settings.toastOff
    if off and off[event] then return end
    -- 0.5.952: notices without their own kind (e.g. "Campfire reported") hidden individually - the title is remembered
    local mutedTitles = ns.db and ns.db.settings.toastMuted
    if mutedTitles and type(title) == "string" and mutedTitles[title] then return end
    -- hold back in combat and show afterwards
    if ns.db and ns.db.settings.toastHoldCombat and ns.inCombat() then
        validUntil = math.min(validUntil or math.huge, ns.now() + 15)
        K._held = K._held or {}
        if #K._held < 6 then K._held[#K._held + 1] = { title, text, color, onClick, event, validUntil = validUntil } end
        return
    end
    color = color or C.accent
    local t = table.remove(toastPool)
    if not t then
        t = CreateFrame("Button", nil, UIParent)
        t:SetSize(340, 56)
        t:SetFrameStrata("DIALOG")
        t.fillTex = K.Fill(t, { 0.04, 0.04, 0.05, 0.96 })
        K.Border(t, C.line)
        -- 0.6.133: image box and image logo (guild module). Two layers each: neutral base layer + color layer tinted in the
        -- notice or accent color - so they match any color choice.
        if ns.GuildPack then
            local GP = "Interface\\AddOns\\Oasis_Guild\\Media\\"
            t.boxBase = t:CreateTexture(nil, "BACKGROUND", nil, 3)
            t.boxBase:SetAllPoints()
            t.boxBase:SetTexture(GP .. "toast_box_base")
            t.boxTint = t:CreateTexture(nil, "BACKGROUND", nil, 4)
            t.boxTint:SetAllPoints()
            t.boxTint:SetTexture(GP .. "toast_box_tint")
            t.imgBox = true
        end
        -- gradient in the notice color from the left
        t.glow = t:CreateTexture(nil, "BORDER")
        t.glow:SetAllPoints()
        -- time bar at the bottom (until the notice disappears)
        t.time = t:CreateTexture(nil, "OVERLAY")
        t.time:SetPoint("BOTTOMLEFT", 1, 1)
        t.time:SetHeight(2)
        -- speaker if a sound plays with it
        t.snd = t:CreateTexture(nil, "OVERLAY")
        t.snd:SetTexture(ns.MEDIA .. "icons\\speaker")
        t.snd:SetSize(12, 12)
        t.snd:SetPoint("TOPRIGHT", -26, -8)
        t.snd:SetVertexColor(0.6, 0.6, 0.62)
        t.close = K.CloseButton(t, function() t.expire = 0 end)
        t.close:SetSize(14, 14)
        t.close:SetPoint("TOPRIGHT", -6, -6)
        -- 0.5.619: turn off this notice kind right here (same setting as Settings > Notices & Sound)
        t.mute = CreateFrame("Button", nil, t)
        t.mute:SetSize(16, 16)
        t.mute:SetPoint("BOTTOMRIGHT", -6, 6)
        t.mute.ic = t.mute:CreateTexture(nil, "OVERLAY")
        t.mute.ic:SetAllPoints()
        t.mute.ic:SetTexture(ns.MEDIA .. "icons\\eye_off")
        t.mute.ic:SetVertexColor(0.5, 0.5, 0.53)
        t.mute:SetScript("OnEnter", function(self)
            self.ic:SetVertexColor(1, 1, 1)
            if t.age < t.expire then t.expire = t.age + 3 end
            local e = ns.Sound and ns.Sound.eventByKey and ns.Sound.eventByKey[t.event]
            if t.byTitle then e = nil end
            K.ShowTip(self, { t.byTitle and L["Do not show this notification again"] or L["Turn off these notifications"],
                "|cff888888" .. (e and L[e.text] or t.byTitle or "") .. "|r",
                "|cff666666" .. L["Turn back on: Settings > Notifications & sound"] .. "|r" })
        end)
        t.mute:SetScript("OnLeave", function(self) self.ic:SetVertexColor(0.5, 0.5, 0.53) GameTooltip:Hide() end)
        t.mute:SetScript("OnClick", function()
            local ev = t.event
            if not (ev and ns.db) then return end
            if t.byTitle then
                ns.db.settings.toastMuted = ns.db.settings.toastMuted or {}
                ns.db.settings.toastMuted[t.byTitle] = true
                ns.print((L["Notifications \"%s\" turned off - turn back on in Settings > Notifications & sound."]):format(t.byTitle))
                GameTooltip:Hide()
                t.expire = 0
                ns.RefreshPage("settings")
                return
            end
            ns.db.settings.toastOff = ns.db.settings.toastOff or {}
            ns.db.settings.toastOff[ev] = true
            local e = ns.Sound and ns.Sound.eventByKey and ns.Sound.eventByKey[ev]
            ns.print((L["Notifications \"%s\" turned off - turn back on in Settings > Notifications & sound."]):format(e and L[e.text] or ev))
            GameTooltip:Hide()
            t.expire = 0
            ns.RefreshPage("settings")
        end)
        t.bar = t:CreateTexture(nil, "ARTWORK")
        t.bar:SetPoint("TOPLEFT")
        t.bar:SetPoint("BOTTOMLEFT")
        t.bar:SetWidth(3)
        t.logo = t:CreateTexture(nil, "ARTWORK")
        t.logo:SetTexture(ns.MEDIA .. "logo64")
        t.logo:SetSize(32, 32)
        t.logo:SetPoint("LEFT", 12, 0)
        if t.imgBox then
            -- 0.6.475: new OASIS logo (palm in ring) also in the notices with the guild module
            t.logo:SetTexture(ns.MEDIA .. "logo256")
            t.logo:SetSize(38, 38)
        end
        t.title = K.Title(t, 13, C.text)
        t.title:SetPoint("TOPLEFT", t.logo, "TOPRIGHT", 12, 2)
        t.title:SetWidth(262)
        t.title:SetWordWrap(true)      -- don't cut anything: wrap long titles
        t.title:SetJustifyV("TOP")
        t.text = K.Text(t, 12, C.muted)
        t.text:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -5)
        t.text:SetWidth(262)
        t.text:SetWordWrap(true)
        t.text:SetJustifyV("TOP")
        t:SetScript("OnClick", function(self)
            if self.cb then pcall(self.cb) end
            self.expire = 0
        end)
        t:SetScript("OnUpdate", function(self, el)
            -- mouse over: pause time (notice stays until the mouse leaves)
            if self.age >= 0.2 and self:IsMouseOver() then self:SetAlpha(1) return end
            self.age = self.age + el
            if self.age < 0.2 then
                self:SetAlpha(self.age / 0.2)
            elseif self.age > self.expire then
                self:SetAlpha(math.max(0, 1 - (self.age - self.expire) / 0.3))
                if self.age > self.expire + 0.3 then
                    self:Hide()
                    for i, a in ipairs(toastActive) do if a == self then table.remove(toastActive, i) break end end
                    table.insert(toastPool, self)
                    layoutToasts()
                end
            else
                self:SetAlpha(1)
            end
            if self.expire > 0 then self.time:SetWidth(math.max(1, (self:GetWidth() - (self.timePad or 2)) * math.max(0, 1 - self.age / self.expire))) end
            -- light dot runs across the bar every 1.6 s (only as far as the bar still reaches)
            if self.timeShine and self.timeShine:IsShown() then
                local w = self.time:GetWidth() or 0
                local x = ((self.age % 1.6) / 1.6) * (w + 22) - 22
                self.timeShine:ClearAllPoints()
                self.timeShine:SetPoint("LEFT", self.time, "LEFT", math.max(0, math.min(w - 22, x)), 0)
                self.timeShine:SetAlpha((w > 30 and x > -10 and x < w) and 1 or 0)
            end
        end)
        t:SetScript("OnEnter", function(self) if self.age < self.expire then self.expire = self.age + 3 end end)
    end
    col(t.bar, color)
    col(t.time, color)
    K.SetBorderColor(t, { color[1] * 0.6, color[2] * 0.6, color[3] * 0.6, 1 })
    if not K.Gradient(t.glow, "HORIZONTAL", { color[1], color[2], color[3], 0.2 }, { color[1], color[2], color[3], 0 }) then t.glow:SetColorTexture(color[1], color[2], color[3], 0.06) end
    if t.imgBox then
        -- image box: own frame and surface instead of Oasis border, line in the notice color, logo in the accent color
        if t.fillTex then t.fillTex:SetAlpha(0) end
        K.SetBorderColor(t, { 0, 0, 0, 0 })
        t.bar:Hide()
        t.glow:SetAlpha(0.5)
        t.boxTint:SetVertexColor(color[1], color[2], color[3], 1)
        t.boxTint:Hide()   -- 0.6.137: border line hidden from the image (looked like an extra frame)
        -- 0.6.135: time bar in the box to the right of the logo up to the eye, with gradient, subtle glow and
        -- a light dot running across the bar
        t.time:ClearAllPoints()
        t.time:SetPoint("BOTTOMLEFT", 60, 9)
        t.timePad = 60 + 34
        t.time:SetTexture("Interface\\Buttons\\WHITE8X8")
        if not K.Gradient(t.time, "HORIZONTAL", { color[1], color[2], color[3], 0.35 }, { color[1], color[2], color[3], 1 }) then t.time:SetVertexColor(color[1], color[2], color[3], 0.9) end
        if not t.timeGlow then
            t.timeGlow = t:CreateTexture(nil, "ARTWORK", nil, -1)
            t.timeGlow:SetPoint("TOPLEFT", t.time, "TOPLEFT", -2, 3)
            t.timeGlow:SetPoint("BOTTOMRIGHT", t.time, "BOTTOMRIGHT", 2, -3)
            t.timeGlow:SetTexture("Interface\\Buttons\\WHITE8X8")
            t.timeGlow:SetBlendMode("ADD")
            t.timeShine = t:CreateTexture(nil, "OVERLAY", nil, 2)
            t.timeShine:SetSize(22, 4)
            t.timeShine:SetTexture("Interface\\Buttons\\WHITE8X8")
            t.timeShine:SetBlendMode("ADD")
        end
        if not K.Gradient(t.timeGlow, "HORIZONTAL", { color[1], color[2], color[3], 0.05 }, { color[1], color[2], color[3], 0.22 }) then t.timeGlow:SetVertexColor(color[1], color[2], color[3], 0.15) end
        if not K.Gradient(t.timeShine, "HORIZONTAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.55 }) then t.timeShine:SetVertexColor(1, 1, 1, 0.4) end
        t.timeGlow:Show() t.timeShine:Hide()   -- 0.6.137: running light dot off (looked restless)
        local ac = C.accent
        if t.logoTint then t.logoTint:SetVertexColor(ac[1], ac[2], ac[3], 1) end
    end
    do
        local ch = ns.Sound and ns.Sound.ChoiceFor and ns.Sound.ChoiceFor(event)
        t.snd:Hide()   -- 0.5.685: speaker display removed
    end
    t.title:SetText(title or "")
    t.text:SetText(text or "")
    -- 0.6.404: action hint ("Click: send") at the bottom right instead of in the text (otherwise lay on the timeline)
    if not t.action then
        t.action = K.Text(t, 10, C.muted, "RIGHT")
        t.action:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -28, 8)
    end
    t.action:SetText(K.toastHint or "")
    K.toastHint = nil
    t.event = event
    local typed = event ~= "toast" and ns.Sound and ns.Sound.eventByKey and ns.Sound.eventByKey[event] and true or false
    -- without own kind: eye hides exactly this notice (title) - only sensible with fixed titles, so only with text
    t.byTitle = (not typed and type(title) == "string" and title ~= "") and title or nil
    t.mute:SetShown(typed or t.byTitle ~= nil)
    -- adjust height to the content (at least as before)
    do
        local th = (title and title ~= "") and (t.title:GetStringHeight() or 14) or 0
        local hasAct = (t.action:GetText() or "") ~= ""
        local function fit()
            local th2 = (title and title ~= "") and (t.title:GetStringHeight() or 14) or 0
            local xh2 = (text and text ~= "") and ((t.text:GetStringHeight() or 14) + 5) or 0
            t:SetHeight(math.max(56, th2 + xh2 + (hasAct and 38 or 26)))
        end
        fit()
        ns.After(0, fit)   -- 0.6.404: measure again after wrapping (otherwise too low)
    end
    t.cb = onClick
    t.age, t.expire = 0, (ns.db and ns.db.settings.toastDur) or 7
    if event == "alert" then t.expire = t.expire * 2 end
    t:SetAlpha(0)
    t:Show()
    table.insert(toastActive, 1, t)
    while #toastActive > 4 do
        local old = table.remove(toastActive)
        old:Hide()
        table.insert(toastPool, old)
    end
    layoutToasts()
    if ns.Sound then ns.Sound.Play(event) end
end
-- show held-back notices after combat
function K.FlushHeldToasts()
    local held = K._held
    K._held = nil
    if not held then return end
    for i, h in ipairs(held) do
        if not h.validUntil or ns.now() <= h.validUntil then
            ns.After(i * 0.4, function() K.Toast(h[1], h[2], h[3], h[4], h[5], h.validUntil) end)
        end
    end
end

------------------------------------------------------------------------
-- Gaming-Bausteine + Animationen (Uebersicht u.a.)
------------------------------------------------------------------------
-- simple tweens: K.Tween(obj, duration, fn(p 0..1, eased out), done)
local tweens = {}
local driver = CreateFrame("Frame", nil, UIParent)
driver:SetScript("OnUpdate", function(_, el)
    for obj, t in pairs(tweens) do
        t.e = t.e + el
        if t.e >= 0 then
            local p = math.min(1, t.e / t.d)
            local ok = pcall(t.fn, 1 - (1 - p) ^ 3)
            if p >= 1 or not ok then
                tweens[obj] = nil
                if t.done then pcall(t.done) end
            end
        end
    end
end)
function K.Tween(obj, dur, fn, done, delay)
    tweens[obj] = { e = -(delay or 0), d = math.max(0.01, dur), fn = fn, done = done }
end
-- fade a frame in softly and let it slide in slightly from below
-- animate tab switch: underline grows from the center, content next to it fades in softly
function K.TabAnim(seg, key)
    if not seg or (ns.db and ns.db.settings.noAnim) then return end
    for _, b in ipairs(seg.buttons or {}) do
        if b.key == key and b.under then
            local w = b:GetWidth() - 12
            b.under:ClearAllPoints()
            b.under:SetPoint("BOTTOM", b, "BOTTOM", 0, 0)
            K.Tween(b.under, 0.22, function(p) b.under:SetWidth(math.max(1, w * (0.2 + 0.8 * p))) end, function()
                b.under:ClearAllPoints()
                b.under:SetPoint("BOTTOMLEFT", 6, 0) b.under:SetPoint("BOTTOMRIGHT", -6, 0)
            end)
        end
    end
    -- previously all siblings were briefly hidden here -> the whole page "twitched" on every tab switch
end
function K.FadeIn(f, delay, dist)
    if not f then return end
    if ns.db and ns.db.settings.noAnim then f:SetAlpha(1) return end   -- animations reduced
    -- already visible and recently faded in (e.g. list refilled after data sync):
    -- don't fade in from 0 again, otherwise the window flickers on every reload of data
    local now = GetTime and GetTime() or 0
    if f.oasisFadedAt and now - f.oasisFadedAt < 20 and f:IsVisible() then f:SetAlpha(1) return end
    f.oasisFadedAt = now
    f:SetAlpha(0)
    K.Tween(f, 0.35, function(p) f:SetAlpha(p) end, function() f:SetAlpha(1) end, delay)
    -- safety net: never stay stuck invisible
    ns.After((delay or 0) + 1, function() if (f:GetAlpha() or 1) < 1 then f:SetAlpha(1) end end)
end
-- count a number up: fs:SetText(fmt(value))
function K.CountUp(fs, to, dur, fmt, delay)
    to = tonumber(to) or 0
    fmt = fmt or function(v) return tostring(math.floor(v + 0.5)) end
    -- set the final value immediately (in case the animation doesn't run), then count up from 0
    fs:SetText(fmt(to))
    if to == 0 then return end
    K.Tween(fs, dur or 0.8, function(p) fs:SetText(fmt(to * p)) end, function() fs:SetText(fmt(to)) end, delay)
end
-- gradient on a texture (color a -> b), without errors on clients without SetGradient
function K.Gradient(tex, dir, a, b)
    if not (CreateColor and tex.SetGradient) then return false end
    tex.oasisGrad = true   -- 0.6.377: gradient - must never be shared when cropping corners (can't be copied)
    return pcall(function()
        tex:SetColorTexture(1, 1, 1, 1)
        tex:SetGradient(dir or "HORIZONTAL", CreateColor(a[1], a[2], a[3], a[4] or 1), CreateColor(b[1], b[2], b[3], b[4] or 1))
    end)
end

-- section header in game style: color mark + UPPERCASE + optional counter on the right
function K.GameHead(parent, text, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(18)
    color = color or C.accent
    f.mark = f:CreateTexture(nil, "ARTWORK")
    f.mark:SetSize(3, 14)
    f.mark:SetPoint("LEFT", 0, 0)
    f.mark:SetColorTexture(color[1], color[2], color[3], 1)
    f.text = K.Title(f, 12, C.text)
    f.text:SetPoint("LEFT", 10, 0)
    f.text:SetText(K.Upper and K.Upper(text) or text:upper())
    f.count = K.Text(f, 11, color)
    f.count:SetPoint("LEFT", f.text, "RIGHT", 8, 0)
    function f:SetCount(v) self.count:SetText(v and tostring(v) or "") end
    -- pulsing dot ("live")
    function f:Live(on)
        if not self.dot then
            self.dot = self:CreateTexture(nil, "OVERLAY")
            self.dot:SetSize(7, 7)
            self.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            self.dot:SetVertexColor(C.mint[1], C.mint[2], C.mint[3])
            self.dot:SetPoint("LEFT", self.count, "RIGHT", 6, 0)
            self:SetScript("OnUpdate", function(s, el)
                s.pt = ((s.pt or 0) + el) % 1.6
                s.dot:SetAlpha(0.35 + 0.65 * (0.5 + 0.5 * math.cos(s.pt / 1.6 * math.pi * 2)))
            end)
        end
        self.dot:SetShown(on and true or false)
    end
    return f
end

-- HUD tile: large icon, glowing edge, value (counts up), label, small progress bar
function K.HudTile(parent, icon, label, color, onClick)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(66)
    color = color or C.accent
    f.color = color
    f.bg = K.Fill(f, C.raised)
    if K.ApplySkin then f:SetSize(120, 66) K.ApplySkin(f, "panel", C.raised) end
    f.glow = f:CreateTexture(nil, "BORDER")
    f.glow:Hide()
    f.top = f:CreateTexture(nil, "ARTWORK")
    f.top:Hide()
    f.hl = f:CreateTexture(nil, "HIGHLIGHT")
    f.hl:SetAllPoints()
    f.hl:SetColorTexture(1, 1, 1, 0.02)
    -- Glas 2026: calm surface, color only in number and icon
    local IG = ns.Insta
    f.glassy = IG and IG.Glass and IG.Glass(f, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.10 }, 12) and true or false
    f.icon = K.Glyph(f, 22, icon, color)
    f.icon:SetPoint("RIGHT", -14, 2)
    f.icon:SetAlpha(0.8)
    f.value = K.Title(f, 22, f.glassy and color or C.text)
    f.value:SetPoint("TOPLEFT", 12, -11)
    f.sub = K.Text(f, 12, C.muted)
    f.sub:SetPoint("BOTTOMLEFT", f.value, "BOTTOMRIGHT", 5, 2)
    f.sub:SetPoint("RIGHT", f.icon, "LEFT", -6, 0)
    f.sub:SetWordWrap(false)
    f.label = K.Text(f, 11, C.muted)
    f.label:SetPoint("BOTTOMLEFT", 12, 11)
    f.label:SetText(f.glassy and label or (K.Upper and K.Upper(label) or label:upper()))
    f.bar = f:CreateTexture(nil, "ARTWORK")
    f.bar:SetPoint("BOTTOMLEFT", f.glassy and 12 or 0, f.glassy and 3 or 0)
    f.bar:SetHeight(2)
    f.bar:SetColorTexture(color[1], color[2], color[3], 0.9)
    f.bar:Hide()
    if onClick then f:SetScript("OnClick", onClick) end
    f:SetScript("OnEnter", function(s)
        if s.glassy then ns.Insta.Glass(s, { 1, 1, 1, 0.06 }, { color[1], color[2], color[3], 0.45 }, 12) end
        s.icon:SetAlpha(1)
        if s.tip then K.ShowTip(s, s.tip) end
    end)
    f:SetScript("OnLeave", function(s)
        if s.glassy then ns.Insta.Glass(s, { 1, 1, 1, 0.03 }, { 1, 1, 1, 0.10 }, 12) end
        s.icon:SetAlpha(0.8)
        GameTooltip:Hide()
    end)
    -- set value; animate = count up; progress 0..1 = bar at the bottom
    function f:Set(value, sub, progress, animate)
        self.sub:SetText(sub or "")
        local n = tonumber(value)
        if animate and n then K.CountUp(self.value, n, 0.9) else self.value:SetText(value or "–") end
        if progress then
            self.bar:Show()
            local w = math.max(1, ((self:GetWidth() or 100) - (self.glassy and 24 or 0)) * math.max(0, math.min(1, progress)))
            if animate then
                self.bar:SetWidth(1)
                K.Tween(self.bar, 0.9, function(p) self.bar:SetWidth(math.max(1, w * p)) end)
            else
                self.bar:SetWidth(w)
            end
        else
            self.bar:Hide()
        end
    end
    return f
end

------------------------------------------------------------------------
-- rank frame (Oasis rank): round (portrait) or square (profile card)
-- Style: { color, width, glow, double, gems, sparks, cycle }
------------------------------------------------------------------------
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local function hsv(h)
    local i = math.floor(h * 6) % 6
    local f = h * 6 - math.floor(h * 6)
    local q, t = 1 - f, f
    local r, g, b = ({ { 1, t, 0 }, { q, 1, 0 }, { 0, 1, t }, { 0, q, 1 }, { t, 0, 1 }, { 1, 0, q } })[i + 1][1],
        ({ { 1, t, 0 }, { q, 1, 0 }, { 0, 1, t }, { 0, q, 1 }, { t, 0, 1 }, { 1, 0, q } })[i + 1][2],
        ({ { 1, t, 0 }, { q, 1, 0 }, { 0, 1, t }, { 0, q, 1 }, { t, 0, 1 }, { 1, 0, q } })[i + 1][3]
    return r * 0.6 + 0.4, g * 0.6 + 0.4, b * 0.6 + 0.4
end

-- round: size = diameter of the content; create content (e.g. portrait) as rf:CreateTexture(nil, "OVERLAY")
-- Rank crests: Media\ranks\tier1..11 (wood, bronze, silver, gold, emerald, sapphire, amethyst, ruby, diamond,
-- Legend, Heart of the Oasis) with the rank number in the inner field; tiers with glow pulse slightly
-- visible width per digit relative to height (measured from the graphics Media\\digits)
local DIGIT_W = { ["0"] = 0.59, ["1"] = 0.31, ["2"] = 0.60, ["3"] = 0.60, ["4"] = 0.67, ["5"] = 0.59, ["6"] = 0.59, ["7"] = 0.57, ["8"] = 0.63, ["9"] = 0.59 }
-- number from digit graphics, exactly centered on the parent frame (replacement for FontString on plaques).
-- same interface as a FontString: :SetText(number), :SetTextColor(r, g, b, a), :SetShown/Show/Hide
-- 0.5.703: digit tile on whole pixels with the same parity as the field (ref). Otherwise (e.g. 8.96 -> 9 px on a
-- 20 px crest) it sits half a pixel off center. On a tie the smaller tile wins.
local function pxLike(v, ref)
    ref = math.floor((ref or 0) + 0.5)
    local n = math.floor(v + 0.5)
    if ref > 0 and (n - ref) % 2 ~= 0 then
        n = ((v - (n - 1)) <= ((n + 1) - v)) and (n - 1) or (n + 1)
    end
    return n
end
K.PxLike = pxLike
function K.DigitText(parent, h, dx, dy)
    local o = { parent = parent, h = h or 14, dx = dx or 0, dy = dy or 0, digs = {}, col = { 1, 1, 1, 1 }, shown = true }
    function o:Layout()
        local s = self.text or ""
        local h = self.h
        local T = pxLike(h * 128 / 100, self.parent.GetWidth and self.parent:GetWidth() or 0)
        local gap = math.max(1, math.floor(h * 0.08 + 0.5))
        local total = 0
        for i = 1, #s do total = total + (DIGIT_W[s:sub(i, i)] or 0.6) * h + (i > 1 and gap or 0) end
        local x = -total / 2
        for i = 1, math.max(#s, #self.digs) do
            local d = self.digs[i]
            local ch = s:sub(i, i)
            if i <= #s and DIGIT_W[ch] then
                if not d then d = self.parent:CreateTexture(nil, "OVERLAY", nil, 6) self.digs[i] = d end
                local w = DIGIT_W[ch] * h
                d:SetTexture(ns.MEDIA .. "digits\\d" .. ch)
                d:SetSize(T, T)
                d:ClearAllPoints()
                d:SetPoint("CENTER", self.parent, "CENTER", math.floor(x + w / 2 + self.dx + 0.5), self.dy)
                d:SetVertexColor(self.col[1], self.col[2], self.col[3], self.col[4] or 1)
                d:SetShown(self.shown)
                x = x + w + gap
            elseif d then
                d:Hide()
            end
        end
    end
    function o:SetText(v) self.text = v ~= nil and tostring(v) or "" self:Layout() end
    function o:GetText() return self.text end
    function o:SetTextColor(r, g, b, a) self.col = { r or 1, g or 1, b or 1, a or 1 } self:Layout() end
    function o:SetShown(v) self.shown = v and true or false self:Layout() end
    function o:Show() self:SetShown(true) end
    function o:Hide() self:SetShown(false) end
    return o
end
-- inner field center per crest (fraction of image height below center), measured from Media\\rank\\frameNN
local FRAME_DY = { [5] = 0.041, [10] = 0.042, [15] = 0.036, [20] = 0.033, [25] = 0.032, [30] = 0.021, [35] = 0.022, [40] = 0.041,
    [45] = 0.035, [50] = 0.041, [55] = 0.030, [60] = 0.044, [65] = 0.032, [70] = 0.043, [75] = 0.027, [80] = 0.026, [85] = 0.025,
    [90] = 0.034, [95] = 0.029, [100] = 0.043 }
function K.RankEmblem(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.glow = f:CreateTexture(nil, "BACKGROUND")
    f.glow:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    f.glow:SetSize(size * 1.15, size * 1.15)
    f.glow:SetPoint("CENTER", 0, -1)
    f.glow:SetBlendMode("ADD")
    f.glow:Hide()
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.num = f:CreateFontString(nil, "OVERLAY")
    K.SetFontSafe(f.num, K.FONT_HEAD, math.max(8, math.floor(size * 0.36)), "OUTLINE", K.FONT)
    f.num:SetJustifyH("CENTER")
    f.num:SetJustifyV("MIDDLE")
    f.num:SetWidth(size)
    -- tooltip: what the crest means; click is passed on to the row below
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        if not self.level or not ns.Rank then return end
        local st = ns.Rank.FRAMES[ns.Rank.FrameIndex(self.level)]
        K.ShowTip(self, { (L["Oasis rank %d"]):format(self.level) .. "  ·  " .. ns.Rank.Title(self.level),
            K.hex(st.color) .. L[st.name] .. "|r",
            "|cff888888" .. L["The Oasis rank is Oasis's guild rank - it rises by playing together, helping, crafting, events and badges."] .. "|r" })
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:SetScript("OnMouseUp", function(self, btn)
        local p = self:GetParent()
        local fn = p and p.GetScript and p:GetScript("OnClick")
        if fn then fn(p, btn) end
    end)
    function f:SetRank(level)
        self.level = level
        if not level or not ns.Rank then self:Hide() return end
        local idx = ns.Rank.FrameIndex(level)
        local st = ns.Rank.FRAMES[idx]
        -- 0.5.578: crest every 5 ranks (Media\\rank\\frameNN, empty inner field), the exact rank number goes on top
        local tier = math.min(100, math.max(5, math.floor(level / 5) * 5))
        local TS = pxLike(size * 1.18, size)
        self.tex:ClearAllPoints()
        self.tex:SetPoint("CENTER")
        self.tex:SetSize(TS, TS)
        self.tex:SetTexture(ns.MEDIA .. "rank\\frame" .. tier .. (size <= 40 and "_s" or ""))
        self.tex:SetDrawLayer("ARTWORK", 1)
        self.tex:SetVertexColor(1, 1, 1, 1)
        self.tex:SetAlpha(1)
        self.tex:Show()
        if self:GetParent() then self:SetFrameLevel(self:GetParent():GetFrameLevel() + 3) end
        self.num:SetText("")
        self.glow:Hide()
        if self.animGlow then self.animGlow = nil self:SetScript("OnUpdate", nil) end
        do
            local s = tostring(level)
            local h = math.floor(size * (#s >= 3 and 0.27 or (#s == 2 and 0.33 or 0.37)) + 0.5)
            local T = pxLike(h * 128 / 100, size)
            local gap = math.max(1, math.floor(h * 0.06 + 0.5))
            -- visible width and center of the 128px digits (without transparent margin).
            local bounds = { ["0"] = {30, 97}, ["1"] = {44, 83}, ["2"] = {30, 98}, ["3"] = {30, 98},
                ["4"] = {26, 101}, ["5"] = {30, 97}, ["6"] = {30, 97}, ["7"] = {31, 96}, ["8"] = {28, 99}, ["9"] = {30, 97} }
            local function digitWidth(ch) local bb = bounds[ch] return (bb[2] - bb[1]) * T / 128 end
            local total = 0
            for i = 1, #s do total = total + digitWidth(s:sub(i, i)) + (i > 1 and gap or 0) end
            -- the inner field sits slightly below the image center per crest (measured from the graphics)
            local py = size <= 40 and 0 or -math.floor((FRAME_DY[tier] or 0.035) * TS + 0.5)
            local x = -total / 2
            self.digs = self.digs or {}
            for i = 1, math.max(#s, #self.digs) do
                local d = self.digs[i]
                if i <= #s then
                    if not d then d = self:CreateTexture(nil, "OVERLAY", nil, 6) self.digs[i] = d end
                    local ch = s:sub(i, i)
                    local w = digitWidth(ch)
                    d:SetTexture(ns.MEDIA .. "digits\\d" .. ch)
                    d:SetSize(T, T)
                    d:ClearAllPoints()
                    d:SetPoint("CENTER", self, "CENTER", x + w / 2 + (64 - (bounds[ch][1] + bounds[ch][2]) / 2) * T / 128, py)
                    d:SetVertexColor(1, 0.9, 0.68)
                    d:Show()
                    x = x + w + gap
                elseif d then
                    d:Hide()
                end
            end
        end
        self:Show()
        do return end
        self.tex:ClearAllPoints()
        self.tex:SetAllPoints()
        -- set image + layer anew every time (reused list rows)
        self.tex:SetTexture(ns.MEDIA .. "emblems\\tier" .. idx)
        self.tex:SetDrawLayer("ARTWORK", 1)
        self.tex:SetVertexColor(1, 1, 1, 1)
        self.tex:SetAlpha(1)
        self.tex:Show()
        if self:GetParent() then self:SetFrameLevel(self:GetParent():GetFrameLevel() + 3) end
        -- number as digit GRAPHICS (Media\\digits\\d0..d9, glyph exactly centered in the tile): font metrics
        -- shift digits per font/size - graphics always sit exactly in the center of the crest.
        self.num:SetText("")
        local s = tostring(level)
        local h = math.floor(size * (#s >= 2 and 0.30 or 0.34) + 0.5)   -- visible digit height (smaller)
        local T = h * 128 / 100                            -- tile size (glyph = 100/128 of the tile)
        local gap = math.max(1, math.floor(h * 0.08 + 0.5))
        local total = 0
        for i = 1, #s do total = total + (DIGIT_W[s:sub(i, i)] or 0.6) * h + (i > 1 and gap or 0) end
        -- the crest's inner field sits minimally below center (measured from the graphics)
        local dy = idx == 1 and -0.017 or (idx == #ns.Rank.FRAMES and -0.026 or -0.008)
        local py = math.floor(dy * size + 0.5)
        local x = -total / 2
        self.digs = self.digs or {}
        local c = st.color
        for i = 1, math.max(#s, #self.digs) do
            local d = self.digs[i]
            if i <= #s then
                if not d then d = self:CreateTexture(nil, "OVERLAY", nil, 6) self.digs[i] = d end
                local ch = s:sub(i, i)
                local w = (DIGIT_W[ch] or 0.6) * h
                d:SetTexture(ns.MEDIA .. "digits\\d" .. ch)
                d:SetSize(T, T)
                d:ClearAllPoints()
                d:SetPoint("CENTER", self, "CENTER", math.floor(x + w / 2 + 0.5), py)
                d:SetVertexColor(math.min(1, c[1] + 0.3), math.min(1, c[2] + 0.3), math.min(1, c[3] + 0.3))
                d:Show()
                x = x + w + gap
            elseif d then
                d:Hide()
            end
        end
        self.glow:SetVertexColor(c[1], c[2], c[3])
        self.glow:SetShown(st.glow and true or false)
        if st.glow ~= self.animGlow then
            self.animGlow = st.glow
            self:SetScript("OnUpdate", st.glow and function(s, el)
                s.t = (s.t or 0) + el
                s.glow:SetAlpha(0.18 + 0.14 * math.sin(s.t * 2.4))
            end or nil)
        end
        self:Show()
    end
    return f
end

-- painted profile frames: 20 tiers (5 ranks each), image 256 px, hole = 1/K.RING_RATIO of image width
K.RING_RATIO = 2.0037
-- center of the hexagon at the bottom per frame (fraction of image width, measured from the graphics: scratchpad hexcenter.py)
K.RING_HEX = { { 0.0043, 0.2918 }, { 0.0076, 0.3009 }, { 0.0058, 0.2958 }, { 0.0061, 0.3033 }, { 0, 0.2972 }, { 0.0038, 0.2988 },
    { 0.0032, 0.3013 }, { 0.0082, 0.3037 }, { 0.0028, 0.292 }, { 0.002, 0.3038 }, { 0.0032, 0.2981 }, { 0.0061, 0.3061 },
    { -0.0018, 0.3053 }, { 0.0028, 0.3072 }, { 0.0087, 0.3079 }, { 0.009, 0.3066 }, { 0.0044, 0.3084 }, { 0.0101, 0.312 },
    { 0.017, 0.3169 }, { 0.006, 0.39 } }
function K.RingTier(level)
    level = tonumber(level)
    if not level then return nil end
    return math.max(1, math.min(20, math.ceil(level / 5)))
end
function K.RingPath(tier) return ns.MEDIA .. ("avatar\\ring%02d"):format(tier) end
function K.RankFrame(parent, size, shape)
    local f = CreateFrame("Frame", nil, parent)
    f.shape = shape or "circle"
    f.size = size
    local pad = 14
    f:SetSize(size + pad * 2, size + pad * 2)
    f.sparks = {}
    if f.shape == "circle" then
        f.glow = f:CreateTexture(nil, "BACKGROUND")
        f.glow:SetTexture(CIRCLE)
        f.glow:SetSize(size + 22, size + 22)
        f.glow:SetPoint("CENTER")
        f.outer = f:CreateTexture(nil, "BORDER", nil, 0)
        f.outer:SetTexture(CIRCLE)
        f.outer:SetPoint("CENTER")
        f.gap = f:CreateTexture(nil, "BORDER", nil, 1)
        f.gap:SetTexture(CIRCLE)
        f.gap:SetPoint("CENTER")
        f.ring = f:CreateTexture(nil, "BORDER", nil, 2)
        f.ring:SetTexture(CIRCLE)
        f.ring:SetPoint("CENTER")
        f.inner = f:CreateTexture(nil, "ARTWORK")
        f.inner:SetTexture(CIRCLE)
        f.inner:SetSize(size, size)
        f.inner:SetPoint("CENTER")
        f.inner:SetVertexColor(C.bg[1], C.bg[2], C.bg[3])
        -- 0.5.586: painted profile frames (Media/avatar/ringNN, one per 5 Oasis ranks) - above the portrait,
        -- below rank numbers (OVERLAY 5). Hole diameter = size, image is K.RING_RATIO times as large.
        f.art = f:CreateTexture(nil, "OVERLAY", nil, 4)
        f.art:SetPoint("CENTER")
        f.art:SetSize(size * K.RING_RATIO, size * K.RING_RATIO)
        f.art:Hide()
    else
        -- square: only edges outside the content (content stays freely visible)
        f.edges, f.edges2, f.glowE = {}, {}, {}
        local function edges(list, layer, sub)
            for i = 1, 4 do
                local t = f:CreateTexture(nil, layer, nil, sub)
                t:SetColorTexture(1, 1, 1, 1)
                list[i] = t
            end
        end
        edges(f.glowE, "BACKGROUND", 0)
        edges(f.edges2, "BORDER", 0)
        edges(f.edges, "BORDER", 1)
        f.gemsT = {}
        for i = 1, 4 do
            local g = f:CreateTexture(nil, "OVERLAY", nil, 5)
            g:SetTexture(CIRCLE)
            g:SetSize(9, 9)
            f.gemsT[i] = g
        end
    end
    -- place a frame around a rectangle of size size: distance d, thickness w
    local function frameEdges(list, d, w)
        local half = size / 2 + d
        local t, b, l, r = list[1], list[2], list[3], list[4]
        t:ClearAllPoints() t:SetPoint("BOTTOMLEFT", f, "CENTER", -half - w, half) t:SetSize(size + 2 * (d + w), w)
        b:ClearAllPoints() b:SetPoint("TOPLEFT", f, "CENTER", -half - w, -half) b:SetSize(size + 2 * (d + w), w)
        l:ClearAllPoints() l:SetPoint("TOPRIGHT", f, "CENTER", -half, half) l:SetSize(w, size + 2 * d)
        r:ClearAllPoints() r:SetPoint("TOPLEFT", f, "CENTER", half, half) r:SetSize(w, size + 2 * d)
    end
    local function tint(list, r, g, b, a) for _, t in ipairs(list) do t:SetVertexColor(r, g, b, a or 1) end end

    function f:SetStyle(st, level)
        self.style = st
        -- rank known -> painted frame instead of drawn rings
        local tier = (self.art and level and K.RingTier) and K.RingTier(level) or nil
        if self.art then
            self.art:SetShown(tier ~= nil)
            if tier then self.art:SetTexture(K.RingPath(tier)) end
            -- rank number in the hexagon at the bottom of the frame (measured from the graphics: center 32 % or 39.5 % below the hole)
            if not self.lvl then
                self.lvl = self:CreateFontString(nil, "OVERLAY", nil, 7)
                self.lvl:SetJustifyH("CENTER")
            end
            if tier then
                local A = size * K.RING_RATIO
                K.SetFontSafe(self.lvl, K.FONT_HEAD, math.max(8, math.floor(A * (level >= 100 and 0.07 or 0.088) + 0.5)), "OUTLINE", K.FONT)
                self.lvl:SetTextColor(1, 0.88, 0.62)
                self.lvl:SetShadowOffset(1, -1)
                self.lvl:SetShadowColor(0, 0, 0, 1)
                self.lvl:ClearAllPoints()
                local hx = K.RING_HEX[tier] or K.RING_HEX[1]
                self.lvl:SetPoint("CENTER", self, "CENTER", A * hx[1], -A * hx[2])
                self.lvl:SetText(level)
                self.lvl:Show()
            else
                self.lvl:Hide()
            end
        end
        local c = st.color
        local w = st.width or 2
        if self.shape == "circle" then
            self.ring:SetSize(size + w * 2, size + w * 2)
            self.ring:SetVertexColor(c[1], c[2], c[3])
            self.gap:SetSize(size + w * 2 + 4, size + w * 2 + 4)
            self.gap:SetVertexColor(C.bg[1], C.bg[2], C.bg[3])
            self.outer:SetSize(size + w * 2 + 8, size + w * 2 + 8)
            self.outer:SetVertexColor(c[1], c[2], c[3], 0.8)
            self.gap:SetShown(st.double and true or false)
            self.outer:SetShown(st.double and true or false)
            self.glow:SetVertexColor(c[1], c[2], c[3], 0.35)
            self.glow:SetShown(st.glow and true or false)
            self.orbit = size / 2 + w + (st.double and 5 or 2)
        else
            frameEdges(self.edges, 2, w)
            tint(self.edges, c[1], c[2], c[3])
            frameEdges(self.edges2, 2 + w + 2, 1)
            tint(self.edges2, c[1], c[2], c[3], 0.7)
            for _, t in ipairs(self.edges2) do t:SetShown(st.double and true or false) end
            frameEdges(self.glowE, 2 + w, 6)
            tint(self.glowE, c[1], c[2], c[3], 0.18)
            for _, t in ipairs(self.glowE) do t:SetShown(st.glow and true or false) end
            local half = size / 2 + 2 + w / 2
            local pos = { { -half, half }, { half, half }, { -half, -half }, { half, -half } }
            for i, g in ipairs(self.gemsT) do
                g:ClearAllPoints()
                g:SetPoint("CENTER", self, "CENTER", pos[i][1], pos[i][2])
                g:SetVertexColor(math.min(1, c[1] + 0.3), math.min(1, c[2] + 0.3), math.min(1, c[3] + 0.3))
                g:SetShown(st.gems and true or false)
            end
            self.half = size / 2 + 2 + w / 2
        end
        -- sparks
        local n = st.sparks or 0
        for i = 1, math.max(n, #self.sparks) do
            local s = self.sparks[i]
            if not s and i <= n then
                s = self:CreateTexture(nil, "OVERLAY", nil, 7)
                s:SetTexture(CIRCLE)
                s:SetSize(5, 5)
                self.sparks[i] = s
            end
            if s then s:SetShown(i <= n) s:SetVertexColor(1, 1, 1) end
        end
        if tier then
            for _, t in ipairs({ self.ring, self.gap, self.outer, self.glow }) do t:Hide() end
            for _, sp in ipairs(self.sparks) do sp:Hide() end
            self:SetScript("OnUpdate", nil)
            return
        end
        if self.ring then self.ring:Show() end
        local animated = st.glow or n > 0 or st.cycle
        self:SetScript("OnUpdate", animated and function(s, el)
            s.t = (s.t or 0) + el
            local t = s.t
            if st.glow then
                local a = 0.22 + 0.18 * math.sin(t * 2.2)
                if s.shape == "circle" then s.glow:SetAlpha(a / 0.35) else for _, e in ipairs(s.glowE) do e:SetAlpha(a / 0.18 * 0.5) end end
            end
            if st.cycle then
                local r, g, b = hsv((t * 0.08) % 1)
                if s.shape == "circle" then s.ring:SetVertexColor(r, g, b) s.outer:SetVertexColor(r, g, b, 0.8) s.glow:SetVertexColor(r, g, b, 0.35)
                else tint(s.edges, r, g, b) tint(s.edges2, r, g, b, 0.7) tint(s.glowE, r, g, b, 0.18) end
            end
            for i = 1, n do
                local sp = s.sparks[i]
                local a = t * 1.2 + (i - 1) * (math.pi * 2 / n)
                if s.shape == "circle" then
                    sp:ClearAllPoints()
                    sp:SetPoint("CENTER", s, "CENTER", math.cos(a) * s.orbit, math.sin(a) * s.orbit)
                else
                    -- run along the edge
                    local h = s.half
                    local per = (a / (math.pi * 2)) % 1 * 4
                    local x, y
                    if per < 1 then x, y = -h + 2 * h * per, h
                    elseif per < 2 then x, y = h, h - 2 * h * (per - 1)
                    elseif per < 3 then x, y = h - 2 * h * (per - 2), -h
                    else x, y = -h, -h + 2 * h * (per - 3) end
                    sp:ClearAllPoints()
                    sp:SetPoint("CENTER", s, "CENTER", x, y)
                end
                sp:SetAlpha(0.6 + 0.4 * math.sin(t * 5 + i))
            end
        end or nil)
    end
    return f
end


-- page tiles (like members): defs = { { icon, label, color, onClick }, ... }
-- shifts all elements previously anchored at the top of the page down by shift
function K.PageTiles(p, defs, shift)
    shift = shift or 76
    local function move(o)
        if not o.GetNumPoints then return end
        local pts = {}
        for i = 1, o:GetNumPoints() do pts[i] = { o:GetPoint(i) } end
        local moved = false
        for _, pt in ipairs(pts) do
            if pt[2] == p and tostring(pt[3]):find("TOP") then pt[5] = (pt[5] or 0) - shift moved = true end
        end
        if moved then
            o:ClearAllPoints()
            for _, pt in ipairs(pts) do o:SetPoint(pt[1], pt[2], pt[3], pt[4], pt[5]) end
        end
    end
    for _, o in ipairs({ p:GetChildren() }) do move(o) end
    for _, o in ipairs({ p:GetRegions() }) do move(o) end
    local tiles = {}
    for i, d in ipairs(defs) do
        local t = K.HudTile(p, d[1], d[2], d[3], d[4])
        t:SetHeight(62)
        tiles[i] = t
    end
    local function layout(w)
        local n = #tiles
        local tw = math.floor(((w or 750) - (n - 1) * 10) / n)
        for i, t in ipairs(tiles) do
            t:SetWidth(tw)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", (i - 1) * (tw + 10), 0)
        end
    end
    p:HookScript("OnSizeChanged", function(_, w) layout(w) end)
    layout(p:GetWidth())
    p:HookScript("OnShow", function(self) self.tilesFresh = true end)
    p.tilesFresh = true
    -- set values: vals = { {value, extra, share}, ... }; animated the first time after opening
    function tiles.Fill(vals)
        local fresh = p.tilesFresh
        for i, t in ipairs(tiles) do
            local v = vals[i]
            if v then t:Set(v[1], v[2], v[3], fresh) end
            if fresh then K.FadeIn(t, (i - 1) * 0.06) end
        end
        p.tilesFresh = false
    end
    return tiles
end


-- name suggestions from the guild list below an edit box (online first); click/Tab accepts
function K.AttachNameSuggest(eb)
    local box = CreateFrame("Frame", nil, eb)
    box:SetFrameStrata("DIALOG")
    box:SetPoint("TOPLEFT", eb, "BOTTOMLEFT", 0, -2)
    box:SetPoint("TOPRIGHT", eb, "BOTTOMRIGHT", 0, -2)
    box:SetHeight(10)
    K.Fill(box, { 0.05, 0.05, 0.06, 0.98 })
    K.Border(box, C.accent2)
    box:Hide()
    box.rows = {}
    local function pick(name)
        eb:SetText(ns.short((ns.Alts and ns.Alts.Canon and ns.Alts.Canon(name)) or name))
        eb:SetCursorPosition(#eb:GetText())
        box:Hide()
    end
    for i = 1, 6 do
        local r = CreateFrame("Button", nil, box)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", 3, -3 - (i - 1) * 20)
        r:SetPoint("RIGHT", -3, 0)
        r.t = K.Text(r, 12, C.text)
        r.t:SetPoint("LEFT", 6, 0)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)
        r:SetScript("OnClick", function(self) pick(self.name) end)
        box.rows[i] = r
    end
    eb:HookScript("OnTextChanged", function(self, user)
        local q = (self:GetText() or ""):lower()
        if not user or #q < 1 then box:Hide() return end
        local list = {}
        for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
            local n = ns.short(m.name)
            if not ns.isMe(m.name) and n:lower():find(q, 1, true) == 1 then list[#list + 1] = m end
        end
        table.sort(list, function(a, b)
            if a.online ~= b.online then return a.online and true or false end
            return a.name < b.name
        end)
        if #list == 0 then box:Hide() return end
        for i, r in ipairs(box.rows) do
            local m = list[i]
            r:SetShown(m ~= nil)
            if m then
                r.name = m.name
                r.t:SetText(ns.colorName(m.name, m.class) .. "  |cff888888" .. (m.level or "") .. "|r" .. (m.online and "  |cff66db9e●|r" or ""))
            end
        end
        box.first = list[1].name
        box:SetHeight(6 + math.min(#list, 6) * 20)
        box:Show()
    end)
    eb:HookScript("OnTabPressed", function() if box:IsShown() and box.first then pick(box.first) end end)
    eb:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function() box:Hide() end) end)
    return box
end

------------------------------------------------------------------------
-- Designs (Settings > Appearance): complete color scheme + gradient + matching font/accent
-- colors are swapped IN PLACE in K.C -> then ns.RebuildMain()
------------------------------------------------------------------------
local PAL_KEYS = { "bg", "side", "panel", "raised", "field", "line", "text", "muted", "dim", "hover" }
K.THEMES = {
    -- Glas 2026: semi-transparent, slightly bluish surfaces, soft light orbs in the background, round corners, Inter
    { key = "glass", sideGlow = 0.06, orbs = true, particles = true, name = "Default", desc = "Glasflaechen, ruhiges Licht, runde Ecken - das Oasis-Design", accent = "", font = "inter",
      bg = { 0.045, 0.050, 0.072, 0.93 }, side = { 0.030, 0.034, 0.050, 0.95 }, panel = { 0.115, 0.125, 0.170, 0.62 }, raised = { 0.150, 0.162, 0.215, 0.72 },
      field = { 0.025, 0.028, 0.045, 0.80 }, line = { 0.300, 0.320, 0.420, 0.45 }, text = { 0.960, 0.965, 0.990, 1 }, muted = { 0.660, 0.690, 0.780, 1 },
      dim = { 0.450, 0.480, 0.570, 1 }, hover = { 0.190, 0.205, 0.270, 0.80 },
      grad = { top = { 0.080, 0.088, 0.130 }, bottom = { 0.025, 0.028, 0.042 } }, gradDef = 1 },
    { key = "future", sideGlow = 0.14, tex = "future", texAlpha = 0.85, name = "Future", desc = "Night blue with neon cyan, fading into violet", accent = "00d4ff", font = "teko",
      bg = { 0.020, 0.030, 0.070, 0.97 }, side = { 0.015, 0.020, 0.050, 1 }, panel = { 0.040, 0.060, 0.120, 1 }, raised = { 0.060, 0.090, 0.170, 1 },
      field = { 0.015, 0.025, 0.060, 1 }, line = { 0.100, 0.260, 0.380, 1 }, text = { 0.880, 0.960, 1.000, 1 }, muted = { 0.550, 0.700, 0.800, 1 },
      dim = { 0.330, 0.450, 0.550, 1 }, hover = { 0.070, 0.120, 0.200, 1 },
      grad = { top = { 0.030, 0.060, 0.130 }, bottom = { 0.070, 0.020, 0.110 } }, gradDef = 1 },
    { key = "fantasy", sideGlow = 0.1, tex = "fantasy", texAlpha = 0.75, name = "Fantasy", desc = "Warm leather, bronze and gold", accent = "e0a040", font = "marcellus",
      bg = { 0.075, 0.055, 0.040, 0.97 }, side = { 0.055, 0.040, 0.028, 1 }, panel = { 0.110, 0.085, 0.060, 1 }, raised = { 0.150, 0.115, 0.080, 1 },
      field = { 0.050, 0.035, 0.025, 1 }, line = { 0.360, 0.270, 0.160, 1 }, text = { 0.960, 0.910, 0.800, 1 }, muted = { 0.740, 0.660, 0.520, 1 },
      dim = { 0.500, 0.430, 0.330, 1 }, hover = { 0.170, 0.130, 0.090, 1 },
      grad = { top = { 0.110, 0.080, 0.055 }, bottom = { 0.035, 0.025, 0.018 } }, gradDef = 1, frame = { 0.55, 0.40, 0.20 } },
    { key = "kawaii", sideGlow = 0.14, tex = "kawaii", texAlpha = 1, name = "Kawaii", desc = "Pastel pink with dots, hearts and bows", accent = "ff6fae", font = "ptsansbold",
      bg = { 0.200, 0.080, 0.140, 0.97 }, side = { 0.150, 0.050, 0.100, 1 }, panel = { 0.270, 0.110, 0.190, 1 }, raised = { 0.330, 0.140, 0.240, 1 },
      field = { 0.140, 0.050, 0.100, 1 }, line = { 0.750, 0.420, 0.580, 1 }, text = { 1.000, 0.950, 0.980, 1 }, muted = { 0.950, 0.750, 0.860, 1 },
      dim = { 0.720, 0.500, 0.620, 1 }, hover = { 0.400, 0.170, 0.290, 1 },
      grad = { top = { 0.320, 0.130, 0.230 }, bottom = { 0.130, 0.045, 0.110 } }, gradDef = 1 },
    -- Discord: flat gray in three steps (bar dark, middle lighter), Blurple as accent, no graphics
    { key = "discord", sideGlow = 0, name = "Discord", desc = "Flat grey like Discord, blurple accent", accent = "5865f2", font = "ptsans",
      bg = { 0.192, 0.200, 0.220, 0.98 }, side = { 0.118, 0.122, 0.133, 1 }, panel = { 0.169, 0.176, 0.192, 1 }, raised = { 0.220, 0.227, 0.251, 1 },
      field = { 0.118, 0.122, 0.133, 1 }, line = { 0.247, 0.255, 0.278, 1 }, text = { 0.859, 0.871, 0.882, 1 }, muted = { 0.710, 0.729, 0.757, 1 },
      dim = { 0.502, 0.518, 0.557, 1 }, hover = { 0.208, 0.216, 0.235, 1 },
      grad = { top = { 0.192, 0.200, 0.220 }, bottom = { 0.192, 0.200, 0.220 } }, gradDef = 0 },
}
K.themeByKey = {}
for _, t in ipairs(K.THEMES) do K.themeByKey[t.key] = t end
-- more designs from add-on modules (guild module): design + optional skin; appears at the end of the design selection
function K.AddTheme(theme, skin)
    if not theme or K.themeByKey[theme.key] then return end
    K.THEMES[#K.THEMES + 1] = theme
    K.themeByKey[theme.key] = theme
    if skin then K.SKINS[theme.key] = skin end
end
-- default = the values the kit starts with
local STD = {}
for _, k in ipairs(PAL_KEYS) do local c = K.C[k] STD[k] = { c[1], c[2], c[3], c[4] } end
local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] or 1 } end

-- two-color design: one dark base color + one accent color, everything else is derived from them
K.DUO_PRESETS = {
    { name = "Night red", base = "15171d", acc = "ff4d6d" }, { name = "Ocean", base = "0b1622", acc = "1fb6ff" },
    { name = "Forest", base = "0f1712", acc = "52c47e" }, { name = "Lavender", base = "16121f", acc = "b38bff" },
    { name = "Sunset", base = "1b1210", acc = "ff8a3d" }, { name = "Glacier", base = "12181e", acc = "9fd8ff" },
    { name = "Gold", base = "15130d", acc = "e8b44a" }, { name = "Cherry blossom", base = "1b1218", acc = "ff7eb6" },
    { name = "Toxic", base = "101410", acc = "a8ff3c" }, { name = "Midnight", base = "0c0d14", acc = "6f7dff" },
    -- crazy combos: strong, colorful base tones
    { name = "Galaxy", base = "2a0f3d", acc = "39ff88" }, { name = "Retro", base = "0f1f4d", acc = "ff8c1a" },
    { name = "Burgundy", base = "3a0d1f", acc = "ffcc33" }, { name = "Lagoon", base = "0b3838", acc = "ff6f61" },
    { name = "Synthwave", base = "3d0d33", acc = "22e5ff" }, { name = "Jungle", base = "123320", acc = "ff3d9a" },
    -- more combos
    { name = "Horde", base = "1a0c0a", acc = "ff1200" }, { name = "Alliance", base = "0a1124", acc = "3d7bff" },
    { name = "Fires", base = "1c0e08", acc = "ffb000" }, { name = "Eis", base = "0d1a24", acc = "6fe7ff" },
    { name = "Gift", base = "141a0c", acc = "c6ff00" }, { name = "Shadow", base = "121014", acc = "9a7dff" },
    { name = "Rosegold", base = "1d1416", acc = "f2a28c" }, { name = "Smaragd", base = "08201a", acc = "1ee3a0" },
    { name = "Kupfer", base = "18110c", acc = "e07b39" }, { name = "Bernstein", base = "1a150a", acc = "ffcf4d" },
    { name = "Petrol", base = "0a1d22", acc = "00c2c7" }, { name = "Magenta", base = "1e0a1c", acc = "ff2bd6" },
    { name = "Mondlicht", base = "10131c", acc = "dfe6ff" }, { name = "Lava", base = "220a06", acc = "ff5a1f" },
    { name = "Arcane", base = "160c26", acc = "d26bff" }, { name = "Nordlicht", base = "071a1a", acc = "7dffb2" },
    { name = "Blutmond", base = "1a0610", acc = "ff3355" },
}
local duoCache
-- sideHex (optional): own color for the left bar; empty = derived from the base color
function K.DuoTheme(baseHex, accHex, sideHex)
    local key = (baseHex or "") .. ":" .. (accHex or "") .. ":" .. (sideHex or "")
    if duoCache and duoCache.ck == key then return duoCache end
    local b = K.FromHex(baseHex or "15171d") or { 0.08, 0.09, 0.11 }
    local a = K.FromHex(accHex or "ff4d6d") or { 1, 0.3, 0.42 }
    local function lit(c, t) return { math.min(1, c[1] + t), math.min(1, c[2] + t), math.min(1, c[3] + t), 1 } end
    local function mx(x, y, t) return { x[1] + (y[1] - x[1]) * t, x[2] + (y[2] - x[2]) * t, x[3] + (y[3] - x[3]) * t, 1 } end
    local function sc(c, f) return { c[1] * f, c[2] * f, c[3] * f, 1 } end
    local th = {
        key = "duo", name = "Two colours", desc = "Your base colour + accent", accent = accHex, sideGlow = 0.05,
        bg = { b[1], b[2], b[3], 0.97 }, side = (sideHex and sideHex ~= "" and K.FromHex(sideHex) and { K.FromHex(sideHex)[1], K.FromHex(sideHex)[2], K.FromHex(sideHex)[3], 1 }) or sc(b, 0.72), panel = mx(lit(b, 0.035), a, 0.025), raised = mx(lit(b, 0.075), a, 0.035),
        field = sc(b, 0.6), line = mx(lit(b, 0.10), a, 0.16), text = mx({ 0.95, 0.95, 0.95 }, a, 0.04),
        muted = mx({ 0.66, 0.66, 0.68 }, a, 0.10), dim = mx({ 0.43, 0.43, 0.45 }, a, 0.10), hover = mx(lit(b, 0.09), a, 0.05),
        grad = { top = mx(lit(b, 0.02), a, 0.10), bottom = sc(b, 0.55) }, gradDef = 1,
    }
    th.ck = key
    duoCache = th
    return th
end
-- 0.5.786: "Custom colors" are no longer a separate design but recolor the chosen design (s.colorOn). Style, border, font,
-- background graphic and click sounds stay from the design; only the palette (surfaces, lines, texts, gradient, accent) comes from the two colors.
local mergedCache
function K.CurrentTheme()
    local s = ns.db and ns.db.settings
    -- legacy: "duo" used to be its own design -> switch to the default design with custom colors
    if s and s.theme == "duo" then s.theme, s.colorOn = "glass", true end
    local base = K.themeByKey[s and s.theme or "glass"] or K.THEMES[1]
    if not (s and s.colorOn) then return base end
    local d = K.DuoTheme(s.duoBase, s.duoAccent, s.duoSide)
    local ck = base.key .. "|" .. tostring(d.ck)
    if mergedCache and mergedCache.mk == ck then return mergedCache end
    local t = {}
    for k, v in pairs(base) do t[k] = v end
    for _, k in ipairs(PAL_KEYS) do if d[k] then t[k] = d[k] end end
    t.grad, t.gradDef, t.accent = d.grad, d.gradDef, d.accent
    t.duoColors = true
    t.mk = ck
    mergedCache = t
    return t
end
-- background opacity 0.1..1 (Settings > Appearance / General)
function K.WindowAlpha()
    local s = ns.db and ns.db.settings
    local wa = tonumber(s and s.windowAlpha) or 1
    return math.max(0.1, math.min(1, wa))
end
--[[ APPEARANCE - order (later stage wins), everything from ns.db.settings, hence identical after /reload:
  1. Design (s.theme)             -> base palette K.C (bg/side/panel/... ), gradient, graphic, skin
     "duo" = two colors: palette from s.duoBase + s.duoAccent (+ s.duoSide = left bar)
  2. Single overrides             -> s.themeGrad (gradient), s.accent (own accent color, Admin.EffectiveAccent)
     A click on a design tile resets these overrides to the design's values.
  3. s.highContrast               -> texts/lines brighter, surfaces set off (on the finished palette)
  4. s.windowAlpha                -> opacity: window, sidebar AND surfaces (panel/raised/field/hover)
                                     evenly; texts and accent stay fully opaque
  5. s.frameAccent                -> Fensterrahmen in Akzentfarbe (K.StyleWindow)
  6. s.themeTexture               -> background graphic over the gradient, multiplied by opacity
  Apply: K.ApplyTheme() (palette) -> Admin.ApplyBrand(true) (accent + logos + rebuild) ]]
-- swap palette in K.C (+ high contrast + surface opacity)
function K.ApplyTheme()
    if K.ExtraThemeApply then K.ExtraThemeApply() end   -- colors of an add-on design (add-on module), otherwise nothing
    local th = K.CurrentTheme()
    local s = ns.db and ns.db.settings or {}
    for _, k in ipairs(PAL_KEYS) do
        local src = th[k] or STD[k]
        local c = K.C[k]
        c[1], c[2], c[3], c[4] = src[1], src[2], src[3], src[4] or 1
    end
    if s.highContrast then
        -- strong: gray texts almost white, dimmed text clearly readable, lines/borders visible, surfaces slightly set off
        local white = { 1, 1, 1, 1 }
        local t = mix(K.C.text, white, 0.8)
        local m = mix(K.C.muted, white, 0.7)
        local d = mix(K.C.dim, white, 0.5)
        local l = mix(K.C.line, white, 0.35)
        local pa = mix(K.C.panel, white, 0.04)
        local ra = mix(K.C.raised, white, 0.06)
        local fi = mix(K.C.field, { 0, 0, 0, 1 }, 0.5)
        for i = 1, 3 do
            K.C.text[i], K.C.muted[i], K.C.dim[i], K.C.line[i] = t[i], m[i], d[i], l[i]
            K.C.panel[i], K.C.raised[i], K.C.field[i] = pa[i], ra[i], fi[i]
        end
    end
    -- stage 4: opacity on the surfaces in the window - the same factor as window/sidebar
    -- (bg/side themselves get it via Texture:SetAlpha in ns.ApplyWindowAlpha, otherwise doubled)
    local wa = K.WindowAlpha()
    if wa < 1 then
        for _, k in ipairs({ "panel", "raised", "field", "hover" }) do
            local c = K.C[k]
            c[4] = math.max(0.08, (c[4] or 1) * wa)
        end
    end
end
-- gradient strength 0..1 (own setting or the design's default)
function K.GradStrength()
    local s = ns.db and ns.db.settings
    local v = s and s.themeGrad
    if v == nil then v = K.CurrentTheme().gradDef or 0 end
    return v
end

-- sidebar: the design's own texture (e.g. default: cool graphite with gradient + grain)
function K.StyleSide(main)
    local th, s = K.CurrentTheme(), ns.db and ns.db.settings or {}
    if not (main and main.sideTex) then return false end
    if th.sideTex and s.themeTexture ~= false then
        main.sideTex:SetTexture(ns.MEDIA .. "themes\\" .. th.sideTex)
        main.sideTex:SetVertexColor(1, 1, 1, 1)
        return true
    end
    return false
end

-- embers as background for any surface (0.5.509): sparks rise slowly and fade out.
-- K.Embers(parent, { n = 24, col = {r,g,b}, level = 1 }) -> Frame; :SetColor(r, g, b)
-- confetti burst (0.5.597): small flakes fly up from 'anchor' and fall (goal reached, vote).
-- one frame per parent frame is reused; with "Reduce animations" nothing happens.
function K.Burst(parent, anchor, n, cols)
    if (ns.db and ns.db.settings.noAnim) or not (parent and anchor) then return end
    local pl, pb = parent:GetLeft(), parent:GetBottom()
    local cx, cy = anchor:GetCenter()
    if not (pl and cx) then return end
    local k = anchor:GetEffectiveScale() / parent:GetEffectiveScale()
    local ax, ay = cx * k - pl, cy * k - pb
    local f = parent.oasisBurst
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f:SetAllPoints(parent)
        f:EnableMouse(false)
        f.p = {}
        parent.oasisBurst = f
    end
    f:SetFrameLevel(parent:GetFrameLevel() + 40)
    cols = cols or { C.accent, C.mint, C.amber, { 1, 1, 1 } }
    n = n or 28
    for i = 1, n do
        local q = f.p[i]
        if not q then q = { t = f:CreateTexture(nil, "OVERLAY") } f.p[i] = q end
        local c = cols[(i % #cols) + 1]
        q.t:SetColorTexture(c[1], c[2], c[3], 1)
        q.t:SetSize(3 + math.random() * 4, 5 + math.random() * 5)
        local a = math.random() * math.pi * 2
        local sp = 90 + math.random() * 160
        q.x, q.y = ax, ay
        q.vx, q.vy = math.cos(a) * sp * 0.7, 160 + math.random() * 220
        q.r, q.vr = math.random() * 6, (math.random() - 0.5) * 14
        q.life, q.max = 1.1 + math.random() * 0.5, 1.6
        q.t:Show()
    end
    for i = n + 1, #f.p do f.p[i].t:Hide() f.p[i].life = 0 end
    f:Show()
    f:SetScript("OnUpdate", function(self, el)
        local alive = false
        for _, q in ipairs(self.p) do
            if q.life > 0 then
                alive = true
                q.life = q.life - el
                q.vy = q.vy - 520 * el
                q.vx = q.vx * (1 - 0.8 * el)
                q.x, q.y = q.x + q.vx * el, q.y + q.vy * el
                q.r = q.r + q.vr * el
                q.t:ClearAllPoints()
                q.t:SetPoint("CENTER", self, "BOTTOMLEFT", q.x, q.y)
                if q.t.SetRotation then q.t:SetRotation(q.r) end
                q.t:SetAlpha(math.max(0, math.min(1, q.life / 0.5)))
                if q.life <= 0 then q.t:Hide() end
            end
        end
        if not alive then self:SetScript("OnUpdate", nil) self:Hide() end
    end)
end
-- rising text ("+5") above an element, fades out after ~0.9 s
function K.FloatText(anchor, text, color)
    if not anchor or (ns.db and ns.db.settings.noAnim) then return end
    local p = anchor:GetParent() or anchor
    p.oasisFloat = p.oasisFloat or {}
    local fs
    for _, x in ipairs(p.oasisFloat) do if not x.busy then fs = x break end end
    if not fs then
        fs = p:CreateFontString(nil, "OVERLAY")
        K.SetFontSafe(fs, K.FONT_HEAD, 14, "OUTLINE", K.FONT)
        p.oasisFloat[#p.oasisFloat + 1] = fs
    end
    fs.busy = true
    color = color or C.mint
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetText(text)
    fs:Show()
    K.Tween(fs, 0.9, function(q)
        fs:ClearAllPoints()
        fs:SetPoint("BOTTOM", anchor, "TOP", 0, 2 + 22 * q)
        fs:SetAlpha(q < 0.6 and 1 or (1 - (q - 0.6) / 0.4))
    end, function() fs:Hide() fs.busy = nil end)
end

function K.Embers(parent, o)
    o = o or {}
    local em = CreateFrame("Frame", nil, parent)
    em:SetAllPoints(parent)
    if em.SetClipsChildren then em:SetClipsChildren(true) end
    em:SetFrameLevel(parent:GetFrameLevel() + (o.level or 1))
    em:EnableMouse(false)
    em.col = o.col or { 1, 0.55, 0.25 }
    function em:SetColor(r, g, b) self.col = { r, g, b } end
    em.p = {}
    for i = 1, (o.n or 24) do
        local t = em:CreateTexture(nil, "ARTWORK")
        t:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Media\\ember")
        t:SetBlendMode("ADD")
        t:Hide()
        em.p[i] = { t = t, life = math.random() * 4 }   -- staggered start
    end
    em:SetScript("OnUpdate", function(self, el)
        if ns.db and ns.db.settings.noAnim then for _, q in ipairs(self.p) do q.t:Hide() end return end
        -- 0.5.722: throttle to about 30 Hz (previously every frame)
        self.acc = (self.acc or 0) + el
        if self.acc < 0.033 then return end
        el, self.acc = self.acc, 0
        local w, h = self:GetWidth(), self:GetHeight()
        if not w or w < 20 then return end
        local c = self.col
        for _, q in ipairs(self.p) do
            q.life = q.life - el
            if q.life <= 0 then
                if true then
                    q.max = 3.5 + math.random() * 4.5
                    q.life = q.max
                    q.x0 = math.random() * w
                    q.y = -4 - math.random() * 8
                    q.vy = (o.speed or 10) * (0.6 + math.random() * 0.9)
                    q.ph = math.random() * 6.28
                    q.sz = (o.size or 5) * (0.5 + math.random() * 0.8)
                    q.a = 0.45 + math.random() * 0.45
                    q.t:SetSize(q.sz, q.sz)
                    q.t:Show()
                else
                    q.t:Hide()
                end
            end
            if q.max and q.life > 0 then
                q.y = q.y + q.vy * el
                local k = 1 - q.life / q.max
                q.t:ClearAllPoints()
                q.t:SetPoint("CENTER", self, "BOTTOMLEFT", q.x0 + math.sin(q.ph + k * 5) * 7, q.y)
                local warm = 0.35
                q.t:SetVertexColor(math.min(1, c[1] + (1 - c[1]) * warm), math.min(1, c[2] + (0.7 - c[2]) * warm), c[3] * (1 - warm))
                q.t:SetAlpha(math.sin(k * math.pi) * q.a * (o.alpha or 0.8) * (0.8 + 0.2 * math.sin(q.ph + k * 30)))
                if q.y > h + 4 then q.life = 0 end
            end
        end
    end)
    return em
end

-- embers in the sidebar: sparks in the accent color with a warm core rise from below,
-- flicker, swirl slightly and burn out towards the top
local EMBER = "Interface\\AddOns\\" .. ADDON .. "\\Media\\ember"
function K.SideParticles(main)
    local th, s = K.CurrentTheme(), ns.db and ns.db.settings or {}
    local side = main and main.sideTex and main.sideTex:GetParent()
    if not side then return end
    local want = th.particles and not s.noAnim
    if not want then
        if main.particles then main.particles:Hide() end
        return
    end
    if main.particles then main.particles:Show() return end
    local pf = CreateFrame("Frame", nil, side)
    pf:SetAllPoints(side)
    -- above the navigation (the rows have their own surfaces), doesn't catch clicks
    pf:SetFrameLevel(side:GetFrameLevel() + 30)
    pf:EnableMouse(false)
    main.particles = pf
    local dots = {}
    -- color: accent, warmed towards yellow/orange (like embers)
    local function emberColor()
        local c = K.C.accent
        local warm = math.random() * 0.45
        return math.min(1, c[1] + (1 - c[1]) * warm), math.min(1, c[2] + (0.75 - c[2]) * warm * 0.8), c[3] * (1 - warm * 0.6)
    end
    local function reset(p, anywhere)
        local w, h = side:GetWidth() or 200, side:GetHeight() or 600
        p.x = 6 + math.random() * (w - 12)
        p.y = anywhere and math.random() * h * 0.7 or (-4 - math.random() * 20)
        p.vy = 14 + math.random() * 26                -- rising
        p.vx = (math.random() - 0.5) * 6
        p.sway, p.phase, p.freq = 2 + math.random() * 7, math.random() * 6.28, 0.8 + math.random() * 1.6
        p.life = 0.55 + math.random() * 0.45           -- fraction of the height until it burns out
        p.a = 0.45 + math.random() * 0.45
        p.flick = math.random() * 6.28
        local sz = 4 + math.random() * 7
        p.t:SetSize(sz, sz)
        p.t:SetVertexColor(emberColor())
    end
    for i = 1, 34 do
        local t = pf:CreateTexture(nil, "OVERLAY")
        t:SetTexture(EMBER)
        t:SetBlendMode("ADD")
        local p = { t = t }
        reset(p, true)
        dots[i] = p
    end
    local acc = 0
    pf:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.025 then return end
        local dt = acc
        acc = 0
        local h = side:GetHeight() or 600
        for _, p in ipairs(dots) do
            p.y = p.y + p.vy * dt
            p.x = p.x + p.vx * dt
            p.phase = p.phase + dt * p.freq
            p.flick = p.flick + dt * (7 + math.random() * 6)
            local rise = p.y / (h * p.life)               -- 0 bottom .. 1 burnt out
            if rise >= 1 then reset(p) rise = 0 end
            local fadeIn = math.min(1, (p.y + 20) / 50)
            local glow = (1 - rise) ^ 1.4 * fadeIn * (0.75 + 0.25 * math.sin(p.flick))
            p.t:SetAlpha(math.max(0, p.a * glow))
            p.t:ClearAllPoints()
            p.t:SetPoint("CENTER", side, "BOTTOMLEFT", p.x + math.sin(p.phase) * p.sway, p.y)
        end
    end)
end

-- 0.6.165: decorative border for windows (main window, start window): 1 px all around in the accent color, with a bright
-- core at the top, plus every now and then a short shimmer once around the border. Lies above the content (otherwise covered).
-- R = corner radius (the lines end before the round corners)
function K.FrameLines(host, R)
    R = R or 12
    local fr = CreateFrame("Frame", nil, host)
    fr:SetAllPoints(host)
    fr:EnableMouse(false)
    fr:SetFrameLevel(math.min(9000, host:GetFrameLevel() + 199))
    host:HookScript("OnShow", function() fr:SetFrameStrata(host:GetFrameStrata()) fr:SetFrameLevel(math.min(9000, host:GetFrameLevel() + 199)) end)

        local function tx(layer) local t = fr:CreateTexture(nil, layer or "OVERLAY") return t end
        -- 0.6.163: thinner and calmer - everything 1 px; accent on top, strongest towards the center and fading out to both
        -- sides, directly below a bright hairline (fine edge), sides equally strong and fading downward
        local top = tx() top:SetHeight(1) top:SetPoint("TOPLEFT", R, 0) top:SetPoint("TOP", 0, 0)
        local top2 = tx() top2:SetHeight(1) top2:SetPoint("TOPLEFT", top, "TOPRIGHT") top2:SetPoint("TOPRIGHT", -R, 0)
        local inner = tx() inner:SetHeight(1) inner:SetPoint("TOPLEFT", R, -1) inner:SetPoint("TOPRIGHT", -R, -1)
        -- 0.6.164: sides over the full height, at the bottom an accent line that lights up towards the center
        local eL = tx() eL:SetWidth(1) eL:SetPoint("TOPLEFT", 0, -R) eL:SetPoint("BOTTOMLEFT", 0, R)
        local eR = tx() eR:SetWidth(1) eR:SetPoint("TOPRIGHT", 0, -R) eR:SetPoint("BOTTOMRIGHT", 0, R)
        local bot = tx() bot:SetHeight(1) bot:SetPoint("BOTTOMLEFT", R, 0) bot:SetPoint("BOTTOM", 0, 0)
        local bot2 = tx() bot2:SetHeight(1) bot2:SetPoint("BOTTOMLEFT", bot, "BOTTOMRIGHT") bot2:SetPoint("BOTTOMRIGHT", -R, 0)
        -- bright core in the middle of the top line (like a light spot on a metal edge)
        local core = tx() core:SetHeight(1) core:SetWidth(160) core:SetBlendMode("ADD")
        local core2 = tx() core2:SetHeight(1) core2:SetWidth(140) core2:SetPoint("TOPLEFT", core, "TOPRIGHT") core2:SetBlendMode("ADD")
        core:SetPoint("TOPLEFT", fr, "TOPLEFT", R, 0) core:SetWidth(60)   -- 0.6.167: core at the top left
        -- 0.6.166: thickness in REAL screen pixels - with UI scale < 1, "1" was less than a pixel and WoW rounded the
        -- lines away on the pixel grid (border and shimmer were therefore invisible)
        top:ClearAllPoints() top:SetPoint("TOPLEFT", R, 0) top:SetPoint("TOPRIGHT", fr, "TOP", 0, 0)
        fr.lines = { top, top2, eL, eR, bot, bot2, inner }
        -- 0.6.166: round corners - quarter arcs (Media/corner_arc, Tools/make_corner_arc.py) connect the lines,
        -- previously they ended before the curve and the gray window edge remained there
        fr.corners = {}
        for _, c in ipairs({ { "TOPLEFT", 0, 1, 0, 1, true }, { "TOPRIGHT", 1, 0, 0, 1, true },
            { "BOTTOMLEFT", 0, 1, 1, 0, false }, { "BOTTOMRIGHT", 1, 0, 1, 0, false } }) do
            local t = tx()
            t:SetTexture(ns.MEDIA .. "corner_arc")
            t:SetTexCoord(c[2], c[3], c[4], c[5])
            t:SetSize(R, R)
            t:SetPoint(c[1], fr, c[1], 0, 0)
            t.isTop = c[6]
            fr.corners[#fr.corners + 1] = t
        end
        local thick = { { top, "h", 1 }, { top2, "h", 1 }, { core, "h", 1 }, { core2, "h", 1 }, { inner, "h", 1, 2 },
            { eL, "v", 1 }, { eR, "v", 1 }, { bot, "h", 1 }, { bot2, "h", 1 } }
        function fr.Pixel()
            local ph = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize()) or 0
            local es = fr:GetEffectiveScale() or 1
            if not ph or ph <= 0 or es <= 0 then return 1 end
            return (768 / ph) / es
        end
        function fr.Relayout()
            local px = fr.Pixel()
            for _, x in ipairs(thick) do
                local t, n = x[1], x[3]
                if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, false) pcall(t.SetTexelSnappingBias, t, 0) end
                if x[2] == "h" then t:SetHeight(px * n) else t:SetWidth(px * n) end
            end
            inner:ClearAllPoints() inner:SetPoint("TOPLEFT", R, -px) inner:SetPoint("TOPRIGHT", -R, -px)
            fr.px = px
        end
        fr.Relayout()
        fr:HookScript("OnSizeChanged", fr.Relayout)
        fr:HookScript("OnShow", fr.Relayout)
        if ns.On then ns.On("UI_SCALE_CHANGED", fr.Relayout) ns.On("DISPLAY_SIZE_CHANGED", fr.Relayout) end
        local last
        local function paint()
            local ac = K.C.accent or { 1, 0.2, 0.2 }
            local key = ac[1] .. ":" .. ac[2] .. ":" .. ac[3]
            if key == last then return end
            last = key
            -- 0.6.167: subtle, like light from the top left - strongest there, fades out to the right along the top and downward
            -- along the left; right side and bottom only a hint
            local function A(x) return { ac[1], ac[2], ac[3], x } end
            K.Gradient(top, "HORIZONTAL", A(0.70), A(0.22))
            K.Gradient(top2, "HORIZONTAL", A(0.22), A(0.04))
            K.Gradient(inner, "HORIZONTAL", { 1, 1, 1, 0.06 }, { 1, 1, 1, 0 })
            K.Gradient(eL, "VERTICAL", A(0), A(0.55))
            K.Gradient(eR, "VERTICAL", A(0), A(0.08))
            K.Gradient(bot, "HORIZONTAL", { 1, 1, 1, 0.01 }, { 1, 1, 1, 0.05 })
            K.Gradient(bot2, "HORIZONTAL", { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.01 })
            -- bright core now sits at the top left (where the light comes from)
            K.Gradient(core, "HORIZONTAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.30 })
            K.Gradient(core2, "HORIZONTAL", { 1, 1, 1, 0.30 }, { 1, 1, 1, 0 })
            local ca = { 0.70, 0.04, 0.02, 0.01 }   -- top left, top right, bottom left, bottom right
            for i, t in ipairs(fr.corners) do t:SetVertexColor(ac[1], ac[2], ac[3], ca[i]) end
        end
        paint()
        -- 0.6.163: every now and then a short bright shimmer runs once around the border (clockwise,
        -- 1.6 s, every 14 s). Two halves per direction that get brighter towards the center; off with "Animations off" (noAnim)
        local function streak(horiz)
            local a, b = tx(), tx()
            a:SetBlendMode("ADD") b:SetBlendMode("ADD")
            if horiz then
                a:SetSize(60, 1) b:SetSize(60, 1)
                b:SetPoint("LEFT", a, "RIGHT")
            else
                a:SetSize(1, 60) b:SetSize(1, 60)
                b:SetPoint("TOP", a, "BOTTOM")
            end
            a:Hide() b:Hide()
            return { a = a, b = b, horiz = horiz }
        end
        local sh, sv = streak(true), streak(false)
        local function tintStreak(s, alpha)
            local ac = K.C.accent or { 1, 0.2, 0.2 }
            local r, g, bl = 0.55 + ac[1] * 0.45, 0.55 + ac[2] * 0.45, 0.55 + ac[3] * 0.45
            local dir = s.horiz and "HORIZONTAL" or "VERTICAL"
            -- VERTICAL runs from bottom to top: upper half bright at the bottom, lower half bright at the top
            if s.horiz then
                K.Gradient(s.a, dir, { r, g, bl, 0 }, { r, g, bl, alpha })
                K.Gradient(s.b, dir, { r, g, bl, alpha }, { r, g, bl, 0 })
            else
                K.Gradient(s.a, dir, { r, g, bl, alpha }, { r, g, bl, 0 })
                K.Gradient(s.b, dir, { r, g, bl, 0 }, { r, g, bl, alpha })
            end
        end
        local function place(s, x, y)
            s.a:ClearAllPoints()
            local th = 1 * (fr.px or 1)   -- 0.6.167: 1 real pixel (0.6.166: 2) (otherwise rounded away with UI scale < 1)
            if s.horiz then s.a:SetHeight(th) s.b:SetHeight(th) else s.a:SetWidth(th) s.b:SetWidth(th) end
            if s.horiz then s.a:SetPoint("RIGHT", fr, "TOPLEFT", x, y) else s.a:SetPoint("BOTTOM", fr, "TOPLEFT", x, y) end
            s.a:Show() s.b:Show()
        end
        local function hide(s) s.a:Hide() s.b:Hide() end
        local SH_EVERY, SH_RUN = 14, 1.6
        local shT = SH_EVERY - 3   -- first shimmer shortly after opening
        fr.shimmer = { h = sh, v = sv }
        local acc = 0
        fr:SetScript("OnUpdate", function(_, el)
            el = el or 0
            acc = acc + el
            if acc >= 0.5 then acc = 0 paint() end
            local st = ns.db and ns.db.settings
            if (st and (st.noAnim or st.frameShimmer == false)) then hide(sh) hide(sv) return end
            shT = shT + el
            if shT < SH_EVERY then return end
            local p = (shT - SH_EVERY) / SH_RUN
            if p >= 1 then shT = 0 hide(sh) hide(sv) return end
            local w, h = fr:GetWidth() or 0, fr:GetHeight() or 0
            if w <= 0 or h <= 0 then return end
            -- gently in and out, brightest in the middle
            local alpha = 0.45 * math.sin(p * math.pi)
            local d = p * (2 * w + 2 * h)
            if d < w then                       -- top, to the right
                hide(sv) tintStreak(sh, alpha) place(sh, d, -0.5)
            elseif d < w + h then               -- right, downward
                hide(sh) tintStreak(sv, alpha) place(sv, w - 0.5, -(d - w))
            elseif d < 2 * w + h then           -- bottom, to the left
                hide(sv) tintStreak(sh, alpha) place(sh, w - (d - w - h), -h + 0.5)
            else                                -- left, upward
                hide(sh) tintStreak(sv, alpha) place(sv, 0.5, -h + (d - 2 * w - h))
            end
        end)
    return fr
end

-- 0.6.186: image border outside around the window (guild module, Media/window_frame from Tools/make_window_frame.py).
-- 12 parts: corners and middle ornament top/bottom keep their shape, the edges between are stretched.
-- measurements in source pixels (image 1509x1012 after cropping); k = UI units per source pixel.
function K.ImageFrame(host, k)
    k = k or 0.3
    -- 0.6.279: "Minimalist red sci-fi HUD frame" (template on black, make_window_frame.py --black): gray edge,
    -- red line, light dots top/bottom in the middle (previously 0.6.188 lava ember fantasy frame 1504x991)
    -- 0.6.280: gray outer band removed (only red line + ember) -> smaller crop, narrower bands
    local SW, SH = 1398, 1028
    local BT, BB, BL, BR = 20, 20, 14, 13        -- bands (up to the inner edge)
    local CW, CHT, CHB = 60, 60, 60              -- corners (bevel)
    local M1, M2 = 599, 799                      -- light dot top/bottom stays unstretched
    local TEX = "Interface\\AddOns\\Oasis_Guild\\Media\\window_frame"
    local OV = 2                                 -- how far the inner edge overlaps the window
    local fr = CreateFrame("Frame", nil, host)
    fr:EnableMouse(false)
    fr:SetPoint("TOPLEFT", host, "TOPLEFT", -(BL * k) + OV, BT * k - OV)
    fr:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", BR * k - OV, -(BB * k) + OV)
    fr:SetFrameStrata(host:GetFrameStrata())
    fr:SetFrameLevel(math.min(9000, host:GetFrameLevel() + 198))
    host:HookScript("OnShow", function() fr:SetFrameStrata(host:GetFrameStrata()) fr:SetFrameLevel(math.min(9000, host:GetFrameLevel() + 198)) end)
    -- 0.6.191: each part twice - base image (bronze) and on top the ember (window_frame_glow, white) in the
    -- frame color (setting frameColor, accent color if none chosen), additive
    fr.glows = {}
    local function piece(x1, y1, x2, y2)
        local t = fr:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexture(TEX)
        t:SetTexCoord(x1 / SW, x2 / SW, y1 / SH, y2 / SH)
        local g = fr:CreateTexture(nil, "OVERLAY", nil, 2)
        g:SetTexture(TEX .. "_glow")
        g:SetTexCoord(x1 / SW, x2 / SW, y1 / SH, y2 / SH)
        g:SetBlendMode("ADD")
        g:SetAllPoints(t)
        fr.glows[#fr.glows + 1] = g
        return t
    end
    local P = {}
    -- corners
    P.tl = piece(0, 0, CW, CHT)             P.tl:SetSize(CW * k, CHT * k) P.tl:SetPoint("TOPLEFT")
    P.tr = piece(SW - CW, 0, SW, CHT)       P.tr:SetSize(CW * k, CHT * k) P.tr:SetPoint("TOPRIGHT")
    P.bl = piece(0, SH - CHB, CW, SH)       P.bl:SetSize(CW * k, CHB * k) P.bl:SetPoint("BOTTOMLEFT")
    P.br = piece(SW - CW, SH - CHB, SW, SH) P.br:SetSize(CW * k, CHB * k) P.br:SetPoint("BOTTOMRIGHT")
    -- middle pieces
    P.tm = piece(M1, 0, M2, BT)             P.tm:SetSize((M2 - M1) * k, BT * k) P.tm:SetPoint("TOP")
    P.bm = piece(M1, SH - BB, M2, SH)       P.bm:SetSize((M2 - M1) * k, BB * k) P.bm:SetPoint("BOTTOM")
    -- edges top/bottom left and right of the middle (stretched)
    P.t1 = piece(CW, 0, M1, BT)             P.t1:SetHeight(BT * k) P.t1:SetPoint("TOPLEFT", P.tl, "TOPRIGHT") P.t1:SetPoint("TOPRIGHT", P.tm, "TOPLEFT")
    P.t2 = piece(M2, 0, SW - CW, BT)        P.t2:SetHeight(BT * k) P.t2:SetPoint("TOPLEFT", P.tm, "TOPRIGHT") P.t2:SetPoint("TOPRIGHT", P.tr, "TOPLEFT")
    P.b1 = piece(CW, SH - BB, M1, SH)       P.b1:SetHeight(BB * k) P.b1:SetPoint("BOTTOMLEFT", P.bl, "BOTTOMRIGHT") P.b1:SetPoint("BOTTOMRIGHT", P.bm, "BOTTOMLEFT")
    P.b2 = piece(M2, SH - BB, SW - CW, SH)  P.b2:SetHeight(BB * k) P.b2:SetPoint("BOTTOMLEFT", P.bm, "BOTTOMRIGHT") P.b2:SetPoint("BOTTOMRIGHT", P.br, "BOTTOMLEFT")
    -- sides (stretched)
    P.l = piece(0, CHT, BL, SH - CHB)       P.l:SetWidth(BL * k) P.l:SetPoint("TOPLEFT", P.tl, "BOTTOMLEFT") P.l:SetPoint("BOTTOMLEFT", P.bl, "TOPLEFT")
    P.r = piece(SW - BR, CHT, SW, SH - CHB) P.r:SetWidth(BR * k) P.r:SetPoint("TOPRIGHT", P.tr, "BOTTOMRIGHT") P.r:SetPoint("BOTTOMRIGHT", P.br, "TOPRIGHT")
    fr.pieces = P
    local lastKey
    function fr.Tint()
        local st = ns.db and ns.db.settings
        local hex = st and st.frameColor
        local c = (hex and hex ~= "" and K.FromHex and K.FromHex(hex)) or K.C.accent or { 1, 0.4, 0.15 }
        local key = c[1] .. ":" .. c[2] .. ":" .. c[3]
        if key == lastKey then return end
        lastKey = key
        -- brighten a bit so the ember glows even with dark colors
        local r, g, b = math.min(1, c[1] * 1.15 + 0.08), math.min(1, c[2] * 1.15 + 0.08), math.min(1, c[3] * 1.15 + 0.08)
        for _, t in ipairs(fr.glows) do t:SetVertexColor(r, g, b, 1) end
    end
    fr.Tint()
    -- 0.6.338: very subtle shimmer - every 8-12 s a small light dot fades in at a random spot,
    -- glides a short distance along the line and fades out again; off with "Animations off"
    local TRAIL = 20   -- 0.6.436: long, softly fading tail
    fr.spark = {}
    for i = 1, TRAIL do
        local t = fr:CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetTexture(ns.MEDIA .. "ember")
        t:SetBlendMode("ADD")
        local sz = (i == 1) and 12 or math.max(4, 10 - i * 0.3)   -- 0.6.436: smaller, more subtle
        t:SetSize(sz, sz)
        t:SetVertexColor(1, 0.82, 0.62)
        t:Hide()
        fr.spark[i] = t
    end
    -- path on the line: corner points clockwise (y downward), length is recalculated per size
    local function path(W, H)
        local ix, iy, c = BL * k * 0.55, BT * k * 0.55, CW * k * 0.62
        local P = { { c, iy }, { W - c, iy }, { W - ix, c }, { W - ix, H - c }, { W - c, H - iy }, { c, H - iy }, { ix, H - c }, { ix, c } }
        local seg, total = {}, 0
        for i = 1, #P do
            local a, b = P[i], P[i % #P + 1]
            local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
            seg[i] = { a = a, b = b, len = len, at = total }
            total = total + len
        end
        return seg, total
    end
    local function pointAt(seg, total, d)
        d = d % total
        for _, sg in ipairs(seg) do
            if d <= sg.at + sg.len then
                local q = (sg.len > 0) and (d - sg.at) / sg.len or 0
                return sg.a[1] + (sg.b[1] - sg.a[1]) * q, sg.a[2] + (sg.b[2] - sg.a[2]) * q
            end
        end
        return seg[1].a[1], seg[1].a[2]
    end
    local acc, lastW, lastH, segs, total = 0, 0, 0, nil, 0
    local wait, run, d0, len, dir = 3, nil, 0, 110, 1   -- pause until the next flash / running flash (0..1)
    local fAcc = 0
    fr:SetScript("OnUpdate", function(_, el)
        -- performance (0.6.479): at most 30x per second (previously every frame, 20 tail points)
        fAcc = fAcc + (el or 0)
        if fAcc < 0.033 then return end
        el, fAcc = fAcc, 0
        acc = acc + (el or 0)
        if acc >= 0.5 then acc = 0 fr.Tint() end
        local st = ns.db and ns.db.settings
        if st and st.noAnim then
            for _, t in ipairs(fr.spark) do t:Hide() end
            return
        end
        local W, H = fr:GetWidth() or 0, fr:GetHeight() or 0
        if W < 50 or H < 50 then return end
        if W ~= lastW or H ~= lastH or not segs then lastW, lastH = W, H segs, total = path(W, H) end
        if not run then
            wait = wait - (el or 0)
            for _, t in ipairs(fr.spark) do t:Hide() end
            if wait > 0 then return end
            -- 0.6.432: like the top bar - long stretch in a random direction
            run, d0 = 0, math.random() * total
            len, dir = total * (0.25 + math.random() * 0.25), (math.random() < 0.5) and 1 or -1
        end
        run = run + (el or 0) / 5            -- 0.6.432: 5 s per run
        if run >= 1 then run, wait = nil, 3 + math.random() * 5 return end
        local fade = math.sin(run * math.pi) ^ 0.8   -- fade in and out softly
        local d = d0 + dir * run * len
        for i, t in ipairs(fr.spark) do
            local x, y = pointAt(segs, total, d - dir * (i - 1) * 4)
            t:ClearAllPoints()
            t:SetPoint("CENTER", fr, "TOPLEFT", x, -y)
            -- 0.6.375: with ADD SetAlpha doesn't work reliably -> brightness into the color (soft fade in/out)
            local kk = fade * ((i == 1) and 0.42 or (0.3 * (1 - (i - 1) / TRAIL) ^ 2))   -- 0.6.436: more subtle, gradient
            t:SetAlpha(1)
            t:SetVertexColor(1 * kk, 0.82 * kk, 0.62 * kk, 1)
            t:Show()
        end
    end)
    -- 0.6.190: border can be grabbed to move - four thin grip strips on the bands (inner area stays
    -- free), they pass dragging on to the window (its own drag scripts -> position is saved)
    local function grip(p1, p2, w, h)
        local g = CreateFrame("Frame", nil, fr)
        g:SetPoint(p1) g:SetPoint(p2)
        if w then g:SetWidth(w) end
        if h then g:SetHeight(h) end
        g:EnableMouse(true)
        g:RegisterForDrag("LeftButton")
        g:SetScript("OnDragStart", function()
            local src = host.dragHead or host
            local fn = src:GetScript("OnDragStart")
            if fn then fn(src, "LeftButton") elseif host:IsMovable() then host:StartMoving() end
        end)
        g:SetScript("OnDragStop", function()
            local src = host.dragHead or host
            local fn = src:GetScript("OnDragStop")
            if fn then fn(src) else host:StopMovingOrSizing() end
        end)
        return g
    end
    fr.grips = {
        grip("TOPLEFT", "TOPRIGHT", nil, BT * k),
        grip("BOTTOMLEFT", "BOTTOMRIGHT", nil, BB * k),
        grip("TOPLEFT", "BOTTOMLEFT", BL * k, nil),
        grip("TOPRIGHT", "BOTTOMRIGHT", BR * k, nil),
    }
    return fr
end

-- 0.6.192: image border on/off (setting imageFrame, default on). Off = slim border with shimmer (frameLines)
function K.ApplyFrameStyle(host)
    if not host then return end
    local st = ns.db and ns.db.settings
    local on = host.imageFrame and not (st and st.imageFrame == false)
    if host.imageFrame then host.imageFrame:SetShown(on and true or false) end
    if host.frameLines then host.frameLines:SetShown(not on) end
    if host.lineFrame then host.lineFrame:SetAlpha(on and 0 or 0.35) end
end

-- 0.6.281: the same image border (red line + ember) narrow around every box in the addon (K.ApplySkin "panel").
-- Guild module only; follows "Decorated window frame" (imageFrame) and "Frame around boxes too" (boxFrame).
-- measurements like K.ImageFrame (source pixels after cropping), without middle piece: edges from the piece next to the corner.
K.boxFrames = setmetatable({}, { __mode = "k" })
local BOX = { SW = 1398, SH = 1028, BT = 20, BB = 20, BL = 14, BR = 13, C = 60, k = 0.16, alpha = 0.5 }
local BOX_BEVEL = BOX.C * BOX.k   -- edge length of the bevel (K.RoundMask cuts boxes with border the same way)
local function boxOn()
    local st = ns.db and ns.db.settings
    return ns.GuildPack ~= nil and not (st and (st.imageFrame == false or st.boxFrame == false))
end
local function frameGlowColor()
    local st = ns.db and ns.db.settings
    local hex = st and st.frameColor
    local c = (hex and hex ~= "" and K.FromHex and K.FromHex(hex)) or K.C.accent or { 1, 0.4, 0.15 }
    return math.min(1, c[1] * 1.15 + 0.08), math.min(1, c[2] * 1.15 + 0.08), math.min(1, c[3] * 1.15 + 0.08)
end
-- minH: smallest height for a border (glass boxes: 40, so rows and buttons stay free)
function K.BoxFrame(box, minH)
    if not box or box.boxFrame or box.noBoxFrame or not ns.GuildPack then return end
    local B, k = BOX, BOX.k
    local TEX = "Interface\\AddOns\\Oasis_Guild\\Media\\window_frame"
    local fr = CreateFrame("Frame", nil, box)
    fr:SetAllPoints()
    fr:EnableMouse(false)
    fr:SetAlpha(BOX.alpha)   -- 0.6.284: weaker than the window frame
    fr:SetFrameLevel(math.min(9000, box:GetFrameLevel() + 3))
    fr.glows = {}
    fr.pieces = {}   -- 0.6.364: line parts, so pages can recolor the border (e.g. profile black)
    local function piece(x1, y1, x2, y2)
        local t = fr:CreateTexture(nil, "OVERLAY", nil, 1)
        t:SetTexture(TEX)
        t:SetTexCoord(x1 / B.SW, x2 / B.SW, y1 / B.SH, y2 / B.SH)
        local g = fr:CreateTexture(nil, "OVERLAY", nil, 2)
        g:SetTexture(TEX .. "_glow")
        g:SetTexCoord(x1 / B.SW, x2 / B.SW, y1 / B.SH, y2 / B.SH)
        g:SetBlendMode("ADD")
        g:SetAllPoints(t)
        fr.glows[#fr.glows + 1] = g
        fr.pieces[#fr.pieces + 1] = t
        return t
    end
    local SW, SH, C2, E = B.SW, B.SH, B.C, B.C + 120   -- E: end of the edge piece next to the corner
    local cs = B.C * k
    local tl = piece(0, 0, C2, C2)             tl:SetSize(cs, cs) tl:SetPoint("TOPLEFT")
    local tr = piece(SW - C2, 0, SW, C2)       tr:SetSize(cs, cs) tr:SetPoint("TOPRIGHT")
    local bl = piece(0, SH - C2, C2, SH)       bl:SetSize(cs, cs) bl:SetPoint("BOTTOMLEFT")
    local br = piece(SW - C2, SH - C2, SW, SH) br:SetSize(cs, cs) br:SetPoint("BOTTOMRIGHT")
    local t = piece(C2, 0, E, B.BT)            t:SetHeight(B.BT * k) t:SetPoint("TOPLEFT", tl, "TOPRIGHT") t:SetPoint("TOPRIGHT", tr, "TOPLEFT")
    local b = piece(C2, SH - B.BB, E, SH)      b:SetHeight(B.BB * k) b:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT") b:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local l = piece(0, C2, B.BL, C2 + 120)     l:SetWidth(B.BL * k) l:SetPoint("TOPLEFT", tl, "BOTTOMLEFT") l:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
    local r = piece(SW - B.BR, C2, SW, C2 + 120) r:SetWidth(B.BR * k) r:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT") r:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    -- boxes that are too small (corners would overlap) get no border
    local function fit()
        local w, h = box:GetWidth() or 0, box:GetHeight() or 0
        -- the main window has its own large frame
        fr:SetShown(boxOn() and not box.imageFrame and not box.noBoxFrame and w >= cs * 2 + 4 and h >= math.max(cs * 2 + 4, minH or 0))
    end
    box:HookScript("OnSizeChanged", fit)
    -- 0.6.315: cut everything covering the whole box (images, surfaces - also in direct child frames) into the
    -- beveled corners. Runs after resize/show so images created later are included.
    local pend
    local function clip()
        pend = nil
        if fr:IsShown() and K.ClipBox then pcall(K.ClipBox, box) end
    end
    local function later() if not pend then pend = true C_Timer.After(0, clip) end end
    box:HookScript("OnSizeChanged", later)
    box:HookScript("OnShow", later)
    later()
    fr.fit = fit
    local cr, cg, cb = frameGlowColor()
    for _, g in ipairs(fr.glows) do g:SetVertexColor(cr, cg, cb, 1) end
    box.boxFrame = fr
    K.boxFrames[fr] = true
    fit()
    return fr
end
-- setting or border color changed: update all box borders (twice per second, only on change)
-- 0.6.283: buttons as images (guild module, Tools/make_buttons.py): normal / hover (brighter line) / active (filled red,
-- on press and permanently for main buttons). Follows the same switches as the box border (imageFrame, boxFrame).
-- images 512x128, corner 24 px (bevel) -> 9-slice via K.NineSlice, ember not recolored (image is red).
local BTN_TEX = "Interface\\AddOns\\Oasis_Guild\\Media\\btn_"
local BTN_N = { w = 1, h = 1, cx = 24 / 512, cy = 24 / 128, center = true }
K.imageButtons = setmetatable({}, { __mode = "k" })
function K.ImageButton(b)
    if not (b and boxOn()) or b.imgBtn then return b and b.imgBtn ~= nil end
    local r = math.max(5, math.floor((b:GetHeight() or 24) * 0.22))
    local sets = {}
    for _, st in ipairs({ "normal", "hover", "active" }) do
        local n = {}
        for k2, v in pairs(BTN_N) do n[k2] = v end
        n.file = BTN_TEX .. st
        sets[st] = K.NineSlice(b, n, r, "BACKGROUND", 3, true)
    end
    -- 0.6.419: glow on hover - additive copy of the image fades in softly
    local glow = K.NineSlice(b, (function() local n = {} for k2, v in pairs(BTN_N) do n[k2] = v end n.file = BTN_TEX .. "active" return n end)(), r, "BACKGROUND", 4, true)
    for _, t in ipairs(glow or {}) do t:SetBlendMode("ADD") t:SetAlpha(0) end
    -- soft glow around the button (0.6.424)
    local halo = b:CreateTexture(nil, "BACKGROUND", nil, -8)
    halo:SetTexture(ns.MEDIA .. "softglow")
    halo:SetBlendMode("ADD")
    halo:SetPoint("TOPLEFT", -14, 10) halo:SetPoint("BOTTOMRIGHT", 14, -10)
    halo:SetVertexColor(1, 0.25, 0.2)
    halo:SetAlpha(0)
    glow = glow or {}
    glow[#glow + 1] = halo
    local glowA, glowTo = 0, 0
    local gf = CreateFrame("Frame", nil, b)
    gf:Hide()
    gf:SetScript("OnUpdate", function(self, el)
        local step = (el or 0) * 4
        if glowA < glowTo then glowA = math.min(glowTo, glowA + step) else glowA = math.max(glowTo, glowA - step) end
        for _, t in ipairs(glow or {}) do t:SetAlpha(glowA) end
        if glowA == glowTo then self:Hide() end
    end)
    local function glowTo_(v)
        if ns.db and ns.db.settings.noAnim then glowA = v for _, t in ipairs(glow or {}) do t:SetAlpha(v) end return end
        glowTo = v gf:Show()
    end
    b:HookScript("OnEnter", function(self) if self:IsEnabled() then glowTo_(0.8) end end)
    b:HookScript("OnLeave", function() glowTo_(0) end)
    sets.glow = glow
    b.imgBtn = sets
    if b.GetHighlightTexture and b:GetHighlightTexture() then b:GetHighlightTexture():SetAlpha(0) end
    if b.bg then b.bg:SetAlpha(0) end
    if b.borders then for _, x in ipairs(b.borders) do x:Hide() end end
    local function show(st)
        for k2, list in pairs(sets) do if k2 ~= "glow" then for _, t in ipairs(list) do t:SetShown(k2 == st) end end end
    end
    local function base() return b.style == "primary" and "active" or "normal" end
    function b:ImgState(st) show(st or base()) end
    b:HookScript("OnEnter", function(self) if self:IsEnabled() then show(self.style == "primary" and "active" or "hover") end end)
    b:HookScript("OnLeave", function() show(base()) end)
    b:HookScript("OnMouseDown", function(self) if self:IsEnabled() then show("active") end end)
    b:HookScript("OnMouseUp", function(self) show(self:IsMouseOver() and (self.style == "primary" and "active" or "hover") or base()) end)
    show(base())
    K.imageButtons[b] = true
    return true
end
-- cut surfaces of a bordered box that cover the whole box at an angle (K.RoundMask splits them if needed)
local CLIP_LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true }
function K.ClipBox(box)
    if not (box and box.boxFrame and K.RoundMask) then return end
    local bw, bh = box:GetWidth() or 0, box:GetHeight() or 0
    if bw < 30 or bh < 30 then return end
    local function scan(owner)
        for _, t in ipairs({ owner:GetRegions() }) do
            if t.GetObjectType and t:GetObjectType() == "Texture" and not t.boxSplit and not t.boxTwinOf
                and not (t.roundMasked and next(t.roundMasked)) and not t.ownMask
                and not (t.GetNumMaskTextures and (t:GetNumMaskTextures() or 0) > 0)
                and CLIP_LAYERS[t:GetDrawLayer() or ""] and (t:GetWidth() or 0) >= bw - 3 and (t:GetHeight() or 0) >= bh - 3 then
                K.RoundMask(t, box, 8)
            end
        end
    end
    scan(box)
    for _, ch in ipairs({ box:GetChildren() }) do
        if ch ~= box.boxFrame and (ch:GetWidth() or 0) >= bw - 3 and (ch:GetHeight() or 0) >= bh - 3 then scan(ch) end
    end
end
-- 0.6.370: tint box border dark (profile/diary): line desaturated and dark, no red glow.
-- off = true hides the border completely (e.g. small buttons)
function K.DarkBoxFrame(x, off)
    if not x then return end
    if off then
        x.noBoxFrame = true
        if x.boxFrame then x.boxFrame:Hide() if x.boxFrame.fit then x.boxFrame.fit() end end
        return
    end
    local fr = x.boxFrame
    if not fr then return end
    fr.tint = { 0.05, 0.05, 0.06 }
    for _, g in ipairs(fr.glows or {}) do g:SetVertexColor(0.05, 0.05, 0.06, 1) end
    for _, pc in ipairs(fr.pieces or {}) do pc:SetDesaturated(true) pc:SetVertexColor(0.22, 0.22, 0.24, 1) end
end
-- 0.6.447: color all box borders below a window/page black (chronicle ...)
local darkDone = setmetatable({}, { __mode = "k" })
function K.DarkFramesIn(root, depth)
    depth = depth or 0
    if not root or depth > 6 or not root.GetChildren then return end
    for _, ch in ipairs({ root:GetChildren() }) do
        if ch.boxFrame and not darkDone[ch] and not ch.noBoxFrame then
            darkDone[ch] = true
            pcall(K.DarkBoxFrame, ch)
        end
        K.DarkFramesIn(ch, depth + 1)
    end
end
function K.RefreshBoxFrames()
    local cr, cg, cb = frameGlowColor()
    for fr in pairs(K.boxFrames) do
        fr.fit()
        local t = fr.tint   -- the box's own color (e.g. dungeon map by difficulty)
        for _, g in ipairs(fr.glows) do
            if t then g:SetVertexColor(t[1], t[2], t[3], 1) else g:SetVertexColor(cr, cg, cb, 1) end
        end
    end
end
do
    local last, acc = nil, 0
    local tick = CreateFrame("Frame")
    tick:SetScript("OnUpdate", function(_, el)
        acc = acc + (el or 0)
        if acc < 0.5 then return end
        acc = 0
        if not next(K.boxFrames) then return end
        local cr, cg, cb = frameGlowColor()
        local key = cr .. ":" .. cg .. ":" .. cb .. ":" .. tostring(boxOn())
        if key ~= last then last = key K.RefreshBoxFrames() end
    end)
end

-- 0.6.230: background images adjustable per side - left (navigation) / right (content):
--   opacity     bgBrightL / bgBright   0..1  (alpha of the image; setting name kept from 0.6.227)
--   brightness  bgLightL  / bgLight    0..2  (below 1: darkening MOD layer, above 1: additive copy = stronger)
K.bgImgs = setmetatable({}, { __mode = "k" })
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function K.BgBright(side)   -- opacity - 0.6.232: no slider anymore, always full
    return 1
end
function K.BgLight(side)    -- brightness
    local st = ns.db and ns.db.settings
    return clamp(tonumber(st and (side == "L" and st.bgLightL or st.bgLight)) or 1, 0, 2)
end
local function applyBg(tex, side)
    local op, li = K.BgBright(side), K.BgLight(side)
    if not tex.oasisBgNoAlpha then tex:SetAlpha(op) end
    local d, m = tex.oasisBgDup, tex.oasisBgDark
    if d then d:SetAlpha(li > 1 and math.min(1, (li - 1) * 0.8) * op or 0) end
    if m then
        local k = li < 1 and li or 1
        m:SetColorTexture(k, k, k, 1)
        m:SetShown(li < 0.999 and tex:IsShown())
    end
end
function K.BgImg(tex, side)
    if not tex or K.bgImgs[tex] then return tex end
    local layer, sub = tex:GetDrawLayer()
    local parent = tex:GetParent()
    local d = parent:CreateTexture(nil, layer, nil, math.min(7, (sub or 0) + 1))
    d:SetAllPoints(tex)
    d:SetBlendMode("ADD")
    d:SetAlpha(0)
    tex.oasisBgDup = d
    -- darken: solid surface in MOD mode (multiplied with the image below)
    local m = parent:CreateTexture(nil, layer, nil, math.min(7, (sub or 0) + 1))
    m:SetAllPoints(tex)
    m:SetColorTexture(1, 1, 1, 1)
    pcall(m.SetBlendMode, m, "MOD")
    m:Hide()
    tex.oasisBgDark = m
    local function sync()
        d:SetTexture(tex:GetTexture())
        local a1, b1, c1, d1, e1, f1, g1, h1 = tex:GetTexCoord()
        if a1 then pcall(d.SetTexCoord, d, a1, b1, c1, d1, e1, f1, g1, h1) end
        d:SetShown(tex:IsShown())
    end
    sync()
    local function vis(on) d:SetShown(on and true or false) applyBg(tex, K.bgImgs[tex]) if not on then m:Hide() end end
    hooksecurefunc(tex, "SetTexture", function() sync() end)
    hooksecurefunc(tex, "SetTexCoord", function() sync() end)
    hooksecurefunc(tex, "Show", function() vis(true) end)
    hooksecurefunc(tex, "Hide", function() vis(false) end)
    hooksecurefunc(tex, "SetShown", function(_, on) vis(on) end)
    K.bgImgs[tex] = side or "R"
    applyBg(tex, side or "R")
    return tex
end
function K.ApplyBgBright()
    for tex, side in pairs(K.bgImgs) do applyBg(tex, side) end
end

-- keep the accent border above everything in the window (same level as the window, highest strata)
function K.FixEdge(main)
    -- 0.6.164: the decorative lines (frameLines, with shimmer) likewise all the way up - they lay below the content and were invisible
    local fl = main and main.frameLines
    if fl then
        fl:SetFrameStrata(main:GetFrameStrata())
        fl:SetFrameLevel(math.min(9000, main:GetFrameLevel() + 199))
    end
    local e = main and main.accentEdge
    if not e then return end
    e:SetFrameStrata(main:GetFrameStrata())
    e:SetFrameLevel(math.min(9000, main:GetFrameLevel() + 200))
end
-- color the main window: gradient on background + sidebar, border color
-- color window/bar surface WITH opacity included (gradient + Region:SetAlpha doesn't work reliably in the client
-- -> with "Two colors" the window stayed opaque). paint remembers the colors, repaint
-- recalculates them with the current opacity (slider live).
local function cp(c) return { c[1], c[2], c[3], c[4] or 1 } end
function K.RepaintWindowTex(tex)
    local p = tex and tex.oasisPaint
    if not p then return false end
    local wa = K.WindowAlpha()
    tex:SetAlpha(1)
    -- 0.5.558: slider at 100 % = fully opaque (not design alpha x 1); below that linear down to the design opacity
    local function al(base)
        base = base or 1
        -- 0.5.791: continuous up to fully opaque. Previously 99 % -> 100 % jumped from (design opacity x 0.99) to 1.0 - for designs
        -- with a translucent background a big leap. Now the opacity approaches 1.0 smoothly between 80 % and 100 %.
        local t = math.max(0, math.min(1, (wa - 0.8) / 0.2))
        return math.min(1, wa * (base + (1 - base) * t))
    end
    if p[1] == "grad" then
        local a, b = p[2], p[3]
        if not K.Gradient(tex, "VERTICAL", { a[1], a[2], a[3], al(a[4]) }, { b[1], b[2], b[3], al(b[4]) }) then
            tex:SetColorTexture(a[1], a[2], a[3], al(a[4]))
        end
    else
        local c = p[2]
        tex:SetColorTexture(c[1], c[2], c[3], al(c[4]))
    end
    return true
end
local function paintWin(tex, c1, c2)
    tex.oasisPaint = c2 and { "grad", cp(c1), cp(c2) } or { "flat", cp(c1) }
    liveTex[tex] = nil   -- don't get flat-recolored by the live preview
    K.RepaintWindowTex(tex)
end
function K.StyleWindow(main)
    if not main then return end
    local th, s = K.CurrentTheme(), ns.db and ns.db.settings or {}
    local fc = s.frameAccent and K.C.accent or th.frame or K.C.line
    if not main.accentEdge then
        local e = CreateFrame("Frame", nil, main)
        e:SetAllPoints(main)
        e:EnableMouse(false)
        K.Border(e, K.C.accent, 1)
        main.accentEdge = e
        -- Raise()/strata change lifts the window -> move the border back to the very top afterwards
        main:HookScript("OnShow", function() K.FixEdge(main) end)
    end
    K.SetBorderColor(main.accentEdge, K.C.accent)
    main.accentEdge:SetShown(s.frameAccent and true or false)
    K.FixEdge(main)
    -- border in accent color: works for every border type (own lines, design border, Blizzard border)
    if main.skinBlizz and main.SetBackdropBorderColor then
        local c = s.frameAccent and K.C.accent or { 1, 1, 1, 1 }
        main:SetBackdropBorderColor(c[1], c[2], c[3], 1)
    elseif main.skinLine then
        local d = main.skinDef or {}
        local c = s.frameAccent and K.C.accent or (d.colored and { 1, 1, 1, 1 }) or (d.lineAccent and K.C.accent) or K.C.line
        for _, x in ipairs(main.skinLine) do x:SetVertexColor(c[1], c[2], c[3], 1) end
    else
        K.SetBorderColor(main, fc)
    end
    local g = K.GradStrength()
    if main.bgTex then
        if g > 0 and th.grad then
            local top, bot = mix(K.C.bg, th.grad.top, g), mix(K.C.bg, th.grad.bottom, g)
            paintWin(main.bgTex, { bot[1], bot[2], bot[3], K.C.bg[4] }, { top[1], top[2], top[3], K.C.bg[4] })
        else
            paintWin(main.bgTex, K.C.bg)
        end
    end
    if main.sideTex then main.sideTex.oasisPaint = nil end   -- design texture in the bar: don't recolor
    if main.sideTex and not K.StyleSide(main) then
        if th.duoColors then
            -- two-color design: left bar in its own color (light gradient), not covered by the base color
            local sc = K.C.side
            paintWin(main.sideTex, { sc[1] * 0.75, sc[2] * 0.75, sc[3] * 0.75, 1 }, { math.min(1, sc[1] * 1.15 + 0.01), math.min(1, sc[2] * 1.15 + 0.01), math.min(1, sc[3] * 1.15 + 0.01), 1 })
        elseif g > 0 and th.grad then
            local top = mix(K.C.side, th.grad.top, g * 0.6)
            local bot = mix(K.C.side, th.grad.bottom, g * 0.6)
            paintWin(main.sideTex, bot, top)
        else
            paintWin(main.sideTex, K.C.side)
        end
    end
    if K.SideParticles then pcall(K.SideParticles, main) end
    -- reapply background transparency after every recolor (gradient resets the surface)
    if ns.ApplyWindowAlpha then C_Timer.After(0, function() pcall(ns.ApplyWindowAlpha, main) end) end
    -- sidebar: shimmer in the accent color, colored at the bottom -> faded out at the top
    local side = main.sideTex and main.sideTex:GetParent()
    if side then
        if not main.sideGlow then
            main.sideGlow = side:CreateTexture(nil, "BACKGROUND", nil, 4)
            main.sideGlow:SetAllPoints(side)
        end
        local ga = th.sideGlow or 0
        if ga > 0 then
            local c = K.C.accent
            if not K.Gradient(main.sideGlow, "VERTICAL", { c[1], c[2], c[3], ga }, { c[1], c[2], c[3], 0 }) then
                main.sideGlow:SetColorTexture(c[1], c[2], c[3], ga * 0.35)
            end
            main.sideGlow:Show()
        else
            main.sideGlow:Hide()
        end
    end
    -- glass: soft light orbs behind the content (accent top left, cool blue bottom right)
    if main.bgTex then
        if th.orbs and not main.orbs then
            -- soft light gradient (Media\softglow.tga), always fully inside the window
            local function orb(w, h, point, x, y)
                local o = main:CreateTexture(nil, "BACKGROUND", nil, 3)
                o:SetTexture(ns.MEDIA .. "softglow")
                o:SetBlendMode("ADD")
                o:SetSize(w, h)
                o:SetPoint(point, main, point, x, y)
                return o
            end
            main.orbs = { orb(640, 520, "TOPLEFT", 0, 0), orb(560, 460, "BOTTOMRIGHT", 0, 0), orb(420, 300, "TOP", 120, 0) }
            -- brightness is in the color (with ADD alpha doesn't work reliably), pulsing scales it
            local function paint(p1, p2)
                for i, o in ipairs(main.orbs) do
                    local c = o.oc
                    if c then
                        local k = c[4] * (i == 2 and p2 or i == 3 and (p1 + p2) / 2 or p1)
                        o:SetVertexColor(c[1] * k, c[2] * k, c[3] * k, 1)
                    end
                end
            end
            main.paintOrbs = paint
            local drv = CreateFrame("Frame", nil, main)
            drv.t = 0
            drv:SetScript("OnUpdate", function(self, el)
                if not main.orbs[1]:IsShown() or (ns.db and ns.db.settings.noAnim) then return end
                self.t = self.t + el
                if self.t - (self.last or 0) < 0.05 then return end
                self.last = self.t
                paint(0.85 + 0.15 * math.sin(self.t * 0.45), 0.85 + 0.15 * math.sin(self.t * 0.37 + 2))
            end)
        end
        if main.orbs then
            local c, wa = K.C.accent, K.WindowAlpha()
            main.orbs[1].oc = { c[1], c[2], c[3], 0.10 * wa }
            main.orbs[2].oc = { 0.30, 0.45, 1.0, 0.07 * wa }
            main.orbs[3].oc = { 0.65, 0.40, 1.0, 0.05 * wa }
            main.paintOrbs(1, 1)
            for _, o in ipairs(main.orbs) do o:SetShown(th.orbs and true or false) end
        end
    end
    -- the design's background graphic (Media\themes\<name>.tga, self-made)
    if main.bgTex then
        if not main.themeTex then
            main.themeTex = main:CreateTexture(nil, "BACKGROUND", nil, 2)
            main.themeTex:SetAllPoints(main.bgTex)
        end
        if th.tex and s.themeTexture ~= false then
            main.themeTex:SetTexture(ns.MEDIA .. "themes\\" .. th.tex)
            main.themeTex:SetAlpha((th.texAlpha or 1) * K.WindowAlpha() * 0.55)   -- 0.6.485: background graphic more subtle
            main.themeTex:Show()
        else
            main.themeTex:Hide()
        end
    end
    if main.borders and (th.frameSize or 1) > 1 then
        local sz = th.frameSize
        for i, t in ipairs(main.borders) do if i <= 2 then t:SetHeight(sz) else t:SetWidth(sz) end end
    end
    -- round window border: round the surfaces below at the corners too (otherwise square corners stick out)
    local wsk = K.Skin("window")
    if wsk and wsk.fill == "round_fill" then
        local r = wsk.r or 12
        -- surface right of the sidebar: right corners; sidebar: left corners; light spots: only their corner
        for _, t in ipairs({ main.bgTex, main.themeTex }) do K.RoundMask(t, main, r, { "tr", "br" }) end
        for _, t in ipairs({ main.sideTex, main.sideGlow }) do K.RoundMask(t, main, r, { "tl", "bl" }) end
        if main.orbs then
            local OC = { { "tl" }, { "br" }, {} }
            for i, o in ipairs(main.orbs) do if OC[i] and #OC[i] > 0 then K.RoundMask(o, main, r, OC[i]) end end
        end
    end
    -- opacity immediately (not only in the next frame): window, bar, shimmer, graphic
    if ns.ApplyWindowAlpha then pcall(ns.ApplyWindowAlpha, main) end
end

------------------------------------------------------------------------
-- skins: real borders per design (window, cards, buttons, switches)
-- own 9-slice graphics in Media\skins\ (top-left corner + top edge, outside at the top),
-- WoW Classic uses Blizzard's own borders from the game (nothing bundled)
------------------------------------------------------------------------
local SKD = "Interface\\AddOns\\" .. ADDON .. "\\Media\\skins\\"
local BLIZZ_GOLD = { 1, 0.82, 0, 1 }
K.SKINS = {
    modern = {
        window = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 14, keepBg = true },
        panel  = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 8 },
        button = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 7 },
        toggle = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 8 },
        field  = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 6 },
    },
    future = {
        window = { fill = "chamfer_fill", line = "chamfer_line", edge = "chamfer_edge", r = 18, keepBg = true, lineAccent = true },
        panel  = { fill = "chamfer_fill", line = "chamfer_line", edge = "chamfer_edge", r = 12 },
        button = { fill = "chamfer_fill", line = "chamfer_line", edge = "chamfer_edge", r = 8, lineAccent = true },
        toggle = { fill = "chamfer_fill", line = "chamfer_line", edge = "chamfer_edge", r = 7 },
        field  = { fill = "chamfer_fill", line = "chamfer_line", edge = "chamfer_edge", r = 7 },
    },
    fantasy = {
        window = { line = "metal_corner", edge = "metal_edge", r = 28, keepBg = true, colored = true },
        panel  = { line = "metal_corner", edge = "metal_edge", r = 12, colored = true },
        button = { line = "metal_corner", edge = "metal_edge", r = 9, colored = true },
        toggle = { line = "metal_corner", edge = "metal_edge", r = 7, colored = true },
        headColor = { 0.96, 0.78, 0.45, 1 },
    },
    classic = {
        window = { blizz = { edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", edgeSize = 32 }, keepBg = true, inset = 9 },
        panel  = { blizz = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                   edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } }, bgColor = { 0.05, 0.05, 0.06, 0.92 }, edgeColor = { 0.75, 0.68, 0.5, 1 } },
        field  = { blizz = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                   edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } }, bgColor = { 0, 0, 0, 0.8 }, edgeColor = { 0.6, 0.6, 0.6, 1 } },
        button = { blizzButton = true },
        toggle = { check = true },
        headColor = BLIZZ_GOLD,
        sideTex = "Interface\\FrameGeneral\\UI-Background-Rock",
        banner = true,
    },
}
K.SKINS.glass = {
    window = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 16, keepBg = true },
    panel  = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 12 },
    button = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 10 },
    toggle = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 10 },
    field  = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 9 },
}
-- round off a texture at the four corners of 'box': one mask per corner (quarter circle), outside
-- the mask CLAMPTOWHITE = visible. Masks are created once per owner frame and shared.
-- guard texture after masking against SetTexCoord errors (the crop is then silently skipped)
-- 0.6.127: fine dot grid as overlay (Media/dotgrid, 16 px grid), adapts to the size
function K.DotGrid(parent, alpha, inset)
    local t = parent:CreateTexture(nil, "ARTWORK", nil, -6)
    inset = inset or 0
    t:SetPoint("TOPLEFT", inset, -inset)
    t:SetPoint("BOTTOMRIGHT", -inset, inset)
    t:SetTexture(ns.MEDIA .. "dotgrid", "REPEAT", "REPEAT")
    t:SetVertexColor(1, 1, 1, alpha or 0.05)
    local function fit()
        local w, h = t:GetWidth() or 0, t:GetHeight() or 0
        if w > 0 and h > 0 then t:SetTexCoord(0, w / 8, 0, h / 8) end   -- 0.6.141: one dot every 8 units (finer)
    end
    parent:HookScript("OnSizeChanged", fit)
    fit()
    if C_Timer then C_Timer.After(0, fit) end
    return t
end
function K.MaskSafe(tex)
    if not tex or tex.oasisSafeTC or not tex.SetTexCoord then return tex end
    local orig = tex.SetTexCoord
    tex.SetTexCoord = function(self, ...) pcall(orig, self, ...) end
    tex.oasisSafeTC = true
    return tex
end
-- corners (optional): mask only these corners, e.g. { "tr", "br" }. 0.5.600: WoW takes at most 3 masks per texture -
-- the 4th (bottom right) was silently dropped -> square edge at the bottom right of the window. So only corners the surface reaches.
function K.RoundMask(tex, box, r, corners)
    if not (tex and tex.AddMaskTexture and box) then return end
    local owner = tex:GetParent()
    if not (owner and owner.CreateMaskTexture) then return end
    owner.roundMasks = owner.roundMasks or {}
    -- 0.6.314: box with image border (beveled corners) -> cut at an angle instead of round, otherwise the rounding sticks out
    -- beyond the bevel of the border. Size = bevel of the box border (+1 safety)
    local shape = "mask_"
    if box.boxFrame then shape, r = "mask_bevel_", BOX_BEVEL + 1 end
    local key = tostring(box) .. ":" .. shape .. r
    local set = owner.roundMasks[key]
    if not set then
        set = {}
        local ok = pcall(function()
            for _, d in ipairs({ { "tl", "TOPLEFT" }, { "tr", "TOPRIGHT" }, { "bl", "BOTTOMLEFT" }, { "br", "BOTTOMRIGHT" } }) do
                local m = owner:CreateMaskTexture()
                m:SetTexture(SKD .. shape .. d[1], "CLAMPTOWHITE", "CLAMPTOWHITE")
                m:SetSize(r, r)
                m:SetPoint(d[2], box, d[2], 0, 0)
                set[#set + 1] = m
            end
        end)
        if not ok then return end
        owner.roundMasks[key] = set
    end
    K.MaskSafe(tex)   -- masked textures throw an error on SetTexCoord
    tex.roundMasked = tex.roundMasked or {}
    -- 0.6.315: box with border and all four corners: more than 3 masks don't work. So the image shows only the left
    -- half (tl, bl + mask "right away"), a twin on top only the right (tr, br + "left away").
    if box.boxFrame and not corners then
        if tex.boxSplit then return end
        tex.boxSplit = true
        -- 0.6.316: don't split color/gradient surfaces - a gradient can't be read out, the twin turned white.
        -- They get only three corners (tl, tr, bl); only images are split (file or K.BgImg)
        -- split only real images (image path or file ID); color surfaces and gradients sometimes report a "file" here too
        local file = tex:GetTexture()
        local isImg = K.bgImgs[tex] or (type(file) == "string" and file:find("[\\/]")) or (type(file) == "number" and file > 0)
        if tex.oasisGrad or not isImg then
            for i = 1, 3 do if not tex.roundMasked[set[i]] then tex.roundMasked[set[i]] = true pcall(tex.AddMaskTexture, tex, set[i]) end end
            return
        end
        if not set.halves then
            local ok = pcall(function()
                local hr = owner:CreateMaskTexture()
                hr:SetTexture(SKD .. "mask_none", "CLAMPTOWHITE", "CLAMPTOWHITE")
                hr:SetPoint("TOPLEFT", box, "TOP", 0, 40) hr:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 40, -40)
                local hl = owner:CreateMaskTexture()
                hl:SetTexture(SKD .. "mask_none", "CLAMPTOWHITE", "CLAMPTOWHITE")
                hl:SetPoint("TOPLEFT", box, "TOPLEFT", -40, 40) hl:SetPoint("BOTTOMRIGHT", box, "BOTTOM", 0, -40)
                set.halves = { hr, hl }
            end)
            if not ok then return end
        end
        local layer, sub = tex:GetDrawLayer()
        local tw = owner:CreateTexture(nil, layer, nil, sub)
        tw:SetAllPoints(tex)
        K.MaskSafe(tw)
        local function sync()
            local file = tex:GetTexture()
            if file then tw:SetTexture(file) elseif not tw.colored then tw:SetColorTexture(1, 1, 1, 1) end
            local a1, b1, c1, d1, e1, f1, g1, h1 = tex:GetTexCoord()
            if a1 then pcall(tw.SetTexCoord, tw, a1, b1, c1, d1, e1, f1, g1, h1) end
            tw:SetAlpha(tex:GetAlpha() or 1)
            local r1, g2, b2, a2 = tex:GetVertexColor()
            if r1 then tw:SetVertexColor(r1, g2, b2, a2 or 1) end
            pcall(tw.SetBlendMode, tw, tex:GetBlendMode())
            if tex.IsDesaturated then tw:SetDesaturated(tex:IsDesaturated() and true or false) end
            tw:SetShown(tex:IsShown())
        end
        sync()
        -- color surfaces (e.g. darkening of K.BgImg): pass the color on directly, it can't be read
        hooksecurefunc(tex, "SetColorTexture", function(_, ...) tw.colored = true pcall(tw.SetColorTexture, tw, ...) end)
        for _, fn in ipairs({ "SetTexture", "SetTexCoord", "SetAlpha", "SetVertexColor", "SetBlendMode",
                              "SetDesaturated", "Show", "Hide", "SetShown" }) do
            if tex[fn] then hooksecurefunc(tex, fn, sync) end
        end
        for _, m in ipairs({ set[1], set[3], set.halves[1] }) do pcall(tex.AddMaskTexture, tex, m) end
        for _, m in ipairs({ set[2], set[4], set.halves[2] }) do pcall(tw.AddMaskTexture, tw, m) end
        tex.boxTwin = tw
        tw.boxTwinOf = tex
        -- brightness layers of K.BgImg lie over the whole surface the same way
        if tex.oasisBgDup then K.RoundMask(tex.oasisBgDup, box, r) end
        if tex.oasisBgDark then K.RoundMask(tex.oasisBgDark, box, r) end
        return
    end
    local want
    if corners then want = {} for _, c in ipairs(corners) do want[c] = true end end
    local ORDER = { "tl", "tr", "bl", "br" }
    for i, m in ipairs(set) do
        if (not want or want[ORDER[i]]) and not tex.roundMasked[m] then
            tex.roundMasked[m] = true
            pcall(tex.AddMaskTexture, tex, m)
        end
    end
end
function K.Skin(role)
    local th = K.CurrentTheme and K.CurrentTheme()
    local s = th and K.SKINS[th.key]
    if not s then return nil end
    if role then return s[role] end
    return s
end
-- 9-slice from corner + edge; corner/edge nil = solid color
local function slice(f, corner, edge, r, layer, sub, c, center)
    local list = {}
    local function tex()
        local x = f:CreateTexture(nil, layer, nil, sub)
        list[#list + 1] = x
        return x
    end
    for _, d in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
        local x = tex()
        if corner then x:SetTexture(SKD .. corner) x:SetTexCoord(d[2], d[3], d[4], d[5]) else x:SetColorTexture(1, 1, 1, 1) end
        x:SetSize(r, r)
        x:SetPoint(d[1])
    end
    local function e(p1, x1, y1, p2, x2, y2, w, h, tc)
        local x = tex()
        if edge then x:SetTexture(SKD .. edge) x:SetTexCoord(unpack(tc)) else x:SetColorTexture(1, 1, 1, 1) end
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
    for _, x in ipairs(list) do x:SetVertexColor(c[1], c[2], c[3], c[4] or 1) end
    return list
end
-- 9-slice from one graphic: n = { file, w, h (fraction of the canvas), cx, cy (corner as fraction), ex (optional: take only this
-- fraction from the corner for the horizontal edges, e.g. when an ornamental notch sits at the top center) }
function K.NineSlice(f, n, r, layer, sub, center)
    local list = {}
    local w, h, cx, cy = n.w or 1, n.h or 1, n.cx, n.cy
    local u = { 0, cx, w - cx, w }
    local v = { 0, cy, h - cy, h }
    local hu = n.ex and { cx, math.min(w - cx, cx + n.ex) } or { cx, w - cx }
    local function piece(l, rr, t, b, p1, x1, y1, p2, x2, y2, sw, sh)
        local x = f:CreateTexture(nil, layer, nil, sub)
        x:SetTexture(n.file)
        x:SetTexCoord(l, rr, t, b)
        x:SetPoint(p1, f, p1, x1, y1)
        if p2 then x:SetPoint(p2, f, p2, x2, y2) end
        if sw then x:SetWidth(sw) end
        if sh then x:SetHeight(sh) end
        list[#list + 1] = x
    end
    -- corners
    piece(u[1], u[2], v[1], v[2], "TOPLEFT", 0, 0, nil, 0, 0, r, r)
    piece(u[3], u[4], v[1], v[2], "TOPRIGHT", 0, 0, nil, 0, 0, r, r)
    piece(u[1], u[2], v[3], v[4], "BOTTOMLEFT", 0, 0, nil, 0, 0, r, r)
    piece(u[3], u[4], v[3], v[4], "BOTTOMRIGHT", 0, 0, nil, 0, 0, r, r)
    -- edges
    piece(hu[1], hu[2], v[1], v[2], "TOPLEFT", r, 0, "TOPRIGHT", -r, 0, nil, r)
    piece(hu[1], hu[2], v[3], v[4], "BOTTOMLEFT", r, 0, "BOTTOMRIGHT", -r, 0, nil, r)
    piece(u[1], u[2], v[2], v[3], "TOPLEFT", 0, -r, "BOTTOMLEFT", 0, r, r, nil)
    piece(u[3], u[4], v[2], v[3], "TOPRIGHT", 0, -r, "BOTTOMRIGHT", 0, r, r, nil)
    if center then piece(u[2], u[3], v[2], v[3], "TOPLEFT", r, -r, "BOTTOMRIGHT", -r, r) end
    return list
end
local function tintList(list, c, a)
    if not list then return end
    for _, x in ipairs(list) do x:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1) end
end
-- recolor surface/border of a skinned frame (redirected from col/SetBorderColor)
function K.SkinFill(f, c, a)
    if f.skinFill then tintList(f.skinFill, c, a) end
    if f.SetBackdropColor and f.skinBlizz then f:SetBackdropColor(c[1], c[2], c[3], a or c[4] or 1) end
end
function K.SkinLine(f, c, a)
    if f.skinColored then return end
    if f.skinLine then tintList(f.skinLine, c, a) end
end
-- give a frame the border of the current design. role: window/panel/button/toggle/field
function K.ApplySkin(f, role, fillColor, lineColor)
    if role == "panel" and K.BoxFrame then pcall(K.BoxFrame, f) end   -- 0.6.281: image border around every box
    local sk = K.Skin(role)
    if not sk or f.skinned then return false end
    -- small frames: corners may be at most half the height/width
    local r = sk.r or 8
    local w, h = f:GetWidth() or 0, f:GetHeight() or 0
    if h > 0 then r = math.min(r, math.floor(h / 2)) end
    if w > 0 then r = math.min(r, math.floor(w / 2)) end
    if sk.check or sk.blizzButton or sk.pill then return false end    -- eigene Behandlung in Toggle/Button
    f.skinned = role
    if f.borders then for _, b in ipairs(f.borders) do b:Hide() end end
    f.skinDef = sk
    if sk.blizz then
        if not f.SetBackdrop and BackdropTemplateMixin then
            Mixin(f, BackdropTemplateMixin)
            f:HookScript("OnSizeChanged", f.OnBackdropSizeChanged)
        end
        if not f.SetBackdrop then return false end
        f:SetBackdrop(sk.blizz)
        f.skinBlizz = true
        if sk.blizz.bgFile then
            local bc = sk.bgColor or fillColor or C.panel
            -- fixed design surface color (Classic) still follows the opacity setting
            local ba = (bc[4] or 1) * (sk.bgColor and K.WindowAlpha() or 1)
            f:SetBackdropColor(bc[1], bc[2], bc[3], ba)
            if f.bg and not sk.keepBg then f.bg:Hide() end
        end
        local ec = sk.edgeColor or { 1, 1, 1, 1 }
        f:SetBackdropBorderColor(ec[1], ec[2], ec[3], ec[4] or 1)
        return true
    end
    -- 0.6.271: border from ONE graphic (corners fixed, edges stretched, middle optional) - for designs from asset packs
    if sk.nine then
        if f.bg and sk.nine.center and not sk.keepBg then
            f.bg:Hide()
            f.bg.skinOwner = f
        end
        f.skinLine = K.NineSlice(f, sk.nine, r, "BORDER", 2, sk.nine.center and not sk.keepBg)
        f.skinColored = true
        return true
    end
    if f.bg and not sk.keepBg then
        f.bg:Hide()
        f.bg.skinOwner = f
    end
    if sk.fill and not sk.keepBg then
        f.skinFill = slice(f, sk.fill, nil, r, "BACKGROUND", 1, fillColor or C.panel, true)
    end
    if sk.line then
        local lc = sk.lineCol or (sk.colored and { 1, 1, 1, 1 }) or (sk.lineAccent and C.accent) or lineColor or C.line
        f.skinLine = slice(f, sk.line, sk.edge, r, "BORDER", 2, lc)
        f.skinColored = sk.colored
    end
    return true
end
-- the design's heading color (Classic: Blizzard gold)
function K.HeadColor()
    local s = K.Skin()
    return s and s.headColor
end
-- main window: border, sidebar, banner (Classic)
function K.SkinWindow(main)
    local s = K.Skin()
    if not s or not main or main.skinWindowDone then return end
    main.skinWindowDone = true
    K.ApplySkin(main, "window")
    -- border line on its own layer above all children (sidebar/content covered it in the corners)
    if main.skinLine and not main.lineFrame then
        local lf = CreateFrame("Frame", nil, main)
        lf:SetAllPoints()
        lf:EnableMouse(false)
        lf:SetFrameLevel(main:GetFrameLevel() + 60)
        for _, t in ipairs(main.skinLine) do t:SetParent(lf) end
        main.lineFrame = lf
    end
    if s.window and s.window.inset and main.bgTex then
        local i = s.window.inset
        main.bgTex:ClearAllPoints()
        main.bgTex:SetPoint("TOPLEFT", i, -i) main.bgTex:SetPoint("BOTTOMRIGHT", -i, i)
        if main.themeTex then main.themeTex:ClearAllPoints() main.themeTex:SetAllPoints(main.bgTex) end
    end
    if s.sideTex and main.sideTex then
        local ok = pcall(main.sideTex.SetTexture, main.sideTex, s.sideTex, "REPEAT", "REPEAT")
        if ok then
            main.sideTex:SetHorizTile(true) main.sideTex:SetVertTile(true)
            main.sideTex:SetVertexColor(0.45, 0.42, 0.38, 1)
        end
    end
    if s.banner and not main.skinBanner then
        local b = main:CreateTexture(nil, "OVERLAY", nil, 5)
        b:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
        b:SetSize(300, 64)
        b:SetPoint("TOP", main, "TOP", 0, 12)
        local t = main:CreateFontString(nil, "OVERLAY", nil, 6)
        t:SetFont(K.FONT_HEAD or K.FONT, 13, "")
        t:SetTextColor(1, 0.82, 0)
        t:SetPoint("TOP", b, "TOP", 0, -14)
        t:SetText("OASIS")
        main.skinBanner = b
    end
end
K.SKINS.kawaii = {
    window = { fill = "round_fill", line = "heart_line", edge = "round_edge", r = 22, keepBg = true, lineAccent = true },
    panel  = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 12 },
    button = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 11, lineAccent = true },
    toggle = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 8 },
    field  = { fill = "round_fill", line = "round_line", edge = "round_edge", r = 8 },
    headColor = { 1, 0.62, 0.82, 1 },
}
-- buttons: design border or Blizzard's red panel buttons (Classic)
function K.SkinButton(b, base)
    if K.ImageButton and K.ImageButton(b) then return end   -- 0.6.283: image buttons (guild module)
    local sk = K.Skin("button")
    if not sk then return end
    if sk.pill and K.PillButton then return K.PillButton(b) end
    if sk.blizzButton then
        if b.borders then for _, x in ipairs(b.borders) do x:Hide() end end
        b.bg:SetAlpha(0)
        local function part(file, layer)
            local t = b:CreateTexture(nil, layer)
            t:SetTexture(file)
            t:SetTexCoord(0, 0.625, 0, 0.6875)
            t:SetAllPoints()
            return t
        end
        b.bUp = part("Interface\\Buttons\\UI-Panel-Button-Up", "BACKGROUND")
        b.bDown = part("Interface\\Buttons\\UI-Panel-Button-Down", "BACKGROUND")
        b.bDown:Hide()
        local hl = part("Interface\\Buttons\\UI-Panel-Button-Highlight", "HIGHLIGHT")
        hl:SetBlendMode("ADD")
        b.label:SetTextColor(1, 0.82, 0)
        b:HookScript("OnMouseDown", function(self) if self:IsEnabled() then self.bUp:Hide() self.bDown:Show() end end)
        b:HookScript("OnMouseUp", function(self) self.bDown:Hide() self.bUp:Show() end)
        b.skinned = "button"
        b.skinBlizz = true
        return
    end
    -- 0.6.274: designs can bring their own border for main buttons (style "primary")
    if b.style == "primary" and K.Skin("primary") then return K.ApplySkin(b, "primary", base) end
    K.ApplySkin(b, "button", base)
end

------------------------------------------------------------------------
-- tile selection with images (e.g. dice designs, colors, fanfares)
-- items: { key, text, icon = path | nil, color = {r,g,b} | nil, round = true (color circle), locked = "Rank 12" | nil,
--          checked = bool, onEnter = fn | nil }
------------------------------------------------------------------------
local tilePop
local TMASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
function K.TilePicker(anchor, title, items, onPick)
    if not tilePop then
        local f = CreateFrame("Frame", "OasisTilePicker", UIParent)
        tilePop = f
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        K.Fill(f, { 0.045, 0.045, 0.05, 0.98 })
        K.Border(f, C.line)
        f.top = f:CreateTexture(nil, "ARTWORK")
        f.top:SetPoint("TOPLEFT", 1, -1) f.top:SetPoint("TOPRIGHT", -1, -1) f.top:SetHeight(2)
        f.title = K.Text(f, 11, C.muted)
        f.title:SetPoint("TOPLEFT", 12, -10)
        local x = K.CloseButton(f, function() f:Hide() end)
        x:SetPoint("TOPRIGHT", -4, -4)
        f.catcher = CreateFrame("Button", nil, UIParent)
        f.catcher:SetAllPoints(UIParent)
        f.catcher:SetFrameStrata("FULLSCREEN")
        f.catcher:SetScript("OnClick", function() f:Hide() end)
        f.catcher:Hide()
        f:SetScript("OnShow", function() f.catcher:Show() end)
        f:SetScript("OnHide", function() f.catcher:Hide() end)
        ns.EscClose("OasisTilePicker")
        f.tiles = {}
    end
    local f = tilePop
    f.top:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
    f.title:SetText(K.Upper(title or ""))
    local COLS, TW, TH, GAP = 5, 78, 82, 6
    for _, t in ipairs(f.tiles) do t:Hide() end
    for i, it in ipairs(items) do
        local t = f.tiles[i]
        if not t then
            t = CreateFrame("Button", nil, f)
            t:SetSize(TW, TH)
            t.bg = K.Fill(t, { 1, 1, 1, 0.035 })
            K.Border(t, C.line)
            t.hl = t:CreateTexture(nil, "HIGHLIGHT") t.hl:SetAllPoints() t.hl:SetColorTexture(1, 1, 1, 0.07)
            t.img = t:CreateTexture(nil, "ARTWORK")
            t.img:SetSize(38, 38)
            t.img:SetPoint("TOP", 0, -10)
            t.name = K.Text(t, 10, C.text, "CENTER")
            t.name:SetPoint("TOPLEFT", 3, -54)
            t.name:SetPoint("TOPRIGHT", -3, -54)
            t.name:SetWordWrap(true)
            t.name:SetMaxLines(2)
            t.lock = K.Text(t, 9, C.amber, "CENTER")
            t.lock:SetPoint("BOTTOM", 0, 4)
            t.check = t:CreateTexture(nil, "OVERLAY")
            t.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
            t.check:SetSize(18, 18)
            t.check:SetPoint("TOPRIGHT", -1, -1)
            f.tiles[i] = t
        end
        local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", 10 + col * (TW + GAP), -30 - row * (TH + GAP))
        t.img:SetTexCoord(0, 1, 0, 1)
        if it.icon then
            t.img:SetTexture(it.icon)
            if it.icon:find("Icons\\") then t.img:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
        else
            t.img:SetTexture(it.round and TMASK or "Interface\\Buttons\\WHITE8X8")
        end
        local c = it.color or { 1, 1, 1 }
        t.img:SetVertexColor(c[1], c[2], c[3])
        t.name:SetText(it.text or "")
        t.lock:SetText(it.locked or "")
        t.check:SetShown(it.checked and true or false)
        K.SetBorderColor(t, it.checked and C.accent or C.line)
        t:SetAlpha(it.locked and 0.45 or 1)
        t:SetScript("OnClick", function()
            if it.locked then return end
            f:Hide()
            if onPick then onPick(it.key) end
        end)
        t:SetScript("OnEnter", function(self) if it.onEnter then pcall(it.onEnter, self) end end)
        t:SetScript("OnLeave", function() GameTooltip:Hide() end)
        t:Show()
    end
    local rows = math.max(1, math.ceil(#items / COLS))
    f:SetSize(20 + math.min(#items, COLS) * (TW + GAP) - GAP, 40 + rows * (TH + GAP))
    f:ClearAllPoints()
    if anchor then f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4) else f:SetPoint("CENTER") end
    f:Show()
    return f
end

-- foreign scripts: the normal fonts only show boxes for Korean/Chinese.
-- Returns the matching font (or nil if none is needed). Prefers the complete
-- fonts of the game client (all characters), otherwise the bundled Noto subset fonts.
local fontOk = {}
local probe
local function firstFont(list)
    for _, path in ipairs(list) do
        if fontOk[path] == nil then
            -- a fresh FontString every time: an old one otherwise keeps its previous font
            probe = UIParent:CreateFontString(nil, "BACKGROUND")
            local ok, res = pcall(probe.SetFont, probe, path, 12, "")
            fontOk[path] = (ok and res ~= false and probe:GetFont() ~= nil) and true or false
        end
        if fontOk[path] then return path end
    end
end
local KR_FONTS = { "Fonts\\2002.TTF", "Fonts\\2002B.TTF" }
local ZH_FONTS = { "Fonts\\ARKai_T.ttf", "Fonts\\ARHei.ttf", "Fonts\\bLEI00D.ttf", "Fonts\\blei00d.TTF" }
function K.CJKFont(text)
    if type(text) ~= "string" then return nil end
    -- Hangul (U+AC00-D7A3): EA..ED; Hangul compatibility jamo: E3 84..86
    if text:find("[\234-\237][\128-\191][\128-\191]") or text:find("\227[\132-\134][\128-\191]") then
        local t = {}
        for _, p in ipairs(KR_FONTS) do t[#t + 1] = p end
        t[#t + 1] = K.fontByKey.notokr and K.fontByKey.notokr.path
        return firstFont(t)
    end
    -- CJK characters (U+4E00-9FFF): E4..E9; Kana (U+3040-30FF): E3 81..83
    if text:find("[\228-\233][\128-\191][\128-\191]") or text:find("\227[\129-\131][\128-\191]") then
        local t = {}
        for _, p in ipairs(ZH_FONTS) do t[#t + 1] = p end
        t[#t + 1] = K.fontByKey.notosc and K.fontByKey.notosc.path
        return firstFont(t)
    end
    -- Cyrillic (D0..D3): only if the chosen font has no Cyrillic characters
    if text:find("[\208-\211][\128-\191]") then
        local key = ns.db and ns.db.settings.uiFont or "inter"
        local cur = K.fontByKey[key]
        if key ~= "arialn" and cur and not cur.cyr then return K.fontByKey.ptsans and K.fontByKey.ptsans.path end
    end
end
-- set a FontString's font to match the text (special font or back to the normal one)
function K.SetNameFont(fs, text, size)
    local cjk = K.CJKFont(text)
    local _, cur, flags = fs:GetFont()
    size = size or cur or 13
    if cjk then
        if fs.cjkFont ~= cjk then
            fs.cjkBase = fs.cjkBase or (fs:GetFont())
            K.SetFontSafe(fs, cjk, size, flags or "", K.FONT)
            fs.cjkFont = cjk
        end
    elseif fs.cjkFont then
        K.SetFontSafe(fs, fs.cjkBase or K.FONT, size, flags or "")
        fs.cjkFont, fs.cjkBase = nil, nil
    end
end

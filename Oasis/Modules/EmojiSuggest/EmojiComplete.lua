-- Oasis: emoji autocomplete in chat
-- Typing ":" and at least 2 letters (e.g. ":lo") shows a list of matching emojis with images
-- above the input. Tab takes the highlighted suggestion, click takes the clicked one.
-- Only hooks (no replaced scripts) on the chat input, so nothing in Blizzard's chat breaks.
-- Turn off: Settings > Comfort > Chat > "Emoji suggestions while typing".
local ADDON, ns = ...
ns.ModuleFile("Oasis_EmojiSuggest", function()   -- Emoji suggestions module (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C = ns.K, ns.K.C

local EC = {}
ns.EmojiComplete = EC
local MAX = 8

-- Index: all :codes: with their entry (own emojis first, no raid symbols)
local index
local function buildIndex()
    index = {}
    local E = ns.Emoji
    if not E or not E.CATS then return end
    local seen = {}
    local cats = {}
    for _, cat in ipairs(E.CATS) do if cat.custom then cats[#cats + 1] = cat end end
    for _, cat in ipairs(E.CATS) do if not cat.custom and not cat.raid then cats[#cats + 1] = cat end end
    for _, cat in ipairs(cats) do
        for _, e in ipairs(cat.items or {}) do
            for i = 2, #e do
                local n = tostring(e[i]):match("^:([%w%+%-_]+):$")
                if n and not seen[n:lower()] then
                    seen[n:lower()] = true
                    index[#index + 1] = { name = n:lower(), code = ":" .. n .. ":", e = e }
                end
            end
        end
    end
    table.sort(index, function(a, b) return a.name < b.name end)
end
local function matches(prefix)
    if not index then buildIndex() end
    prefix = prefix:lower()
    local starts, contains = {}, {}
    for _, x in ipairs(index) do
        -- don't suggest locked emojis (Oasis rank too low)
        local ok = not ns.Emoji.Allowed or ns.Emoji.Allowed(x.e, ns.me and ns.me())
        if not ok then
        elseif x.name:sub(1, #prefix) == prefix then starts[#starts + 1] = x
        elseif #prefix >= 3 and x.name:find(prefix, 1, true) then contains[#contains + 1] = x end
    end
    for _, x in ipairs(contains) do starts[#starts + 1] = x end
    while #starts > MAX do table.remove(starts) end
    return starts
end

------------------------------------------------------------------------
-- Suggestion list
------------------------------------------------------------------------
local pop
local function buildPop()
    pop = CreateFrame("Frame", "OasisEmojiComplete", UIParent)
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:SetWidth(220)
    K.Fill(pop, { 0.04, 0.04, 0.05, 0.96 })
    K.Border(pop, C.line)
    pop.rows = {}
    pop.hint = K.Text(pop, 9, C.dim, "RIGHT")
    pop.hint:SetPoint("BOTTOMRIGHT", -6, 4)
    pop.hint:SetText(L["Tab = next"])
    for i = 1, MAX do
        local r = CreateFrame("Button", nil, pop)
        r:SetHeight(22)
        r:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 22)
        r:SetPoint("RIGHT", pop, "RIGHT", -4, 0)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.22)
        r.hl = r:CreateTexture(nil, "HIGHLIGHT")
        r.hl:SetAllPoints()
        r.hl:SetColorTexture(1, 1, 1, 0.06)
        r.t = K.Text(r, 12, C.text)
        r.t:SetPoint("LEFT", 6, 0)
        r:SetScript("OnMouseDown", function(self) EC.Accept(self.x) end)
        pop.rows[i] = r
    end
    pop:Hide()
end
local function show(eb, list)
    if not pop then buildPop() end
    pop.eb, pop.list = eb, list
    pop.sel = math.min(pop.sel or 1, #list)
    if pop.sel < 1 then pop.sel = 1 end
    for i, r in ipairs(pop.rows) do
        local x = list[i]
        r.x = x
        if x then
            local tex = ns.Emoji.Tex and ns.Emoji.Tex(x.e, 18) or ""
            r.t:SetText(tex .. "  " .. x.code)
            r.bg:SetShown(i == pop.sel)
            r:Show()
        else
            r:Hide()
        end
    end
    pop:SetHeight(8 + #list * 22 + 14)
    pop:ClearAllPoints()
    pop:SetPoint("BOTTOMLEFT", eb, "TOPLEFT", 0, 4)
    pop:Show()
end
function EC.Hide() if pop then pop:Hide() pop.sel = 1 pop.cyc = nil end end
local function mark(i)
    for k, r in ipairs(pop.rows) do r.bg:SetShown(k == i) end
end

-- partial word ":xx" directly before the cursor
local function partial(eb)
    local text = ns.safe(eb:GetText()) or ""
    local pos = eb:GetCursorPosition() or #text
    local before = text:sub(1, pos)
    local s, word = before:match("()%:([%w%+%-_]+)$")
    if not s then return nil end
    -- only at word start (otherwise e.g. times like "12:30")
    if s > 1 and not before:sub(s - 1, s - 1):match("%s") then return nil end
    if #word < 2 then return nil end
    return word, s, pos, text
end
EC.Matches, EC.Partial = matches, partial   -- for tests
local function enabled() return not (ns.db and ns.db.settings.emojiNoComplete) end

function EC.Update(eb)
    if not enabled() then EC.Hide() return end
    -- typed yourself while cycling: current suggestion stays
    if pop and pop.cyc then pop.cyc = nil end
    local word = partial(eb)
    if not word then EC.Hide() return end
    local list = matches(word)
    if #list == 0 then EC.Hide() return end
    show(eb, list)
end
function EC.Accept(x)
    if not pop or not pop:IsShown() then return false end
    local eb = pop.eb
    x = x or (pop.list and pop.list[pop.sel or 1])
    if not eb or not x then return false end
    local word, s, pos, text = partial(eb)
    if not word then EC.Hide() return false end
    local newText = text:sub(1, s - 1) .. x.code .. " " .. text:sub(pos + 1)
    eb:SetText(newText)
    eb:SetCursorPosition(s - 1 + #x.code + 1)
    -- emojis inserted via suggestion also land in "Recent" (before only clicks in the picker)
    if ns.Emoji and ns.Emoji.Remember then pcall(ns.Emoji.Remember, x.code) end
    EC.Hide()
    return true
end

function EC.Cycle()
    local eb, list = pop.eb, pop.list
    if not eb or not list or #list == 0 then return end
    if #list == 1 and not pop.cyc then EC.Accept(list[1]) return end
    local text = ns.safe(eb:GetText()) or ""
    local c = pop.cyc
    if not c then
        local word, s, pos = partial(eb)
        if not word then EC.Hide() return end
        c = { s = s, len = pos - s + 1, idx = 0 }
        pop.cyc = c
    end
    c.idx = c.idx % #list + 1
    local code = list[c.idx].code .. " "
    local newText = text:sub(1, c.s - 1) .. code .. text:sub(c.s + c.len)
    eb:SetText(newText)
    eb:SetCursorPosition(c.s - 1 + #code)
    c.len = #code
    pop.sel = c.idx
    mark(c.idx)
end

local hooked = {}
local function attach(eb)
    if not eb or hooked[eb] or not eb.HookScript then return end
    hooked[eb] = true
    eb:HookScript("OnTextChanged", function(self, user)
        if user then pcall(EC.Update, self) end
    end)
    -- Tab cycles through the suggestions (each Tab inserts the next directly), with only one: insert
    eb:HookScript("OnTabPressed", function(self)
        if pop and pop:IsShown() and pop.eb == self then pcall(EC.Cycle) end
    end)
    eb:HookScript("OnEditFocusLost", function() C_Timer.After(0.15, EC.Hide) end)
    eb:HookScript("OnEscapePressed", EC.Hide)
    eb:HookScript("OnEnterPressed", EC.Hide)
    eb:HookScript("OnHide", EC.Hide)
end
ns.Listen("LOGIN", function()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do attach(_G["ChatFrame" .. i .. "EditBox"]) end
end)
-- also the input of the guild chat page (once it exists)
function EC.Attach(eb) attach(eb) end
end)

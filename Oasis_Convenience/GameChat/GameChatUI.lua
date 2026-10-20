-- Oasis: Game chat - windows "Search chat" / "Alert hits" and the settings (Game aids > Game chat)
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_GameChat", function()   -- module Game chat (can be disabled, see ModuleLoader.lua)
local L = ns.L
local K, C = ns.K, ns.K.C
local GC = ns.GameChat
if not GC then return end
local G = GC.G

------------------------------------------------------------------------
-- window: lines as selectable text (Ctrl+C copies)
------------------------------------------------------------------------
local SHOW_MAX = 400
local function buildViewer()
    local f = CreateFrame("Frame", "OasisChatViewer", UIParent)
    f:SetSize(640, 440)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    K.Fill(f, { 0.04, 0.04, 0.05, 0.97 })
    K.Border(f, C.line)
    f.title = K.Title(f, 14, C.text)
    f.title:SetPoint("TOPLEFT", 14, -13)
    f.close = K.CloseButton(f, function() f:Hide() end)
    f.close:SetPoint("TOPRIGHT", -6, -6)

    f.input = K.Input(f, 300, L["Search ..."], function() f:Refresh() end)
    f.input:SetPoint("TOPLEFT", 14, -42)
    f.tab = K.Button(f, "", 200, 24, "ghost", function(self)
        local items = {}
        for _, cf in ipairs(GC.Frames()) do
            local name = GC.TabName(cf)
            if name ~= "" then
                items[#items + 1] = { text = name, checked = cf == f.frame, fn = function() f.frame = cf f:Refresh() end }
            end
        end
        K.ShowMenu(self, items, L["Chat tab"], 200)
    end)
    f.tab:SetPoint("LEFT", f.input, "RIGHT", 8, 0)
    f.count = K.Text(f, 11, C.dim, "RIGHT")
    f.count:SetPoint("TOPRIGHT", -16, -48)

    local sf = CreateFrame("ScrollFrame", nil, f)
    sf:SetPoint("TOPLEFT", 14, -76)
    sf:SetPoint("BOTTOMRIGHT", -14, 44)
    K.Fill(sf, { 0, 0, 0, 0.35 })
    K.Border(sf, C.line)
    local eb = CreateFrame("EditBox", nil, sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFont(K.FONT, 12, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetTextInsets(8, 8, 6, 6)
    eb:SetWidth(600)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    sf:SetScrollChild(eb)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local max = self:GetVerticalScrollRange() or 0
        self:SetVerticalScroll(math.max(0, math.min(max, (self:GetVerticalScroll() or 0) - delta * 48)))
    end)
    sf:SetScript("OnSizeChanged", function(self, w) eb:SetWidth(math.max(100, (w or 600) - 4)) end)
    f.sf, f.eb = sf, eb

    f.all = K.Button(f, L["Select all"], 130, 24, "ghost", function()
        eb:SetFocus()
        eb:HighlightText()
    end)
    f.all:SetPoint("BOTTOMLEFT", 14, 12)
    f.hint = K.Text(f, 11, C.dim)
    f.hint:SetPoint("LEFT", f.all, "RIGHT", 10, 0)
    f.hint:SetText(L["Select text, then press Ctrl+C to copy."])
    f.clear = K.Button(f, L["Clear matches"], 120, 24, "ghost", function()
        for i = #GC.hits, 1, -1 do GC.hits[i] = nil end
        f:Refresh()
    end)
    f.clear:SetPoint("BOTTOMRIGHT", -14, 12)

    function f:Refresh()
        self.dirty = nil
        local alerts = self.mode == "alerts"
        self.title:SetText(alerts and L["Chat alerts: matches"] or L["Search chat"])
        self.input:SetShown(not alerts)
        self.tab:SetShown(not alerts)
        self.clear:SetShown(alerts)
        local lines
        if alerts then
            lines = GC.hits
        else
            if not self.frame then self.frame = SELECTED_CHAT_FRAME or ChatFrame1 end
            if self.frame == ChatFrame2 then self.frame = ChatFrame1 end
            self.tab:SetLabel(L["Rider"] .. ": " .. GC.TabName(self.frame))
            lines = GC.Search(self.frame, self.input:GetText())
        end
        local out = {}
        for i = math.max(1, #lines - SHOW_MAX + 1), #lines do
            local l = lines[i]
            out[#out + 1] = (l.ts and date("[%H:%M] ", l.ts) or "") .. (alerts and ("<" .. l.w .. "> ") or "") .. l.t
        end
        self.count:SetText(#lines > SHOW_MAX and (L["%d lines, showing the last %d"]):format(#lines, SHOW_MAX) or (L["%d lines"]):format(#lines))
        if #out == 0 then
            out[1] = alerts and L["No matches yet. Add keywords in the settings under Gameplay helpers > Game chat."]
                or L["Nothing found. The search covers what appeared in this tab since you logged in."]
        end
        self.eb:SetText(table.concat(out, "\n"))
        self.eb:ClearFocus()
        C_Timer.After(0, function() self.sf:SetVerticalScroll(self.sf:GetVerticalScrollRange() or 0) end)
    end
    -- append new lines as long as nobody is selecting
    f:SetScript("OnUpdate", function(self, el)
        self.acc = (self.acc or 0) + el
        if self.acc < 1 then return end
        self.acc = 0
        if self.dirty and not self.eb:HasFocus() and not self.input:HasFocus() then self:Refresh() end
    end)
    f:Hide()
    ns.EscClose(f)
    return f
end
function GC.OpenViewer(mode, frame)
    if not GC.viewer then GC.viewer = buildViewer() end
    local f = GC.viewer
    if f:IsShown() and f.mode == mode then f:Hide() return end
    f.mode = mode
    if frame then f.frame = frame end
    f:Show()
    f:Refresh()
    -- search/copy also works without game chat (then reads the chat frame), only the alerts need it
    if mode == "alerts" and not G().gcOn then ns.print(L["Game chat is switched off - switch it on under Settings > Gameplay helpers > Game chat."]) end
end

------------------------------------------------------------------------
-- settings
------------------------------------------------------------------------
-- edit box + "Add" + entries as buttons (click removes)
local editors = {}
local function editor(card, y, w, key, placeholder, normalize)
    local e = { chips = {} }
    e.box = CreateFrame("Frame", nil, card)
    e.box:SetPoint("TOPLEFT", 14, y - 30)
    e.box:SetSize(w, 52)
    e.more = K.Text(card, 11, C.dim, "RIGHT")
    e.more:SetPoint("BOTTOMRIGHT", e.box, "BOTTOMRIGHT", 0, 4)
    e.none = K.Text(e.box, 11, C.dim)
    e.none:SetPoint("TOPLEFT", 0, -5)
    e.none:SetText(L["Nothing added yet."])
    function e:Update()
        for _, c in ipairs(self.chips) do c:Hide() end
        local list = G()[key]
        local x, row, hidden = 0, 0, 0
        for i, v in ipairs(list) do
            local c = self.chips[i]
            if not c then
                c = K.Button(self.box, "", 80, 22, "ghost")
                self.chips[i] = c
            end
            c:SetLabel(v .. "  |cffff5a4ax|r")
            local cw = math.min(w, math.floor((c.label:GetStringWidth() or 60) + 22))
            if x + cw > w then x, row = 0, row + 1 end
            if row > 1 or (row == 1 and x + cw > w - 34) then
                hidden = hidden + 1
            else
                c:SetWidth(cw)
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", x, -row * 26)
                c:SetScript("OnClick", function()
                    GC.ListRemove(key, v)
                    self:Update()
                end)
                c:Show()
                x = x + cw + 6
            end
        end
        self.more:SetText(hidden > 0 and ("+" .. hidden) or "")
        self.none:SetShown(#list == 0)
    end
    local function add()
        local value = e.input:GetText()
        if normalize then
            local why
            value, why = normalize(value)
            if not value then ns.print(why) return end
        end
        local ok, why = GC.ListAdd(key, value)
        if ok then e.input:SetText("") else ns.print(why) end
        e:Update()
    end
    e.input = K.Input(card, w - 112, L[placeholder])
    e.input:SetPoint("TOPLEFT", 14, y)
    e.input.onEnter = add
    e.add = K.Button(card, L["Add"], 104, 24, "ghost", add)
    e.add:SetPoint("LEFT", e.input, "RIGHT", 8, 0)
    e:Update()
    editors[#editors + 1] = e
    return e
end
local function muteValue(text)
    local channel, name = tostring(text or ""):match("^%s*(.-)%s*;%s*(.-)%s*$")
    if not channel or channel == "" or name == "" then return nil, L["Usage: channel; player name"] end
    return GC.MuteKey(channel, name)
end
local function stampText()
    local cur = G().gcStamp
    for _, st in ipairs(GC.STAMPS) do if st.key == cur then return st.key == "none" and L["Off"] or st.text end end
    return L["Game setting"]
end

local NAMES = {
    { "gcShort", "Shorten names", "Shows only the first name in chat. Whispering and right-click still use the full name." },
    { "gcLevel", "Level before the name", "Shows the level as soon as your game knows it (target, group, guild, friends, /who) - in the difficulty colour" },
    { "gcClassIcon", "Class icon before the name" },
    { "gcRaceIcon", "Race icon before the name" },
    { "gcLinkIcons", "Icons on item and spell links" },
    { "gcTokens", "Resolve shortcuts in text", "item:6948 and spell:10060 become clickable links, :mage: or :troll: become icons - only for you, the text itself is what gets sent" },
    { "gcChNum", "Shorten channel names", "[2. Trade - Orgrimmar] becomes [2]" },
    { "gcQuiet", "Quiet text", "Channel and name keep the channel colour, the message itself turns light grey (channels, say, yell)" },
    { "gcHover", "Item tooltip on hover", "Shows the tooltip when you hover an item link in chat instead of only on click" },
}
local FILTERS = {
    { "gcFilter", "Enable filters", "Applies to channels, say, yell, emotes and whispers - never to guild, party and raid and never to your own messages" },
    { "gcWhole", "Whole words only", "Otherwise \"boost\" also matches \"boosting\"" },
    { "gcCyr", "Hide Cyrillic text" },
    { "gcHan", "Hide Chinese characters" },
    { "gcRepeat", "Hide repeated messages", "The same message from the same player in the same channel within the chosen time" },
}
local BUTTONS = {
    { "gcHideMenu", "Hide the chat menu button" },
    { "gcHideChannel", "Hide the channel button" },
    { "gcHideSocial", "Hide the social button" },
    { "gcHideScroll", "Hide the scroll buttons" },
}
local function build(f)
    local H = ns.SettingsHelpers
    local s = G()
    f.noCompact = true
    -- 0.6.266: no own scroll area anymore - the settings scroll themselves and measure the page by its
    -- contents. The inner scroll area was as large as the page: you could not reach the very bottom.
    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 0, 0)
    -- 0.6.272: with EllesmereUI chat Oasis has not touched the chat since 0.6.254 (ns.ForeignChat) - the toggles
    -- here then silently did nothing. Now a notice sits on top and the page is greyed out.
    if ns.ForeignChat and ns.ForeignChat() then
        local warn = H.cardH(f, 0, 0, 738, 74, "eye_off", L["EllesmereUI chat detected"],
            L["EllesmereUI draws the chat. To avoid doing things twice, Oasis stays out of the chat - the switches on this page only work without EllesmereUI chat."])
        if warn.s then warn.s:SetWordWrap(true) warn.s:SetPoint("RIGHT", -14, 0) end
        body:SetPoint("TOPLEFT", 0, -86)
        body:SetAlpha(0.45)
    end
    body:SetSize(770, 900)
    local function apply() pcall(GC.ApplyAll) end
    local W, IN = 362, 334
    local function toggles(card, list, y, after)
        for _, o in ipairs(list) do
            H.toggle(card, 14, y, o[2], o[1], o[3], after, IN)
            y = y - 28
        end
        return y
    end

    -- left column
    local y = 0
    local c = H.cardH(body, 0, y, W, 152, "checklist", L["Game chat"])
    H.toggle(c, 14, -48, "Improve Blizzard's chat windows", "gcOn", "Master switch for everything on this page. Applies to new messages; messages protected during combat stay untouched.", apply, IN)
    H.toggle(c, 14, -80, "Also public channels, say and yell", "gcAllChannels", "Default: only guild, party, raid and whispers. The filters for Trade and General only work with this on.", apply, IN)
    H.note(c, L["Oasis does not replace any part of Blizzard's chat; it adjusts the lines afterwards."], 14, -116, IN)
    y = y - 152 - 12

    local h = 50 + #NAMES * 28 + 40
    c = H.cardH(body, 0, y, W, h, "profile", L["Names and icons"])
    local cy = toggles(c, NAMES, -48)
    H.rowLabel(c, L["Timestamp"], 14, cy - 4)
    local stamp = K.Button(c, stampText(), 170, 24, "ghost")
    stamp:SetPoint("TOPLEFT", 178, cy)
    stamp:SetScript("OnClick", function(self)
        local items = { { text = L["Game setting"], checked = s.gcStamp == nil, fn = function() s.gcStamp = nil GC.ApplyStamp() self:SetLabel(stampText()) end } }
        for _, st in ipairs(GC.STAMPS) do
            items[#items + 1] = { text = st.key == "none" and L["Off"] or st.text, checked = s.gcStamp == st.key,
                fn = function() s.gcStamp = st.key GC.ApplyStamp() self:SetLabel(stampText()) end }
        end
        K.ShowMenu(self, items, L["Timestamp"], 170)
    end)
    y = y - h - 12

    h = 50 + #BUTTONS * 28 + 8
    c = H.cardH(body, 0, y, W, h, "modules", L["Buttons on the chat window"])
    toggles(c, BUTTONS, -48, function() pcall(GC.ApplyButtons) end)
    y = y - h - 12

    -- 0.6.111: chat toggles from Comfort and selection gathered here
    local CO = ns.Comfort and ns.Comfort.CHAT_OPTS or {}
    h = 50 + (#CO + 2) * 28 + 8
    c = H.cardH(body, 0, y, W, h, "polls", L["Chat window"])
    cy = -48
    for _, o in ipairs(CO) do
        H.toggle(c, 14, cy, o[2], o[1], o[3], o[4] and function() pcall(o[4]) end or nil, IN)
        cy = cy - 28
    end
    if s.gcLiveSelect == nil then s.gcLiveSelect = true end
    if s.gcAltSelect == nil then s.gcAltSelect = true end
    H.toggle(c, 14, cy, "Select text by dragging", "gcLiveSelect", "Dragging across the chat selects letter by letter, Ctrl+C copies, right-click shows more", nil, IN)
    cy = cy - 28
    H.toggle(c, 14, cy, "Alt + click opens the selection box", "gcAltSelect", "The chat as a text box over the window - for selecting across many lines", nil, IN)
    local leftBottom = y - h - 12

    -- right column
    y = 0
    h = 50 + #FILTERS * 28 + 40 + 26 + 88 + 26 + 88 + 8
    c = H.cardH(body, 376, y, W, h, "eye_off", L["Filters and mutes"])
    cy = toggles(c, FILTERS, -48)
    H.rowLabel(c, L["Time window for repeats"], 14, cy - 4)
    local rep = K.Slider(c, 120, 5, 600, 5, function() return tonumber(s.gcRepeatSec) or 60 end, function(v) s.gcRepeatSec = v end,
        function(v) return v .. " s" end)
    rep:SetPoint("TOPLEFT", 226, cy - 2)
    cy = cy - 40
    H.rowLabel(c, "|cffe8b44a" .. L["Blocked words"] .. "|r", 14, cy)
    cy = cy - 26
    editor(c, cy, IN, "gcPhrases", "Word or phrase")
    cy = cy - 88
    H.rowLabel(c, "|cffe8b44a" .. L["Mute a player in one channel"] .. "|r", 14, cy)
    cy = cy - 26
    editor(c, cy, IN, "gcMutes", "Channel; player name", muteValue)
    y = y - h - 12

    h = 50 + 28 + 40 + 36
    c = H.cardH(body, 376, y, W, h, "chronicle", L["Search and history"])
    H.toggle(c, 14, -48, "Keep chat history between sessions", "gcHist", "The last lines of each tab are back after you log in (up to 7 days old, as plain text). They are stored only on your PC.", nil, IN)
    H.rowLabel(c, L["Lines per tab"], 14, -80)
    local keep = K.Slider(c, 150, 20, 300, 10, function() return tonumber(s.gcHistLines) or 100 end, function(v) s.gcHistLines = v end)
    keep:SetPoint("TOPLEFT", 196, -78)
    local find = K.Button(c, L["Search chat"], 160, 24, "primary", function() GC.OpenViewer("search") end)
    find:SetPoint("TOPLEFT", 14, -116)
    H.note(c, "/oa chatsuche", 184, -121, 160)
    y = y - h - 12

    h = 50 + 2 * 28 + 8 + 88 + 36
    c = H.cardH(body, 376, y, W, h, "announce", L["Keyword alerts"])
    H.toggle(c, 14, -48, "Notify me about keywords", "gcAlert", "When a new chat message contains one of your keywords, Oasis shows a notice and keeps the line", nil, IN)
    H.toggle(c, 14, -76, "Sound on alert", "gcAlertSound", nil, nil, IN)
    editor(c, -112, IN, "gcWords", "Keyword, e.g. looking for healer")
    local hitsBtn = K.Button(c, L["View matches"], 160, 24, "ghost", function() GC.OpenViewer("alerts") end)
    hitsBtn:SetPoint("TOPLEFT", 14, -200)
    H.note(c, "/oa chatalarm", 184, -205, 160)
    local rightBottom = y - h - 12

    body:SetHeight(-math.min(leftBottom, rightBottom) + 30)
end
local function refresh()
    for _, e in ipairs(editors) do pcall(e.Update, e) end
end
if ns.AddSettingsTab then ns.AddSettingsTab("gamechat", "Game chat", build, refresh) end

end)

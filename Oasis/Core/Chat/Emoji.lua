-- Oasis - emojis in chat
-- WoW cannot display real emoji characters and allows no images in sent messages.
-- So: you type short codes (:lol:, <3, :gg: ...), Oasis replaces them with images when displaying
-- (only people with Oasis see the image - everyone else sees the code). Raid icons {rt1}..{rt8} are seen by everyone.
-- Graphics: Twemoji (CC-BY 4.0), see Media\emoji\CREDITS.txt
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local Emoji = {}
ns.Emoji = Emoji
local PATH = ns.MEDIA .. "emoji\\"

-- key = file, codes = everything that becomes it (the first code is used on insert)
Emoji.LIST = {
    { "smile", ":)", ":-)" }, { "grin", ":D", ":-D", ":happy:" }, { "xd", "xD", "XD" }, { "wink", ";)", ";-)" },
    { "tongue", ":P", ":p", ":-P" }, { "sad", ":(", ":-(" }, { "cry", ":'(" }, { "wow", ":O", ":o", ":pog:", ":poggers:", ":omg:" },
    { "heart", "<3" }, { "lol", ":lol:", ":kekw:", ":lul:", ":omegalul:" }, { "rofl", ":rofl:" }, { "cool", ":cool:", ":ez:", ":chad:" },
    { "love", ":love:" }, { "angry", ":angry:" }, { "think", ":think:" }, { "facepalm", ":facepalm:" },
    { "party", ":party:", ":hype:" }, { "sleep", ":sleep:" }, { "sweat", ":sweat:" }, { "hug", ":hug:" },
    { "eyes", ":eyes:", ":sus:" }, { "skull", ":skull:" }, { "ghost", ":ghost:" }, { "poop", ":poop:" },
    { "fire", ":fire:" }, { "thumbsup", ":+1:", ":thumbsup:", ":w:" }, { "thumbsdown", ":-1:", ":thumbsdown:", ":l:" }, { "clap", ":clap:" },
    { "pray", ":pray:", ":f:" }, { "muscle", ":muscle:", ":gigachad:", ":strong:" }, { "wave", ":wave:" }, { "ok", ":ok:" },
    { "100", ":100:" }, { "gg", ":gg:" }, { "crown", ":crown:" }, { "star", ":star:" },
    { "beer", ":beer:" }, { "coffee", ":coffee:" }, { "money", ":money:" }, { "gem", ":gem:" },
    { "swords", ":swords:" }, { "shield", ":shield:" }, { "dice", ":dice:" }, { "rip", ":rip:" },
    { "rocket", ":rocket:" }, { "tada", ":tada:" },
    -- Fun emojis (Discord/Twitch names point to matching free images)
    { "sob", ":sob:", ":sadge:", ":pepehands:" }, { "smiling_tear", ":copium:", ":tear:" }, { "clown", ":clown:" },
    { "nerd", ":nerd:", ":actually:" }, { "moai", ":moai:" }, { "melt", ":melt:" }, { "salute", ":salute:", ":o7:" },
    { "pleading", ":pleading:", ":please:" }, { "flushed", ":flushed:", ":monkas:" }, { "smirk", ":smirk:", ":based:" },
    { "upside", ":upside:" }, { "moneyface", ":moneyface:", ":rich:" }, { "mindblown", ":mindblown:" }, { "steam", ":steam:", ":mad:" },
    { "cold", ":cold:" }, { "hot", ":hot:" }, { "sick", ":sick:" }, { "vomit", ":vomit:" }, { "shush", ":shush:" },
    { "hmm", ":hmm:" }, { "yawn", ":yawn:" }, { "drool", ":drool:" }, { "cowboy", ":yeehaw:", ":cowboy:" }, { "devil", ":devil:" },
    { "alien", ":alien:" }, { "robot", ":robot:", ":bot:" }, { "frog", ":frog:", ":pepe:" }, { "goat", ":goat:" },
    { "monkey", ":monkey:", ":hide:" }, { "dog", ":dog:" }, { "cat", ":cat:" }, { "popcorn", ":popcorn:" },
    { "salt", ":salt:", ":salty:" }, { "cap", ":cap:" }, { "nails", ":nails:" }, { "deal", ":deal:" }, { "chef", ":chef:" },
    { "brain", ":brain:", ":bigbrain:" }, { "trash", ":trash:" }, { "siren", ":siren:" }, { "stonks", ":stonks:" },
    { "notstonks", ":notstonks:" }, { "bomb", ":bomb:" }, { "zap", ":zap:" }, { "sparkles", ":sparkles:" },
    { "pizza", ":pizza:" }, { "cake", ":cake:" }, { "wine", ":wine:" }, { "meat", ":meat:" }, { "dragon", ":dragon:" },
    { "horse", ":horse:", ":mount:" }, { "bow", ":bow:" }, { "axe", ":axe:" }, { "potion", ":potion:" }, { "mage", ":mage:" },
    { "zombie", ":zombie:" }, { "troll", ":troll:" }, { "pirate", ":pirate:" },
}
-- Categories for the picker: standard, guild (own, also animated), raid icons
Emoji.CATS = { { key = "std", name = "Default", items = Emoji.LIST } }
-- own guild emojis (CustomEmojis + ImportEmojis.bat) live in the guild module Oasis_Guild and are added via Emoji.AddCats
local RAID = {}
for i = 1, 8 do RAID[i] = { "raid" .. i, "{rt" .. i .. "}", raid = true } end
Emoji.CATS[#Emoji.CATS + 1] = { key = "raid", name = "Raid", items = RAID, raid = true }

-- :name: -> entry ; short smileys (only as a separate "word") -> entry
-- Animated entries (from GIFs): n = frames, h = strip height in pixels (64 per frame), d = seconds per frame
local named, short = {}, {}
Emoji.anims = {}   -- [file] = entry
-- own emojis first: their codes (e.g. :pepehands:) take precedence over the fallback aliases in the default set
local order = {}
for _, cat in ipairs(Emoji.CATS) do if cat.custom then order[#order + 1] = cat end end
for _, cat in ipairs(Emoji.CATS) do if not cat.custom then order[#order + 1] = cat end end
for _, cat in ipairs(order) do
    if not cat.raid then
        for _, e in ipairs(cat.items) do
            if e.n and e.n > 1 then Emoji.anims[e[1]] = e end
            for i = 2, #e do
                local c = e[i]
                local n = c:match("^:([%w%+%-_]+):$")
                if n then named[n:lower()] = named[n:lower()] or e else short[c] = e end
            end
        end
    end
end

-- Image section of an animated emoji for the current time
local function frameOf(e)
    return math.floor(GetTime() / (e.d or 0.1)) % e.n
end
Emoji.FrameOf = frameOf
-- yoff: set a bit lower in chat (otherwise the image sits above the text line)
local function tex(e, size, yoff)
    if type(e) == "string" then e = { e } end
    yoff = yoff or 0
    local PATH = e.base or PATH
    if e.n and e.n > 1 then
        local top = frameOf(e) * 64
        return "|T" .. PATH .. e[1] .. ":" .. (size or 0) .. ":" .. (size or 0) .. ":0:" .. yoff .. ":64:" .. e.h .. ":0:64:" .. top .. ":" .. (top + 64) .. "|t"
    end
    if yoff ~= 0 then return "|T" .. PATH .. e[1] .. ":" .. (size or 0) .. ":" .. (size or 0) .. ":0:" .. yoff .. "|t" end
    return "|T" .. PATH .. e[1] .. ":" .. (size or 0) .. "|t"
end
Emoji.Tex = tex

-- Image back to the short code (for text that already went through the chat filter)
local codeOf = {}
function Emoji.CodeOf(key) return codeOf[key] end   -- 0.6.103: for the chat history (image -> short code)
for _, cat in ipairs(Emoji.CATS) do
    for _, e in ipairs(cat.items) do
        if e[2] and not codeOf[e[1]] then codeOf[e[1]] = e[2] end
    end
end
local GPATH = "Interface\\AddOns\\Oasis\\Media\\art\\emoji\\"   -- Textures of the guild emojis (guild module)
local TEX_PAT = "|T" .. PATH:gsub("%p", "%%%0") .. "([^:|]+)[^|]*|t"
local TEX_PAT_G = "|T" .. GPATH:gsub("%p", "%%%0") .. "([^:|]+)[^|]*|t"
function Emoji.Unrender(msg)
    if type(msg) ~= "string" or not (msg:find(PATH, 1, true) or msg:find(GPATH, 1, true)) then return msg end
    msg = msg:gsub("|Haddon:oasisemo:[^|]*|h(.-)|h", "%1")
    msg = msg:gsub(TEX_PAT, function(key) return codeOf[key] end)
    return (msg:gsub(TEX_PAT_G, function(key) return codeOf[key] end))
end

-- Emoji in chat as (invisible) link: only then can WoW show a tooltip on hover
local entryOf = {}
for _, cat in ipairs(Emoji.CATS) do
    for _, e in ipairs(cat.items) do if not entryOf[e[1]] then entryOf[e[1]] = e end end
end
-- 0.5.728: guild emojis from the guild module: append tab (before "Raid") and fill lookup tables
function Emoji.AddCats(cats, base)
    for _, c in ipairs(cats or {}) do
        local n = #Emoji.CATS + 1
        local cat = { key = "c" .. n, name = c.name, items = c.items, custom = true, fixedName = true }
        local at = n
        for i, x in ipairs(Emoji.CATS) do if x.key == "raid" then at = i break end end
        table.insert(Emoji.CATS, at, cat)
        for _, e in ipairs(cat.items) do
            e.base = base
            if e.n and e.n > 1 then Emoji.anims[e[1]] = e end
            for i = 2, #e do
                local code = e[i]
                local nm = code:match("^:([%w%+%-_]+):$")
                if nm then named[nm:lower()] = e else short[code] = e end
            end
            if e[2] and not codeOf[e[1]] then codeOf[e[1]] = e[2] end
            if not entryOf[e[1]] then entryOf[e[1]] = e end
        end
    end
end
-- only if the client knows "addon:" links (otherwise clicking it would cause an error)
local function linksOk()
    return (LinkTypes and LinkTypes.addon ~= nil) or (EventRegistry ~= nil and LinkUtil ~= nil and C_AddOns ~= nil)
end
-- Size in chat: configured, or automatically as large as the font
local function chatSize()
    if Emoji.sizeOverride then return Emoji.sizeOverride end   -- Oasis window with smaller font (private chat ...)
    local v = ns.db and tonumber(ns.db.settings.emojiChatSize) or 0
    if v > 0 then return v end
    local _, fh = ChatFrame1 and ChatFrame1.GetFont and ChatFrame1:GetFont()
    return math.floor((fh or 14) * 1.0 + 0.5)
end
-- 0.5.602: only minimally lower now (previously 18 %) - in the bottom chat line the image otherwise stuck out below the
-- window edge and got clipped (Blizzard chat like EllesmereUI)
local function yoffFor(sz) return -math.floor((sz or 20) * 0.06 + 0.5) end
local BLANK = ns.MEDIA .. "blank"
local function linked(e)
    local sz = chatSize()
    if not linksOk() then return tex(e, sz, yoffFor(sz)) end
    -- 0.6.102 mode 4: animated emojis in chat as invisible placeholder, Oasis lays the moving image on top
    if Emoji._inFilter and e.n and e.n > 1 and ns.db and tonumber(ns.db.settings.emojiRedraw) == 4 then
        local yo = yoffFor(sz)
        return "|Haddon:oasisemo:" .. e[1]:gsub("\\", "~") .. "|h|T" .. BLANK .. ":" .. sz .. ":" .. sz .. ":0:" .. yo .. "|t|h"
    end
    return "|Haddon:oasisemo:" .. e[1]:gsub("\\", "~") .. "|h" .. tex(e, sz, yoffFor(sz)) .. "|h"
end
function Emoji.ShowLinkTip(owner, link)
    local key = link and link:match("^addon:oasisemo:(.+)$")
    key = key and key:gsub("~", "\\")
    local e = key and entryOf[key]
    if not e then return false end
    local codes = {}
    for i = 3, #e do codes[#codes + 1] = e[i] end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:AddLine(tex(e, 64) .. "   |cffffffff" .. (e[2] or "") .. "|r")
    -- play animated emojis (GIFs) in the tooltip too
    if e.n and e.n > 1 then
        Emoji.tipAnim = Emoji.tipAnim or CreateFrame("Frame")
        Emoji.tipAnim.e = e
        Emoji.tipAnim:SetScript("OnUpdate", function(self)
            if not GameTooltip:IsShown() or GameTooltip:GetOwner() ~= owner then self:SetScript("OnUpdate", nil) return end
            local l = _G.GameTooltipTextLeft1
            if l then l:SetText(tex(self.e, 64) .. "   |cffffffff" .. (self.e[2] or "") .. "|r") end
        end)
    end
    if #codes > 0 then GameTooltip:AddLine(L["also:"] .. " " .. table.concat(codes, "  "), 0.6, 0.6, 0.65) end
    GameTooltip:Show()
    return true
end
-- All chat windows: the fixed ones (1..NUM_CHAT_WINDOWS) and the temporary ones (whisper tabs, from number 11) from
-- CHAT_FRAMES. Previously only the fixed ones were included: in the whisper tab animated emojis stood still and the
-- buttons at the input were missing.
local function chatFrameNames()
    local out, seen = {}, {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local n = "ChatFrame" .. i
        out[#out + 1], seen[n] = n, true
    end
    if type(CHAT_FRAMES) == "table" then
        for _, n in ipairs(CHAT_FRAMES) do
            if type(n) == "string" and not seen[n] then seen[n] = true out[#out + 1] = n end
        end
    end
    return out
end
Emoji.ChatFrameNames = chatFrameNames
-- 0.6.235: EllesmereUI (chat module) keeps the Blizzard chat running invisibly (text alpha 0) and draws the
-- visible text in its OWN ScrollingMessageFrame on the window's background. The emojis
-- (mode 4) must be aligned to ITS lines - on the invisible Blizzard lines they sat offset.
-- Access via the public mapping EllesmereUI._chatCFD(cf).bg -> child of type ScrollingMessageFrame.
local function euiWindow(cf)
    local E = rawget(_G, "EllesmereUI")
    local CFD = type(E) == "table" and E._chatCFD
    if not cf or type(CFD) ~= "function" then return nil end
    local ok, d = pcall(CFD, cf)
    local bg = ok and type(d) == "table" and d.bg
    if not (bg and bg.GetChildren) then return nil end
    -- 0.6.236: detect by content instead of type name (the custom frame didn't report itself as
    -- "ScrollingMessageFrame"): child with line list and message count; visible one preferred
    local any
    for _, c in ipairs({ bg:GetChildren() }) do
        if type(c.visibleLines) == "table" and c.GetNumMessages then
            if c:IsVisible() then return c end
            any = any or c
        end
    end
    return any
end
-- Diagnostics: what is attached to the EllesmereUI surface?
function Emoji.EuiDiag(cf)
    local E = rawget(_G, "EllesmereUI")
    local CFD = type(E) == "table" and E._chatCFD
    if type(CFD) ~= "function" then return "kein _chatCFD" end
    local ok, d = pcall(CFD, cf)
    if not ok or type(d) ~= "table" then return "CFD-Fehler" end
    if not d.bg then return "keine bg-Flaeche" end
    local parts = {}
    for _, c in ipairs({ d.bg:GetChildren() }) do
        parts[#parts + 1] = (c.GetObjectType and c:GetObjectType() or "?") .. (type(c.visibleLines) == "table" and ("[" .. #c.visibleLines .. "]") or "")
            .. (c.IsVisible and (c:IsVisible() and "+" or "-") or "")
    end
    return "bg-Kinder: " .. (#parts > 0 and table.concat(parts, " ") or "keine")
end
Emoji.EuiWindow = euiWindow
-- Chat diagnostics: read only, don't print chat lines or install scroll hooks.
-- The report contains no messages and stays local; the copy opens outside the chat.
local chatWatchTimer
local function watchValue(f, method)
    if not f or type(f[method]) ~= "function" then return "?" end
    local ok, value = pcall(f[method], f)
    value = ok and ns.safe(value)
    if type(value) == "number" then return ("%.2f"):format(value) end
    if type(value) == "boolean" then return value and "1" or "0" end
    return "?"
end
local function watchFrame(f)
    if not f then return "missing" end
    local values = {}
    for _, method in ipairs({ "GetScrollOffset", "GetNumMessages", "GetMaxScrollRange", "GetNumVisibleLines",
        "IsVisible", "GetEffectiveAlpha", "GetWidth", "GetHeight", "GetTop", "GetBottom", "GetFading" }) do
        values[#values + 1] = watchValue(f, method)
    end
    local shown, text, inside, secret, ink = 0, 0, 0, 0, 0
    local lines = ns.safe(f.visibleLines)
    if type(lines) == "table" then
        for _, fs in ipairs(lines) do
            if ns.safe(fs:IsShown()) then
                shown = shown + 1
                local raw = fs:GetText()
                if issecretvalue and issecretvalue(raw) then
                    secret = secret + 1
                elseif type(raw) == "string" and raw ~= "" then
                    text = text + 1
                    local alpha = fs.GetEffectiveAlpha and ns.safe(fs:GetEffectiveAlpha())
                    if type(alpha) == "number" and alpha > 0 then ink = ink + 1 end
                    local ft, fb = ns.safe(f:GetTop()), ns.safe(f:GetBottom())
                    local lt, lb = ns.safe(fs:GetTop()), ns.safe(fs:GetBottom())
                    if type(ft) == "number" and type(fb) == "number" and type(lt) == "number" and type(lb) == "number"
                        and lt > fb and lb < ft then inside = inside + 1 end
                end
            end
        end
    end
    return table.concat(values, "/") .. (" lines=%d text=%d inside=%d secret=%d ink=%d containerAlpha=%s"):format(
        shown, text, inside, secret, ink, watchValue(f.FontStringContainer, "GetEffectiveAlpha"))
end
local function showChatWatch()
    local report = ns.db and ns.db.chatWatchReport
    if report and ns.WhisperLog and ns.WhisperLog.Copy then
        ns.WhisperLog.Copy(L["Chat diagnostics"], report)
    end
end
ns.slash.chatwatch = function(arg)
    if not ns.db then return end
    if arg and arg:match("^%s*bericht%s*$") then showChatWatch() return end
    if chatWatchTimer then chatWatchTimer:Cancel() chatWatchTimer = nil end
    local cf = SELECTED_CHAT_FRAME or ChatFrame1
    if not cf then return end
    local out = { "Oasis " .. ns.version .. " chatwatch (30 s)",
        "offset/messages/range/visibleLines/visible/alpha/width/height/top/bottom/fading",
        "Read-only; no chat text captured. Scroll normally after the first 3 seconds." }
    local function sample(n)
        out[#out + 1] = ("%02ds Blizzard %s"):format(n, watchFrame(cf))
        out[#out + 1] = ("%02ds EllesmereUI %s"):format(n, watchFrame(euiWindow(cf)))
        ns.db.chatWatchReport = table.concat(out, "\n")
    end
    sample(0)
    if ns.K and ns.K.Toast then
        ns.K.Toast(L["Chat diagnostics"], L["Recording for 30 seconds. The report will then open for copying."], nil, nil, "none")
    end
    local n = 0
    chatWatchTimer = C_Timer.NewTicker(1, function()
        n = n + 1
        sample(n)
        if n >= 30 then
            chatWatchTimer:Cancel()
            chatWatchTimer = nil
            showChatWatch()
        end
    end)
end
-- Hooks per chat window (tooltip, input, buttons): run at login and again when WoW opens a tab
local wirers = {}
function Emoji.WireChatFrames()
    Emoji._stepFrames = nil
    for _, fn in ipairs(wirers) do
        local ok, e = pcall(fn)
        if not ok then ns.err("Emoji", e) end
    end
end
ns.Listen("LOGIN", function()
    Emoji.WireChatFrames()
    if not (ns.ForeignChat and ns.ForeignChat()) and hooksecurefunc and type(FCF_OpenTemporaryWindow) == "function" then
        hooksecurefunc("FCF_OpenTemporaryWindow", function() C_Timer.After(0, Emoji.WireChatFrames) end)
    end
end)
-- Chat window: tooltip on hover (hook only, Blizzard's own link handling stays)
local tipHooked = setmetatable({}, { __mode = "k" })
wirers[#wirers + 1] = function()
    for _, n in ipairs(chatFrameNames()) do
        local cf = _G[n]
        if cf and cf.HookScript and not tipHooked[cf] then
            tipHooked[cf] = true
            cf:HookScript("OnHyperlinkEnter", function(self, link) Emoji.ShowLinkTip(self, link) end)
            cf:HookScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
        end
    end
end

-- Convert text outside links (item/player links contain colons!)
-- locked emojis (from Oasis rank): only show as image if the SENDER has the rank
local renderSender
function Emoji.Allowed(e, who)
    -- 0.6.534: own guild emojis -> leadership's setting (rank, off, leadership only) first
    local own = type(e) == "table" and type(e[1]) == "string" and e[1]:match("^x\\(.+)$")
    if own and ns.MediaPack then
        local ok = ns.MediaPack.MayUse("emoji", own, who)
        if ok ~= nil then return ok end
    end
    if who and ns.isMe(who) and ns.UnlockAll and ns.UnlockAll() then return true end
    local need = ns.Rewards and ns.Rewards.EmojiLevel and ns.Rewards.EmojiLevel(e)
    if not need then return true end
    if not who then return true end
    local lvl = ns.Rank and ns.Rank.Of and ns.Rank.Of(who)
    return (lvl or 0) >= need
end
-- Build the pattern once (previously reassembled per word and message)
local TAIL_PATS = { "^(%a+)(...)([%.,!%?]*)$", "^(%a+)(..)([%.,!%?]*)$" }
local function renderPlain(s)
    s = s:gsub(":([%w%+%-_]+):", function(n)
        local e = named[n:lower()]
        if e and Emoji.Allowed(e, renderSender) then return linked(e) end
    end)
    -- short smileys only as a separate word (otherwise e.g. "12:30" or a URL would be broken up).
    -- trailing punctuation stays ("xD!" -> image + "!"), smileys attached directly to a word
    -- are also recognized ("hallo:)" -> "hallo" + image), times/links are not.
    s = s:gsub("(%S+)", function(w)
        local e = short[w]
        if e then return linked(e) end
        -- split off trailing punctuation ("xD!", ":D?!", "<3.")
        local core, tail = w:match("^(.-)([%.,!%?;]+)$")
        if core and core ~= "" and short[core] then return linked(short[core]) .. tail end
        -- Smiley directly at the end of a word ("hallo:)", "gg:D!"), only with letters before it
        if not w:find("[:;]") then return nil end
        for _, pat in ipairs(TAIL_PATS) do
            local base, code, rest = w:match(pat)
            if base and short[code] and code:find("^[:;]") then
                return base .. linked(short[code]) .. rest
            end
        end
    end)
    return s
end
function Emoji.Render(msg, sender)
    renderSender = sender
    if type(msg) ~= "string" or msg == "" then return msg end
    -- Quick check: all short codes contain : ; < { or xD/XD (previously it triggered on every "x")
    if not (msg:find("[:;<{]") or msg:find("[xX]D")) then return msg end
    local out, pos = {}, 1
    while true do
        local a, b = msg:find("|H.-|h.-|h", pos)
        if not a then break end
        out[#out + 1] = renderPlain(msg:sub(pos, a - 1))
        out[#out + 1] = msg:sub(a, b)
        pos = b + 1
    end
    out[#out + 1] = renderPlain(msg:sub(pos))
    local res = table.concat(out)
    -- animated emoji included? Then the animation (StepChat) runs for the next 15 min
    if res ~= msg and res:find("emoji\\guild\\", 1, true) then Emoji.animShown = GetTime() end
    return res
end

------------------------------------------------------------------------
-- Animation in chat: advance visible chat lines with animated emojis frame by frame
-- (addons like TwitchEmotes do it the same way; display only, nothing is sent)
------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
-- y offset can be negative (emoji sits on the baseline) -> include it, otherwise the image stands still
local ANIM_PAT = "(emoji\\(guild\\[%w_]+)):(%d+):(%d+):0:(%-?%d+):64:(%d+):0:64:(%d+):(%d+)|t"
local function animText(t)
    return (t:gsub(ANIM_PAT, function(path, key, sw, sh, yo, h, top, bottom)
        local e = Emoji.anims[key]
        if not e then return nil end
        local nt = frameOf(e) * 64
        return path .. ":" .. sw .. ":" .. sh .. ":0:" .. yo .. ":64:" .. h .. ":0:64:" .. nt .. ":" .. (nt + 64) .. "|t"
    end))
end
-- 0.6.1: redraw depending on the machine (/oa emojimodus): 1 = line directly (default), 2 = clear the line first, then
-- set again, 3 = via the window's chat history (TransformMessages) - for clients that don't redraw a changed
-- line (text was demonstrably advanced, image stood still anyway)
local function redrawMode() return tonumber(ns.db and ns.db.settings.emojiRedraw) or 1 end
local function stepLine(fs)
    local t = fs:GetText()
    if not t or issecret(t) or not t:find("emoji\\guild\\", 1, true) then return end
    local new = animText(t)
    if new ~= t then
        if redrawMode() == 2 then fs:SetText("") end
        fs:SetText(new)
    end
end
------------------------------------------------------------------------
-- Mode 4 (0.6.102): own images over the placeholders. Some clients don't redraw a changed chat line
-- (text demonstrably advanced, image stood still) - real textures still move there (as in the
-- emoji window). Position: measure the line with the same font, on wrap find the line via the spaces.
------------------------------------------------------------------------
-- Offset factor for mode 4: own setting (/oa emojiversatz), otherwise 1.
-- 0.6.234: Mac assumption from 0.6.233 removed again - the affected player is not on a Mac.
function Emoji.XScale()
    return tonumber(ns.db and ns.db.settings.emojiXScale) or 1
end
local OV_PAT = "|Haddon:oasisemo:([^|]+)|h|T[^|]-blank:(%d+):(%d+):0:(%-?%d+)|t|h"
local ov = { info = setmetatable({}, { __mode = "k" }), layers = {}, pool = {}, used = 0 }
local measFS, wrapFS
local function measWidth(fs, t)
    if not measFS then measFS = UIParent:CreateFontString(nil, "BACKGROUND") measFS:SetWordWrap(false) measFS:SetAlpha(0) end
    local f, s, fl = fs:GetFont()
    if not f then return 0 end
    measFS:SetFont(f, s, fl or "")
    measFS:SetText(t)
    return (measFS.GetUnboundedStringWidth and measFS:GetUnboundedStringWidth()) or measFS:GetStringWidth() or 0
end
local function measRows(fs, t)
    if not wrapFS then wrapFS = UIParent:CreateFontString(nil, "BACKGROUND") wrapFS:SetWordWrap(true) wrapFS:SetAlpha(0) end
    local f, s, fl = fs:GetFont()
    if not f then return 1 end
    wrapFS:SetFont(f, s, fl or "")
    wrapFS:SetWidth(fs:GetWidth() or 300)
    wrapFS:SetText(t)
    return (wrapFS.GetNumLines and wrapFS:GetNumLines()) or 1
end
-- Emojis of a line with position (x from the left, image line) - only recomputed when the text changes
local function lineItems(fs, raw)
    -- 0.6.162: the font is part of the cache key - chat addons (EllesmereUI etc.) often set the font only
    -- after the first measurement, otherwise the old position stuck and the emoji sat permanently off
    local f, s, fl = fs:GetFont()
    local ts = fs.GetTextScale and fs:GetTextScale()
    local fkey = tostring(f) .. "|" .. tostring(s) .. "|" .. tostring(fl) .. "|" .. tostring(ts) .. "|" .. tostring(fs.GetWidth and fs:GetWidth())
    local c = ov.info[fs]
    if c and c.raw == raw and c.fkey == fkey then return c.items end
    local items = {}
    local multi = fs.GetNumLines and (fs:GetNumLines() or 1) > 1
    -- 0.6.106: calibrate against the real line - if the chat line reports a different total width than our own measurement
    -- (different font rendering, icons ...), x is converted with the same factor
    local factor = 1
    local real
    if not multi then
        real = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or (fs.GetStringWidth and fs:GetStringWidth())
        local mine = measWidth(fs, raw)
        if real and real > 0 and mine > 0 then factor = real / mine end
        if factor < 0.5 or factor > 2 then factor = 1 end
    end
    local pos = 1
    while true do
        local a, e, key, sw, sh, yo = raw:find(OV_PAT, pos)
        if not a then break end
        key = key:gsub("~", "\\")
        local an = Emoji.anims[key]
        if an then
            local prefix = raw:sub(1, a - 1)
            local x, row = nil, 1
            if not multi then
                -- 0.6.143: calculate from the right - WoW reports the real line width itself, only the text
                -- after the emoji is measured (usually nothing). From the left, measurement errors added up (emoji sat far to the right).
                local sz = tonumber(sw) or 14
                if real and real > 0 then
                    local suffix = raw:sub(e + 1)
                    x = real - sz - ((suffix ~= "" and measWidth(fs, suffix) * factor) or 0)
                    if x < 0 then x = measWidth(fs, prefix) * factor end
                else
                    x = measWidth(fs, prefix) * factor
                end
            else
                -- Image line of the emoji and its start (after the last space that still wraps before it)
                row = measRows(fs, raw:sub(1, e))
                local start = 1
                if row > 1 then
                    for s = #prefix, 1, -1 do
                        if prefix:sub(s, s) == " " and measRows(fs, raw:sub(1, s - 1)) < row then start = s + 1 break end
                    end
                end
                x = measWidth(fs, prefix:sub(start))
            end
            items[#items + 1] = { e = an, x = x, row = row, sz = tonumber(sw) or 14, yo = tonumber(yo) or 0 }
        end
        pos = e + 1
    end
    ov.info[fs] = { raw = raw, items = items, factor = factor, fkey = fkey }
    return items
end
local function ovLayer(cf)
    local l = ov.layers[cf]
    if not l then
        l = CreateFrame("Frame", nil, UIParent)
        l:SetFrameStrata(cf:GetFrameStrata() or "MEDIUM")
        l:SetFrameLevel((cf:GetFrameLevel() or 1) + 6)
        l:SetAllPoints(cf)
        ov.layers[cf] = l
    end
    -- same scale as the chat window: measured in its units (0.6.103 - otherwise sat too far right)
    return l
end
local function ovStep(frames)
    for _, t in ipairs(ov.pool) do t.keep = false end
    local n = 0
    for _, cf in ipairs(frames) do
        local lines = cf and cf:IsVisible() and type(cf.visibleLines) == "table" and cf.visibleLines
        if lines then
            local layer = ovLayer(cf)
            layer:Show()
            for _, fs in ipairs(lines) do
                if fs.IsShown and fs:IsShown() then
                    local raw = fs:GetText()
                    if raw and not issecret(raw) and raw:find("oasisemo:", 1, true) and raw:find("blank:", 1, true) then
                        local rows = math.max(1, (fs.GetNumLines and fs:GetNumLines()) or 1)
                        local lh = (fs:GetHeight() or 14) / rows
                        -- 0.6.105: only image lines inside the chat window (scrolled-up lines stick out above it)
                        local ct, cb, ft = cf:GetTop(), cf:GetBottom(), fs:GetTop()
                        for _, it in ipairs(lineItems(fs, raw)) do
                            local rowTop = ft and (ft - (it.row - 1) * lh)
                            local inside = not (ct and cb and rowTop) or (rowTop <= ct + 2 and rowTop - lh >= cb - 2)
                            if inside then
                            n = n + 1
                            local t = ov.pool[n]
                            if not t then t = layer:CreateTexture(nil, "OVERLAY") ov.pool[n] = t end
                            if t:GetParent() ~= layer then t:SetParent(layer) end
                            local e = it.e
                            t:SetTexture((e.base or PATH) .. e[1])
                            local top = frameOf(e) * 64
                            t:SetTexCoord(0, 1, top / e.h, (top + 64) / e.h)
                            -- 0.6.108: measured in chat line units, placed in those of the image layer -> convert
                            -- (at chat scale 0.64 the image otherwise sat offset); respect the line's text alignment
                            local k = (fs:GetEffectiveScale() or 1) / (layer:GetEffectiveScale() or 1)
                            local jx = 0
                            local jh = fs.GetJustifyH and fs:GetJustifyH()
                            if (jh == "RIGHT" or jh == "CENTER") and it.row == 1 and rows == 1 then
                                local free = (fs:GetWidth() or 0) - ((fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0)
                                if free > 0 then jx = (jh == "RIGHT") and free or free / 2 end
                            end
                            -- 0.6.147: text scale of the line (SetTextScale) - WoW reports widths without it but draws
                            -- scaled down; without this factor the emoji sat ~14 % too far right for some players
                            local ts = (fs.GetTextScale and tonumber((fs:GetTextScale()))) or 1
                            if ts <= 0.2 or ts > 5 then ts = 1 end
                            -- 0.6.152: manual correction (/oa emojiversatz) in case a client draws differently than it measures
                            local xs = Emoji.XScale()
                            t:SetSize(it.sz * k * ts, it.sz * k * ts)
                            t:ClearAllPoints()
                            t:SetPoint("CENTER", fs, "TOPLEFT", (jx + it.x * xs + it.sz / 2) * k * ts, (-((it.row - 1) * lh + lh / 2) + it.yo * ts) * k)
                            ov.dbg = ov.dbg or { k = k, fs = fs, x = it.x, t = t, jh = jh }
                            t:SetAlpha(fs.GetEffectiveAlpha and fs:GetEffectiveAlpha() or 1)
                            t:Show()
                            end
                        end
                    end
                end
            end
        elseif cf and ov.layers[cf] then
            ov.layers[cf]:Hide()
        end
    end
    for i = n + 1, #ov.pool do ov.pool[i]:Hide() end
    return n
end
Emoji.OverlayStep = ovStep

local lastTransform = 0
local function stepBuffer(cf)
    if not cf.TransformMessages then return false end
    local now = GetTime()
    if now - lastTransform < 0.08 then return true end
    cf:TransformMessages(function(message)
        return type(message) == "string" and not issecret(message) and message:find("emoji\\guild\\", 1, true) ~= nil
    end, function(message, ...)
        return animText(message), ...
    end)
    return true
end
-- own Oasis text fields (chat bubbles, preview): advance animated emojis there as well
Emoji.tracked = setmetatable({}, { __mode = "k" })
function Emoji.Track(fs)
    if fs and fs.GetText then Emoji.tracked[fs] = true end
end
function Emoji.StepChat()
    if not ns.db or ns.db.settings.chatEmoji == false then return end
    -- only if an animated emoji was shown in the last 15 min or Oasis fields contain some
    -- (performance 0.5.482: previously all visible chat lines were processed 20x per second)
    if GetTime() - (Emoji.animShown or -1e9) > 900 and not next(Emoji.tracked) then return end
    local frames = Emoji._stepFrames
    if not frames then
        frames = {}
        for _, n in ipairs(chatFrameNames()) do frames[#frames + 1] = _G[n] end
        Emoji._stepFrames = frames
    end
    for _, f in ipairs(Emoji.frames or {}) do
        local have = false
        for _, x in ipairs(frames) do if x == f then have = true break end end
        if not have then frames[#frames + 1] = f end
    end
    -- Always advance Oasis's own fields (guild chat page, whisper bubbles, polls) - 0.6.289: the
    -- EllesmereUI block from 0.6.257 was meant only for the invisible Blizzard lines but stopped these too
    for fs in pairs(Emoji.tracked) do
        if fs.IsVisible and fs:IsVisible() then pcall(stepLine, fs) end
    end
    -- 0.5.565: don't advance the chat window whose link is under the mouse (the tooltip belongs to it) -
    -- SetText rebuilds the link areas, WoW reports "mouse left" and the preview vanished immediately
    local tipOwner = GameTooltip and GameTooltip:IsShown() and GameTooltip:GetOwner() or nil
    if redrawMode() == 4 then
        -- 0.6.235: with EllesmereUI measure EllesmereUI's visible frames instead of the invisible Blizzard lines
        local ovFrames = frames
        if rawget(_G, "EllesmereUI") then
            ovFrames = {}
            for i, f in ipairs(frames) do ovFrames[i] = euiWindow(f) or f end
        end
        local ok, e = pcall(ovStep, ovFrames)
        if not ok then ns.err("Emoji", e) end
        return
    end
    if (ns.ForeignChat and ns.ForeignChat()) then return end   -- 0.6.257: modes 1-3 only in Blizzard chat (mode 4 runs above)
    local viaBuffer = redrawMode() == 3
    for _, cf in ipairs(frames) do
        local lines = cf and cf ~= tipOwner and cf:IsVisible() and cf.visibleLines
        if lines and viaBuffer and cf.TransformMessages and cf ~= Emoji.frames[1] then
            local ok, e = pcall(stepBuffer, cf)
            if not ok then ns.err("Emoji", e) end
        elseif lines then
            for _, fs in ipairs(lines) do
                -- Don't advance the line under the mouse: SetText rebuilds the link areas, a click on the
                -- name in a line with an animated emoji got lost because of that (no whisper, no menu)
                if fs.IsShown and fs:IsShown() and not (fs.IsMouseOver and fs:IsMouseOver()) then pcall(stepLine, fs) end
            end
        end
    end
    if viaBuffer and GetTime() - lastTransform >= 0.08 then lastTransform = GetTime() end
end
-- 0.5.511: ~30 frames/s instead of 12.5 (every 0.08 s) - the GIFs have 0.02-0.06 s per frame and stuttered/ran
-- seemingly too slow. Runs only while animated emojis can be visible (StepChat checks that itself).
ns.Listen("LOGIN", function()
    if not next(Emoji.anims) or Emoji.stepper then return end
    -- after /reload: restored chat history may contain animated emojis -> run for 15 min
    Emoji.animShown = GetTime()
    local st = CreateFrame("Frame")
    Emoji.stepper = st
    local acc = 0
    st:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc < 0.033 then return end
        acc = 0
        local ok, e = pcall(Emoji.StepChat)
        if not ok then ns.err("Emoji", e) end
    end)
end)

------------------------------------------------------------------------
-- Chat filter: display only, the text is still what gets sent
------------------------------------------------------------------------
local EVENTS = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }
local function filter(self, event, msg, ...)
    if not ns.db or ns.db.settings.chatEmoji == false then return false end
    msg = ns.safe(msg)   -- in combat messages can be "secret" -> don't touch
    if not msg then return false end
    local sender = ns.safe((...))
    -- own sent whisper: "sender" here is the RECIPIENT -> I am the sender
    -- (otherwise locked emojis were checked against their rank and stayed as code)
    if event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM" then sender = ns.me() end
    Emoji._inFilter = true
    local ok, new = pcall(Emoji.Render, msg, sender and ns.fullName(sender) or nil)
    Emoji._inFilter = nil
    if not ok then new = msg end
    if new ~= msg then return false, new, ... end
    return false
end
local function addFilter(ev)
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if add then pcall(add, ev, filter) end
end
for _, ev in ipairs(EVENTS) do addFilter(ev) end

------------------------------------------------------------------------
-- Picker window
------------------------------------------------------------------------
local picker
local function activeEditBox()
    local eb = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) or (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
    if eb then return eb end
    return ChatFrame1EditBox
end
Emoji.frames = {}   -- further chat windows (e.g. guild chat page) whose emojis are animated
-- Where was the user just typing? (clicking the emoji button closes the input -> afterwards
-- reopen exactly there, otherwise WoW turns a whisper into "Say")
local PREFIX_OF = { SAY = "/s ", YELL = "/y ", PARTY = "/p ", RAID = "/ra ", GUILD = "/g ", OFFICER = "/o ",
    INSTANCE_CHAT = "/i ", RAID_WARNING = "/rw " }
-- Target of a chat input as slash prefix ("/w Tomas ", "/p " ...), nil = no chat input box
local function targetOf(eb)
    if not eb or not eb.GetAttribute then return nil end
    local ct = ns.safe(eb:GetAttribute("chatType"))
    if ct == "WHISPER" or ct == "BN_WHISPER" then
        -- also Battle.net whispers (friends list: "Tomas erzaehlen")
        local who = ns.safe(eb:GetAttribute("tellTarget"))
        if who and who ~= "" then return "/w " .. who .. " " end
    elseif ct == "CHANNEL" then
        local ch = ns.safe(eb:GetAttribute("channelTarget"))
        if ch then return "/" .. ch .. " " end
    elseif ct then
        return PREFIX_OF[ct]
    end
end
Emoji.TargetOf = targetOf
-- only remember while actually typing in the input: if it loses focus (click on the
-- emoji button), WoW resets it to "Say" - that must not overwrite the remembered target
function Emoji.RememberTarget(eb)
    eb = eb or activeEditBox()
    if not eb or not eb:IsShown() or not (eb.HasFocus and eb:HasFocus()) then return end
    local pre = targetOf(eb)
    -- WoW briefly switches to "Say" when reopening - that must not overwrite a just-remembered target (guild, group,
    -- whisper)
    local lt = Emoji.lastTarget
    if pre == "/s " and lt and lt.pre ~= "/s " and lt.t and GetTime() - lt.t < 8 then return end
    if pre then
        local okc, cp = pcall(eb.GetCursorPosition, eb)
        Emoji.lastTarget = { pre = pre, text = ns.safe(eb:GetText()) or "", eb = eb, t = GetTime(), cur = okc and tonumber(cp) or nil,
            ct = ns.safe(eb:GetAttribute("chatType")), who = ns.safe(eb:GetAttribute("tellTarget")) }
    end
end
-- after clicking the emoji button: WoW closed the input/set it to "Say" ->
-- reopen immediately with the remembered target and the started text
-- Open chat input with target + text (or do nothing if it is already open exactly like that)
local function openWith(pre, text, ct, who0)
    local cur = activeEditBox()
    if cur and cur:IsShown() and cur.HasFocus and cur:HasFocus() and targetOf(cur) == pre
        and (ns.safe(cur:GetText()) or "") == text then return end
    if ns.inCombat() then return end
    local who = pre:match("^/w (.-) $")
    if ct == "BN_WHISPER" and (who0 or who) then
        -- Battle.net whisper: open and set type + target directly (WoW's function doesn't always work here)
        who = who0 or who
        ns.Trace("BN_WHISPER " .. who)
        if ChatFrame_SendBNetTell then pcall(ChatFrame_SendBNetTell, who) end
        -- NO SetAttribute on Blizzard's chat input anymore: that "taints" it and WoW
        -- then blocks protected functions ("Oasis wurde blockiert ... callback()")
        local nb = activeEditBox()
        if nb and nb:IsShown() then nb:SetText(text) nb:SetFocus() end
        return
    end
    local bnID = who and BNet_GetBNetIDAccount and ns.safe(BNet_GetBNetIDAccount(who))
    if who and bnID and ChatFrame_SendBNetTell then
        -- Battle.net friend: open via WoW's Battle.net whisper
        ns.Trace("ChatFrame_SendBNetTell")
        ChatFrame_SendBNetTell(who)
        local nb = activeEditBox()
        if nb then nb:SetText(text) end
    elseif who and ChatFrame_SendTell then
        -- Open whisper with WoW's own function (like "Reply"), then insert the text
        ns.Trace("ChatFrame_SendTell")
        ChatFrame_SendTell(who)
        local nb = activeEditBox()
        if nb then nb:SetText(text) end
    elseif ChatFrame_OpenChat then
        ns.OpenChat(pre .. text)
    end
end
function Emoji.RestoreChat()
    local lt = Emoji.lastTarget
    if lt then openWith(lt.pre, lt.text or "", lt.ct, lt.who) end
end
------------------------------------------------------------------------
-- Speaker button at the chat input: ONE place for the behavior (Oasis's own button and nesUI's button
-- both call in here). Rule: a sound just goes out - no chat input opens before or after.
-- Only if text was already there does the input come back with that text.
------------------------------------------------------------------------
-- Mouse down: remember target and "was there text already?" BEFORE WoW closes the input on click
function Emoji.SoundButtonDown(btn, eb)
    if not btn then return end
    local cur = eb and eb:IsShown() and ns.safe(eb:GetText()) or ""
    btn.hadText = type(cur) == "string" and cur:gsub("%s", "") ~= ""
    pcall(Emoji.RememberTarget, eb)
end
function Emoji.SoundButtonClick(btn, eb)
    if not (btn and eb and ns.Sound and ns.Sound.OpenPicker) then return end
    local had = btn.hadText
    -- send to wherever was just being typed (whisper -> only that person, group -> only the group)
    local lt = Emoji.lastTarget
    local fresh = lt and lt.eb == eb and lt.t and GetTime() - lt.t < 5
    local ct = (fresh and lt.ct) or (eb:IsShown() and ns.safe(eb:GetAttribute("chatType"))) or (lt and lt.ct) or "GUILD"
    local tgt = (fresh and lt.who) or ns.safe(eb:GetAttribute("tellTarget")) or (lt and lt.who)
    local ok = { GUILD = true, OFFICER = true, PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true, BN_WHISPER = true }
    if not ok[ct] or ((ct == "WHISPER" or ct == "BN_WHISPER") and not tgt) then ct, tgt = "GUILD", nil end
    if ns.Sound.SetSendTarget then ns.Sound.SetSendTarget(ct, tgt) end
    ns.Sound.OpenPicker(btn, nil, function(k)
        ns.Sound.SendInChat(k, ct, (ct == "WHISPER" or ct == "BN_WHISPER") and tgt or nil)
        if had then
            C_Timer.After(0.05, function() pcall(Emoji.RestoreChat) end)
        elseif not ns.inCombat() then
            -- close an empty input if it is (still) open - with every close function this client knows
            local function closeEmpty()
                if ns.inCombat() or not eb:IsShown() then return end
                if (ns.safe(eb:GetText()) or ""):gsub("%s", "") ~= "" then return end
                pcall(eb.SetText, eb, "")
                local U = ChatFrameUtil
                if U and U.DeactivateChat then pcall(U.DeactivateChat, eb)
                elseif ChatEdit_DeactivateChat then pcall(ChatEdit_DeactivateChat, eb)
                elseif eb.Deactivate then pcall(eb.Deactivate, eb) end
                if eb.HasFocus and eb:HasFocus() and eb.ClearFocus then pcall(eb.ClearFocus, eb) end
            end
            for _, d in ipairs({ 0.05, 0.25, 0.6, 1.2 }) do C_Timer.After(d, closeEmpty) end
        end
    end, "send")
    -- don't lose started text: only then does the input reopen
    ns.Sound.restoreChat = had and true or nil
    if had then C_Timer.After(0.05, function() pcall(Emoji.RestoreChat) end) end
end

-- record every time WoW switches the chat header ("Whisper to X", "Party" ...)
if hooksecurefunc and ChatEdit_UpdateHeader then
    hooksecurefunc("ChatEdit_UpdateHeader", function(eb) pcall(Emoji.RememberTarget, eb) end)
end
-- Keep only the target (group, whisper, guild ...), never the text: forget after sending or cancelling
local function forgetText() if Emoji.lastTarget then Emoji.lastTarget.text = "" end end
if hooksecurefunc and ChatEdit_SendText then hooksecurefunc("ChatEdit_SendText", forgetText) end
local forgetHooked = setmetatable({}, { __mode = "k" })
wirers[#wirers + 1] = function()
    for _, n in ipairs(chatFrameNames()) do
        local eb = _G[n .. "EditBox"]
        if eb and not forgetHooked[eb] then
            forgetHooked[eb] = true
            eb:HookScript("OnEnterPressed", forgetText)
            eb:HookScript("OnEscapePressed", forgetText)
        end
    end
end
-- recently used emojis (own tab at the very front)
local RECENT_MAX = 28
local byCode = {}
for _, cat in ipairs(Emoji.CATS) do
    for _, e in ipairs(cat.items) do
        for i = 2, #e do if not byCode[e[i]] then byCode[e[i]] = e end end
    end
end
-- for other windows (sound picker "Emoji dazu"): entry for a code, set image, quick list
function Emoji.Entry(code) return byCode[code] end
function Emoji.SetIcon(texObj, e)
    if not (texObj and e) then return end
    texObj:SetTexCoord(0, 1, 0, 1)
    if e.raid then texObj:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. e[1]:match("%d+"))
    else
        texObj:SetTexture((e.base or PATH) .. e[1])
        if e.n and e.n > 1 then texObj:SetTexCoord(0, 1, 0, 64 / e.h) end
    end
end
-- Favorites, then recent, then frequently used (without raid icons, without duplicates)
function Emoji.QuickCodes(n)
    local st = ns.db and ns.db.settings or {}
    local out, seen = {}, {}
    local function add(c) if #out < n and c and byCode[c] and not byCode[c].raid and not seen[c] then seen[c] = true out[#out + 1] = c end end
    for _, c in ipairs(st.emojiFav or {}) do add(c) end
    for _, c in ipairs(st.emojiRecent or {}) do add(c) end
    local cnt = {}
    for c, k in pairs(st.emojiCount or {}) do cnt[#cnt + 1] = { c, k } end
    table.sort(cnt, function(a, b) return a[2] > b[2] end)
    for _, e in ipairs(cnt) do add(e[1]) end
    return out
end
Emoji.RECENT = { key = "recent", name = "Last seen", items = {} }
function Emoji.RefreshRecent()
    local items = {}
    for _, code in ipairs(ns.db and ns.db.settings.emojiRecent or {}) do
        if byCode[code] then items[#items + 1] = byCode[code] end
    end
    Emoji.RECENT.items = items
end
local function remember(code)
    if not ns.db or not byCode[code] or byCode[code].raid then return end
    local l = ns.db.settings.emojiRecent or {}
    for i = #l, 1, -1 do if l[i] == code then table.remove(l, i) end end
    table.insert(l, 1, code)
    while #l > RECENT_MAX do table.remove(l) end
    ns.db.settings.emojiRecent = l
    -- "Haeufig": how often used by yourself (0.5.592)
    local cnt = ns.db.settings.emojiCount or {}
    cnt[code] = (cnt[code] or 0) + 1
    ns.db.settings.emojiCount = cnt
end
-- "Beliebt in der Gilde": count emoji codes in guild messages (per sender + emoji at most 1x/minute)
ns.On("CHAT_MSG_GUILD", function(msg, sender)
    msg = ns.safe(msg)
    if type(msg) ~= "string" or not msg:find("[:<;xX]") or not (ns.Popular and ns.Popular.Add) then return end
    local n = 0
    for w in msg:gmatch("%S+") do
        local e = byCode[w]
        if e and not e.raid then
            n = n + 1
            if n > 8 then break end
            ns.Popular.Add("emoji", e[2], ns.safe(sender) or "")
        end
    end
end)
Emoji.Remember = remember
-- Insert the code at the remembered cursor position (instead of always at the end); pos = characters before it
local function spliceAt(base, pos, code)
    pos = tonumber(pos)
    if not pos or pos < 0 or pos >= #base then
        return base .. ((base ~= "" and not base:find("%s$")) and " " or "") .. code .. " ", nil
    end
    local a, b = base:sub(1, pos), base:sub(pos + 1)
    local ins = ((a ~= "" and not a:find("%s$")) and " " or "") .. code .. ((b:find("^%s") and "") or " ")
    return a .. ins .. b, #a + #ins
end

function Emoji.Insert(code)
    remember(code)
    if ns.db and ns.db.settings.emojiClose and Emoji.picker then Emoji.picker:Hide() end
    local tgt = Emoji.target
    -- own input fields (e.g. guild chat page): just insert
    if tgt and tgt:IsVisible() and not targetOf(tgt) then
        local t = tgt:GetText() or ""
        tgt:Insert(((t ~= "" and not t:find("%s$")) and " " or "") .. code .. " ")
        tgt:SetFocus()
        return
    end
    -- Chat: WoW closes/clears the input on click into the picker (especially when it is empty).
    -- So don't type into the input, but reopen it with target + finished text (incl. emoji),
    -- and check again shortly after in case WoW closed it afterwards anyway.
    local eb = (tgt and targetOf(tgt) and tgt) or activeEditBox()
    -- Input closed, but the target (guild, group, whisper ...) is still set on it: just reactivate it
    local lt0 = Emoji.lastTarget
    if eb and not eb:IsShown() and ChatEdit_ActivateChat and not ns.inCombat() and targetOf(eb)
        and (not lt0 or targetOf(eb) == lt0.pre) then
        pcall(ChatEdit_ActivateChat, eb)
        if lt0 and (lt0.text or "") ~= "" and (ns.safe(eb:GetText()) or "") == "" then eb:SetText(lt0.text) end
    end
    -- Input is open (again): insert directly, don't reopen anything
    if eb and eb:IsShown() and targetOf(eb) and not ns.inCombat() then
        local cur = ns.safe(eb:GetText()) or ""
        if cur:match("^%s*$") then cur = "" end
        -- WoW reset the input to "Say", but e.g. guild/group/whisper was remembered:
        -- prepend the command so the message still goes there when sent
        local ltp = Emoji.lastTarget and Emoji.lastTarget.pre
        local lt1 = Emoji.lastTarget
        -- Remember the cursor position: only valid while the text is still exactly the remembered one
        local pos = lt1 and lt1.cur and (lt1.text or "") == cur and lt1.cur or nil
        if ltp and targetOf(eb) ~= ltp and not cur:find("^/") then
            cur = ltp .. cur
            if pos then pos = pos + #ltp end
        end
        local text, at = spliceAt(cur, pos, code)
        eb:SetFocus()
        eb:SetText(text)
        eb:SetCursorPosition(at or #text)
        local pre = targetOf(eb)
        Emoji.lastTarget = { pre = pre, text = text, eb = eb, cur = at or #text, ct = ns.safe(eb:GetAttribute("chatType")), who = ns.safe(eb:GetAttribute("tellTarget")) }
        return
    end
    local lt = Emoji.lastTarget
    local pre = (lt and lt.pre) or targetOf(eb) or "/s "
    local base = lt and lt.text or ""
    if eb and eb:IsShown() and targetOf(eb) == pre then base = ns.safe(eb:GetText()) or base end
    local pos0 = lt and lt.cur and (lt.text or "") == base and lt.cur or nil
    if base:match("^%s*$") then base, pos0 = "", nil end   -- Placeholder space from the emoji button
    local text = spliceAt(base, pos0, code)
    local ct = lt and lt.pre == pre and lt.ct or (eb and ns.safe(eb:GetAttribute("chatType")))
    local who = lt and lt.pre == pre and lt.who or (eb and ns.safe(eb:GetAttribute("tellTarget")))
    Emoji.lastTarget = { pre = pre, text = text, eb = eb, ct = ct, who = who }
    openWith(pre, text, ct, who)
    C_Timer.After(0.05, function() pcall(Emoji.RestoreChat) end)
    C_Timer.After(0.3, function() pcall(Emoji.RestoreChat) end)
end

-- Tab "Oasis": all emojis unlocked with the Oasis rank, sorted by rank
Emoji.OASIS = { key = "oasis", name = "Oasis", items = {}, custom = true }
ns.GuildOption({ page = "chat", key = "emLock", default = true,   -- 0.6.417: Standard an label = "Besondere Emojis erst ab Oasis-Rang",
    desc = "Off: all animated guild emojis can be used by everyone right away" })
local function refreshOasisCat()
    local out, seen = {}, {}
    local RW = ns.Rewards
    if not (RW and RW.EmojiLevel) then return end
    for _, cat in ipairs(Emoji.CATS) do
        for _, e in ipairs(cat.items) do
            local need = RW.EmojiLevel(e)
            if need and not seen[e] then seen[e] = true out[#out + 1] = e end
        end
    end
    table.sort(out, function(a, b)
        local x, y = RW.EmojiLevel(a), RW.EmojiLevel(b)
        if x ~= y then return x < y end
        return tostring(a[2]) < tostring(b[2])
    end)
    Emoji.OASIS.items = out
end
-- Favorites (0.5.590): right-click an emoji; own tab at the very front, order = when saved
local FAV_MAX = 60
Emoji.FAV = { key = "fav", name = "Favourites", items = {} }
local function favList() if not ns.db then return {} end ns.db.settings.emojiFav = ns.db.settings.emojiFav or {} return ns.db.settings.emojiFav end
function Emoji.IsFav(code)
    for _, c in ipairs(favList()) do if c == code then return true end end
    return false
end
function Emoji.ToggleFav(code)
    if not code or not byCode[code] then return end
    local l = favList()
    for i = #l, 1, -1 do if l[i] == code then table.remove(l, i) return false end end
    if #l >= FAV_MAX then table.remove(l) end
    table.insert(l, 1, code)
    return true
end
function Emoji.RefreshFav()
    local items = {}
    for _, code in ipairs(favList()) do if byCode[code] then items[#items + 1] = byCode[code] end end
    Emoji.FAV.items = items
end
-- Frequent (own use), Popular (guild chat), Combos (several emojis in one click) - 0.5.592
Emoji.OFTEN = { key = "often", name = "Frequent", items = {} }
Emoji.POPULAR = { key = "popular", name = "Popular", items = {} }
Emoji.COMBOS = { key = "combos", name = "Combos", items = {} }
local COMBO_MAX, COMBO_LEN = 24, 8
local function comboList() if not ns.db then return {} end ns.db.settings.emojiCombos = ns.db.settings.emojiCombos or {} return ns.db.settings.emojiCombos end
function Emoji.AddCombo(codes)
    if type(codes) ~= "table" or #codes < 2 then return false end
    local s = table.concat(codes, " ")
    local l = comboList()
    for i = #l, 1, -1 do if l[i] == s then table.remove(l, i) end end
    table.insert(l, 1, s)
    while #l > COMBO_MAX do table.remove(l) end
    return true
end
function Emoji.RemoveCombo(idx) table.remove(comboList(), idx) end
function Emoji.RefreshExtra()
    local st = ns.db and ns.db.settings or {}
    local cnt, out = {}, {}
    for c, n in pairs(st.emojiCount or {}) do if byCode[c] and not byCode[c].raid then cnt[#cnt + 1] = { c, n } end end
    table.sort(cnt, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    for i = 1, math.min(RECENT_MAX, #cnt) do out[i] = byCode[cnt[i][1]] end
    Emoji.OFTEN.items = out
    local pop = {}
    for _, e in ipairs((ns.Popular and ns.Popular.Top) and ns.Popular.Top("emoji", RECENT_MAX) or {}) do
        if byCode[e[1]] then pop[#pop + 1] = byCode[e[1]] end
    end
    Emoji.POPULAR.items = pop
    local combos = {}
    for i, str in ipairs(comboList()) do
        local codes = {}
        for c in str:gmatch("%S+") do if byCode[c] then codes[#codes + 1] = c end end
        if #codes > 0 then
            -- Stand-in: looks like the first emoji but carries all codes
            combos[#combos + 1] = setmetatable({ combo = codes, comboIdx = i }, { __index = byCode[codes[1]] })
        end
    end
    Emoji.COMBOS.items = combos
end
local function pickerCats()
    Emoji.RefreshRecent()
    Emoji.RefreshFav()
    Emoji.RefreshExtra()
    refreshOasisCat()
    -- 0.5.960: the group "Meine" (favorites, recent, frequent, popular) no longer exists in the picker
    local list = {}
    -- 0.5.667: tabs "Standard" and "Kombos" removed, Oasis emojis are with the stickers
    -- 0.5.668: no separate Oasis tab anymore - the rank emojis are in their tabs anyway (Anime, Pepe ...)
    -- 0.5.956: standard emojis are back (sub-tab "Standard" under stickers) - without the guild module there was no picker at all
    for _, c in ipairs(Emoji.CATS) do list[#list + 1] = c end
    return list
end
local function buildPicker()
    local f = CreateFrame("Frame", "OasisEmojiPicker", UIParent)
    Emoji.picker = f
    local COLS = 14
    local S = (ns.db and tonumber(ns.db.settings.emojiPickSize)) or 38
    pickerCats()   -- Fill Oasis/favorites tabs before the cell count is fixed
    local maxN = math.max(RECENT_MAX, FAV_MAX)
    for _, c in ipairs(Emoji.CATS) do maxN = math.max(maxN, #c.items) end
    if Emoji.OASIS and Emoji.OASIS.items then maxN = math.max(maxN, #Emoji.OASIS.items) end
    local rows = math.ceil(maxN / COLS)
    local GRID_TOP = -62
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        -- convert to UIParent so the position is correct on the next open
        local l, t = self:GetLeft(), self:GetTop()
        if l and t and ns.db then ns.db.settings.emojiPos = { "TOPLEFT", l, t } end
    end)
    -- 0.5.590: glass card (rounded corners), opacity from the settings; header with slight accent gradient
    local GL = ns.Insta and ns.Insta.Glass
    f.glass = GL and pcall(GL, f, { 0.035, 0.035, 0.045, 0.8 }, { 1, 1, 1, 0.1 }, 14) or false
    if not f.glass then
        f.bgTex = K.Fill(f, C.bg)
        K.Border(f, C.line)
    end
    f.headGrad = f:CreateTexture(nil, "BACKGROUND", nil, 3)
    f.headGrad:SetPoint("TOPLEFT", 3, -3) f.headGrad:SetPoint("TOPRIGHT", -3, -3) f.headGrad:SetHeight(64)
    if not K.Gradient(f.headGrad, "VERTICAL", { C.accent[1], C.accent[2], C.accent[3], 0 }, { C.accent[1], C.accent[2], C.accent[3], 0.10 }) then f.headGrad:Hide() end
    function f:ApplyAlpha()
        local a = (ns.db and tonumber(ns.db.settings.emojiAlpha)) or 0.8
        if self.glass then pcall(GL, self, { 0.035, 0.035, 0.045, a }, { 1, 1, 1, 0.1 }, 14)
        else self.bgTex:SetAlpha(a) end
    end
    f:ApplyAlpha()
    ns.EscClose("OasisEmojiPicker")
    -- Header as on the Oasis pages: accent stripe + upper case
    local title = K.GameHead(f, L["Emojis"], C.accent)
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetWidth(160)
    -- 0.6.413: header like the soundboard: icon + "OASIS EMOJIS"
    title:Hide()
    f.logo = K.Glyph(f, 20, ns.MEDIA .. "icons\\smile", C.accent)
    f.logo:SetPoint("TOPLEFT", 16, -15)
    f.title = K.Title(f, 17, C.text)
    f.title:SetPoint("LEFT", f.logo, "RIGHT", 10, 0)
    f.title:SetText("OASIS  |cffb8b8bc" .. K.Upper(L["Emojis"]) .. "|r")
    local close = K.CloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -4, -4)
    -- Picker settings (gear next to the X)
    local gear = CreateFrame("Button", nil, f)
    gear:SetSize(20, 20)
    gear:SetPoint("RIGHT", close, "LEFT", -6, 0)
    gear.icon = K.Glyph(gear, 14, ns.MEDIA .. "icons\\settings", C.muted)
    gear.icon:SetPoint("CENTER")
    gear:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3])
        K.ShowTip(self, { L["Appearance"], L["Size, transparency, behaviour"] })
    end)
    gear:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
    gear:SetScript("OnClick", function() Emoji.ShowPickerOptions() end)
    -- Search across all tabs (short code), Enter = insert first emoji
    f.search = K.Input(f, 150, L["Search ..."], function(t)
        f.q = (t or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        f:ShowCat(f.cat or "std", true)
    end)
    f.search:SetHeight(24)
    f.search:SetPoint("TOPLEFT", 12, -34)
    f.search:SetPoint("TOPRIGHT", -12, -34)
    f.search:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        local sel = f.kbIdx and f.cells[f.kbIdx]
        if sel and sel.has and sel.code then Emoji.Insert(sel.code) return end
        for _, b in ipairs(f.cells) do if b.has and b.code then Emoji.Insert(b.code) break end end
    end)
    -- Arrow keys in the search field: selection moves through the grid, Enter inserts
    if f.search.SetAltArrowKeyMode then pcall(f.search.SetAltArrowKeyMode, f.search, false) end
    f.search:SetScript("OnArrowPressed", function(_, key)
        local n = 0
        for i, b in ipairs(f.cells) do if b.has then n = i end end
        if n == 0 then return end
        local cols = f.cols or 10
        local i = f.kbIdx or 0
        if key == "LEFT" then i = i - 1 elseif key == "RIGHT" then i = i + 1
        elseif key == "UP" then i = i - cols elseif key == "DOWN" then i = (i == 0) and 1 or (i + cols) end
        if i < 1 then i = 1 elseif i > n then i = n end
        f.kbIdx = i
        -- scroll into the visible area
        local row = math.floor((i - 1) / cols)
        local vis = f.visRows or 4
        if row < (f.scroll or 0) then f.scroll = row elseif row >= (f.scroll or 0) + vis then f.scroll = row - vis + 1 end
        for j, b in ipairs(f.cells) do b.kb:SetShown(j == i) end
        f:Layout()
        f:Preview(f.cells[i])
    end)
    f.search:HookScript("OnTabPressed", function()
        -- Tab: next tab
        local cats = pickerCats()
        for i, c in ipairs(cats) do
            if c.key == f.cat then f:ShowCat(cats[i % #cats + 1].key) break end
        end
    end)
    f.search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)

    -- 0.5.659: tabs in 4 groups (Mine / Emojis / Stickers / WoW), below them the group's sub-tabs
    -- 0.5.957: standard emojis are the first sub-tab under stickers (no group of their own)
    local GROUP_OF = { fav = "mine", recent = "mine", often = "mine", popular = "mine" }
    local GROUPS = { { key = "sticker", text = L["Emojis"] } }   -- WoW/Raid are under stickers
    local function groupOf(c)
        if GROUP_OF[c.key] then return GROUP_OF[c.key] end
        return "sticker"
    end
    f.groupOf = {}
    local subItems = {}
    for _, c in ipairs(pickerCats()) do
        local g = groupOf(c)
        f.groupOf[c.key] = g
        subItems[g] = subItems[g] or {}
        table.insert(subItems[g], { key = c.key, text = L[c.name] })
    end
    local gItems = {}
    for _, g in ipairs(GROUPS) do if subItems[g.key] then gItems[#gItems + 1] = g end end
    f.lastOfGroup = {}
    f.tabs = K.Segments(f, gItems, function(g)
        f:ShowCat(f.lastOfGroup[g] or (subItems[g] and subItems[g][1].key))
    end)
    f.tabs:SetPoint("TOPLEFT", 8, -64)
    f.subTabs = {}
    for g, list in pairs(subItems) do
        if #list > 1 then
            local sg = K.Segments(f, list, function(k) f:ShowCat(k) end, nil, { size = 11, pad = 16 })
            sg:SetPoint("TOPLEFT", 6, -56)
            sg:Hide()
            f.subTabs[g] = sg
        end
    end
    local line = K.Divider(f)
    f.tabLine = line
    -- Group tabs at the top, sub-tabs (if the group has several) below - wrap when narrow
    local function wrap(seg, avail, y0)
        local x, row = 0, 0
        for _, b in ipairs(seg.buttons) do
            local bw = b:GetWidth()
            if x > 0 and x + bw > avail then x, row = 0, row + 1 end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", seg, "TOPLEFT", x, -row * 24)
            x = x + bw + 2
        end
        seg:ClearAllPoints()
        seg:SetPoint("TOPLEFT", 8, y0)
        seg:SetSize(avail, (row + 1) * 24)
        return row + 1
    end
    function f:LayoutTabs(W)
        local avail = math.max(100, W - 16)
        -- Wide windows like sounds; narrow windows wrap the targets below the title.
        local searchY = -52   -- 0.6.413: more room below the header
        local cols = math.max(1, math.min(4, math.floor((W - 20) / 78)))
        for i, b in ipairs(self.chans or {}) do
            b:ClearAllPoints()
            if W >= 620 then
                b:SetSize(86, 26)
                b:SetPoint("TOPRIGHT", -62 - (4 - i) * 92, -12)
            else
                b:SetSize(74, 20)
                b:SetPoint("TOPLEFT", 12 + ((i - 1) % cols) * 78, -44 - math.floor((i - 1) / cols) * 24)
            end
        end
        if W < 620 then searchY = -44 - math.ceil(4 / cols) * 24 end
        self.search:ClearAllPoints()
        self.search:SetPoint("TOPLEFT", 12, searchY)
        self.search:SetPoint("TOPRIGHT", -12, searchY)
        local tabsY = searchY - 34
        local y
        if #self.tabs.buttons <= 1 then if self.tabs.Hide then self.tabs:Hide() end y = tabsY   -- 0.6.413: only one group -> no extra tab
        else if self.tabs.Show then self.tabs:Show() end y = tabsY - wrap(self.tabs, avail, tabsY) * 24 - 2 end
        local g = self.groupOf[self.cat or ""]
        for k, sg in pairs(self.subTabs) do sg:SetShown(k == g) end
        local sg = g and self.subTabs[g]
        if sg then y = y - wrap(sg, avail, y) * 24 end
        local lineY = y - 4
        self.tabLine:ClearAllPoints()
        self.tabLine:SetPoint("TOPLEFT", 10, lineY)
        self.tabLine:SetPoint("TOPRIGHT", -10, lineY)
        GRID_TOP = lineY - 6
    end

    -- Cells (reassigned per category)
    f.cells = {}
    for i = 1, maxN do
        local b = CreateFrame("Button", nil, f)
        -- Tile: subtle background, accent glow on hover
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetPoint("TOPLEFT", 1, -1)
        b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
        b.bg:SetColorTexture(1, 1, 1, 0.035)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetPoint("TOPLEFT", 1, -1)
        b.hl:SetPoint("BOTTOMRIGHT", -1, 1)
        b.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.22)
        -- 0.6.413: round tiles like in the soundboard
        if K.RoundMask then pcall(K.RoundMask, b.bg, b, 6) pcall(K.RoundMask, b.hl, b, 6) end
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        -- locked: small padlock badge with the required Oasis rank
        -- locked: dark band at the bottom with padlock + rank
        b.lockBg = b:CreateTexture(nil, "OVERLAY", nil, 1)
        b.lockBg:SetColorTexture(0, 0, 0, 0.78)
        b.lockBg:SetPoint("BOTTOMLEFT", 1, 1)
        b.lockBg:SetPoint("BOTTOMRIGHT", -1, 1)
        b.lockBg:SetHeight(12)
        b.lockIcon = b:CreateTexture(nil, "OVERLAY", nil, 2)
        b.lockIcon:SetTexture(ns.MEDIA .. "diamond")
        b.lockIcon:SetSize(9, 9)
        b.lockIcon:SetPoint("BOTTOMLEFT", 3, 2)
        b.lockTxt = b:CreateFontString(nil, "OVERLAY", nil, 2)
        K.SetFontSafe(b.lockTxt, K.FONT_HEAD, 9, "OUTLINE", K.FONT)
        b.lockTxt:SetPoint("BOTTOMRIGHT", -3, 2)
        b.lockTxt:SetTextColor(1, 0.82, 0.3)
        -- Favorite: small golden star at the top right
        b.star = b:CreateTexture(nil, "OVERLAY", nil, 3)
        b.star:SetTexture(ns.MEDIA .. "icons\\star_on")
        b.star:SetVertexColor(1, 0.82, 0.3)
        b.star:SetSize(10, 10)
        b.star:SetPoint("TOPRIGHT", -1, -1)
        b.star:Hide()
        -- Combo: count at the bottom right (x3)
        b.comboTxt = b:CreateFontString(nil, "OVERLAY", nil, 4)
        K.SetFontSafe(b.comboTxt, K.FONT_HEAD, 10, "OUTLINE", K.FONT)
        b.comboTxt:SetPoint("BOTTOMRIGHT", -2, 2)
        b.comboTxt:SetTextColor(1, 0.85, 0.45)
        -- Keyboard selection (arrow keys in the search field)
        b.kb = b:CreateTexture(nil, "BACKGROUND", nil, 2)
        b.kb:SetPoint("TOPLEFT", 1, -1) b.kb:SetPoint("BOTTOMRIGHT", -1, 1)
        b.kb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
        b.kb:Hide()
        -- Reorder favorites: drag in the favorites tab and drop on another emoji
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self) f:StartDrag(self) end)
        b:SetScript("OnDragStop", function() f:EndDrag() end)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, btn)
            local e = self.entry
            -- Combo: right-click deletes it
            if btn == "RightButton" and e and e.combo then
                Emoji.RemoveCombo(e.comboIdx)
                K.Toast(L["Emojis"], L["Combo deleted."], C.dim)
                f:ShowCat("combos", true)
                return
            end
            -- Shift+click: put the emoji into the combo builder (instead of inserting)
            if btn ~= "RightButton" and IsShiftKeyDown() and e and not e.combo and not e.raid and self.code then
                f:ComboAdd(self.code, self)
                return
            end
            if btn == "RightButton" then
                if not self.favCode then return end
                local on = Emoji.ToggleFav(self.favCode)
                self.star:SetShown(on and true or false)
                -- Star pops up
                if on and not (ns.db and ns.db.settings.noAnim) then
                    local st = self.star
                    K.Tween(st, 0.35, function(p) local k = 1 + 0.8 * math.sin(p * math.pi) st:SetSize(10 * k, 10 * k) end, function() st:SetSize(10, 10) end)
                end
                if f.cat == "fav" then f:ShowCat("fav", true) end
                return
            end
            if not self.code then return end
            -- small press effect on the image
            if not (ns.db and ns.db.settings.noAnim) then
                local ic = self.icon
                K.Tween(ic, 0.22, function(p)
                    local d = 2 + 4 * math.sin(p * math.pi)
                    ic:ClearAllPoints() ic:SetPoint("TOPLEFT", d, -d) ic:SetPoint("BOTTOMRIGHT", -d, d)
                end, function() ic:ClearAllPoints() ic:SetPoint("TOPLEFT", 2, -2) ic:SetPoint("BOTTOMRIGHT", -2, 2) end)
            end
            Emoji.Insert(self.code)
        end)
        b:SetScript("OnEnter", function(self)
            if self.tip then K.ShowTip(self, self.tip) end
            -- slightly enlarge on hover + show large in the preview at the bottom
            if not (ns.db and ns.db.settings.noAnim) then
                local ic = self.icon
                K.Tween(ic, 0.14, function(p)
                    local d = 2 - 4 * p
                    ic:ClearAllPoints() ic:SetPoint("TOPLEFT", d, -d) ic:SetPoint("BOTTOMRIGHT", -d, d)
                end)
            end
            self:SetFrameLevel(f:GetFrameLevel() + 6)
            f:Preview(self)
        end)
        b:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
            local ic = self.icon
            K.Tween(ic, 0.12, function(p)
                local d = -2 + 4 * p
                ic:ClearAllPoints() ic:SetPoint("TOPLEFT", d, -d) ic:SetPoint("BOTTOMRIGHT", -d, d)
            end, function() ic:ClearAllPoints() ic:SetPoint("TOPLEFT", 2, -2) ic:SetPoint("BOTTOMRIGHT", -2, 2) end)
            self:SetFrameLevel(f:GetFrameLevel() + 2)
            f:Preview(nil)
        end)
        f.cells[i] = b
    end
    f.foot = K.Text(f, 10, C.dim)
    f.foot:SetPoint("BOTTOMLEFT", 10, 10)
    f.foot:SetPoint("RIGHT", f, "RIGHT", -20, 0)
    f.foot:SetWordWrap(false)
    -- Preview on hover: emoji large at the bottom left + its codes in the footer
    f.prev = f:CreateTexture(nil, "OVERLAY")
    f.prev:SetSize(26, 26)
    f.prev:SetPoint("BOTTOMLEFT", 8, 4)
    f.prev:Hide()
    function f:Preview(cell)
        local e = cell and cell.entry
        self.prevAnim = nil
        self.foot:ClearAllPoints()
        self.foot:SetPoint("RIGHT", self, "RIGHT", -20, 0)
        if not e then
            self.prev:Hide()
            self.foot:SetPoint("BOTTOMLEFT", 10, 10)
            self.foot:SetText(self.footDefault or "")
            return
        end
        self.prev:SetTexCoord(0, 1, 0, 1)
        if e.raid then self.prev:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. e[1]:match("%d+"))
        else
            self.prev:SetTexture((e.base or PATH) .. e[1])
            if e.n and e.n > 1 then self.prevAnim = e self.prev:SetTexCoord(0, 1, 0, 64 / e.h) end
        end
        self.prev:Show()
        self.foot:SetPoint("BOTTOMLEFT", 40, 11)
        local codes = {}
        for j = 2, #e do codes[#codes + 1] = e[j] end
        self.foot:SetText("|cffffffff" .. table.concat(codes, "   ") .. "|r   |cff666666" .. L["Right-click: favourite  ·  Shift-click: combo"] .. "|r")
    end

    -- Combo builder: Shift+click collects emojis, then insert or save as combo
    f.combo = {}
    f.cb = CreateFrame("Frame", nil, f)
    f.cb:SetPoint("BOTTOMLEFT", 8, 30)
    f.cb:SetPoint("BOTTOMRIGHT", -8, 30)
    f.cb:SetHeight(28)
    f.cb.bg = f.cb:CreateTexture(nil, "BACKGROUND")
    f.cb.bg:SetAllPoints()
    f.cb.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.10)
    if K.RoundMask then K.RoundMask(f.cb.bg, f.cb.bg, 8) end
    f.cb.lbl = K.Text(f.cb, 11, C.muted)
    f.cb.lbl:SetPoint("LEFT", 8, 0)
    f.cb.lbl:SetText(L["Combo:"])
    f.cb.icons = {}
    for i = 1, COMBO_LEN do
        local t = f.cb:CreateTexture(nil, "ARTWORK")
        t:SetSize(22, 22)
        t:SetPoint("LEFT", f.cb.lbl, "RIGHT", 6 + (i - 1) * 24, 0)
        f.cb.icons[i] = t
    end
    f.cb.clear = K.Button(f.cb, "x", 24, 20, "ghost", function() f.combo = {} f:PaintCombo() end)
    f.cb.clear:SetPoint("RIGHT", -4, 0)
    f.cb.save = K.Button(f.cb, L["Save"], 70, 20, "ghost", function()
        if Emoji.AddCombo(f.combo) then
            K.Toast(L["Emojis"], L["Combo saved - see the Combos tab."], C.mint)
            f.combo = {}
            f.needTabs = true
            f:PaintCombo()
            if f.cat == "combos" then f:ShowCat("combos", true) end
        else
            K.Toast(L["Emojis"], L["A combo needs at least 2 emojis."], C.dim)
        end
    end)
    f.cb.save:SetPoint("RIGHT", f.cb.clear, "LEFT", -4, 0)
    f.cb.ins = K.Button(f.cb, L["Insert"], 80, 20, "primary", function()
        if #f.combo == 0 then return end
        local codes = f.combo
        f.combo = {}
        f:PaintCombo()
        for _, c in ipairs(codes) do remember(c) end
        Emoji.Insert(table.concat(codes, " "))
    end)
    f.cb.ins:SetPoint("RIGHT", f.cb.save, "LEFT", -4, 0)
    f.cb:Hide()
    function f:PaintCombo()
        local n = #self.combo
        for i, t in ipairs(self.cb.icons) do
            local c = self.combo[i]
            if c and byCode[c] then Emoji.SetIcon(t, byCode[c]) t:Show() else t:Hide() end
        end
        local was = self.cb:IsShown()
        self.cb:SetShown(n > 0)
        self.bottomPad = n > 0 and 62 or 30
        if was ~= (n > 0) then self:Layout() end
    end
    function f:ComboAdd(code, cell)
        if #self.combo >= COMBO_LEN then K.Toast(L["Emojis"], (L["At most %d emojis per combo."]):format(COMBO_LEN), C.dim) return end
        self.combo[#self.combo + 1] = code
        self:PaintCombo()
        -- small hop of the new image in the bar
        local t = self.cb.icons[#self.combo]
        if t and not (ns.db and ns.db.settings.noAnim) then
            K.Tween(t, 0.25, function(p) local k = 1 + 0.4 * math.sin(p * math.pi) t:SetSize(22 * k, 22 * k) end, function() t:SetSize(22, 22) end)
        end
    end

    -- Drag favorites: image follows the mouse, dropping on another favorite = move there
    f.ghost = CreateFrame("Frame", nil, UIParent)
    f.ghost:SetSize(32, 32)
    f.ghost:SetFrameStrata("TOOLTIP")
    f.ghost.t = f.ghost:CreateTexture(nil, "ARTWORK")
    f.ghost.t:SetAllPoints()
    f.ghost:Hide()
    f.ghost:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / sc + 10, y / sc - 10)
    end)
    function f:StartDrag(cell)
        if self.cat ~= "fav" or (self.q or "") ~= "" or not cell.favCode then return end
        self.dragCode = cell.favCode
        Emoji.SetIcon(self.ghost.t, cell.entry)
        self.ghost:Show()
        cell:SetAlpha(0.3)
    end
    function f:EndDrag()
        local code = self.dragCode
        self.dragCode = nil
        self.ghost:Hide()
        if not code then return end
        local target
        for _, b in ipairs(self.cells) do if b:IsShown() and b.favCode and b:IsMouseOver() then target = b.favCode end end
        local l = favList()
        if target and target ~= code then
            local from, to
            for i, c in ipairs(l) do if c == code then from = i end if c == target then to = i end end
            if from and to then table.remove(l, from) table.insert(l, to, code) end
        end
        self:ShowCat("fav", true)
    end
    -- Choose target as in the sound window: guild / group / raid / last whisper partner (in chat colors)
    local CHS = { { "GUILD", "Guild", "/g ", { 0.25, 1, 0.25 } }, { "PARTY", "Group", "/p ", { 0.67, 0.67, 1 } },
        { "RAID", "Raid", "/ra ", { 1, 0.5, 0 } }, { "WHISPER", "Whisper", nil, { 1, 0.5, 1 } } }
    f.chans = {}
    for i, d in ipairs(CHS) do
        local b = K.Button(f, L[d[2]], 74, 20, "ghost", function()
            local lt = Emoji.lastTarget or {}
            local pre = d[3]
            if d[1] == "WHISPER" then
                local who = (lt.pre and lt.pre:match("^/w (.-) $")) or (ChatEdit_GetLastTellTarget and ns.safe(ChatEdit_GetLastTellTarget()))
                if not who or who == "" then ns.print(L["You have not whispered anyone yet."]) return end
                pre = "/w " .. who .. " "
            end
            Emoji.lastTarget = { pre = pre, text = lt.text or "", eb = lt.eb, t = GetTime(), ct = d[1] }
            f:MarkChan()
            pcall(Emoji.RestoreChat)
        end)
        b.ch, b.col = d[1], d[4]
        b.tint = b:CreateTexture(nil, "BACKGROUND", nil, 2)
        b.tint:SetAllPoints()
        b:SetPoint("TOPRIGHT", -62 - (#CHS - i) * 78, -8)
        f.chans[i] = b
    end
    function f:MarkChan()
        local lt = Emoji.lastTarget
        local pre = lt and lt.pre or "/g "
        local cur = pre == "/p " and "PARTY" or pre == "/i " and "PARTY" or pre == "/ra " and "RAID" or pre:match("^/w ") and "WHISPER" or (pre == "/g " and "GUILD") or nil
        for _, b in ipairs(self.chans) do
            local on = b.ch == cur
            K.SetBorderColor(b, on and b.col or { b.col[1] * 0.45, b.col[2] * 0.45, b.col[3] * 0.45 })
            b.tint:SetColorTexture(b.col[1], b.col[2], b.col[3], on and 0.28 or 0.06)
            b.label:SetTextColor(b.col[1], b.col[2], b.col[3], on and 1 or 0.7)
        end
    end
    f:HookScript("OnShow", function(self) self:MarkChan() end)
    -- Apply cell size (setting "Groesse in der Auswahl")
    -- Size: width/height from the settings (slider or dragging the bottom right corner).
    -- Column count follows from the width; whatever doesn't fit the height scrolls with the mouse wheel.
    function f:Layout()
        local st = ns.db and ns.db.settings or {}
        S = tonumber(st.emojiPickSize) or 38
        -- Tabs wrap when needed -> can be made narrow
        local minW = 220
        self.minW = minW
        if self.SetResizeBounds then self:SetResizeBounds(minW, 170, 1200, 900) end
        local W = math.max(minW, math.min(1200, tonumber(st.emojiW) or (14 * S + 20)))
        local H = math.max(170, math.min(900, tonumber(st.emojiH) or 330))
        if self.resizing then
            W, H = math.max(minW, self:GetWidth()), math.max(170, self:GetHeight())
        else
            self:SetSize(W, H)
        end
        self:LayoutTabs(W)
        -- At least one grid row stays visible even below wrapped tabs.
        local minH = math.max(170, -GRID_TOP + S + (self.bottomPad or 30))
        if self.SetResizeBounds then self:SetResizeBounds(minW, minH, 1200, 900) end
        if H < minH then
            H = minH
            self:SetHeight(H)
        end
        COLS = math.max(4, math.floor((W - 20) / S))
        local visRows = math.max(1, math.floor((H + GRID_TOP - (self.bottomPad or 30)) / S))
        self.visRows, self.cols = visRows, COLS
        local used = 0
        for i, b in ipairs(self.cells) do if b.has then used = i end end
        local totalRows = math.ceil(used / COLS)
        self.maxScroll = math.max(0, totalRows - visRows)
        self.scroll = math.max(0, math.min(self.scroll or 0, self.maxScroll))
        for i, b in ipairs(self.cells) do
            local row = math.floor((i - 1) / COLS) - self.scroll
            b:SetSize(S - 2, S - 2)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", 10 + ((i - 1) % COLS) * S, GRID_TOP - row * S)
            b:SetShown(b.has and row >= 0 and row < visRows or false)
        end
        -- Scroll hint on the right
        if self.scrollBar then
            self.scrollBar:SetShown(self.maxScroll > 0)
            if self.maxScroll > 0 then
                local trackH = visRows * S
                local h = math.max(16, trackH * visRows / math.max(1, totalRows))
                self.scrollBar:SetHeight(h)
                self.scrollBar:ClearAllPoints()
                self.scrollBar:SetPoint("TOPRIGHT", self, "TOPRIGHT", -3, GRID_TOP - (trackH - h) * self.scroll / self.maxScroll)
            end
        end
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, d)
        self.scroll = math.max(0, math.min(self.maxScroll or 0, (self.scroll or 0) - d))
        self:Layout()
    end)
    f.scrollBar = f:CreateTexture(nil, "OVERLAY")
    f.scrollBar:SetWidth(3)
    f.scrollBar:SetColorTexture(1, 1, 1, 0.25)
    -- Bottom right corner: drag = resize (gets saved)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(220, 170, 1200, 900) end
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(f:GetFrameLevel() + 30)
    grip.t = grip:CreateTexture(nil, "OVERLAY")
    grip.t:SetAllPoints()
    grip.t:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function()
        local l, t = f:GetLeft(), f:GetTop()
        if l and t then
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
        end
        f.resizing = true
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        f.resizing = nil
        if ns.db then
            ns.db.settings.emojiW = math.floor(f:GetWidth() + 0.5)
            ns.db.settings.emojiH = math.floor(f:GetHeight() + 0.5)
            local l, t = f:GetLeft(), f:GetTop()
            if l and t then ns.db.settings.emojiPos = { "TOPLEFT", l, t } end
        end
        f:Layout()
        if f.opts and f.opts:IsShown() then f.opts:Refresh() end
    end)
    f:SetScript("OnSizeChanged", function(self)
        if self.resizing and ns.db then
            ns.db.settings.emojiW = math.floor(self:GetWidth() + 0.5)
            ns.db.settings.emojiH = math.floor(self:GetHeight() + 0.5)
            self:Layout()
        end
    end)

    function f:ShowCat(key, quiet)
        local cat
        for _, c in ipairs(pickerCats()) do if c.key == key then cat = c end end
        cat = cat or pickerCats()[1] or Emoji.CATS[1]
        if ns.db then ns.db.settings.emojiCat = cat.key end
        self.cat = cat.key
        local g = self.groupOf and self.groupOf[cat.key]
        if g then
            self.lastOfGroup[g] = cat.key
            self.tabs:Select(g)
            if self.subTabs[g] then self.subTabs[g]:Select(cat.key) end
            -- Group changed: show/hide the sub-tab row, grid adapts
            if self.shownGroup ~= g then self.shownGroup = g if self.Layout then self:Layout() end end
        end
        -- Search: matches from all tabs (without duplicates)
        local items = cat.items
        local q = self.q or ""
        if q ~= "" then
            items = {}
            local seen = {}
            for _, c in ipairs(Emoji.CATS) do
                for _, e in ipairs(c.items) do
                    if not seen[e] then
                        for j = 2, #e do
                            if tostring(e[j]):lower():find(q, 1, true) then seen[e] = true items[#items + 1] = e break end
                        end
                    end
                end
            end
        end
        local favSet = {}
        for _, c in ipairs(favList()) do favSet[c] = true end
        if not quiet or q ~= (self.lastQ or "") then self.kbIdx = nil end
        self.lastQ = q
        local animate = not quiet and self.lastCat ~= cat.key and not (ns.db and ns.db.settings.noAnim)
        self.lastCat = cat.key
        for i, b in ipairs(self.cells) do
            local e = items[i]
            b.entry = e
            b.favCode = e and not e.raid and e[2] or nil
            b.star:SetShown(e and favSet[e[2]] and true or false)
            if e and animate then
                -- Tab switch: fade in tiles one after another from top left to bottom right
                b:SetAlpha(0)
                local d = math.min(0.3, (i - 1) * 0.006)
                K.Tween(b, 0.2, function(p) b:SetAlpha(p) end, function() b:SetAlpha(1) end, d)
            elseif e then
                b:SetAlpha(1)
            end
            if e then
                b.anim = nil
                b.icon:SetTexCoord(0, 1, 0, 1)
                if e.raid then
                    b.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. e[1]:match("%d+"))
                else
                    b.icon:SetTexture((e.base or PATH) .. e[1])
                    -- animated: strip with frames, the section is advanced in OnUpdate
                    if e.n and e.n > 1 then
                        b.anim = e
                        b.icon:SetTexCoord(0, 1, 0, 64 / e.h)
                    end
                end
                b.code = e[2]
                local codes = {}
                for j = 2, #e do codes[#codes + 1] = e[j] end
                b.tip = { e[2], (#codes > 1 and (table.concat(codes, "   ") .. "\n") or "") .. L["Click: insert"] }
                -- special emojis: only from a certain Oasis rank
                local need = ns.Rewards and ns.Rewards.EmojiLevel(e)
                local locked = need and ns.Rank and ns.Rank.Mine().level < need and not (ns.UnlockAll and ns.UnlockAll())
                -- 0.6.534: leadership's setting for own guild emojis (off / leadership only / rank)
                local ownCode = type(e[1]) == "string" and e[1]:match("^x\\(.+)$")
                local mayOwn = ownCode and ns.MediaPack and ns.MediaPack.MayUse("emoji", ownCode, nil)
                if mayOwn ~= nil then
                    locked = not mayOwn
                    if need == ns.MediaPack.LEAD then need = L["Leaders"] elseif need == ns.MediaPack.OFF then need = L["off"] end
                end
                b.icon:SetDesaturated(locked and true or false)
                b.icon:SetAlpha(locked and 0.35 or 1)
                b.lockBg:SetShown(locked and true or false)
                b.lockTxt:SetShown(locked and true or false)
                b.lockIcon:SetShown(locked and true or false)
                b.lockTxt:SetText(need or "")
                if locked then
                    b.code = nil
                    b.tip = { e[2], "|cffffd24a" .. (L["From Oasis rank %d"]):format(need) .. "|r" }
                end
                -- Combo: all codes in one click
                if e.combo then
                    b.code = table.concat(e.combo, " ")
                    b.favCode = nil
                    b.star:Hide()
                    b.tip = { L["Combo"], table.concat(e.combo, "  "), "|cff888888" .. L["Click: insert all  ·  Right-click: delete"] .. "|r" }
                    b.icon:SetDesaturated(false) b.icon:SetAlpha(1)
                    b.lockBg:Hide() b.lockTxt:Hide() b.lockIcon:Hide()
                end
                b.comboTxt:SetText(e.combo and ("x" .. #e.combo) or "")
                b.kb:SetShown(self.kbIdx == i)
                b.has = true
                b:Show()
            else
                b.has = nil
                b.code, b.tip = nil, nil
                b:Hide()
            end
        end
        if q ~= "" then
            self.footDefault = (#items > 0) and (L["%d matches"]):format(#items) .. "  ·  " .. L["Enter: insert first"] or L["Nothing found."]
        elseif cat.key == "fav" and #items == 0 then
            self.footDefault = L["Right-click an emoji = favourite"]
        elseif cat.key == "fav" then
            self.footDefault = L["Drag to reorder favourites  ·  Arrow keys + Enter in the search field"]
        elseif cat.key == "combos" then
            self.footDefault = L["Shift-click emojis to put them into the combo builder"]
        elseif cat.key == "popular" then
            self.footDefault = L["What was used most in guild chat over the last days"]
        else
            self.footDefault = cat.raid and L["Raid markers – everyone sees them, even without Oasis"] or L["everyone with Oasis sees them – without Oasis the code is shown"]
        end
        self:Preview(nil)
        -- empty favorites: hint in the middle of the grid
        if not self.emptyTxt then
            self.emptyTxt = K.Text(self, 12, C.dim, "CENTER")
            self.emptyTxt:SetPoint("CENTER", 0, -10)
            self.emptyTxt:SetWidth(260)
            self.emptyTxt:SetWordWrap(true)
        end
        local none = #items == 0
        self.emptyTxt:SetShown(none)
        if none then
            self.emptyTxt:SetText(q ~= "" and L["Nothing found."] or (cat.key == "fav" and L["No favourites yet.\nRight-click an emoji to keep it here."])
                or (cat.key == "combos" and L["No combos yet.\nShift-click several emojis, then Save."]) or "")
        end
        self:Layout()
    end
    f:ShowCat(ns.db and ns.db.settings.emojiCat or "std")
    f:SetScript("OnUpdate", function(self)
        local pe = self.prevAnim
        if pe then
            local k = frameOf(pe)
            self.prev:SetTexCoord(0, 1, k * 64 / pe.h, (k + 1) * 64 / pe.h)
        end
        for _, b in ipairs(self.cells) do
            local e = b.anim
            if e and b:IsShown() then
                local k = frameOf(e)
                b.icon:SetTexCoord(0, 1, k * 64 / e.h, (k + 1) * 64 / e.h)
            end
        end
    end)
    f:Hide()
    return f
end
-- Emoji picker settings: small window to the right of the picker (sliders, toggles)
local function buildOptions(pk)
    local st = ns.db.settings
    local o = CreateFrame("Frame", nil, pk)
    o:SetSize(250, 430)
    o:SetPoint("TOPLEFT", pk, "TOPRIGHT", 6, 0)
    o:SetFrameLevel(pk:GetFrameLevel() + 20)
    o:EnableMouse(true)
    local GL = ns.Insta and ns.Insta.Glass
    if not (GL and pcall(GL, o, { 0.035, 0.035, 0.045, 0.96 }, { 1, 1, 1, 0.1 }, 12)) then
        o.bg = K.Fill(o, C.bg)
        K.Border(o, C.line)
    end
    local t = K.Title(o, 12, C.text)
    t:SetPoint("TOPLEFT", 12, -10)
    t:SetText(L["Appearance"])
    local x = K.CloseButton(o, function() o:Hide() end)
    x:SetPoint("TOPRIGHT", -4, -4)
    local y = -38
    local function head(text)
        local h = K.GameHead(o, text, C.accent)
        h:SetPoint("TOPLEFT", 12, y)
        h:SetPoint("RIGHT", o, "RIGHT", -12, 0)
        y = y - 24
    end
    -- onRelease: only apply on release (picker size: otherwise the slider moves away under the mouse)
    local function slider(minV, maxV, step, key, def, fmt, apply, onRelease)
        local sl = K.Slider(o, 226, minV, maxV, step,
            function() return tonumber(st[key]) or def end,
            function(v) st[key] = v if apply then apply(v) end end, fmt, onRelease)
        sl:SetPoint("TOPLEFT", 12, y)
        y = y - 34
        return sl
    end
    head(L["Background"])
    o.alpha = slider(0.3, 1, 0.05, "emojiAlpha", 0.8, function(v) return math.floor(v * 100 + 0.5) .. " %" end,
        function() if picker then picker:ApplyAlpha() end end)
    head(L["Size in the picker"])
    o.pick = slider(28, 56, 2, "emojiPickSize", 38, function(v) return v .. " px" end, nil,
        function() if picker then picker:Layout() end end)
    head(L["Window size"])
    o.w = slider(220, 1200, 10, "emojiW", 14 * 38 + 20, function(v) return (L["Width %d"]):format(v) end, nil,
        function() if picker then picker:Layout() end end)
    o.h = slider(170, 900, 10, "emojiH", 330, function(v) return (L["Height %d"]):format(v) end, nil,
        function() if picker then picker:Layout() end end)
    head(L["Size in chat"])
    o.chat = slider(0, 36, 2, "emojiChatSize", 0, function(v) return v == 0 and L["Auto"] or (v .. " px") end)
    o.close = K.Toggle(o, L["Close after picking"], function() return st.emojiClose and true or false end,
        function(v) st.emojiClose = v and true or false end)
    o.close:SetWidth(226)
    o.close:SetPoint("TOPLEFT", 12, y - 4)
    -- Message sent: close the picker (on) or keep it open (off)
    o.sendClose = K.Toggle(o, L["Close after sending"], function() return st.emojiCloseOnSend ~= false end,
        function(v) st.emojiCloseOnSend = v and true or false end)
    o.sendClose:SetWidth(226)
    o.sendClose:SetPoint("TOPLEFT", 12, y - 32)
    o:SetHeight(462)
    o.clearFav = K.Button(o, L["Clear favourites"], 226, 24, "ghost", function()
        st.emojiFav = {}
        if picker and picker:IsShown() then picker:ShowCat(picker.cat or "std", true) end
        K.Toast(L["Emojis"], L["Favourites cleared."], C.mint)
    end)
    o.clearFav:SetPoint("BOTTOMLEFT", 12, 42)
    o.clear = K.Button(o, L["Clear recently used"], 226, 24, "ghost", function()
        st.emojiRecent = {}
        if picker then picker.needRebuild = true end
        K.Toast(L["Emojis"], L["Recently used cleared."], C.mint)
    end)
    o.clear:SetPoint("BOTTOMLEFT", 12, 12)
    function o:Refresh()
        self.alpha:Refresh() self.pick:Refresh() self.w:Refresh() self.h:Refresh() self.chat:Refresh() self.close:Refresh() self.sendClose:Refresh()
    end
    o:Hide()
    return o
end
function Emoji.ShowPickerOptions()
    if not picker then return end
    picker.opts = picker.opts or buildOptions(picker)
    if picker.opts:IsShown() then picker.opts:Hide() return end
    picker.opts:Refresh()
    picker.opts:Show()
end

function Emoji.TogglePicker(anchor)
    -- "Zuletzt" tab gets added -> rebuild the tab bar
    local function tabSig()
        local sig = ""
        for _, c in ipairs(pickerCats()) do sig = sig .. c.key .. "," end
        return sig
    end
    local sig = tabSig()
    if picker and not picker:IsShown() and (picker.needRebuild or sig ~= picker.tabSig) then
        picker = nil
    end
    picker = picker or buildPicker()
    -- 0.6.438: border like the soundboard (was missing when the window was built early)
    if picker and not picker.boxFrame and K.BoxFrame then pcall(K.BoxFrame, picker, 40) end
    if picker and picker.boxFrame then picker.boxFrame:Show() end
    picker.tabSig = sig
    if picker:IsShown() then picker:Hide() return end
    Emoji.RememberTarget()
    picker:ClearAllPoints()
    local pos = ns.db and ns.db.settings.emojiPos
    if pos then
        -- moved by the user: reopen there
        picker:SetPoint(pos[1], UIParent, "BOTTOMLEFT", pos[2], pos[3])
    elseif anchor then
        picker:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 6)
    else
        picker:SetPoint("BOTTOMLEFT", ChatFrame1 or UIParent, "TOPLEFT", 0, 40)
    end
    picker:Show()
end
ns.slash.emoji = function() Emoji.TogglePicker() end
ns.slash.emojis = ns.slash.emoji

-- Diagnostics: /oa emojitest - why don't animated emojis work for someone? Output in chat (a screenshot is enough),
-- additionally stored in OasisDB.emojiDiag (SavedVariables)
local DIAG_ADDONS = { "Prat-3.0", "Chattynator", "ElvUI", "Glass", "Chatter", "WIM", "BasicChatMods", "TwitchEmotes", "TwitchEmotes_Solaris", "ls_Glass", "nesUI", "EllesmereUI", "EllesmereUIChat" }
ns.slash.emojimodus = function(rest)
    local m = tonumber(tostring(rest or ""):match("%d"))
    if m and m >= 1 and m <= 4 then ns.db.settings.emojiRedraw = (m ~= 1) and m or nil end
    if redrawMode() ~= 4 then for _, t in ipairs(ov.pool) do t:Hide() end end
    ns.print(("Emoji-Modus %d  (1 = normal, 2 = Zeile neu setzen, 3 = ueber den Chatverlauf, 4 = eigene Bilder ueber dem Chat - wirkt ab dem naechsten Emoji). Aendern: /oa emojimodus 1|2|3|4"):format(redrawMode()))
end
ns.slash.emojimode = ns.slash.emojimodus
-- 0.6.152: /oa emojiversatz 0.88 - compresses the computed position in mode 4 (1 = off). For clients where the
-- emoji sits right of the placeholder despite correct measurements.
ns.slash.emojiversatz = function(rest)
    local v = tonumber((tostring(rest or ""):gsub(",", ".")))
    if v and v >= 0.5 and v <= 1.5 then
        ns.db.settings.emojiXScale = v   -- 0.6.233: also store 1 (= deliberately off), "auto" deletes
        if ov.info then for k in pairs(ov.info) do ov.info[k] = nil end end
    end
    if tostring(rest or ""):lower():find("auto", 1, true) then
        ns.db.settings.emojiXScale = nil
        if ov.info then for k in pairs(ov.info) do ov.info[k] = nil end end
    end
    local own = tonumber(ns.db.settings.emojiXScale)
    ns.print(("Emoji-Versatz %.2f  (%s)  - kleiner = weiter links. Aendern: /oa emojiversatz 1.05 | /oa emojiversatz auto"):format(
        Emoji.XScale(), own and "eigene Einstellung" or "Default"))
end
ns.slash.emojitest = function()
    local out = {}
    local function add(s) out[#out + 1] = s ns.print(s) end
    local st = ns.db and ns.db.settings or {}
    local nAnim = 0
    for _ in pairs(Emoji.anims) do nAnim = nAnim + 1 end
    add(("Emojitest %s | Modus " .. redrawMode() .. " | chatEmoji=%s noAnim=%s | animiert=%d | Gildenpaket=%s | Takt=%s | zuletzt gezeigt vor %s s | Felder=%d"):format(
        tostring(ns.version), tostring(st.chatEmoji), tostring(st.noAnim), nAnim, tostring(ns.GuildPack ~= nil),
        tostring(Emoji.stepper ~= nil and Emoji.stepper:GetScript("OnUpdate") ~= nil),
        Emoji.animShown and math.floor(GetTime() - Emoji.animShown) or "nie", (function() local n = 0 for _ in pairs(Emoji.tracked) do n = n + 1 end return n end)()))
    local other = {}
    local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    for _, a in ipairs(DIAG_ADDONS) do if isLoaded and isLoaded(a) then other[#other + 1] = a end end
    add("Chat-Addons: " .. (#other > 0 and table.concat(other, ", ") or "keine bekannten"))
    if rawget(_G, "EllesmereUI") then   -- 0.6.235
        local w = euiWindow(ChatFrame1)
        add("EllesmereUI-Chatfenster: " .. (w and ("gefunden - Emojis richten sich danach (Zeilen: " .. tostring(w.visibleLines and #w.visibleLines or "?") .. ")") or "nicht gefunden - Emojis an Blizzard-Zeilen"))
        add("EllesmereUI-Aufbau: " .. Emoji.EuiDiag(ChatFrame1))
    end
    -- 0.6.153: everything that affects font rendering - to detect the offset of moving emojis automatically
    do
        local cf = ChatFrame1
        local ff, fsz, ffl = cf and cf.GetFont and cf:GetFont()
        local pw, ph = 0, 0
        if GetPhysicalScreenSize then pw, ph = GetPhysicalScreenSize() end
        local function cv(n) local ok, v = pcall(function() return (C_CVar and C_CVar.GetCVar(n)) or (GetCVar and GetCVar(n)) end) return ok and tostring(v) or "?" end
        local line1 = cf and cf.visibleLines and cf.visibleLines[1]
        add(("Schrift: %s %s %s | Bildschirm %dx%d, UI %.0fx%.0f | uiScale=%s useUiScale=%s | Chat-Skala=%.2f eff=%.3f | Zeile Textskala=%s Schrift=%s"):format(
            tostring(ff and ff:match("[^\\/]+$") or ff), tostring(fsz), tostring(ffl), pw or 0, ph or 0,
            GetScreenWidth and GetScreenWidth() or 0, GetScreenHeight and GetScreenHeight() or 0,
            cv("uiScale"), cv("useUiScale"), cf and cf:GetScale() or 0, cf and cf:GetEffectiveScale() or 0,
            tostring(line1 and line1.GetTextScale and line1:GetTextScale() or "-"),
            tostring(line1 and line1.GetFont and select(2, line1:GetFont()) or "-")))
        add(("Emoji-Versatz: %.2f (%s)  Mac: %s"):format(Emoji.XScale(), st.emojiXScale and "von Hand" or "automatisch",
            tostring(IsMacClient and IsMacClient() or false)))
    end
    Emoji._stepFrames = nil
    local watch = {}
    for _, n in ipairs(chatFrameNames()) do
        local cf = _G[n]
        if cf and cf:IsVisible() then
            local lines = cf.visibleLines
            local withEmoji, stepped, secret = 0, 0, 0
            local sample
            if type(lines) == "table" then
                for _, fs in ipairs(lines) do
                    local t = fs.GetText and fs:GetText()
                    if t and issecret(t) then secret = secret + 1
                    elseif t and t:find("emoji\\guild\\", 1, true) then
                        withEmoji = withEmoji + 1
                        sample = sample or t:match("(emoji\\guild\\[^|]+)|t")
                        watch[#watch + 1] = { fs = fs, t = t, n = n }
                        if t:find(ANIM_PAT) then stepped = stepped + 1 end
                        if not t:find(ANIM_PAT) then sample = "PASST NICHT: " .. ((t:match("(emoji\\guild\\[^|]+)|t")) or "?") end
                    end
                end
            end
            add(("%s: visibleLines=%s (%s) Emoji-Zeilen=%d Muster passt=%d geheim=%d %s"):format(n,
                type(lines), type(lines) == "table" and #lines or "-", withEmoji, stepped, secret, sample and ("| " .. sample) or ""))
        end
    end
    -- after 1.5 s: have the emoji lines really changed (= animation running)?
    C_Timer.After(1.5, function()
        local moved = 0
        for _, w in ipairs(watch) do if w.fs:GetText() ~= w.t then moved = moved + 1 end end
        local s = ("Nach 1,5 s veraendert: %d von %d Emoji-Zeilen"):format(moved, #watch)
        out[#out + 1] = s
        ns.print(s)
    end)
    if redrawMode() == 4 and ov.dbg and ov.dbg.fs then
        local d = ov.dbg
        local fe, te = d.fs:GetEffectiveScale() or 1, d.t:GetEffectiveScale() or 1
        add(("Modus 4 Lage: Umrechnung=%.3f Ausrichtung=%s Zeile links=%.0f Bild links=%.0f erwartet=%.0f (Bildschirmpunkte) UIParent=%.2f"):format(
            d.k, tostring(d.jh), (d.fs:GetLeft() or 0) * fe, (d.t:GetLeft() or 0) * te, ((d.fs:GetLeft() or 0) + d.x) * fe, UIParent:GetEffectiveScale() or 0))
        ov.dbg = nil
    end
    if redrawMode() == 4 then
        local shown = 0
        for fs, c in pairs(ov.info) do
            if shown < 3 and c.items and c.items[1] and fs.IsVisible and fs:IsVisible() then
                shown = shown + 1
                add(("Modus 4: x=%.0f Faktor=%.3f Zeilenbreite=%.0f Fensterskala=%.2f Textskala=%s"):format(c.items[1].x or -1, c.factor or 1,
                    fs.GetStringWidth and fs:GetStringWidth() or -1, fs.GetEffectiveScale and fs:GetEffectiveScale() or -1,
                    tostring(fs.GetTextScale and fs:GetTextScale() or "-")))
                if shown == 1 then
                    -- 0.6.145: text of the line (control characters visible) and for 15 s three guide lines on the line:
                    -- green = line start according to WoW, red = the emoji should start here, blue = line end according to WoW
                    add("Zeile: " .. tostring(c.raw or ""):gsub("|", "||"):sub(1, 220))
                    ov.marks = ov.marks or {}
                    local real = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
                    local tsc = (fs.GetTextScale and tonumber((fs:GetTextScale()))) or 1
                    for i, d in ipairs({ { 0, 0, 1, 0 }, { c.items[1].x or 0, 1, 0, 0 }, { real, 0.2, 0.5, 1 } }) do
                        -- 0.6.147: on its own layer above the chat window (otherwise lay below it and was invisible)
                        if not ov.markFrame then
                            ov.markFrame = CreateFrame("Frame", nil, UIParent)
                            ov.markFrame:SetFrameStrata("TOOLTIP")
                            ov.markFrame:SetAllPoints(UIParent)
                        end
                        local m = ov.marks[i] or ov.markFrame:CreateTexture(nil, "OVERLAY")
                        ov.marks[i] = m
                        m:SetColorTexture(d[2], d[3], d[4], 1)
                        m:ClearAllPoints()
                        m:SetSize(2, (fs:GetHeight() or 14) + 8)
                        local k = (fs:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
                        m:SetPoint("TOP", fs, "TOPLEFT", d[1] * k * tsc, 4)
                        m:Show()
                    end
                    C_Timer.After(15, function() for _, m in ipairs(ov.marks) do m:Hide() end end)
                    add("Hilfslinien 15 s: gruen = Zeilenanfang, rot = Emoji-Anfang (berechnet), blau = Zeilenende - bitte Screenshot")
                end
            end
        end
    end
    add("Bitte Screenshot davon schicken, waehrend ein animiertes Emoji im Chat steht.")
    if ns.db then ns.db.emojiDiag = { t = time(), lines = out } end
    -- 0.6.155: whole output (including the line after 1.5 s) in a text window - selected, Ctrl+C copies
    C_Timer.After(1.7, function()
        if ns.WhisperLog and ns.WhisperLog.Copy then pcall(ns.WhisperLog.Copy, "Emojitest", table.concat(out, "\n")) end
    end)
end

------------------------------------------------------------------------
-- Button in the chat input box
------------------------------------------------------------------------
local buttons = {}
-- Alt+Space in an input opens/closes the emoji picker
-- (only hooked via HookScript - Blizzard's input itself is not modified)
local hotkeyDone = setmetatable({}, { __mode = "k" })   -- instead of field on Blizzard's chat input
function Emoji.AttachHotkey(eb, anchor)
    if not eb or hotkeyDone[eb] then return end
    hotkeyDone[eb] = true
    eb:HookScript("OnKeyDown", function(self, key)
        if key == "SPACE" and IsAltKeyDown() and (not ns.db or ns.db.settings.emojiHotkey ~= false) then
            Emoji.RememberTarget(self)
            Emoji.target = self
            Emoji.TogglePicker(anchor and anchor() or self)
        end
    end)
end
function Emoji.UpdateButtons()
    local on = ns.db and ns.db.settings.emojiButton ~= false
    -- nesUI has its own sound/emoji buttons in the chat bar -> don't show them twice here
    if _G.nesUI then on = false end
    for _, b in pairs(buttons) do b:SetShown(on) end
end
local function attach(eb)
    if not eb or buttons[eb] then return end
    local b = CreateFrame("Button", nil, eb)
    b:SetSize(16, 16)
    b:SetPoint("RIGHT", eb, "RIGHT", -6, 0)
    b:SetFrameLevel(eb:GetFrameLevel() + 5)
    b:SetHitRectInsets(-5, -3, -6, -6)   -- larger click area than the 16 px icon (was hard to hit)
    -- plain monochrome icon as in the Oasis sidebar (same size as the sound button)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(ns.MEDIA .. "icons\\smile")
    b.icon:SetVertexColor(0.6, 0.6, 0.62)
    b:SetScript("OnEnter", function(self)
        Emoji.RememberTarget(eb)
        self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        K.ShowTip(self, { L["Emojis"], L["Click: open picker"], "|cff888888" .. L["In chat: Alt+Space"] .. "|r" })
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.6, 0.6, 0.62)
        GameTooltip:Hide()
    end)
    -- like Alt+Space: remember the target (mouse down = input still has focus) and use exactly this input
    b:SetScript("OnMouseDown", function()
        Emoji.RememberTarget(eb)
        -- WoW closes an empty input completely on click (not with text) -> briefly put a space in it,
        -- which disappears again on reopen (remembered text is empty)
        if eb:IsShown() and eb.HasFocus and eb:HasFocus() and (ns.safe(eb:GetText()) or "") == "" then
            eb:Insert(" ")
        end
    end)
    b:SetScript("OnClick", function(self)
        Emoji.RememberTarget(eb)
        Emoji.target = eb
        Emoji.TogglePicker(self)
        -- reopen a moment later (by then WoW has already closed the input)
        C_Timer.After(0.05, function() pcall(Emoji.RestoreChat) end)
        -- WoW sometimes closes an empty input only a bit later -> check again to be safe
        C_Timer.After(0.25, function() pcall(Emoji.RestoreChat) end)
    end)
    buttons[eb] = b
    -- next to it: send sound
    local sb = CreateFrame("Button", nil, b)   -- attached to the emoji button: shown/hidden with it
    sb:SetSize(16, 16)
    sb:SetPoint("RIGHT", b, "LEFT", -6, 0)
    sb:SetFrameLevel(eb:GetFrameLevel() + 5)
    sb:SetHitRectInsets(-3, -3, -6, -6)
    sb.icon = sb:CreateTexture(nil, "ARTWORK")
    sb.icon:SetAllPoints()
    sb.icon:SetTexture(ns.MEDIA .. "icons\\speaker")
    sb.icon:SetVertexColor(0.6, 0.6, 0.62)
    sb:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        K.ShowTip(self, { L["Send sound"], L["Everyone with Oasis hears it - at most every 30 seconds."] })
    end)
    sb:SetScript("OnLeave", function(self) self.icon:SetVertexColor(0.6, 0.6, 0.62) GameTooltip:Hide() end)
    -- as with the emoji button: remember target + started text BEFORE WoW closes the input on click
    -- (previously it was read only after closing -> whisper/group sometimes fell back to guild,
    -- and the chat stayed closed for guild, started text was gone)
    sb:SetScript("OnMouseDown", function(self) Emoji.SoundButtonDown(self, eb) end)
    sb:SetScript("OnClick", function(self) Emoji.SoundButtonClick(self, eb) end)
    b.snd = sb
    -- Cooldown visible (0.5.592)
    if ns.Sound and ns.Sound.AttachCooldown then pcall(ns.Sound.AttachCooldown, sb) end
end
-- Preview above the chat input: WoW cannot show images in the input box, short codes stay text there.
-- So a small bar above it shows how the message will look with emojis.
-- 0.5.518: only briefly when an emoji was just recognized - and only the emojis, not the whole message.
-- Typing on (without a new emoji) hides it; it disappears by itself after 2.5 s.
local previewCount = setmetatable({}, { __mode = "k" })
function Emoji.Preview(eb)
    if ns.db and ns.db.settings.emojiPreview == false then return end
    local txt = eb:GetText() or ""
    local ok, rendered = pcall(Emoji.Render, txt)
    local f = Emoji.previewF
    if not ok or type(rendered) ~= "string" or rendered == txt or txt == "" then
        previewCount[eb] = 0
        if f then f:Hide() end
        return
    end
    local icons = {}
    for t in rendered:gmatch("|T.-|t") do icons[#icons + 1] = t end
    local before = previewCount[eb] or 0
    previewCount[eb] = #icons
    if #icons <= before then
        -- no new emoji: kept typing -> preview gone
        if f then f:Hide() end
        return
    end
    if not f then
        f = CreateFrame("Frame", nil, UIParent)
        f:SetFrameStrata("DIALOG")
        f:SetHeight(26)
        f.bg = K.Fill(f, { 0.05, 0.05, 0.07, 0.9 })
        K.Border(f, C.line)
        f.t = K.Text(f, 13, C.text)
        f.t:SetPoint("LEFT", 8, 0)
        f.t:SetPoint("RIGHT", -8, 0)
        f.t:SetWordWrap(false)
        Emoji.previewF = f
    end
    f:ClearAllPoints()
    -- Suggestion list (:th... Tab) sits in the same place -> preview above it then
    local pop = _G.OasisEmojiComplete
    local anchor = (pop and pop:IsShown()) and pop or eb
    f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    -- only the message's emojis (at most 12), newest last
    local first = math.max(1, #icons - 11)
    local list = {}
    for i = first, #icons do list[#list + 1] = icons[i] end
    f.t:SetText("|cff888888" .. L["Emoji recognised"] .. "|r   " .. table.concat(list, " "))
    f:SetWidth(math.min(math.max(140, (f.t:GetStringWidth() or 120) + 20), math.max(200, eb:GetWidth() or 300)))
    f:SetFrameStrata("TOOLTIP")
    f.hideAt = GetTime() + 2.5
    if not f.timer then
        f.timer = true
        f:SetScript("OnUpdate", function(self) if self.hideAt and GetTime() > self.hideAt then self.hideAt = nil self:Hide() end end)
    end
    f:SetAlpha(1)
    f:Show()
    if K.FadeIn then f.oasisFadedAt = nil pcall(K.FadeIn, f, 0, 4) end
end

local editWired = setmetatable({}, { __mode = "k" })
wirers[#wirers + 1] = function()
    for _, n in ipairs(chatFrameNames()) do
        local eb = _G[n .. "EditBox"]
        local fresh = eb and not editWired[eb]
        if fresh then editWired[eb] = true end
        attach(eb)
        Emoji.AttachHotkey(eb, function() return buttons[eb] end)
        -- WoW chat: arrow up/down recalls the last messages even WITHOUT Alt (can be turned off: settings.chatArrowAlt)
        if fresh and eb.SetAltArrowKeyMode and not (ns.db and ns.db.settings.chatArrowAlt) then pcall(eb.SetAltArrowKeyMode, eb, false) end
        -- Track the chat target directly at the input (switch via /p, /w, click ...), only while typing
        if fresh and eb.HookScript then
            eb:HookScript("OnAttributeChanged", function(self, name)
                if name == "chattype" or name == "chatType" or name == "telltarget" or name == "tellTarget" or name == "channeltarget" then
                    pcall(Emoji.RememberTarget, self)
                end
            end)
            eb:HookScript("OnTextChanged", function(self) pcall(Emoji.RememberTarget, self) pcall(Emoji.Preview, self) end)
            eb:HookScript("OnEditFocusLost", function() if Emoji.previewF then Emoji.previewF:Hide() end end)
            eb:HookScript("OnHide", function() if Emoji.previewF then Emoji.previewF:Hide() end end)
            eb:HookScript("OnEditFocusGained", function(self) pcall(Emoji.RememberTarget, self) end)
            -- Enter = message sent: close the picker or keep it open depending on the setting
            eb:HookScript("OnEnterPressed", function()
                if ns.db and ns.db.settings.emojiCloseOnSend ~= false and picker and picker:IsShown() then picker:Hide() end
            end)
        end
    end
    Emoji.UpdateButtons()
end

------------------------------------------------------------------------
-- Speech bubbles over heads: show short codes as emojis there too.
-- Blizzard draws the bubbles itself; outside instances addons may change their text
-- (in instances the bubbles are locked - the text stays as it is there).
------------------------------------------------------------------------
local function bubbleText(bubble)
    if not bubble or (bubble.IsForbidden and bubble:IsForbidden()) then return nil end
    for _, holder in ipairs({ bubble, bubble.GetChildren and select(1, bubble:GetChildren()) or nil }) do
        if holder and not (holder.IsForbidden and holder:IsForbidden()) and holder.GetRegions then
            for _, r in ipairs({ holder:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "FontString" then return r end
            end
        end
    end
    -- newer clients: child frame with .String
    for _, c in ipairs({ bubble:GetChildren() }) do
        if c.String and c.String.GetText then return c.String end
    end
end
local function fixBubbles()
    if not (C_ChatBubbles and C_ChatBubbles.GetAllChatBubbles) then return end
    if IsInInstance and IsInInstance() then return end
    local ok, list = pcall(C_ChatBubbles.GetAllChatBubbles, false)
    if not ok or type(list) ~= "table" then return end
    for _, b in ipairs(list) do
        local fs = bubbleText(b)
        if fs then
            local okT, txt = pcall(fs.GetText, fs)
            if okT and type(txt) == "string" and not (issecretvalue and issecretvalue(txt)) and txt:find(":", 1, true) then
                local okR, r = pcall(Emoji.Render, txt)
                if okR and type(r) == "string" and r ~= txt then pcall(fs.SetText, fs, r) end
            end
        end
    end
end
Emoji.FixBubbles = fixBubbles
for _, ev in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_MONSTER_SAY" }) do
    ns.On(ev, function()
        if ns.db and ns.db.settings.emojiBubbles == false then return end
        -- the bubble is created only shortly after the event
        ns.After(0.05, fixBubbles)
        ns.After(0.25, fixBubbles)
    end)
end

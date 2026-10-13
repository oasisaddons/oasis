-- Oasis - Emojis im Chat
-- WoW kann keine echten Emoji-Zeichen anzeigen und laesst keine Bilder in gesendeten Nachrichten zu.
-- Deshalb: man schreibt Kurzcodes (:lol:, <3, :gg: ...), Oasis ersetzt sie beim Anzeigen durch Bilder
-- (nur wer Oasis hat, sieht das Bild - alle anderen den Code). Raid-Symbole {rt1}..{rt8} sieht jeder.
-- Grafiken: Twemoji (CC-BY 4.0), siehe Media\emoji\CREDITS.txt
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local Emoji = {}
ns.Emoji = Emoji
local PATH = ns.MEDIA .. "emoji\\"

-- key = Datei, codes = alles, was dazu wird (erster Code wird beim Einfuegen benutzt)
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
    -- Spass-Emojis (Discord-/Twitch-Namen zeigen auf passende freie Bilder)
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
-- Kategorien fuer die Auswahl: Standard, Gilde (eigene, auch animiert), Raid-Symbole
Emoji.CATS = { { key = "std", name = "Standard", items = Emoji.LIST } }
-- eigene Gilden-Emojis (CustomEmojis + ImportEmojis.bat) liegen im Gildenmodul Oasis_Guild und kommen ueber Emoji.AddCats dazu
local RAID = {}
for i = 1, 8 do RAID[i] = { "raid" .. i, "{rt" .. i .. "}", raid = true } end
Emoji.CATS[#Emoji.CATS + 1] = { key = "raid", name = "Raid", items = RAID, raid = true }

-- :name: -> Eintrag ; kurze Smileys (nur als eigenes "Wort") -> Eintrag
-- Animierte Eintraege (aus GIFs): n = Bilder, h = Hoehe des Streifens in Pixel (je Bild 64), d = Sekunden je Bild
local named, short = {}, {}
Emoji.anims = {}   -- [Datei] = Eintrag
-- eigene Emojis zuerst: ihre Codes (z.B. :pepehands:) haben Vorrang vor den Ersatz-Aliasen im Standard-Satz
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

-- Bildausschnitt eines animierten Emojis fuer den aktuellen Zeitpunkt
local function frameOf(e)
    return math.floor(GetTime() / (e.d or 0.1)) % e.n
end
Emoji.FrameOf = frameOf
-- yoff: im Chat etwas tiefer setzen (sonst sitzt das Bild ueber der Textzeile)
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

-- Bild zurueck in den Kurzcode (fuer Text, der schon durch den Chat-Filter gelaufen ist)
local codeOf = {}
for _, cat in ipairs(Emoji.CATS) do
    for _, e in ipairs(cat.items) do
        if e[2] and not codeOf[e[1]] then codeOf[e[1]] = e[2] end
    end
end
local GPATH = "Interface\\AddOns\\Oasis_Guild\\Media\\emoji\\"   -- Texturen der Gilden-Emojis (Gildenmodul)
local TEX_PAT = "|T" .. PATH:gsub("%p", "%%%0") .. "([^:|]+)[^|]*|t"
local TEX_PAT_G = "|T" .. GPATH:gsub("%p", "%%%0") .. "([^:|]+)[^|]*|t"
function Emoji.Unrender(msg)
    if type(msg) ~= "string" or not (msg:find(PATH, 1, true) or msg:find(GPATH, 1, true)) then return msg end
    msg = msg:gsub("|Haddon:oasisemo:[^|]*|h(.-)|h", "%1")
    msg = msg:gsub(TEX_PAT, function(key) return codeOf[key] end)
    return (msg:gsub(TEX_PAT_G, function(key) return codeOf[key] end))
end

-- Emoji im Chat als (unsichtbarer) Link: nur so kann WoW beim Ueberfahren einen Tooltip zeigen
local entryOf = {}
for _, cat in ipairs(Emoji.CATS) do
    for _, e in ipairs(cat.items) do if not entryOf[e[1]] then entryOf[e[1]] = e end end
end
-- 0.5.728: Gilden-Emojis aus dem Gildenmodul: Reiter anhaengen (vor "Raid") und Suchtabellen fuellen
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
-- nur, wenn der Client "addon:"-Links kennt (sonst gaebe ein Klick darauf einen Fehler)
local function linksOk()
    return (LinkTypes and LinkTypes.addon ~= nil) or (EventRegistry ~= nil and LinkUtil ~= nil and C_AddOns ~= nil)
end
-- Groesse im Chat: eingestellt oder automatisch so gross wie die Schrift
local function chatSize()
    if Emoji.sizeOverride then return Emoji.sizeOverride end   -- Oasis-Fenster mit kleinerer Schrift (Privatchat ...)
    local v = ns.db and tonumber(ns.db.settings.emojiChatSize) or 0
    if v > 0 then return v end
    local _, fh = ChatFrame1 and ChatFrame1.GetFont and ChatFrame1:GetFont()
    return math.floor((fh or 14) * 1.0 + 0.5)
end
-- 0.5.602: nur noch minimal tiefer (vorher 18 %) - in der untersten Chatzeile ragte das Bild sonst unter den
-- Fensterrand und wurde abgeschnitten (Blizzard-Chat wie EllesmereUI)
local function yoffFor(sz) return -math.floor((sz or 20) * 0.06 + 0.5) end
local function linked(e)
    local sz = chatSize()
    if not linksOk() then return tex(e, sz, yoffFor(sz)) end
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
    -- animierte Emojis (GIFs) auch im Tooltip abspielen
    if e.n and e.n > 1 then
        Emoji.tipAnim = Emoji.tipAnim or CreateFrame("Frame")
        Emoji.tipAnim.e = e
        Emoji.tipAnim:SetScript("OnUpdate", function(self)
            if not GameTooltip:IsShown() or GameTooltip:GetOwner() ~= owner then self:SetScript("OnUpdate", nil) return end
            local l = _G.GameTooltipTextLeft1
            if l then l:SetText(tex(self.e, 64) .. "   |cffffffff" .. (self.e[2] or "") .. "|r") end
        end)
    end
    if #codes > 0 then GameTooltip:AddLine(L["auch:"] .. " " .. table.concat(codes, "  "), 0.6, 0.6, 0.65) end
    GameTooltip:Show()
    return true
end
-- Alle Chatfenster: die festen (1..NUM_CHAT_WINDOWS) und die zeitweiligen (Fluester-Reiter, ab Nummer 11) aus
-- CHAT_FRAMES. Vorher liefen nur die festen mit: im Fluester-Reiter standen animierte Emojis still und die
-- Knoepfe an der Eingabe fehlten.
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
-- Anschluesse je Chatfenster (Tooltip, Eingabe, Knoepfe): laufen beim Login und wieder, wenn WoW einen Reiter oeffnet
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
    if hooksecurefunc and type(FCF_OpenTemporaryWindow) == "function" then
        hooksecurefunc("FCF_OpenTemporaryWindow", function() C_Timer.After(0, Emoji.WireChatFrames) end)
    end
end)
-- Chatfenster: Tooltip beim Ueberfahren (nur anhaengen, Blizzards eigene Link-Behandlung bleibt)
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

-- Text ausserhalb von Links umwandeln (Item-/Spieler-Links enthalten Doppelpunkte!)
-- gesperrte Emojis (erst ab Oasis-Rang): nur als Bild zeigen, wenn der ABSENDER den Rang hat
local renderSender
function Emoji.Allowed(e, who)
    if ns.GuildOpt and ns.GuildOpt("emLock") == false then return true end
    if who and ns.isMe(who) and ns.UnlockAll and ns.UnlockAll() then return true end
    local need = ns.Rewards and ns.Rewards.EmojiLevel and ns.Rewards.EmojiLevel(e)
    if not need then return true end
    if not who then return true end
    local lvl = ns.Rank and ns.Rank.Of and ns.Rank.Of(who)
    return (lvl or 0) >= need
end
-- Muster einmal bauen (vorher je Wort und Nachricht neu zusammengesetzt)
local TAIL_PATS = { "^(%a+)(...)([%.,!%?]*)$", "^(%a+)(..)([%.,!%?]*)$" }
local function renderPlain(s)
    s = s:gsub(":([%w%+%-_]+):", function(n)
        local e = named[n:lower()]
        if e and Emoji.Allowed(e, renderSender) then return linked(e) end
    end)
    -- kurze Smileys nur als eigenes Wort (sonst wuerde z.B. "12:30" oder eine URL zerlegt).
    -- Satzzeichen dahinter bleiben stehen ("xD!" -> Bild + "!"), direkt am Wort haengende Smileys
    -- werden auch erkannt ("hallo:)" -> "hallo" + Bild), Uhrzeiten/Links nicht.
    s = s:gsub("(%S+)", function(w)
        local e = short[w]
        if e then return linked(e) end
        -- Satzzeichen hinten abtrennen ("xD!", ":D?!", "<3.")
        local core, tail = w:match("^(.-)([%.,!%?;]+)$")
        if core and core ~= "" and short[core] then return linked(short[core]) .. tail end
        -- Smiley direkt am Wortende ("hallo:)", "gg:D!"), nur mit Buchstaben davor
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
    -- Schnellpruefung: alle Kurzcodes enthalten : ; < { oder xD/XD (vorher sprang sie bei jedem "x" an)
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
    -- animiertes Emoji dabei? Dann laeuft die Animation (StepChat) die naechsten 15 Min
    if res ~= msg and res:find("emoji\\guild\\", 1, true) then Emoji.animShown = GetTime() end
    return res
end

------------------------------------------------------------------------
-- Animation im Chat: sichtbare Chatzeilen mit animierten Emojis Bild fuer Bild weiterschalten
-- (so machen es auch Addons wie TwitchEmotes; nur Anzeige, nichts wird gesendet)
------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
-- y-Versatz kann negativ sein (Emoji sitzt auf der Grundlinie) -> mit erfassen, sonst bleibt das Bild stehen
local ANIM_PAT = "(emoji\\(guild\\[%w_]+)):(%d+):(%d+):0:(%-?%d+):64:(%d+):0:64:(%d+):(%d+)|t"
local function stepLine(fs)
    local t = fs:GetText()
    if not t or issecret(t) or not t:find("emoji\\guild\\", 1, true) then return end
    local new = t:gsub(ANIM_PAT, function(path, key, sw, sh, yo, h, top, bottom)
        local e = Emoji.anims[key]
        if not e then return nil end
        local nt = frameOf(e) * 64
        return path .. ":" .. sw .. ":" .. sh .. ":0:" .. yo .. ":64:" .. h .. ":0:64:" .. nt .. ":" .. (nt + 64) .. "|t"
    end)
    if new ~= t then fs:SetText(new) end
end
-- eigene Oasis-Textfelder (Chatblasen, Vorschau): animierte Emojis dort ebenfalls weiterschalten
Emoji.tracked = setmetatable({}, { __mode = "k" })
function Emoji.Track(fs)
    if fs and fs.GetText then Emoji.tracked[fs] = true end
end
function Emoji.StepChat()
    if not ns.db or ns.db.settings.chatEmoji == false then return end
    -- nur, wenn in den letzten 15 Min ein animiertes Emoji angezeigt wurde oder Oasis-Felder welche tragen
    -- (Performance 0.5.482: vorher liefen 20x pro Sekunde alle sichtbaren Chatzeilen durch)
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
    for fs in pairs(Emoji.tracked) do
        if fs.IsVisible and fs:IsVisible() then pcall(stepLine, fs) end
    end
    -- 0.5.565: Chatfenster, ueber dessen Link gerade die Maus steht (Tooltip gehoert ihm), nicht weiterschalten -
    -- SetText baut die Link-Flaechen neu, WoW meldet "Maus weg" und die Vorschau verschwand sofort
    local tipOwner = GameTooltip and GameTooltip:IsShown() and GameTooltip:GetOwner() or nil
    for _, cf in ipairs(frames) do
        local lines = cf and cf ~= tipOwner and cf:IsVisible() and cf.visibleLines
        if lines then
            for _, fs in ipairs(lines) do
                -- Zeile unter der Maus nicht weiterschalten: SetText baut die Link-Flaechen neu, ein Klick auf den
                -- Namen in einer Zeile mit animiertem Emoji ging dadurch verloren (kein Fluestern, kein Menue)
                if fs.IsShown and fs:IsShown() and not (fs.IsMouseOver and fs:IsMouseOver()) then pcall(stepLine, fs) end
            end
        end
    end
end
-- 0.5.511: ~30 Bilder/s statt 12,5 (alle 0,08 s) - die GIFs haben 0,02-0,06 s je Bild und ruckelten/liefen
-- scheinbar zu langsam. Laeuft nur, solange animierte Emojis sichtbar sein koennen (StepChat prueft das selbst).
ns.Listen("LOGIN", function()
    if not next(Emoji.anims) or Emoji.stepper then return end
    -- nach /reload: wiederhergestellter Chatverlauf kann animierte Emojis enthalten -> 15 Min mitlaufen
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
-- Chat-Filter: nur Anzeige, gesendet wird weiterhin der Text
------------------------------------------------------------------------
local EVENTS = { "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }
local function filter(self, event, msg, ...)
    if not ns.db or ns.db.settings.chatEmoji == false then return false end
    msg = ns.safe(msg)   -- im Kampf koennen Nachrichten "geheim" sein -> nicht anfassen
    if not msg then return false end
    local sender = ns.safe((...))
    -- eigene gesendete Fluesternachricht: "sender" ist hier der EMPFAENGER -> Absender bin ich
    -- (sonst wurden gesperrte Emojis nach dessen Rang geprueft und blieben als Code stehen)
    if event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM" then sender = ns.me() end
    local new = Emoji.Render(msg, sender and ns.fullName(sender) or nil)
    if new ~= msg then return false, new, ... end
    return false
end
local function addFilter(ev)
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if add then pcall(add, ev, filter) end
end
for _, ev in ipairs(EVENTS) do addFilter(ev) end

------------------------------------------------------------------------
-- Auswahl-Fenster
------------------------------------------------------------------------
local picker
local function activeEditBox()
    local eb = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()) or (ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow())
    if eb then return eb end
    return ChatFrame1EditBox
end
Emoji.frames = {}   -- weitere Chatfenster (z.B. Gildenchat-Seite), deren Emojis animiert werden
-- Wohin wurde gerade geschrieben? (Klick auf den Emoji-Knopf schliesst die Eingabe -> danach
-- genau dorthin wieder oeffnen, sonst macht WoW aus einem Fluestern "Sagen")
local PREFIX_OF = { SAY = "/s ", YELL = "/y ", PARTY = "/p ", RAID = "/ra ", GUILD = "/g ", OFFICER = "/o ",
    INSTANCE_CHAT = "/i ", RAID_WARNING = "/rw " }
-- Ziel einer Chat-Eingabe als Slash-Vorsatz ("/w Tomas ", "/p " ...), nil = kein Chat-Eingabefeld
local function targetOf(eb)
    if not eb or not eb.GetAttribute then return nil end
    local ct = ns.safe(eb:GetAttribute("chatType"))
    if ct == "WHISPER" or ct == "BN_WHISPER" then
        -- auch Battle.net-Fluestern (Freundesliste: "Tomas erzaehlen")
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
-- nur merken, solange wirklich in der Eingabe getippt wird: verliert sie den Fokus (Klick auf den
-- Emoji-Knopf), stellt WoW sie auf "Sagen" zurueck - das darf das gemerkte Ziel nicht ueberschreiben
function Emoji.RememberTarget(eb)
    eb = eb or activeEditBox()
    if not eb or not eb:IsShown() or not (eb.HasFocus and eb:HasFocus()) then return end
    local pre = targetOf(eb)
    -- WoW stellt beim Wiederoeffnen kurz auf "Sagen" - das darf ein eben gemerktes Ziel (Gilde, Gruppe,
    -- Fluestern) nicht ueberschreiben
    local lt = Emoji.lastTarget
    if pre == "/s " and lt and lt.pre ~= "/s " and lt.t and GetTime() - lt.t < 8 then return end
    if pre then
        local okc, cp = pcall(eb.GetCursorPosition, eb)
        Emoji.lastTarget = { pre = pre, text = ns.safe(eb:GetText()) or "", eb = eb, t = GetTime(), cur = okc and tonumber(cp) or nil,
            ct = ns.safe(eb:GetAttribute("chatType")), who = ns.safe(eb:GetAttribute("tellTarget")) }
    end
end
-- nach dem Klick auf den Emoji-Knopf: WoW hat die Eingabe geschlossen/auf "Sagen" gestellt ->
-- sofort mit dem gemerkten Ziel und dem angefangenen Text wieder oeffnen
-- Chat-Eingabe mit Ziel + Text oeffnen (oder nichts tun, wenn sie schon genau so offen ist)
local function openWith(pre, text, ct, who0)
    local cur = activeEditBox()
    if cur and cur:IsShown() and cur.HasFocus and cur:HasFocus() and targetOf(cur) == pre
        and (ns.safe(cur:GetText()) or "") == text then return end
    if ns.inCombat() then return end
    local who = pre:match("^/w (.-) $")
    if ct == "BN_WHISPER" and (who0 or who) then
        -- Battle.net-Fluestern: oeffnen und Typ + Ziel direkt setzen (WoWs Funktion klappt hier nicht immer)
        who = who0 or who
        ns.Trace("BN_WHISPER " .. who)
        if ChatFrame_SendBNetTell then pcall(ChatFrame_SendBNetTell, who) end
        -- KEIN SetAttribute auf Blizzards Chat-Eingabe mehr: das "verseucht" sie (Taint) und WoW
        -- blockiert danach geschuetzte Funktionen ("Oasis wurde blockiert ... callback()")
        local nb = activeEditBox()
        if nb and nb:IsShown() then nb:SetText(text) nb:SetFocus() end
        return
    end
    local bnID = who and BNet_GetBNetIDAccount and ns.safe(BNet_GetBNetIDAccount(who))
    if who and bnID and ChatFrame_SendBNetTell then
        -- Battle.net-Freund: ueber WoWs Battle.net-Fluestern oeffnen
        ns.Trace("ChatFrame_SendBNetTell")
        ChatFrame_SendBNetTell(who)
        local nb = activeEditBox()
        if nb then nb:SetText(text) end
    elseif who and ChatFrame_SendTell then
        -- Fluestern mit WoWs eigener Funktion oeffnen (wie "Antworten"), dann den Text einsetzen
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
-- Lautsprecher-Knopf an der Chat-Eingabe: EINE Stelle fuer das Verhalten (Oasis-eigener Knopf und der Knopf von nesUI
-- rufen beide hier hinein). Regel: ein Sound geht einfach raus - vorher und nachher oeffnet sich keine
-- Chat-Eingabe. Nur wenn dort schon Text stand, kommt die Eingabe mit diesem Text zurueck.
------------------------------------------------------------------------
-- Maus runter: Ziel und "stand schon Text da?" merken, BEVOR WoW die Eingabe beim Klick schliesst
function Emoji.SoundButtonDown(btn, eb)
    if not btn then return end
    local cur = eb and eb:IsShown() and ns.safe(eb:GetText()) or ""
    btn.hadText = type(cur) == "string" and cur:gsub("%s", "") ~= ""
    pcall(Emoji.RememberTarget, eb)
end
function Emoji.SoundButtonClick(btn, eb)
    if not (btn and eb and ns.Sound and ns.Sound.OpenPicker) then return end
    local had = btn.hadText
    -- dorthin schicken, wo gerade geschrieben wurde (Fluestern -> nur die Person, Gruppe -> nur die Gruppe)
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
            -- leere Eingabe schliessen, falls sie (noch) offen ist - mit jeder Schliess-Funktion, die dieser Client kennt
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
    -- angefangenen Text nicht verlieren: nur dann geht die Eingabe wieder auf
    ns.Sound.restoreChat = had and true or nil
    if had then C_Timer.After(0.05, function() pcall(Emoji.RestoreChat) end) end
end

-- jedes Mal mitschreiben, wenn WoW den Chat-Kopf umstellt ("Fluestern an X", "Gruppe" ...)
if hooksecurefunc and ChatEdit_UpdateHeader then
    hooksecurefunc("ChatEdit_UpdateHeader", function(eb) pcall(Emoji.RememberTarget, eb) end)
end
-- Nur das Ziel (Gruppe, Fluestern, Gilde ...) behalten, nie den Text: nach dem Senden oder Abbrechen vergessen
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
-- zuletzt benutzte Emojis (eigener Reiter ganz vorne)
local RECENT_MAX = 28
local byCode = {}
for _, cat in ipairs(Emoji.CATS) do
    for _, e in ipairs(cat.items) do
        for i = 2, #e do if not byCode[e[i]] then byCode[e[i]] = e end end
    end
end
-- fuer andere Fenster (Sound-Auswahl "Emoji dazu"): Eintrag zu einem Code, Bild setzen, Schnell-Liste
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
-- Favoriten, dann zuletzt, dann haeufig benutzte (ohne Raid-Symbole, ohne Doppelte)
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
Emoji.RECENT = { key = "recent", name = "Zuletzt", items = {} }
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
    -- "Haeufig": wie oft selbst benutzt (0.5.592)
    local cnt = ns.db.settings.emojiCount or {}
    cnt[code] = (cnt[code] or 0) + 1
    ns.db.settings.emojiCount = cnt
end
-- "Beliebt in der Gilde": Emoji-Codes in Gildennachrichten mitzaehlen (je Absender + Emoji hoechstens 1x/Minute)
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
-- Code an der gemerkten Schreibstelle einsetzen (statt immer ans Ende); pos = Zeichen davor
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
    -- eigene Eingabefelder (z.B. Gildenchat-Seite): einfach einfuegen
    if tgt and tgt:IsVisible() and not targetOf(tgt) then
        local t = tgt:GetText() or ""
        tgt:Insert(((t ~= "" and not t:find("%s$")) and " " or "") .. code .. " ")
        tgt:SetFocus()
        return
    end
    -- Chat: WoW schliesst/leert die Eingabe beim Klick in die Auswahl (vor allem, wenn sie leer ist).
    -- Deshalb nicht in die Eingabe tippen, sondern sie mit Ziel + fertigem Text (inkl. Emoji) neu oeffnen,
    -- und kurz danach nochmal pruefen, falls WoW sie hinterher doch zugemacht hat.
    local eb = (tgt and targetOf(tgt) and tgt) or activeEditBox()
    -- Eingabe zu, aber Ziel (Gilde, Gruppe, Fluestern ...) steht noch an ihr: einfach wieder aktivieren
    local lt0 = Emoji.lastTarget
    if eb and not eb:IsShown() and ChatEdit_ActivateChat and not ns.inCombat() and targetOf(eb)
        and (not lt0 or targetOf(eb) == lt0.pre) then
        pcall(ChatEdit_ActivateChat, eb)
        if lt0 and (lt0.text or "") ~= "" and (ns.safe(eb:GetText()) or "") == "" then eb:SetText(lt0.text) end
    end
    -- Eingabe ist (wieder) offen: direkt einfuegen, nichts neu oeffnen
    if eb and eb:IsShown() and targetOf(eb) and not ns.inCombat() then
        local cur = ns.safe(eb:GetText()) or ""
        if cur:match("^%s*$") then cur = "" end
        -- WoW hat die Eingabe auf "Sagen" zurueckgestellt, gemerkt war aber z.B. Gilde/Gruppe/Fluestern:
        -- Befehl voranstellen, dann geht die Nachricht beim Senden trotzdem dorthin
        local ltp = Emoji.lastTarget and Emoji.lastTarget.pre
        local lt1 = Emoji.lastTarget
        -- Schreibstelle merken: nur gueltig, wenn der Text noch genau der gemerkte ist
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
    if base:match("^%s*$") then base, pos0 = "", nil end   -- Platzhalter-Leerzeichen vom Emoji-Knopf
    local text = spliceAt(base, pos0, code)
    local ct = lt and lt.pre == pre and lt.ct or (eb and ns.safe(eb:GetAttribute("chatType")))
    local who = lt and lt.pre == pre and lt.who or (eb and ns.safe(eb:GetAttribute("tellTarget")))
    Emoji.lastTarget = { pre = pre, text = text, eb = eb, ct = ct, who = who }
    openWith(pre, text, ct, who)
    C_Timer.After(0.05, function() pcall(Emoji.RestoreChat) end)
    C_Timer.After(0.3, function() pcall(Emoji.RestoreChat) end)
end

-- Reiter "Oasis": alle Emojis, die man mit dem Oasis-Rang freischaltet, sortiert nach Rang
Emoji.OASIS = { key = "oasis", name = "Oasis", items = {}, custom = true }
ns.GuildOption({ page = "chat", key = "emLock", default = false, label = "Besondere Emojis erst ab Oasis-Rang",
    desc = "Aus: alle animierten Gilden-Emojis sind fuer jeden sofort benutzbar" })
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
-- Favoriten (0.5.590): Rechtsklick auf ein Emoji; eigener Reiter ganz vorne, Reihenfolge = wann gemerkt
local FAV_MAX = 60
Emoji.FAV = { key = "fav", name = "Favoriten", items = {} }
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
-- Haeufig (eigene Nutzung), Beliebt (Gildenchat), Kombos (mehrere Emojis auf einen Klick) - 0.5.592
Emoji.OFTEN = { key = "often", name = "Haeufig", items = {} }
Emoji.POPULAR = { key = "popular", name = "Beliebt", items = {} }
Emoji.COMBOS = { key = "combos", name = "Kombos", items = {} }
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
            -- Stellvertreter: sieht aus wie das erste Emoji, traegt aber alle Codes
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
    -- 0.5.960: die Gruppe "Meine" (Favoriten, Zuletzt, Haeufig, Beliebt) gibt es in der Auswahl nicht mehr
    local list = {}
    -- 0.5.667: Reiter "Standard" und "Kombos" entfernt, Oasis-Emojis stehen bei den Stickern
    -- 0.5.668: kein eigener Oasis-Reiter mehr - die Rang-Emojis stehen ohnehin in ihren Reitern (Anime, Pepe ...)
    -- 0.5.956: Standard-Emojis sind wieder dabei (Unterreiter "Standard" bei den Stickern) - ohne Gildenmodul gab es sonst gar keine Auswahl
    for _, c in ipairs(Emoji.CATS) do list[#list + 1] = c end
    return list
end
local function buildPicker()
    local f = CreateFrame("Frame", "OasisEmojiPicker", UIParent)
    Emoji.picker = f
    local COLS = 14
    local S = (ns.db and tonumber(ns.db.settings.emojiPickSize)) or 38
    pickerCats()   -- Oasis-/Favoriten-Reiter fuellen, bevor die Zellenzahl feststeht
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
        -- auf UIParent umrechnen, damit die Position beim naechsten Oeffnen stimmt
        local l, t = self:GetLeft(), self:GetTop()
        if l and t and ns.db then ns.db.settings.emojiPos = { "TOPLEFT", l, t } end
    end)
    -- 0.5.590: Glas-Karte (runde Ecken), Deckkraft aus den Einstellungen; Kopf mit leichtem Akzent-Verlauf
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
    -- Kopf wie auf den Oasis-Seiten: Akzentstreifen + Grossbuchstaben
    local title = K.GameHead(f, L["Emojis"], C.accent)
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetWidth(160)
    local close = K.CloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -4, -4)
    -- Einstellungen der Auswahl (Zahnrad neben dem X)
    local gear = CreateFrame("Button", nil, f)
    gear:SetSize(20, 20)
    gear:SetPoint("RIGHT", close, "LEFT", -6, 0)
    gear.icon = K.Glyph(gear, 14, ns.MEDIA .. "icons\\settings", C.muted)
    gear.icon:SetPoint("CENTER")
    gear:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3])
        K.ShowTip(self, { L["Darstellung"], L["Groesse, Transparenz, Verhalten"] })
    end)
    gear:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
    gear:SetScript("OnClick", function() Emoji.ShowPickerOptions() end)
    -- Suche ueber alle Reiter (Kurzcode), Enter = erstes Emoji einfuegen
    f.search = K.Input(f, 150, L["Suchen ..."], function(t)
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
    -- Pfeiltasten im Suchfeld: Auswahl wandert durchs Raster, Enter fuegt ein
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
        -- in den sichtbaren Bereich scrollen
        local row = math.floor((i - 1) / cols)
        local vis = f.visRows or 4
        if row < (f.scroll or 0) then f.scroll = row elseif row >= (f.scroll or 0) + vis then f.scroll = row - vis + 1 end
        for j, b in ipairs(f.cells) do b.kb:SetShown(j == i) end
        f:Layout()
        f:Preview(f.cells[i])
    end)
    f.search:HookScript("OnTabPressed", function()
        -- Tab: naechster Reiter
        local cats = pickerCats()
        for i, c in ipairs(cats) do
            if c.key == f.cat then f:ShowCat(cats[i % #cats + 1].key) break end
        end
    end)
    f.search:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)

    -- 0.5.659: Reiter in 4 Gruppen (Meine / Emojis / Sticker / WoW), darunter die Unterreiter der Gruppe
    -- 0.5.957: Standard-Emojis stehen als erster Unterreiter bei den Stickern (keine eigene Gruppe)
    local GROUP_OF = { fav = "mine", recent = "mine", often = "mine", popular = "mine" }
    local GROUPS = { { key = "sticker", text = L["Emojis"] } }   -- WoW/Raid stehen bei den Stickern
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
    -- Gruppenreiter oben, Unterreiter (falls die Gruppe mehrere hat) darunter - umbrechen, wenn schmal
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
        -- Breite Fenster wie Sounds; schmale Fenster umbrechen die Ziele unter dem Titel.
        local searchY = -34
        local cols = math.max(1, math.min(4, math.floor((W - 20) / 78)))
        for i, b in ipairs(self.chans or {}) do
            b:ClearAllPoints()
            if W >= 550 then
                b:SetPoint("TOPRIGHT", -62 - (4 - i) * 78, -8)
            else
                b:SetPoint("TOPLEFT", 12 + ((i - 1) % cols) * 78, -34 - math.floor((i - 1) / cols) * 24)
            end
        end
        if W < 550 then searchY = -34 - math.ceil(4 / cols) * 24 end
        self.search:ClearAllPoints()
        self.search:SetPoint("TOPLEFT", 12, searchY)
        self.search:SetPoint("TOPRIGHT", -12, searchY)
        local tabsY = searchY - 30
        local y = tabsY - wrap(self.tabs, avail, tabsY) * 24 - 2
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

    -- Zellen (werden je Kategorie neu belegt)
    f.cells = {}
    for i = 1, maxN do
        local b = CreateFrame("Button", nil, f)
        -- Kachel: dezenter Grund, beim Hovern Akzent-Schein
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetPoint("TOPLEFT", 1, -1)
        b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
        b.bg:SetColorTexture(1, 1, 1, 0.035)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetPoint("TOPLEFT", 1, -1)
        b.hl:SetPoint("BOTTOMRIGHT", -1, 1)
        b.hl:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.22)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetPoint("TOPLEFT", 2, -2)
        b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        -- gesperrt: kleines Schloss-Schild mit dem noetigen Oasis-Rang
        -- gesperrt: dunkles Band unten mit Schloss + Rang
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
        -- Favorit: kleiner goldener Stern oben rechts
        b.star = b:CreateTexture(nil, "OVERLAY", nil, 3)
        b.star:SetTexture(ns.MEDIA .. "icons\\star_on")
        b.star:SetVertexColor(1, 0.82, 0.3)
        b.star:SetSize(10, 10)
        b.star:SetPoint("TOPRIGHT", -1, -1)
        b.star:Hide()
        -- Kombo: Anzahl unten rechts (x3)
        b.comboTxt = b:CreateFontString(nil, "OVERLAY", nil, 4)
        K.SetFontSafe(b.comboTxt, K.FONT_HEAD, 10, "OUTLINE", K.FONT)
        b.comboTxt:SetPoint("BOTTOMRIGHT", -2, 2)
        b.comboTxt:SetTextColor(1, 0.85, 0.45)
        -- Tastatur-Auswahl (Pfeiltasten im Suchfeld)
        b.kb = b:CreateTexture(nil, "BACKGROUND", nil, 2)
        b.kb:SetPoint("TOPLEFT", 1, -1) b.kb:SetPoint("BOTTOMRIGHT", -1, 1)
        b.kb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
        b.kb:Hide()
        -- Favoriten umsortieren: im Reiter Favoriten ziehen und auf einem anderen Emoji loslassen
        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self) f:StartDrag(self) end)
        b:SetScript("OnDragStop", function() f:EndDrag() end)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, btn)
            local e = self.entry
            -- Kombo: Rechtsklick loescht sie
            if btn == "RightButton" and e and e.combo then
                Emoji.RemoveCombo(e.comboIdx)
                K.Toast(L["Emojis"], L["Kombo geloescht."], C.dim)
                f:ShowCat("combos", true)
                return
            end
            -- Shift+Klick: Emoji in den Kombo-Baukasten legen (statt einfuegen)
            if btn ~= "RightButton" and IsShiftKeyDown() and e and not e.combo and not e.raid and self.code then
                f:ComboAdd(self.code, self)
                return
            end
            if btn == "RightButton" then
                if not self.favCode then return end
                local on = Emoji.ToggleFav(self.favCode)
                self.star:SetShown(on and true or false)
                -- Stern ploppt auf
                if on and not (ns.db and ns.db.settings.noAnim) then
                    local st = self.star
                    K.Tween(st, 0.35, function(p) local k = 1 + 0.8 * math.sin(p * math.pi) st:SetSize(10 * k, 10 * k) end, function() st:SetSize(10, 10) end)
                end
                if f.cat == "fav" then f:ShowCat("fav", true) end
                return
            end
            if not self.code then return end
            -- kleiner Druck-Effekt auf dem Bild
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
            -- beim Ueberfahren leicht vergroessern + unten gross in der Vorschau zeigen
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
    -- Vorschau beim Ueberfahren: Emoji gross unten links + seine Codes in der Fusszeile
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
        self.foot:SetText("|cffffffff" .. table.concat(codes, "   ") .. "|r   |cff666666" .. L["Rechtsklick: Favorit  ·  Shift+Klick: Kombo"] .. "|r")
    end

    -- Kombo-Baukasten: Shift+Klick sammelt Emojis, dann einfuegen oder als Kombo merken
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
    f.cb.lbl:SetText(L["Kombo:"])
    f.cb.icons = {}
    for i = 1, COMBO_LEN do
        local t = f.cb:CreateTexture(nil, "ARTWORK")
        t:SetSize(22, 22)
        t:SetPoint("LEFT", f.cb.lbl, "RIGHT", 6 + (i - 1) * 24, 0)
        f.cb.icons[i] = t
    end
    f.cb.clear = K.Button(f.cb, "x", 24, 20, "ghost", function() f.combo = {} f:PaintCombo() end)
    f.cb.clear:SetPoint("RIGHT", -4, 0)
    f.cb.save = K.Button(f.cb, L["Merken"], 70, 20, "ghost", function()
        if Emoji.AddCombo(f.combo) then
            K.Toast(L["Emojis"], L["Kombo gemerkt - Reiter Kombos."], C.mint)
            f.combo = {}
            f.needTabs = true
            f:PaintCombo()
            if f.cat == "combos" then f:ShowCat("combos", true) end
        else
            K.Toast(L["Emojis"], L["Eine Kombo braucht mindestens 2 Emojis."], C.dim)
        end
    end)
    f.cb.save:SetPoint("RIGHT", f.cb.clear, "LEFT", -4, 0)
    f.cb.ins = K.Button(f.cb, L["Einfuegen"], 80, 20, "primary", function()
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
        if #self.combo >= COMBO_LEN then K.Toast(L["Emojis"], (L["Hoechstens %d Emojis je Kombo."]):format(COMBO_LEN), C.dim) return end
        self.combo[#self.combo + 1] = code
        self:PaintCombo()
        -- kleines Hochhuepfen des neuen Bildes in der Leiste
        local t = self.cb.icons[#self.combo]
        if t and not (ns.db and ns.db.settings.noAnim) then
            K.Tween(t, 0.25, function(p) local k = 1 + 0.4 * math.sin(p * math.pi) t:SetSize(22 * k, 22 * k) end, function() t:SetSize(22, 22) end)
        end
    end

    -- Favoriten ziehen: Bild folgt der Maus, Loslassen auf einem anderen Favoriten = dorthin verschieben
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
    -- Ziel waehlen wie im Sound-Fenster: Gilde / Gruppe / Raid / letzter Fluesterpartner (in Chatfarben)
    local CHS = { { "GUILD", "Gilde", "/g ", { 0.25, 1, 0.25 } }, { "PARTY", "Gruppe", "/p ", { 0.67, 0.67, 1 } },
        { "RAID", "Raid", "/ra ", { 1, 0.5, 0 } }, { "WHISPER", "Fluestern", nil, { 1, 0.5, 1 } } }
    f.chans = {}
    for i, d in ipairs(CHS) do
        local b = K.Button(f, L[d[2]], 74, 20, "ghost", function()
            local lt = Emoji.lastTarget or {}
            local pre = d[3]
            if d[1] == "WHISPER" then
                local who = (lt.pre and lt.pre:match("^/w (.-) $")) or (ChatEdit_GetLastTellTarget and ns.safe(ChatEdit_GetLastTellTarget()))
                if not who or who == "" then ns.print(L["Noch niemand angefluestert."]) return end
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
    -- Zellengroesse anwenden (Einstellung "Groesse in der Auswahl")
    -- Groesse: Breite/Hoehe aus den Einstellungen (Regler oder Ziehen an der Ecke unten rechts).
    -- Spaltenzahl ergibt sich aus der Breite, was nicht in die Hoehe passt, scrollt per Mausrad.
    function f:Layout()
        local st = ns.db and ns.db.settings or {}
        S = tonumber(st.emojiPickSize) or 38
        -- Reiter brechen bei Bedarf um -> schmal ziehen geht
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
        -- Mindestens eine Rasterzeile bleibt auch unter umgebrochenen Reitern sichtbar.
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
        -- Scroll-Hinweis rechts
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
    -- Ecke unten rechts: ziehen = Groesse aendern (wird gespeichert)
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
            -- Gruppe gewechselt: Unterreiter-Reihe ein-/ausblenden, Raster passt sich an
            if self.shownGroup ~= g then self.shownGroup = g if self.Layout then self:Layout() end end
        end
        -- Suche: Treffer aus allen Reitern (ohne doppelte)
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
                -- Reiterwechsel: Kacheln von oben links nach unten rechts nacheinander einblenden
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
                    -- animiert: Streifen mit Einzelbildern, Ausschnitt wird im OnUpdate weitergeschaltet
                    if e.n and e.n > 1 then
                        b.anim = e
                        b.icon:SetTexCoord(0, 1, 0, 64 / e.h)
                    end
                end
                b.code = e[2]
                local codes = {}
                for j = 2, #e do codes[#codes + 1] = e[j] end
                b.tip = { e[2], (#codes > 1 and (table.concat(codes, "   ") .. "\n") or "") .. L["Klick: einfuegen"] }
                -- besondere Emojis: erst ab einem Oasis-Rang
                local need = ns.Rewards and ns.Rewards.EmojiLevel(e)
                local locked = need and ns.GuildOpt("emLock") ~= false and ns.Rank and ns.Rank.Mine().level < need and not (ns.UnlockAll and ns.UnlockAll())
                b.icon:SetDesaturated(locked and true or false)
                b.icon:SetAlpha(locked and 0.35 or 1)
                b.lockBg:SetShown(locked and true or false)
                b.lockTxt:SetShown(locked and true or false)
                b.lockIcon:SetShown(locked and true or false)
                b.lockTxt:SetText(need or "")
                if locked then
                    b.code = nil
                    b.tip = { e[2], "|cffffd24a" .. (L["Ab Oasis-Rang %d"]):format(need) .. "|r" }
                end
                -- Kombo: alle Codes auf einen Klick
                if e.combo then
                    b.code = table.concat(e.combo, " ")
                    b.favCode = nil
                    b.star:Hide()
                    b.tip = { L["Kombo"], table.concat(e.combo, "  "), "|cff888888" .. L["Klick: alles einfuegen  ·  Rechtsklick: loeschen"] .. "|r" }
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
            self.footDefault = (#items > 0) and (L["%d Treffer"]):format(#items) .. "  ·  " .. L["Enter: erstes einfuegen"] or L["Nichts gefunden."]
        elseif cat.key == "fav" and #items == 0 then
            self.footDefault = L["Rechtsklick auf ein Emoji = Favorit"]
        elseif cat.key == "fav" then
            self.footDefault = L["Favoriten per Ziehen umsortieren  ·  Pfeiltasten + Enter im Suchfeld"]
        elseif cat.key == "combos" then
            self.footDefault = L["Shift+Klick auf Emojis legt sie in den Kombo-Baukasten"]
        elseif cat.key == "popular" then
            self.footDefault = L["Was in den letzten Tagen im Gildenchat am meisten benutzt wurde"]
        else
            self.footDefault = cat.raid and L["Raid-Symbole - sieht jeder, auch ohne Oasis"] or L["sehen alle mit Oasis - ohne Oasis steht dort der Code"]
        end
        self:Preview(nil)
        -- leere Favoriten: Hinweis mitten im Raster
        if not self.emptyTxt then
            self.emptyTxt = K.Text(self, 12, C.dim, "CENTER")
            self.emptyTxt:SetPoint("CENTER", 0, -10)
            self.emptyTxt:SetWidth(260)
            self.emptyTxt:SetWordWrap(true)
        end
        local none = #items == 0
        self.emptyTxt:SetShown(none)
        if none then
            self.emptyTxt:SetText(q ~= "" and L["Nichts gefunden."] or (cat.key == "fav" and L["Noch keine Favoriten.\nRechtsklick auf ein Emoji merkt es hier."])
                or (cat.key == "combos" and L["Noch keine Kombos.\nShift+Klick auf mehrere Emojis, dann Merken."]) or "")
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
-- Einstellungen der Emoji-Auswahl: kleines Fenster rechts an der Auswahl (Schieberegler, Schalter)
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
    t:SetText(L["Darstellung"])
    local x = K.CloseButton(o, function() o:Hide() end)
    x:SetPoint("TOPRIGHT", -4, -4)
    local y = -38
    local function head(text)
        local h = K.GameHead(o, text, C.accent)
        h:SetPoint("TOPLEFT", 12, y)
        h:SetPoint("RIGHT", o, "RIGHT", -12, 0)
        y = y - 24
    end
    -- onRelease: erst beim Loslassen anwenden (Groesse der Auswahl: sonst wandert der Regler unter der Maus weg)
    local function slider(minV, maxV, step, key, def, fmt, apply, onRelease)
        local sl = K.Slider(o, 226, minV, maxV, step,
            function() return tonumber(st[key]) or def end,
            function(v) st[key] = v if apply then apply(v) end end, fmt, onRelease)
        sl:SetPoint("TOPLEFT", 12, y)
        y = y - 34
        return sl
    end
    head(L["Hintergrund"])
    o.alpha = slider(0.3, 1, 0.05, "emojiAlpha", 0.8, function(v) return math.floor(v * 100 + 0.5) .. " %" end,
        function() if picker then picker:ApplyAlpha() end end)
    head(L["Groesse in der Auswahl"])
    o.pick = slider(28, 56, 2, "emojiPickSize", 38, function(v) return v .. " px" end, nil,
        function() if picker then picker:Layout() end end)
    head(L["Fenstergroesse"])
    o.w = slider(220, 1200, 10, "emojiW", 14 * 38 + 20, function(v) return (L["Breite %d"]):format(v) end, nil,
        function() if picker then picker:Layout() end end)
    o.h = slider(170, 900, 10, "emojiH", 330, function(v) return (L["Hoehe %d"]):format(v) end, nil,
        function() if picker then picker:Layout() end end)
    head(L["Groesse im Chat"])
    o.chat = slider(0, 36, 2, "emojiChatSize", 0, function(v) return v == 0 and L["Auto"] or (v .. " px") end)
    o.close = K.Toggle(o, L["Nach Auswahl schliessen"], function() return st.emojiClose and true or false end,
        function(v) st.emojiClose = v and true or false end)
    o.close:SetWidth(226)
    o.close:SetPoint("TOPLEFT", 12, y - 4)
    -- Nachricht abgeschickt: Auswahl zu (an) oder offen lassen (aus)
    o.sendClose = K.Toggle(o, L["Nach dem Senden schliessen"], function() return st.emojiCloseOnSend ~= false end,
        function(v) st.emojiCloseOnSend = v and true or false end)
    o.sendClose:SetWidth(226)
    o.sendClose:SetPoint("TOPLEFT", 12, y - 32)
    o:SetHeight(462)
    o.clearFav = K.Button(o, L["Favoriten leeren"], 226, 24, "ghost", function()
        st.emojiFav = {}
        if picker and picker:IsShown() then picker:ShowCat(picker.cat or "std", true) end
        K.Toast(L["Emojis"], L["Favoriten geleert."], C.mint)
    end)
    o.clearFav:SetPoint("BOTTOMLEFT", 12, 42)
    o.clear = K.Button(o, L["Zuletzt benutzte leeren"], 226, 24, "ghost", function()
        st.emojiRecent = {}
        if picker then picker.needRebuild = true end
        K.Toast(L["Emojis"], L["Zuletzt benutzte geleert."], C.mint)
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
    -- "Zuletzt"-Reiter kommt neu dazu -> Reiterleiste neu aufbauen
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
    picker.tabSig = sig
    if picker:IsShown() then picker:Hide() return end
    Emoji.RememberTarget()
    picker:ClearAllPoints()
    local pos = ns.db and ns.db.settings.emojiPos
    if pos then
        -- selbst verschoben: dort wieder oeffnen
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

------------------------------------------------------------------------
-- Knopf im Chat-Eingabefeld
------------------------------------------------------------------------
local buttons = {}
-- Alt+Leertaste in einer Eingabe oeffnet/schliesst die Emoji-Auswahl
-- (nur angehaengt per HookScript - Blizzards Eingabe selbst wird nicht veraendert)
local hotkeyDone = setmetatable({}, { __mode = "k" })   -- statt Feld an Blizzards Chat-Eingabe
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
    -- nesUI hat eigene Sound-/Emoji-Knoepfe in der Chat-Leiste -> hier nicht doppelt zeigen
    if _G.nesUI then on = false end
    for _, b in pairs(buttons) do b:SetShown(on) end
end
local function attach(eb)
    if not eb or buttons[eb] then return end
    local b = CreateFrame("Button", nil, eb)
    b:SetSize(16, 16)
    b:SetPoint("RIGHT", eb, "RIGHT", -6, 0)
    b:SetFrameLevel(eb:GetFrameLevel() + 5)
    b:SetHitRectInsets(-5, -3, -6, -6)   -- groessere Klickflaeche als das 16-px-Symbol (war schwer zu treffen)
    -- schlichtes, einfarbiges Symbol wie in der Oasis-Seitenleiste (gleich gross wie der Sound-Knopf)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(ns.MEDIA .. "icons\\smile")
    b.icon:SetVertexColor(0.6, 0.6, 0.62)
    b:SetScript("OnEnter", function(self)
        Emoji.RememberTarget(eb)
        self.icon:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
        K.ShowTip(self, { L["Emojis"], L["Klick: Auswahl oeffnen"], "|cff888888" .. L["Im Chat: Alt+Leertaste"] .. "|r" })
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.6, 0.6, 0.62)
        GameTooltip:Hide()
    end)
    -- wie Alt+Leertaste: Ziel merken (Maus runter = Eingabe hat noch den Fokus) und genau diese Eingabe nehmen
    b:SetScript("OnMouseDown", function()
        Emoji.RememberTarget(eb)
        -- leere Eingabe macht WoW beim Klick ganz zu (mit Text nicht) -> kurz ein Leerzeichen hineinsetzen,
        -- das beim Wiederoeffnen wieder verschwindet (gemerkter Text ist leer)
        if eb:IsShown() and eb.HasFocus and eb:HasFocus() and (ns.safe(eb:GetText()) or "") == "" then
            eb:Insert(" ")
        end
    end)
    b:SetScript("OnClick", function(self)
        Emoji.RememberTarget(eb)
        Emoji.target = eb
        Emoji.TogglePicker(self)
        -- einen Moment spaeter (WoW hat die Eingabe dann schon zugemacht) wieder oeffnen
        C_Timer.After(0.05, function() pcall(Emoji.RestoreChat) end)
        -- leere Eingabe schliesst WoW manchmal erst etwas spaeter -> zur Sicherheit nochmal pruefen
        C_Timer.After(0.25, function() pcall(Emoji.RestoreChat) end)
    end)
    buttons[eb] = b
    -- daneben: Sound schicken
    local sb = CreateFrame("Button", nil, b)   -- an den Emoji-Knopf gehaengt: mit ihm ein-/ausgeblendet
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
        K.ShowTip(self, { L["Sound schicken"], L["Alle mit Oasis hoeren ihn - hoechstens alle 30 Sekunden."] })
    end)
    sb:SetScript("OnLeave", function(self) self.icon:SetVertexColor(0.6, 0.6, 0.62) GameTooltip:Hide() end)
    -- wie beim Emoji-Knopf: Ziel + angefangenen Text merken, BEVOR WoW die Eingabe beim Klick schliesst
    -- (vorher wurde erst nach dem Schliessen gelesen -> Fluestern/Gruppe fiel teils auf Gilde zurueck,
    -- und der Chat blieb fuer Gilde zu, angefangener Text war weg)
    sb:SetScript("OnMouseDown", function(self) Emoji.SoundButtonDown(self, eb) end)
    sb:SetScript("OnClick", function(self) Emoji.SoundButtonClick(self, eb) end)
    b.snd = sb
    -- Abklingzeit sichtbar (0.5.592)
    if ns.Sound and ns.Sound.AttachCooldown then pcall(ns.Sound.AttachCooldown, sb) end
end
-- Vorschau ueber der Chat-Eingabe: WoW kann im Eingabefeld keine Bilder zeigen, Kurzcodes bleiben dort Text.
-- Darum zeigt eine kleine Leiste darueber, wie die Nachricht mit Emojis aussehen wird.
-- 0.5.518: nur kurz, wenn gerade ein Emoji erkannt wurde - und nur die Emojis, nicht die ganze Nachricht.
-- Weitertippen (ohne neues Emoji) blendet sie aus; nach 2,5 s verschwindet sie von selbst.
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
        -- kein neues Emoji: weitergeschrieben -> Vorschau weg
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
    -- Vorschlagsliste (:th... Tab) liegt an derselben Stelle -> Vorschau dann darueber
    local pop = _G.OasisEmojiComplete
    local anchor = (pop and pop:IsShown()) and pop or eb
    f:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    -- nur die Emojis der Nachricht (hoechstens 12), das neueste zuletzt
    local first = math.max(1, #icons - 11)
    local list = {}
    for i = first, #icons do list[#list + 1] = icons[i] end
    f.t:SetText("|cff888888" .. L["Emoji erkannt"] .. "|r   " .. table.concat(list, " "))
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
        -- WoW-Chat: Pfeil hoch/runter holt die letzten Nachrichten auch OHNE Alt zurueck (abschaltbar: settings.chatArrowAlt)
        if fresh and eb.SetAltArrowKeyMode and not (ns.db and ns.db.settings.chatArrowAlt) then pcall(eb.SetAltArrowKeyMode, eb, false) end
        -- Chat-Ziel direkt an der Eingabe mitschreiben (Wechsel per /p, /w, Klick ...), nur solange getippt wird
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
            -- Enter = Nachricht abgeschickt: Auswahl je nach Einstellung schliessen oder offen lassen
            eb:HookScript("OnEnterPressed", function()
                if ns.db and ns.db.settings.emojiCloseOnSend ~= false and picker and picker:IsShown() then picker:Hide() end
            end)
        end
    end
    Emoji.UpdateButtons()
end

------------------------------------------------------------------------
-- Sprechblasen ueber den Koepfen: Kurzcodes auch dort als Emoji zeigen.
-- Blizzard zeichnet die Blasen selbst; ausserhalb von Instanzen duerfen Addons ihren Text aendern
-- (in Instanzen sind die Blasen gesperrt - dort bleibt der Text, wie er ist).
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
    -- neuere Clients: Kind-Frame mit .String
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
        -- die Blase entsteht erst kurz nach dem Ereignis
        ns.After(0.05, fixBubbles)
        ns.After(0.25, fixBubbles)
    end)
end

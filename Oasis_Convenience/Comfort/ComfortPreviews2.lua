-- Oasis - Comfort: previews for the tabs rebuilt in tiles (0.6.653): game chat, everyday helpers, item tooltips, bars.
-- Same pattern as ComfortPreviews.lua: build(frame) once, update(frame) after every change, FOCUS2 = part a switch changes.
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
local L = ns.L
local K, C = ns.K, ns.K.C
local PREV = ns.ComfortPreviews
if not (K and PREV) then return end

local function S() return ns.db.settings end
local function on(k) return S()[k] and true or false end
local function panel(parent, w, h, x, y, color)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f:SetPoint("TOPLEFT", x, y)
    f.bg = K.Fill(f, color or { 0.05, 0.05, 0.07, 0.95 })
    K.Border(f, C.line)
    return f
end
local function text(parent, size, col, x, y, s)
    local t = K.Text(parent, size, col or C.text)
    t:SetPoint("TOPLEFT", x, y)
    if s then t:SetText(s) end
    return t
end
local function icon(parent, size, tex, x, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetPoint("TOPLEFT", x, y)
    if tex then t:SetTexture(tex) end
    return t
end
local function caption(f)
    local t = K.Text(f, 10, C.dim)
    t:SetPoint("BOTTOMLEFT", 2, 4)
    t:SetPoint("RIGHT", f, "RIGHT", -4, 0) t:SetJustifyH("LEFT") t:SetWordWrap(true)
    local txt = L["Move the mouse over an option - the part it changes is framed here"]
    t:SetText(txt)
    f._cap, f._capText = t, txt
    return t
end
local function lines(f, n, x, y, step, size)
    local out = {}
    for i = 1, n do
        out[i] = text(f, size or 11, C.text, x, y - (i - 1) * (step or 18))
        out[i]:SetPoint("RIGHT", f, "RIGHT", -6, 0) out[i]:SetJustifyH("LEFT") out[i]:SetWordWrap(false)
    end
    return out
end
local function onoff(k, yes, no) return on(k) and ("|cff7fd77f" .. L[yes] .. "|r") or ("|cff888888" .. L[no] .. "|r") end
local function compact(list)
    local out = {}
    for _, l in ipairs(list) do if l and l ~= "" then out[#out + 1] = l end end
    return out
end

-- game chat: a chat window
local function chatWindow(f)
    f.win = panel(f, 250, 150, 0, 0, { 0, 0, 0, 0.55 })
    f.l = lines(f.win, 6, 6, -6, 22)
    caption(f)
end
local function chatLine(ch, lvl, cls, name, msg, chColor)
    local nm = name
    if on("gcShort") then nm = nm:match("^(%S+)") or nm end
    local parts = {}
    if on("gcClassIcon") then parts[#parts + 1] = "|TInterface\\Icons\\ClassIcon_" .. cls .. ":12|t" end
    if on("gcLevel") then parts[#parts + 1] = "|cff40c040" .. lvl .. "|r" end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls:upper()]
    local nameTxt = (c and on("cpChatLinks")) and ("|c" .. (c.colorStr or "ffffffff") .. nm .. "|r") or nm
    parts[#parts + 1] = "[" .. nameTxt .. "]"
    local num = ch:match("^%[(%d+)%.")
    local chName = (on("gcChNum") and num) and ("[" .. num .. "]") or ch
    local body = on("gcQuiet") and ("|cffbbbbbb" .. msg .. "|r") or msg
    return chColor .. chName .. "|r " .. table.concat(parts, " ") .. ": " .. body
end
local function setLines(f, list) for i, t in ipairs(f.l) do t:SetText(list[i] or "") end end

PREV.chatmain = {
    build = chatWindow,
    update = function(f)
        if not on("gcOn") then
            setLines(f, { "|cff888888" .. L["Blizzard chat, unchanged"] .. "|r", "", "", "", on("cfChatTop") and ("|cffd8b04a" .. L["Input line above the chat"] .. "|r") or "" })
            return
        end
        setLines(f, {
            chatLine("[Guild]", 23, "Warrior", "Mira Stern", "who's up for Deadmines?", "|cff40ff40"),
            on("gcAllChannels") and chatLine("[2. Trade - Orgrimmar]", 31, "Mage", "Tomas Berg", "selling ore", "|cffffc0c0")
                or ("|cff666666[2. Trade] ... " .. L["(untouched)"] .. "|r"),
            chatLine("[Party]", 22, "Priest", "Lia Moor", "ready", "|cffaaaaff"),
            on("gcLiveSelect") and ("|cff7fd77f" .. L["Drag to select, Ctrl+C copies"] .. "|r") or "",
            on("cfChatTop") and ("|cffd8b04a" .. L["Input line above the chat"] .. "|r") or "",
            on("emojiNoComplete") and ("|cff888888" .. L["No emoji suggestions"] .. "|r") or "",
        })
    end,
}
PREV.chatnames = {
    build = chatWindow,
    update = function(f)
        if not on("gcOn") then setLines(f, { "|cff888888" .. L["Master switch is off"] .. "|r" }) return end
        setLines(f, {
            chatLine("[Guild]", 23, "Warrior", "Mira Stern", "LFM Deadmines", "|cff40ff40"),
            chatLine("[2. Trade - Orgrimmar]", 31, "Mage", "Tomas Berg", on("gcLinkIcons") and "|TInterface\\Icons\\INV_Ore_Copper_01:12|t [Copper Ore]" or "[Copper Ore]", "|cffffc0c0"),
            chatLine("[Party]", 22, "Priest", "Lia Moor", on("gcTokens") and "|TInterface\\Icons\\ClassIcon_Mage:12|t ready" or ":mage: ready", "|cffaaaaff"),
            on("gcHover") and ("|cff7fd77f" .. L["Tooltip on hovering a link"] .. "|r") or "",
        })
    end,
}
PREV.chatfilter = {
    build = chatWindow,
    update = function(f)
        local fil = on("gcOn") and on("gcFilter")
        setLines(f, compact({
            "|cffffc0c0[2. Trade]|r [Tomas]: selling ore",
            (fil and on("gcCyr")) and "" or "|cffffc0c0[2. Trade]|r [Ivan]: продаю руду",
            (fil and on("gcHan")) and "" or "|cffffc0c0[2. Trade]|r [Li]: ore",
            "|cffffc0c0[2. Trade]|r [Bob]: WTS boost",
            (fil and on("gcRepeat")) and "" or "|cffffc0c0[2. Trade]|r [Bob]: WTS boost",
            "|cff40ff40[Guild]|r [Mira]: " .. L["never filtered"],
        }))
    end,
}
PREV.chathist = {
    build = chatWindow,
    update = function(f)
        setLines(f, compact({
            on("gcHist") and ("|cff888888-- " .. L["yesterday"] .. " --|r") or "",
            on("gcHist") and "|cff40ff40[Guild]|r [Mira]: gn8" or "",
            "|cffffc0c0[2. Trade]|r [Tomas]: LF healer for Deadmines",
            on("gcAlert") and ("|cffffd100>> " .. L["Keyword alert: healer"] .. "|r") or "",
            (on("gcAlert") and on("gcAlertSound")) and ("|cff888888" .. L["(with sound)"] .. "|r") or "",
        }))
    end,
}

-- everyday helpers
PREV.road = {
    build = function(f)
        f.box = panel(f, 250, 248, 0, 0)
        f.l = lines(f.box, 12, 8, -8, 19, 10)
        caption(f)
    end,
    update = function(f)
        setLines(f, {
            onoff("cpXP", "12.4k XP/h - 38 min to level 24", "No XP bar"),
            onoff("cpXPShare", "Guild: ~40 min to level 30", "No milestone message"),
            onoff("cpFlight", "Flight: 1:42 left", "No flight timer"),
            onoff("cpTracking", "After dying: [Find Herbs] back on", "Tracking stays off after dying"),
            onoff("cpInstances", "Instances this hour: 3/5", "No instance counter"),
            onoff("cpTrainer", "Level 24: 3 new spells (1g 20s)", "No trainer hint"),
            onoff("cpReagents", "Only 18 arrows left!", "No supply warning"),
            onoff("cpPet", "Pet is hungry", "No pet warning"),
            onoff("cpMail", "Mailbox: [Open all]", "Open mail one by one"),
            onoff("cfFastLoot", "Loot taken at once", "Normal looting"),
            onoff("cfDurability", "Gear at 18 % - repair soon", "No durability warning"),
            onoff("cpFishing", "Fishing: double right-click casts", "Fishing: from the action bar"),
        })
    end,
}
PREV.groupguild = {
    build = function(f)
        f.box = panel(f, 250, 170, 0, 0)
        f.l = lines(f.box, 7, 8, -8, 22, 10)
        caption(f)
    end,
    update = function(f)
        setLines(f, {
            onoff("cfBlockDuels", "Duel from Grok: declined", "Duel from Grok: asks you"),
            onoff("cfInvites", "Invite from a stranger: declined", "Invite from a stranger: asks you"),
            onoff("cfWhisperInv", "Mira whispers 'inv' - invited", "No invite by whisper"),
            onoff("cpQuestShare", "Lia: Wolves 6/8 (in her tooltip)", "No group quest progress"),
            onoff("cpProfCD", "Transmute ready: Tomas", "No profession cooldowns"),
            onoff("cpRare", "Rare nearby: Bjarn!", "No rare alert"),
            onoff("cpRareShare", "Guild sees: Bjarn in Dun Morogh", "Rares stay private"),
        })
    end,
}
-- item tooltips: an item tooltip and a bag slot
PREV.itemtips = {
    build = function(f)
        f.tt = panel(f, 240, 150, 0, 0, { 0.03, 0.03, 0.05, 0.92 })
        f.name = text(f.tt, 12, { 0.12, 1, 0 }, 10, -8, L["Sturdy Sword"])
        f.arrow = icon(f.tt, 14, "Interface\\Icons\\INV_Misc_ArrowUp", 214, -8)
        f.l = lines(f.tt, 6, 10, -30, 18, 10)
        f.bagIcon = icon(f, 32, "Interface\\Icons\\INV_Sword_04", 10, -160)
        f.bagArrow = icon(f, 14, "Interface\\Icons\\INV_Misc_ArrowUp", 30, -160)
        caption(f)
    end,
    update = function(f)
        f.arrow:SetShown(not on("upgradeTipOff"))
        f.bagArrow:SetShown(not on("upgradeIconOff"))
        setLines(f, compact({
            on("cpTooltip") and ("|cffffffff" .. L["Item level"] .. " 24  ·  ID 2488|r") or "",
            on("cpTooltip") and ("|cffffd100" .. L["Sells for"] .. " 35s|r") or "",
            on("cpDisenchant") and ("|cff8080ff" .. L["Disenchants into: Strange Dust"] .. "|r") or "",
            (not on("invTooltipOff")) and ("|cff888888" .. L["Your characters: Lia 1, bank 2"] .. "|r") or "",
            on("cpInspect") and ("|cffffffff" .. L["Inspected: item level 26 (+2 over you)"] .. "|r") or "",
            on("cpTooltipGuild") and ("|cff66db9e" .. L["Guild: officer, alt of Mira"] .. "|r") or "",
        }))
    end,
}
-- bars & window: the bottom of the screen
PREV.bars = {
    build = function(f)
        f.screen = panel(f, 250, 200, 0, 0, { 0.08, 0.1, 0.08, 0.9 })
        f.err = text(f.screen, 12, { 1, 0.15, 0.15 }, 40, -30, L["Not enough rage"])
        f.act = {}
        for i = 1, 6 do f.act[i] = icon(f.screen, 22, "Interface\\Icons\\Ability_Warrior_Charge", 30 + (i - 1) * 30, -140) end
        f.micro = {}
        for i = 1, 6 do f.micro[i] = icon(f.screen, 16, "Interface\\Icons\\INV_Misc_Gear_01", 8 + (i - 1) * 18, -176) end
        f.bags = {}
        for i = 1, 4 do f.bags[i] = icon(f.screen, 16, "Interface\\Icons\\INV_Misc_Bag_10", 168 + (i - 1) * 18, -176) end
        f.hint = text(f, 10, C.dim, 0, -206)
        caption(f)
    end,
    update = function(f)
        f.err:SetShown(not on("cfHideErrors"))
        local hov = on("cfBarsHover")
        for _, t in ipairs(f.micro) do t:SetAlpha(on("cfHideMicro") and (hov and 0.25 or 0) or 1) end
        for _, t in ipairs(f.bags) do t:SetAlpha(on("cfHideBags") and (hov and 0.25 or 0) or 1) end
        for i, t in ipairs(f.act) do if on("cpRange") and i <= 2 then t:SetVertexColor(1, 0.3, 0.3) else t:SetVertexColor(1, 1, 1) end end
        f.hint:SetText(((on("cfHideMicro") or on("cfHideBags")) and hov) and L["Faint: shows when the mouse is over it"] or "")
    end,
}

local function li(n) return function(f) return f.l and f.l[n] end end
PREV.FOCUS2 = {
    gcOn = "win", gcAllChannels = li(2), gcLiveSelect = li(4), gcAltSelect = li(4), cfChatTop = li(5), emojiNoComplete = li(6),
    cpChatLinks = "win", cfChatArrows = "win", cfChatNoFade = "win", cfChatRestore = "win",
    gcShort = "win", gcLevel = "win", gcClassIcon = "win", gcRaceIcon = "win", gcLinkIcons = li(2), gcTokens = li(3),
    gcChNum = li(2), gcQuiet = "win", gcHover = li(4),
    gcFilter = "win", gcWhole = "win", gcCyr = "win", gcHan = "win", gcRepeat = "win",
    gcHist = li(1), gcAlert = "win", gcAlertSound = "win",
    cpXP = li(1), cpXPShare = li(2), cpFlight = li(3), cpTracking = li(4), cpInstances = li(5), cpTrainer = li(6),
    cpReagents = li(7), cpPet = li(8), cpMail = li(9), cfFastLoot = li(10), cfDurability = li(11), cpFishing = li(12),
    cfBlockDuels = li(1), cfInvites = li(2), cfWhisperInv = li(3), cpQuestShare = li(4), cpProfCD = li(5), cpRare = li(6), cpRareShare = li(7),
    cpTooltip = "tt", cpDisenchant = "tt", cpTooltipGuild = "tt", cpInspect = "tt", upgradeTipOff = "arrow", upgradeIconOff = "bagIcon", invTooltipOff = "tt",
    cfHideMicro = function(f) return f.micro and f.micro[1] end, cfHideBags = function(f) return f.bags and f.bags[1] end,
    cfBarsHover = "screen", cfHideErrors = "err", cpRange = function(f) return f.act and f.act[1] end,
    cfQuests = "log", cfSummon = "e3", cfBlockShared = "log",
    cfSellJunk = "bag", cfRepair = "m1", cfRepairGuild = "m1", cpReagBuy = "pop1",
}

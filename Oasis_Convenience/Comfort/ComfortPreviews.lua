-- Oasis - Comfort: live previews for the settings pages (0.6.612). Every tab with switches gets a small mock-up on the
-- left that changes the moment a switch or slider moves: tooltip, quest log, vendor, bags, minimap, chat, sounds ...
-- ComfortSettings.lua calls PREV[tab].build(frame) once and PREV[tab].update(frame) after every change.
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
local L = ns.L
local K, C = ns.K, ns.K.C
if not K then return end

local PREV = {}
ns.ComfortPreviews = PREV
local function S() return ns.db.settings end
local function on(k) return S()[k] and true or false end
local function onD(k) return S()[k] ~= false end   -- on by default

-- helpers ---------------------------------------------------------------
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
local function caption(f, s)
    local t = K.Text(f, 10, C.dim)
    t:SetPoint("BOTTOMLEFT", 2, 4)
    t:SetPoint("RIGHT", f, "RIGHT", -4, 0) t:SetJustifyH("LEFT") t:SetWordWrap(true)
    local txt = s or L["Move the mouse over an option - the part it changes is framed here"]
    t:SetText(txt)
    f._cap, f._capText = t, txt
    return t
end

-- 0.6.649: hovering a switch frames the part of the preview it changes and says what it does
local FOCUS = {
    twQuestLevel = "log", twTaxi = "e1", twTrainAll = "e2", twBgRelease = "e3", twLootSparkle = "e3", cfQuestPlates = "e3", cfQuestTarget = "e3",
    twJunkMark = "bag", twGear = "bag", cfDestroyCheap = "bag", cfOpenButton = "bag", cfRestockOn = "pop1", cfAmmo = "pop2", twAhIlvl = "ah",
    cfLootConfirm = "m1", cfEasyDestroy = "m2",
    twTipClass = "name", twTipBar = "bar", cfTipRank = "guild", cfTipTarget = "tgt", cfTipCombat = "combat", cfTipFaction = "tt",
    cfSquareMap = "map", cfMapButtons = "map", twCamera = "cam", twNoGlow = "glow",
    cfNoCombatTab = function(f) return f.tabs and f.tabs[2] end, cfNoChatButtons = function(f) return f.btns and f.btns[1] end, cfSpamFilter = "win",
    whisperForward = "offer",
    cfMuteChimes = function(f) return f.rows and f.rows[1] and f.rows[1].t end, cfMuteFizzle = function(f) return f.rows and f.rows[2] and f.rows[2].t end,
    cfMuteTrains = function(f) return f.rows and f.rows[3] and f.rows[3].t end, cfMuteYawns = function(f) return f.rows and f.rows[4] and f.rows[4].t end,
}
function PREV.Focus(f, key, title, desc)
    if not f then return end
    if not f._hi then
        local h = CreateFrame("Frame", nil, f)
        h:SetFrameLevel((f:GetFrameLevel() or 1) + 30)
        h.l = {}
        for i = 1, 4 do h.l[i] = h:CreateTexture(nil, "OVERLAY") h.l[i]:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.95) end
        h.l[1]:SetPoint("TOPLEFT") h.l[1]:SetPoint("TOPRIGHT") h.l[1]:SetHeight(2)
        h.l[2]:SetPoint("BOTTOMLEFT") h.l[2]:SetPoint("BOTTOMRIGHT") h.l[2]:SetHeight(2)
        h.l[3]:SetPoint("TOPLEFT") h.l[3]:SetPoint("BOTTOMLEFT") h.l[3]:SetWidth(2)
        h.l[4]:SetPoint("TOPRIGHT") h.l[4]:SetPoint("BOTTOMRIGHT") h.l[4]:SetWidth(2)
        h:Hide()
        f._hi = h
    end
    if not key then
        f._hi:Hide()
        if f._cap then f._cap:SetText(f._capText or "") f._cap:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
        return
    end
    local target = FOCUS[key] or (PREV.FOCUS2 and PREV.FOCUS2[key])
    if type(target) == "function" then target = target(f) elseif type(target) == "string" then target = f[target] end
    if target and target.GetObjectType then
        f._hi:ClearAllPoints()
        f._hi:SetPoint("TOPLEFT", target, "TOPLEFT", -4, 4)
        f._hi:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 4, -4)
        f._hi:Show()
    else
        f._hi:Hide()
    end
    if f._cap then
        f._cap:SetText((title or "") .. (desc and desc ~= "" and (": " .. desc) or ""))
        f._cap:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end
end
PREV.HINT = "Move the mouse over an option - the part it changes is framed here"
local CLASS = RAID_CLASS_COLORS and RAID_CLASS_COLORS.MAGE or { r = 0.25, g = 0.78, b = 0.92 }

------------------------------------------------------------------------
-- quests: quest log lines, Forever quest, reward choice, flight master, trainer, sparkle
------------------------------------------------------------------------
PREV.quests = {
    build = function(f)
        f.log = panel(f, 250, 112, 0, 0)
        text(f.log, 11, C.amber or C.accent, 8, -6, L["Quest log"])
        f.q = {}
        local Q = { { "Wolves Across the Border", 12 }, { "The Forgotten Pools", 13, forever = true }, { "Raptor Thieves", 15 } }
        for i, q in ipairs(Q) do
            f.q[i] = text(f.log, 11, C.text, 10, -10 - i * 20)
            f.q[i].d = q
        end
        f.auto = text(f.log, 10, C.dim, 10, -92)
        f.rew = panel(f, 250, 70, 0, -120)
        text(f.rew, 11, C.amber or C.accent, 8, -6, L["Quest reward"])
        f.items = {}
        local R = { { 135147, L["Better"] }, { 133784, "1g 20s" }, { 135130, "35s" } }
        for i, r in ipairs(R) do
            local b = icon(f.rew, 30, r[1], 10 + (i - 1) * 78, -26)
            local m = f.rew:CreateTexture(nil, "OVERLAY")
            m:SetPoint("TOPLEFT", b, -3, 3) m:SetPoint("BOTTOMRIGHT", b, 3, -3)
            m:SetColorTexture(1, 0.82, 0, 0.35) m:Hide()
            b.mark = m
            text(f.rew, 9, C.dim, 44 + (i - 1) * 78, -34, r[2])
            f.items[i] = b
        end
        f.plate = panel(f, 250, 26, 0, -198 + 70)
        f.plate:Hide()
        f.extra = panel(f, 250, 64, 0, -198)
        f.e1 = text(f.extra, 10, C.text, 8, -6)
        f.e2 = text(f.extra, 10, C.text, 8, -22)
        f.e3 = text(f.extra, 10, C.text, 8, -38)
        caption(f)
    end,
    update = function(f)
        local mode = S().cfForeverQuests or 3
        for _, t in ipairs(f.q) do
            local q = t.d
            local title = on("twQuestLevel") and ("[" .. q[2] .. "] " .. L[q[1]]) or L[q[1]]
            if q.forever then title = "|cff6fb7ff" .. title .. "|r  |cff6fb7ff" .. L["NEW"] .. "|r" end
            t:SetText(title)
        end
        f.auto:SetText(on("cfQuests") and ((mode == 1 and L["Forever quests: you read them yourself"]) or (mode == 2 and L["Forever quests: only turned in"]) or L["Forever quests: accepted and turned in"])
            or L["Quest automation is off (Helpers)"])
        local pick = S().cfRewardPick or 1
        for i, b in ipairs(f.items) do b.mark:SetShown((pick == 2 and i == 1) or (pick == 3 and i == 2)) end
        f.e1:SetText(on("twTaxi") and ("|cff7fd77f" .. L["Flight master: flight map opens at once"] .. "|r") or ("|cff888888" .. L["Flight master: you talk first"] .. "|r"))
        f.e2:SetText(on("twTrainAll") and ("|cff7fd77f" .. L["Trainer: \"Train all\" button"] .. "|r") or ("|cff888888" .. L["Trainer: learn one by one"] .. "|r"))
        f.e3:SetText((on("twBgRelease") and ("|cff7fd77f" .. L["Battleground: released at once"] .. "|r  ") or "")
            .. (on("twLootSparkle") and ("|cffffd100" .. L["Quest items sparkle"] .. "|r  ") or "")
            .. (on("cfQuestPlates") and ("|cffffd100" .. L["Nameplate: ! 3/8"] .. "|r  ") or "")
            .. (on("cfQuestTarget") and ("|cff7fd77f" .. L["Quest enemy key"] .. "|r") or ""))
    end,
}

------------------------------------------------------------------------
-- vendor & bags: bag slots with junk coin / gear dots, restock popup, quiver, AH row, delete box
------------------------------------------------------------------------
PREV.vendor = {
    build = function(f)
        f.bag = panel(f, 250, 92, 0, 0)
        text(f.bag, 11, C.amber or C.accent, 8, -6, L["Bags"])
        local items = { 135140, 133784, 135147, 132889, 135130, 134937 }
        f.slots = {}
        for i, tex in ipairs(items) do
            local s = icon(f.bag, 32, tex, 10 + (i - 1) * 38, -26)
            s.coin = icon(f.bag, 12, "Interface\\MoneyFrame\\UI-CopperIcon", 0, 0)
            s.coin:ClearAllPoints() s.coin:SetPoint("TOPLEFT", s, 1, -1)
            s.dot = f.bag:CreateTexture(nil, "OVERLAY")
            s.dot:SetSize(7, 7) s.dot:SetPoint("TOPRIGHT", s, -1, -1) s.dot:SetColorTexture(1, 1, 1, 1)
            f.slots[i] = s
        end
        f.hint = text(f.bag, 9, C.dim, 10, -66)
        f.pop = panel(f, 250, 46, 0, -100)
        f.pop1 = text(f.pop, 10, C.text, 8, -6)
        f.pop2 = text(f.pop, 10, C.text, 8, -24)
        f.ah = panel(f, 250, 40, 0, -154)
        icon(f.ah, 24, 135147, 8, -8)
        f.ahName = text(f.ah, 11, { 0.12, 1, 0 }, 40, -6, L["Sturdy Sword"])
        f.ahLvl = text(f.ah, 11, C.amber or C.accent, 210, -12)
        f.misc = panel(f, 250, 44, 0, -202)
        f.m1 = text(f.misc, 10, C.text, 8, -6)
        f.m2 = text(f.misc, 10, C.text, 8, -24)
        caption(f)
    end,
    update = function(f)
        local junk, gear = on("twJunkMark"), on("twGear")
        local cols = { { 0.95, 0.35, 0.3 }, { 0.45, 0.65, 1 } }
        for i, s in ipairs(f.slots) do
            s.coin:SetShown(junk and (i == 2 or i == 4))
            local c = gear and (i == 3 and cols[1] or i == 5 and cols[2])
            if c then s.dot:SetVertexColor(c[1], c[2], c[3]) s.dot:Show() else s.dot:Hide() end
        end
        f.hint:SetText((junk and L["Alt+right-click: junk"] or "") .. ((junk and gear) and "   " or "") .. (gear and L["Ctrl+right-click: group"] or ""))
        f.pop1:SetText(on("cfRestockOn") and L["\"Restock 20x Water for 1s 25c?\""] or ("|cff888888" .. L["No restock question"] .. "|r"))
        f.pop2:SetText(on("cfAmmo") and L["\"Fill your quiver: 600 x Sharp Arrow?\""] or ("|cff888888" .. L["Quiver stays as it is"] .. "|r"))
        f.ahLvl:SetText(on("twAhIlvl") and "27" or "")
        f.m1:SetText(on("cfLootConfirm") and ("|cff7fd77f" .. L["Bind-on-pickup loot: taken without asking"] .. "|r") or ("|cff888888" .. L["Bind-on-pickup loot: you confirm"] .. "|r"))
        f.m2:SetText(on("cfEasyDestroy") and ("|cff7fd77f" .. L["Delete: the word is filled in"] .. "|r") or ("|cff888888" .. L["Delete: you type the word"] .. "|r"))
        f.hint:SetText(f.hint:GetText() .. ((on("cfDestroyCheap") and ("   |cffff9050" .. L["full -> cheapest?"] .. "|r")) or "") .. ((on("cfOpenButton") and ("   |cff7fd77f" .. L["[Open]"] .. "|r")) or ""))
    end,
}

------------------------------------------------------------------------
-- tooltips: a unit tooltip that follows every switch
------------------------------------------------------------------------
PREV.tooltips = {
    -- 0.6.638: looks like the game's tooltip - its border and background, its fonts and its line order
    build = function(f)
        f.tt = CreateFrame("Frame", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f.tt:SetPoint("TOPLEFT", 10, -10)
        f.tt:SetWidth(220)
        if f.tt.SetBackdrop then
            f.tt:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            f.tt:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        else
            K.Fill(f.tt, { 0.03, 0.03, 0.05, 0.92 })
        end
        local function line(head)
            local t = f.tt:CreateFontString(nil, "ARTWORK", head and "GameTooltipHeaderText" or "GameTooltipText")
            t:SetJustifyH("LEFT")
            return t
        end
        f.name, f.guild, f.lvl, f.fac, f.tgt = line(true), line(), line(), line(), line()
        f.name:SetText("Jaina")
        f.lvl:SetText(L["Level 32 Human Mage"] .. " (" .. L["Player"] .. ")")
        f.bar = CreateFrame("StatusBar", nil, f.tt)
        f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        f.bar:SetMinMaxValues(0, 1) f.bar:SetValue(0.7) f.bar:SetStatusBarColor(0, 1, 0)
        f.combat = text(f, 10, C.dim, 10, -150)
        caption(f, L["This is how the box looks with the mouse over a player"])
    end,
    update = function(f)
        if on("twTipClass") then f.name:SetTextColor(CLASS.r, CLASS.g, CLASS.b) else f.name:SetTextColor(1, 1, 1) end
        f.guild:SetText(on("cfTipRank") and "|cff40ff40<Oasis>|r Officer" or "")
        f.fac:SetText(L["Alliance"])
        f.tgt:SetText(on("cfTipTarget") and (L["Target:"] .. " |cffff7d0aThrall|r") or "")
        -- stack the lines like the game does (empty ones take no space)
        local y = -10
        for _, t in ipairs({ f.name, f.guild, f.lvl, f.fac, f.tgt }) do
            if (t:GetText() or "") ~= "" then
                t:ClearAllPoints() t:SetPoint("TOPLEFT", 10, y) t:Show()
                y = y - (t == f.name and 18 or 15)
            else
                t:Hide()
            end
        end
        local inside = on("twTipBar")
        f.tt:SetHeight(-y + (inside and 18 or 8))
        f.bar:ClearAllPoints()
        if inside then
            f.bar:SetPoint("BOTTOMLEFT", f.tt, "BOTTOMLEFT", 9, 9) f.bar:SetPoint("BOTTOMRIGHT", f.tt, "BOTTOMRIGHT", -9, 9) f.bar:SetHeight(6)
        else
            f.bar:SetPoint("TOPLEFT", f.tt, "BOTTOMLEFT", 2, -1) f.bar:SetPoint("TOPRIGHT", f.tt, "BOTTOMRIGHT", -2, -1) f.bar:SetHeight(8)
        end
        if f.tt.SetBackdropColor then
            if on("cfTipFaction") then f.tt:SetBackdropColor(0.05, 0.1, 0.35, 0.95) else f.tt:SetBackdropColor(0, 0, 0, 0.9) end
        end
        f.combat:SetText(on("cfTipCombat") and L["In combat: hidden - hold Shift to see it"] or L["In combat: always shown"])
    end,
}

------------------------------------------------------------------------
-- minimap & camera: round or square minimap with addon buttons, camera and glow, fishing
------------------------------------------------------------------------
PREV.minimapcam = {
    build = function(f)
        f.map = CreateFrame("Frame", nil, f)
        f.map:SetSize(150, 150)
        f.map:SetPoint("TOPLEFT", 50, -10)
        f.map.bg = f.map:CreateTexture(nil, "BACKGROUND")
        f.map.bg:SetAllPoints()
        f.map.bg:SetColorTexture(0.22, 0.28, 0.15, 1)
        f.mask = f.map:CreateMaskTexture()
        f.mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        f.mask:SetAllPoints(f.map)
        f.map.bg:AddMaskTexture(f.mask)
        f.masked = true
        f.me = icon(f.map, 18, "Interface\\Minimap\\MinimapArrow", 66, -66)
        f.btns = {}
        for i, a in ipairs({ 0.3, 1.1, 2.0, 2.8 }) do
            local b = icon(f, 22, ({ 136243, 134400, 133784, 132320 })[i], 0, 0)
            b:ClearAllPoints()
            b:SetPoint("CENTER", f.map, "CENTER", math.cos(a) * 82, math.sin(a) * 82)
            f.btns[i] = b
        end
        f.cam = text(f, 10, C.text, 0, -180)
        f.glow = text(f, 10, C.text, 0, -198)
        f.fish = text(f, 10, C.text, 0, -216)
        caption(f)
    end,
    update = function(f)
        local sq = on("cfSquareMap")
        if sq and f.masked then f.map.bg:RemoveMaskTexture(f.mask) f.masked = false
        elseif not sq and not f.masked then f.map.bg:AddMaskTexture(f.mask) f.masked = true end
        for _, b in ipairs(f.btns) do b:SetAlpha(on("cfMapButtons") and 0.12 or 1) end
        f.cam:SetText(on("twCamera") and ("|cff7fd77f" .. L["Camera: zooms out much further"] .. "|r") or ("|cff888888" .. L["Camera: normal distance"] .. "|r"))
        f.glow:SetText(on("twNoGlow") and ("|cff7fd77f" .. L["Screen glow: off (sharper picture)"] .. "|r") or ("|cff888888" .. L["Screen glow: as set in the game"] .. "|r"))
        f.fish:SetText(on("twFishing") and ("|cff7fd77f" .. L["Fishing: double right-click casts"] .. "|r") or ("|cff888888" .. L["Fishing: from the action bar"] .. "|r"))
    end,
}

------------------------------------------------------------------------
-- sounds: listen to each sound; muted ones are crossed out
------------------------------------------------------------------------
local SOUNDS = { { "cfMuteChimes", "Clock chimes", 566564 }, { "cfMuteFizzle", "Spell fizzle", 569773 }, { "cfMuteTrains", "/train emote", 539802 }, { "cfMuteYawns", "Cat yawn", 562388 } }
PREV.sounds = {
    build = function(f)
        f.rows = {}
        for i, sd in ipairs(SOUNDS) do
            local y = -10 - (i - 1) * 40
            local b = K.Button(f, L["Listen"], 80, 26, "ghost", function() if PlaySoundFile then pcall(PlaySoundFile, sd[3], "Master") end end)
            b:SetPoint("TOPLEFT", 0, y)
            local t = text(f, 11, C.text, 92, y - 6, L[sd[2]])
            f.rows[i] = { t = t, key = sd[1] }
        end
        caption(f, L["Muted sounds stay silent even with \"Listen\""])
    end,
    update = function(f)
        for _, r in ipairs(f.rows) do
            local m = on(r.key)
            r.t:SetTextColor(m and 0.5 or 1, m and 0.5 or 1, m and 0.5 or 1)
            local s = r.t:GetText() or ""
            s = s:gsub("  |cffff5050" .. L["muted"] .. "|r$", "")
            r.t:SetText(m and (s .. "  |cffff5050" .. L["muted"] .. "|r") or s)
        end
    end,
}

------------------------------------------------------------------------
-- chat: a chat window with tabs, buttons, spam lines and the font size
------------------------------------------------------------------------
PREV.chatclean = {
    build = function(f)
        f.tabs = {}
        for i, n in ipairs({ "General", "Combat Log", "Guild" }) do
            local t = panel(f, 74, 20, 30 + (i - 1) * 78, 0, { 0.1, 0.1, 0.12, 0.9 })
            text(t, 10, C.text, 6, -4, L[n])
            f.tabs[i] = t
        end
        f.win = panel(f, 220, 170, 30, -22, { 0, 0, 0, 0.55 })
        f.btns = {}
        for i = 1, 3 do
            local b = icon(f, 20, ({ 136243, 132320, 134400 })[i], 2, -30 - (i - 1) * 26)
            f.btns[i] = b
        end
        f.lines = {}
        for i = 1, 6 do f.lines[i] = text(f.win, 12, C.text, 6, -6 - (i - 1) * 18) end
        caption(f)
    end,
    update = function(f)
        f.tabs[2]:SetShown(not on("cfNoCombatTab"))
        for _, b in ipairs(f.btns) do b:SetShown(not on("cfNoChatButtons")) end
        local size = S().cfChatFont or 14
        local L1 = {
            "|cff40ff40[Guild] Mira: who's up for Deadmines?|r",
            { "|cffffff00Bob has defeated Al in a duel|r", spam = true },
            "|cffff80ff[Whisper] Lia: on my way|r",
            { "|cffffff00Gorr seems a little tipsy.|r", spam = true },
            "|cffffd100[1. General] Trade wool for gold|r",
            "|cff40ff40[Guild] Toran: lfm|r",
        }
        local y, n = -6, 0
        for _, l in ipairs(L1) do
            local isSpam = type(l) == "table"
            if not (isSpam and on("cfSpamFilter")) then
                n = n + 1
                local t = f.lines[n]
                t:SetFont(K.FONT or STANDARD_TEXT_FONT, size * 0.8, "")
                t:ClearAllPoints() t:SetPoint("TOPLEFT", 6, y)
                t:SetText(isSpam and l[1] or l)
                t:Show()
                y = y - size * 1.15
            end
        end
        for i = n + 1, #f.lines do f.lines[i]:Hide() end
    end,
}

------------------------------------------------------------------------
-- whispers: offer to the alt
------------------------------------------------------------------------
PREV.whisper = {
    build = function(f)
        f.chat = panel(f, 240, 90, 0, 0, { 0, 0, 0, 0.55 })
        text(f.chat, 11, { 1, 0.5, 1 }, 6, -6, "To Lia: are you there?")
        text(f.chat, 11, { 1, 1, 0 }, 6, -24, L["Lia is offline."])
        f.offer = text(f.chat, 11, { 0.5, 0.85, 1 }, 6, -46)
        caption(f)
    end,
    update = function(f)
        f.offer:SetText(on("whisperForward") and L["Oasis: send it to their alt Arven? [Send]"] or "")
    end,
}

------------------------------------------------------------------------
-- map extras: sample icons for each layer
------------------------------------------------------------------------
-- 0.6.642: real zone (Tirisfal Glades) with the explored areas, trails as lines in class colours, game symbols
local function zone(parent, mapID, w)
    local sc = w / 1002
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, math.floor(668 * sc + 0.5))
    box:SetClipsChildren(true)
    local bg = box:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.32, 0.27, 0.18, 1)
    local ok, tiles = pcall(function() return C_Map and C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(mapID, 1) end)
    if ok and type(tiles) == "table" then
        for i, id in ipairs(tiles) do
            local c, r = (i - 1) % 4, math.floor((i - 1) / 4)
            local t = box:CreateTexture(nil, "BACKGROUND", nil, 1)
            t:SetTexture(id)
            t:SetSize(256 * sc, 256 * sc)
            t:SetPoint("TOPLEFT", c * 256 * sc, -r * 256 * sc)
        end
    end
    for _, entry in ipairs(ns.MapRevealData and ns.MapRevealData[mapID] or {}) do
        local pw, ph, ox, oy, texs = entry:match("^(%d+):(%d+):(%d+):(%d+):(.+)$")
        pw, ph, ox, oy = tonumber(pw), tonumber(ph), tonumber(ox), tonumber(oy)
        if pw then
            local ids = {}
            for id in texs:gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
            local cols, rows = math.ceil(pw / 256), math.ceil(ph / 256)
            for r = 1, rows do
                for c = 1, cols do
                    local id = ids[(r - 1) * cols + c]
                    if id then
                        local tw = (c < cols) and 256 or (pw - 256 * (cols - 1))
                        local th = (r < rows) and 256 or (ph - 256 * (rows - 1))
                        local t = box:CreateTexture(nil, "BACKGROUND", nil, 2)
                        t:SetTexture(id)
                        local fw, fh = 16, 16
                        while fw < tw do fw = fw * 2 end
                        while fh < th do fh = fh * 2 end
                        t:SetTexCoord(0, tw / fw, 0, th / fh)
                        t:SetSize(tw * sc, th * sc)
                        t:SetPoint("TOPLEFT", (ox + 256 * (c - 1)) * sc, -(oy + 256 * (r - 1)) * sc)
                    end
                end
            end
        end
    end
    return box
end
PREV.zone = zone

PREV.mapextras = {
    build = function(f)
        f.map = zone(f, 1420, 262)
        f.map:SetPoint("TOPLEFT", 0, -4)
        local W, H = f.map:GetWidth(), f.map:GetHeight()
        local function at(o, x, y) o:ClearAllPoints() o:SetPoint("CENTER", f.map, "TOPLEFT", x * W, -y * H) end
        local function ico(tex, size, x, y, atlas)
            local t = f.map:CreateTexture(nil, "OVERLAY")
            t:SetSize(size, size)
            if atlas and t.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then t:SetAtlas(atlas) else t:SetTexture(tex) end
            at(t, x, y)
            return t
        end
        f.i = {}
        -- dungeon entrance: Scarlet Monastery
        f.i.mapDungeons = ico("Interface\\Minimap\\Dungeon", 18, 0.83, 0.3, "Dungeon")
        -- danger zone: Agamand Mills
        local d = f.map:CreateTexture(nil, "ARTWORK")
        d:SetTexture(ns.MEDIA .. "softglow") d:SetBlendMode("ADD") d:SetVertexColor(1, 0.15, 0.1) d:SetAlpha(0.8)
        d:SetSize(56, 56) at(d, 0.37, 0.24)
        f.i.mapDanger = d
        -- vendors, repair, mailbox, flight master: Brill
        f.poi = {
            ico("Interface\\Icons\\INV_Misc_Coin_01", 10, 0.55, 0.5, "Banker"),
            ico("Interface\\Icons\\Trade_BlackSmithing", 10, 0.59, 0.53, "Repair"),
            ico("Interface\\Icons\\INV_Letter_15", 10, 0.55, 0.56, "Mailbox"),
            ico("Interface\\Icons\\Ability_Mount_Wyvern_01", 12, 0.62, 0.47, "FlightMaster"),
        }
        -- quest giver of a dungeon quest
        f.i.mapQuestGivers = ico("Interface\\GossipFrame\\AvailableQuestIcon", 14, 0.7, 0.42, "QuestNormal")
        -- trails as lines
        local function path(pts)
            local list = {}
            for i = 2, #pts do
                local l = f.map:CreateLine(nil, "ARTWORK", nil, 2)
                if not l then return list end
                l:SetThickness(2)
                l:SetStartPoint("TOPLEFT", f.map, pts[i - 1][1] * W, -pts[i - 1][2] * H)
                l:SetEndPoint("TOPLEFT", f.map, pts[i][1] * W, -pts[i][2] * H)
                l.q = (i - 1) / (#pts - 1)
                list[#list + 1] = l
            end
            return list
        end
        -- own: from Deathknell towards Brill; the first part only with "whole session"
        f.trailOld = path({ { 0.17, 0.58 }, { 0.22, 0.6 }, { 0.27, 0.57 }, { 0.31, 0.6 } })
        f.trail = path({ { 0.31, 0.6 }, { 0.36, 0.57 }, { 0.41, 0.6 }, { 0.46, 0.56 }, { 0.5, 0.54 } })
        f.me = ico(ns.MEDIA .. "pinarrow", 12, 0.5, 0.54)
        -- another player
        f.gtrail = path({ { 0.74, 0.72 }, { 0.7, 0.66 }, { 0.66, 0.62 }, { 0.63, 0.57 } })
        f.gname = f.map:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f.gname:SetPoint("BOTTOM", f.map, "TOPLEFT", 0.63 * W, -0.57 * H + 4)
        f.gname:SetText("Mira")
        f.coords = f.map:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.coords:SetPoint("BOTTOMRIGHT", -4, 4)
        f.layer = text(f, 10, C.text, 0, -H - 14)
        caption(f)
    end,
    update = function(f)
        f.i.mapDungeons:SetShown(onD("mapDungeons"))
        f.i.mapDanger:SetShown(on("mapDanger"))
        for _, t in ipairs(f.poi) do t:SetShown(onD("mapPoi")) end
        f.i.mapQuestGivers:SetShown(on("mapQuestGivers"))
        local _, cls = UnitClass("player")
        local mr, mg, mb = 1, 0.85, 0.3
        if cls and ns.classColor then mr, mg, mb = ns.classColor(cls) end
        local own, long = on("mapTrails"), on("trailSession")
        for _, l in ipairs(f.trail) do l:SetColorTexture(mr, mg, mb, 0.35 + 0.65 * l.q) l:SetShown(own) end
        for _, l in ipairs(f.trailOld) do l:SetColorTexture(mr, mg, mb, 0.25) l:SetShown(own and long) end
        local gc = RAID_CLASS_COLORS and RAID_CLASS_COLORS.MAGE or { r = 0.25, g = 0.78, b = 0.92 }
        local other = on("mapTrailsGuild")
        for _, l in ipairs(f.gtrail) do l:SetColorTexture(gc.r, gc.g, gc.b, 0.35 + 0.65 * l.q) l:SetShown(other) end
        f.gname:SetShown(other)
        f.gname:SetTextColor(gc.r, gc.g, gc.b)
        f.coords:SetText(on("mmCoords") and "50.2, 54.8" or "")
        f.layer:SetText(onD("layerAsk") and L["Layer requests from the guild: asked"] or ("|cff888888" .. L["Layer requests: ignored"] .. "|r"))
    end,
}

------------------------------------------------------------------------
-- 0.6.630: examples on top of the settings tabs (full width, ComfortSettings buildTabPage)
------------------------------------------------------------------------
local function val(k, def) local v = S()[k] if v == nil then return def end return v end
local function cname(name, cls)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
    local hex = c and c.colorStr or "ffffffff"
    return "|c" .. hex .. name .. "|r"
end

-- game chat: four sample lines that follow the switches
PREV.tab_gamechat = {
    h = 128,
    build = function(f)
        f.win = panel(f, 738, 110, 0, 0, { 0, 0, 0, 0.55 })
        f.lines = {}
        for i = 1, 4 do f.lines[i] = text(f.win, 12, C.text, 10, -10 - (i - 1) * 23) end
        f.cap = caption(f)
    end,
    update = function(f)
        local onC = val("gcOn", true)
        local function who(first, last, cls, race, lvl)
            local nm = (onC and val("gcShort", false)) and first or (first .. " " .. last)
            local pre = ""
            if onC and val("gcRaceIcon", false) then pre = pre .. "|A:raceicon-" .. race .. ":14:14|a " end
            if onC and val("gcClassIcon", false) then pre = pre .. "|A:groupfinder-icon-class-" .. cls:lower() .. ":14:14|a " end
            local lv = (onC and val("gcLevel", true)) and ("|cff40c040" .. lvl .. "|r ") or ""
            return pre .. lv .. "[" .. cname(nm, cls) .. "]"
        end
        local ore = (onC and val("gcLinkIcons", true)) and "|T134566:14|t|cffffffff[Copper Ore]|r" or "|cffffffff[Copper Ore]|r"
        local lfm = (onC and val("gcTokens", true)) and ("LFM |cff888888(" .. L["looking for more"] .. ")|r") or "LFM"
        local ch = (onC and val("gcChNum", false)) and "[2]" or "[2. Trade - Orgrimmar]"
        local quiet = onC and val("gcQuiet", false)
        local function body(t, col) return quiet and ("|cffb8b8b8" .. t .. "|r") or (col .. t .. "|r") end
        local L1 = {
            "|cff40ff40[" .. L["Guild"] .. "]|r " .. who("Mira", "Stern", "MAGE", "orc-female", 23) .. ": " .. body(L["anyone up for Deadmines?"] .. " " .. lfm, "|cff40ff40"),
            "|cffffc0c0" .. ch .. "|r " .. who("Tomas", "Berg", "WARRIOR", "tauren-male", 31) .. ": " .. body(L["selling"] .. " ", "|cffffc0c0") .. ore .. body(" x20", "|cffffc0c0"),
            who("Anna", "Berg", "PRIEST", "undead-female", 19) .. " |cffff80ff" .. L["whispers"] .. ": " .. L["on my way"] .. "|r",
            "|cffaaaaff[" .. L["Party"] .. "]|r " .. who("Lia", "Moor", "HUNTER", "troll-female", 22) .. ": " .. body(L["ready"], "|cffaaaaff"),
        }
        for i, t in ipairs(f.lines) do t:SetText(L1[i]) end
        f.cap:SetText(onC and L["Preview - changes show at once"] or L["Game chat is off - Blizzard's chat stays as it is"])
    end,
}

-- helpers: what happens at the vendor, with quests and invites + Blizzard bars
PREV.tab_comfort = {
    h = 132,
    build = function(f)
        f.log = panel(f, 440, 112, 0, 0, { 0, 0, 0, 0.55 })
        f.lines = {}
        for i = 1, 5 do f.lines[i] = text(f.log, 11, C.text, 10, -8 - (i - 1) * 20) end
        f.bars = panel(f, 286, 112, 452, 0)
        text(f.bars, 10, C.dim, 10, -8, L["Blizzard bars"])
        f.micro = {}
        local MI = { 132089, 133741, 136222, 132222, 134414, 136207, 135940, 134400 }
        for i, id in ipairs(MI) do f.micro[i] = icon(f.bars, 22, id, 10 + (i - 1) * 26, -28) end
        f.bags = {}
        for i = 1, 5 do f.bags[i] = icon(f.bars, 22, 133633, 10 + (i - 1) * 26, -56) end
        f.hint = text(f.bars, 10, C.dim, 10, -84)
        f.dur = text(f.bars, 11, C.amber or C.accent, 160, -60)
        caption(f)
    end,
    update = function(f)
        local L1 = {}
        if on("cfSellJunk") then L1[#L1 + 1] = (L["Sold %d grey items for %s"]):format(7, "1s 20c") end
        if on("cfRepair") then L1[#L1 + 1] = (L["Repaired for %s%s"]):format("3s 45c", on("cfRepairGuild") and (" (" .. L["Guild bank"] .. ")") or "") end
        if on("cfQuests") then L1[#L1 + 1] = L["Quest accepted"] .. ": Wolves Across the Border" end
        if on("cfBlockDuels") then L1[#L1 + 1] = L["Duel from Gorr declined"] end
        if on("cfInvites") then L1[#L1 + 1] = L["Invite from a stranger declined"] end
        if on("cfSummon") and #L1 < 5 then L1[#L1 + 1] = L["Summon from Toran accepted"] end
        if #L1 == 0 then L1[1] = "|cff888888" .. L["Nothing happens automatically - turn on a helper below."] .. "|r" end
        for i, t in ipairs(f.lines) do
            t:SetText(L1[i] and ("|cffe8b44aOasis|r  " .. L1[i]) or "")
            if L1[i] and L1[i]:find("^|cff888888") then t:SetText(L1[i]) end
        end
        local hov = on("cfBarsHover")
        for _, b in ipairs(f.micro) do b:SetAlpha(on("cfHideMicro") and (hov and 0.18 or 0) or 1) end
        for _, b in ipairs(f.bags) do b:SetAlpha(on("cfHideBags") and (hov and 0.18 or 0) or 1) end
        f.hint:SetText((on("cfHideMicro") or on("cfHideBags")) and (hov and L["hidden - appears under the mouse"] or L["hidden"]) or "")
        f.dur:SetText(on("cfDurability") and (L["Durability"] .. " 78 %") or "")
    end,
}

-- guild helpers: item tooltip + player tooltip + XP line
PREV.tab_helpers = {
    h = 132,
    build = function(f)
        f.item = panel(f, 360, 112, 0, 0)
        f.it = {}
        for i = 1, 5 do f.it[i] = text(f.item, 11, C.text, 10, -8 - (i - 1) * 19) end
        f.pl = panel(f, 366, 112, 372, 0)
        f.pt = {}
        for i = 1, 5 do f.pt[i] = text(f.pl, 11, C.text, 10, -8 - (i - 1) * 19) end
        caption(f)
    end,
    update = function(f)
        local A = { "|cff1eff00Silver-thread Robe|r", "|cffffffff" .. L["Chest"] .. "  ·  " .. L["Cloth"] .. "|r" }
        if on("cpTooltip") then
            A[#A + 1] = "|cffffffff" .. L["Vendor price"] .. ":|r 31s 40c"
            A[#A + 1] = "|cff888888" .. L["Item level"] .. " 26  ·  ID 6403|r"
        end
        if on("cpDisenchant") then A[#A + 1] = "|cff8080ff" .. L["Disenchants into"] .. ":|r Strange Dust, Lesser Magic Essence" end
        for i, t in ipairs(f.it) do t:SetText(A[i] or "") end
        local B = { cname("Mira Stern", "MAGE"), "|cffffffff" .. L["Level"] .. " 23 Orc " .. L["Mage"] .. "|r" }
        if on("cpTooltipGuild") then
            B[#B + 1] = "|cff40ff40<OASIS>|r  |cffe8b44a" .. L["Oasis rank"] .. " 12|r"
            B[#B + 1] = "|cff888888" .. L["Professions"] .. ": Tailoring 145, Enchanting 120|r"
        end
        if on("cpInspect") then B[#B + 1] = "|cffffffff" .. L["Item level"] .. " 24|r  |cff40c040(+3)|r" end
        if on("cpXP") and #B < 5 then B[#B + 1] = "|cff8080ff12.4k XP/h  ·  38 min " .. L["to level"] .. " 24|r" end
        for i, t in ipairs(f.pt) do t:SetText(B[i] or "") end
    end,
}

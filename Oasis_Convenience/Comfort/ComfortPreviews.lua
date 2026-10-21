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
    t:SetText(s or L["Preview - changes show at once"])
    return t
end
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
            .. (on("twLootSparkle") and ("|cffffd100" .. L["Quest items sparkle"] .. "|r") or ""))
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
    end,
}

------------------------------------------------------------------------
-- tooltips: a unit tooltip that follows every switch
------------------------------------------------------------------------
PREV.tooltips = {
    build = function(f)
        f.tt = panel(f, 230, 120, 10, -10, { 0.03, 0.03, 0.05, 0.92 })
        f.name = text(f.tt, 13, C.text, 10, -8, "Jaina")
        f.l2 = text(f.tt, 11, C.text, 10, -28, L["Level 32 Human Mage"])
        f.rank = text(f.tt, 11, { 0.6, 0.85, 1 }, 10, -46)
        f.tgt = text(f.tt, 11, C.text, 10, -64)
        f.bar = CreateFrame("StatusBar", nil, f.tt)
        f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        f.bar:SetMinMaxValues(0, 1) f.bar:SetValue(0.7) f.bar:SetStatusBarColor(0, 1, 0)
        f.combat = text(f, 10, C.dim, 10, -140)
        caption(f)
    end,
    update = function(f)
        if on("twTipClass") then f.name:SetTextColor(CLASS.r, CLASS.g, CLASS.b) else f.name:SetTextColor(1, 1, 1) end
        f.rank:SetText(on("cfTipRank") and "<Oasis>  Officer" or "")
        f.tgt:SetText(on("cfTipTarget") and (L["Target:"] .. " |cffff7d0aThrall|r") or "")
        f.bar:ClearAllPoints()
        if on("twTipBar") then
            f.bar:SetPoint("BOTTOMLEFT", f.tt, "BOTTOMLEFT", 10, 8) f.bar:SetPoint("BOTTOMRIGHT", f.tt, "BOTTOMRIGHT", -10, 8) f.bar:SetHeight(5)
        else
            f.bar:SetPoint("TOPLEFT", f.tt, "BOTTOMLEFT", 2, -2) f.bar:SetPoint("TOPRIGHT", f.tt, "BOTTOMRIGHT", -2, -2) f.bar:SetHeight(8)
        end
        if on("cfTipFaction") then f.tt.bg:SetVertexColor(0.05, 0.08, 0.25, 0.95) else f.tt.bg:SetVertexColor(0.03, 0.03, 0.05, 0.92) end
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
PREV.mapextras = {
    build = function(f)
        f.map = f:CreateTexture(nil, "BACKGROUND")
        f.map:SetSize(240, 160)
        f.map:SetPoint("TOPLEFT", 0, -4)
        f.map:SetTexture("Interface\\WorldMap\\Elwynn\\Elwynn6")
        f.i = {}
        local function add(key, tex, x, y, size)
            local t = icon(f, size or 18, tex, x, y)
            f.i[key] = t
        end
        add("mapDungeons", "Interface\\Minimap\\Dungeon", 40, -30, 22)
        add("mapDanger", nil, 150, -40, 46)
        f.i.mapDanger:SetColorTexture(1, 0.1, 0.1, 0.3)
        add("mapPoi", "Interface\\Icons\\INV_Misc_Bag_10", 100, -90)
        add("mapQuestGivers", "Interface\\GossipFrame\\AvailableQuestIcon", 190, -110)
        f.trail = {}
        for i = 1, 8 do local t = f:CreateTexture(nil, "ARTWORK") t:SetColorTexture(1, 0.85, 0.3, 0.8) t:SetSize(4, 4) t:SetPoint("TOPLEFT", 20 + i * 14, -130 + i * 4) f.trail[i] = t end
        f.gtrail = {}
        for i = 1, 8 do local t = f:CreateTexture(nil, "ARTWORK") t:SetColorTexture(0.4, 0.8, 1, 0.8) t:SetSize(4, 4) t:SetPoint("TOPLEFT", 120 + i * 12, -70 - i * 3) f.gtrail[i] = t end
        f.coords = text(f, 10, C.text, 0, -170)
        f.layer = text(f, 10, C.text, 0, -188)
        caption(f)
    end,
    update = function(f)
        f.i.mapDungeons:SetShown(onD("mapDungeons"))
        f.i.mapDanger:SetShown(on("mapDanger"))
        f.i.mapPoi:SetShown(onD("mapPoi"))
        f.i.mapQuestGivers:SetShown(on("mapQuestGivers"))
        for _, t in ipairs(f.trail) do t:SetShown(on("mapTrails")) end
        for _, t in ipairs(f.gtrail) do t:SetShown(on("mapTrailsGuild")) end
        f.coords:SetText(on("mmCoords") and L["Minimap: 42.3, 65.1  ·  120 m to the target"] or "")
        f.layer:SetText(onD("layerAsk") and L["Layer requests from the guild: asked"] or ("|cff888888" .. L["Layer requests: ignored"] .. "|r"))
    end,
}

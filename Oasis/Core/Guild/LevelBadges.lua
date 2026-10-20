-- Oasis: level badges 10/20/30/40/50/60 (0.5.571, images from the guild leader: Media\levels\lvlNN.tga, small lvlNN_s.tga)
--  * own level 10/20/.../60 reached: large popup with badge
--  * Chronicle/Dashboard: level entries at a multiple of ten show the badge
--  * Member list: most recently earned badge shown small before the level
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

local LB = {}
ns.LevelBadges = LB

-- Path to the badge of the highest reached multiple of ten (nil below 10)
function LB.For(level, small)
    level = tonumber(level)
    if not level or level < 10 then return nil end
    local tier = math.min(60, math.floor(level / 10) * 10)
    return ns.MEDIA .. "levels\\lvl" .. tier .. (small and "_s" or "")
end
-- only exactly at a multiple of ten (for "reached level 30")
function LB.Exact(level, small)
    level = tonumber(level)
    if not level or level < 10 or level > 60 or level % 10 ~= 0 then return nil end
    return LB.For(level, small)
end

-- large popup -------------------------------------------------------------------------
local pop
local function build()
    pop = CreateFrame("Frame", "OasisLevelBadgePop", UIParent)
    pop:SetSize(320, 360)
    pop:SetPoint("CENTER", 0, 120)
    pop:SetFrameStrata("FULLSCREEN_DIALOG")
    pop:EnableMouse(false)
    pop.badge = pop:CreateTexture(nil, "ARTWORK")
    pop.badge:SetPoint("TOP", 0, 0)
    pop.title = K.Title(pop, 26, C.text)
    pop.title:SetPoint("TOP", pop.badge, "BOTTOM", 0, -10)
    pop.sub = K.Text(pop, 13, C.muted)
    pop.sub:SetPoint("TOP", pop.title, "BOTTOM", 0, -6)
    pop:Hide()
end
function LB.Celebrate(level)
    local path = LB.Exact(level)
    if not path then return end
    if not pop then build() end
    pop.badge:SetTexture(path)
    pop.title:SetText((L["Level %d reached!"]):format(level))
    pop.sub:SetText(level >= 60 and L["Welcome to the endgame!"] or L["New level badge unlocked"])
    pop:SetAlpha(0)
    pop:Show()
    if ns.Sound and ns.Sound.Next then ns.Sound.Next("levelup") end
    local anim = K.Tween and not (ns.db and ns.db.settings.noAnim)
    if not anim then
        pop.badge:SetSize(220, 220) pop:SetAlpha(1)
        ns.After(4, function() pop:Hide() end)
        return
    end
    -- Safety: disappear again even without a running animation (e.g. window hidden)
    pop.use = (pop.use or 0) + 1
    local use = pop.use
    ns.After(4.8, function() if pop.use == use then pop:Hide() end end)
    -- jump in (overshoot), hold briefly, fade out upwards
    K.Tween(pop, 4.2, function(q)
        local s
        if q < 0.12 then
            local t = q / 0.12
            s = 0.3 + 0.85 * (1 - (1 - t) * (1 - t))   -- up to 1.15
        elseif q < 0.2 then
            s = 1.15 - 0.15 * ((q - 0.12) / 0.08)
        else
            s = 1
        end
        pop.badge:SetSize(220 * s, 220 * s)
        local a = q < 0.1 and q / 0.1 or (q > 0.82 and (1 - q) / 0.18 or 1)
        pop:SetAlpha(a)
        pop:ClearAllPoints()
        pop:SetPoint("CENTER", 0, 120 + (q > 0.82 and (q - 0.82) / 0.18 * 40 or 0))
    end, function() pop:Hide() end)
end
ns.Listen("LEVEL_UP", function(level)
    level = tonumber(level)
    if level and level % 10 == 0 then ns.After(0.6, function() pcall(LB.Celebrate, level) end) end
end)
ns.slash.stufenabzeichen = function(rest) LB.Celebrate(tonumber(rest) or 30) end

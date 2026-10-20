-- Oasis: Glimmer (0.6.521) - known nodes of the guild gathering map near you light up on the minimap
-- Only herbs/ore/fishing spots of your own gathering professions (like the gathering map), only out of combat and
-- instances. From 60 m a soft, pulsing ring on the node, from 25 m a quiet sound once.
-- toggle: Settings > Map (guild gathering map)
local ADDON, ns = ...  ns = Oasis or ns  -- sub-addon: namespace of Oasis
ns.ModuleFile("Oasis_MapExtras", function()
local GM = ns.Gather
local function S() return ns.db.settings end
local NEAR, PING = 60, 25

local pool, pinged = {}, {}
local function ring(i)
    local t = pool[i]
    if t then return t end
    t = CreateFrame("Frame", nil, Minimap)
    t:SetSize(22, 22)
    t:SetFrameLevel(Minimap:GetFrameLevel() + 6)
    t.tex = t:CreateTexture(nil, "OVERLAY")
    t.tex:SetAllPoints()
    t.tex:SetTexture(ns.MEDIA .. "softglow")
    t.tex:SetBlendMode("ADD")
    t.ag = t:CreateAnimationGroup()
    t.ag:SetLooping("BOUNCE")
    local a = t.ag:CreateAnimation("Alpha")
    a:SetFromAlpha(0.25) a:SetToAlpha(0.9) a:SetDuration(0.8)
    local s = t.ag:CreateAnimation("Scale")
    s:SetScaleFrom(0.8, 0.8) s:SetScaleTo(1.15, 1.15) s:SetDuration(0.8)
    pool[i] = t
    return t
end
local acc = 0
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.5 then return end
    acc = 0
    local used = 0
    if S().glimmer ~= false and GM and GM.MiniCtx and not ns.inCombat() then
        local c = GM.MiniCtx()
        if c then
            for _, r in ipairs(GM.Nodes(c.map) or {}) do
                if GM.PROF_KINDS[r.kind] and (not GM.OwnKind or GM.OwnKind(r.kind)) and not S()["gatherOff_" .. r.kind] and r.x and r.y then
                    local x, y, dist, m = GM.MiniPlace(c, r.x, r.y)
                    if m <= NEAR and dist < 0.95 and used < 8 then
                        used = used + 1
                        local t = ring(used)
                        local k = GM.KINDS[r.kind]
                        local col = k and k.color or { 1, 1, 1 }
                        t.tex:SetVertexColor(col[1], col[2], col[3], 1)
                        t:ClearAllPoints()
                        t:SetPoint("CENTER", Minimap, "CENTER", x, y)
                        t:Show()
                        if not t.ag:IsPlaying() then t.ag:Play() end
                        local key = r.map .. ":" .. math.floor(r.x * 1000) .. ":" .. math.floor(r.y * 1000)
                        if m <= PING and (not pinged[key] or GetTime() - pinged[key] > 300) then
                            pinged[key] = GetTime()
                            if S().glimmerSound ~= false and PlaySound and SOUNDKIT and SOUNDKIT.MAP_PING then pcall(PlaySound, SOUNDKIT.MAP_PING) end
                        end
                    end
                end
            end
        end
    end
    for i = used + 1, #pool do pool[i].ag:Stop() pool[i]:Hide() end
end)

end)

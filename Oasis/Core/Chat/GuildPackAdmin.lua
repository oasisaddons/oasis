-- Oasis: Gildenleitung > Emojis & Sounds (0.6.533)
--  * komplette Liste des installierten Gildenpakets: Bild bzw. Abspielen, Code, Rang (ab Oasis-Rang 2-100), An/Aus
--  * "Speichern & freigeben": schreibt die offizielle Freigabe (Store gpack) - Rangsperren und Aus gelten fuer alle,
--    egal was in den Dateien der Mitglieder steht (siehe GuildPack.lua)
--  * Wer hat es?: wie viele aktive Mitglieder das freigegebene Paket installiert haben, wem es fehlt
--  * Ankuendigen (Gildenchat per Klick), Link zur Bau-Seite, alle auf frei / Werte aus den Dateien
-- Bearbeiten nur mit dem Recht fuer Gildeneinstellungen (guildcfg) - alle anderen sehen die Liste nur.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C
local MP = ns.MediaPack
if not MP then return end

local draft = { em = {}, so = {} }   -- [code] = Stufe (2-100), 0 = aus, nil = Standard aus der Datei
local filter = "all"                 -- all | emoji | sound | off
local function canEdit() return MP.CanPublish() end
local function rows()
    local em, so = MP.Items()
    local out = {}
    for _, e in ipairs(em) do
        local d = draft.em[e[1]]
        local lvl = d ~= nil and d or MP.OfficialLevel("emoji", e[1]) or e[2]
        if lvl == 200 then lvl = 200 end
        out[#out + 1] = { kind = "emoji", key = e[1], lvl = lvl, file = e[2], frames = e[3] }
    end
    for _, s in ipairs(so) do
        local d = draft.so[s[1]]
        local lvl = d ~= nil and d or MP.OfficialLevel("sound", s[1]) or s[2]
        local c = ns.Sound and ns.Sound.byKey and ns.Sound.byKey[s[1]]
        out[#out + 1] = { kind = "sound", key = s[1], lvl = lvl, file = s[2], text = c and c.text or s[1] }
    end
    local res = {}
    for _, r in ipairs(out) do
        if filter == "all" or (filter == "off" and r.lvl == 0) or (filter == "lead" and r.lvl == 200) or r.kind == filter then res[#res + 1] = r end
    end
    return res
end
local function setLvl(r, v)
    local t = (r.kind == "sound") and draft.so or draft.em
    t[r.key] = v
    ns.RefreshPage("admin")
end
local function changed()
    for _ in pairs(draft.em) do return true end
    for _ in pairs(draft.so) do return true end
    return false
end

local function build(f)
    f.state = K.Text(f, 12, C.text)
    f.state:SetPoint("TOPLEFT", 4, -2) f.state:SetPoint("RIGHT", -360, 0)
    f.state:SetJustifyH("LEFT") f.state:SetWordWrap(true) f.state:SetSpacing(4)
    f.pub = K.Button(f, L["Save & release"], 170, 24, "primary", function()
        if MP.Publish(draft) then
            draft = { em = {}, so = {} }
            K.Toast(L["Guild pack"], L["Released: version, content and rank locks now apply to the whole guild."], C.mint)
        end
        ns.RefreshPage("admin")
    end)
    f.pub:SetPoint("TOPRIGHT", 0, 0)
    f.ann = K.Button(f, L["Announce in guild chat"], 180, 24, "ghost", function()
        local m = MP.Mine()
        if not m then return end
        ns.OfferChat(L["Guild pack"], (L["New guild pack v%d with %d emojis and %d sounds! Unpack the ZIP into the AddOns folder, restart WoW. Build: oasisaddon.com"]):format(m.v, m.emojis, m.sounds), "GUILD")
    end)
    f.ann:SetPoint("TOPRIGHT", f.pub, "BOTTOMRIGHT", 0, -6)
    f.link = K.Button(f, L["Link to the builder"], 150, 24, "ghost", MP.ShowUrl)
    f.link:SetPoint("RIGHT", f.ann, "LEFT", -6, 0)
    -- Filter + Sammelaktionen
    f.seg = K.Segments(f, { { key = "all", text = L["All"] }, { key = "emoji", text = L["Emojis"] }, { key = "sound", text = L["Sounds"] }, { key = "lead", text = L["Leaders only"] }, { key = "off", text = L["Switched off"] } },
        function(k) filter = k ns.RefreshPage("admin") end, nil, { size = 12, pad = 16 })
    f.seg:SetPoint("TOPLEFT", 0, -78)
    f.free = K.Button(f, L["All free"], 110, 22, "ghost", function()
        for _, r in ipairs(rows()) do setLvl(r, 2) end
    end)
    f.free:SetPoint("TOPRIGHT", 0, -78)
    f.reset = K.Button(f, L["Values from the files"], 160, 22, "ghost", function() draft = { em = {}, so = {} } ns.RefreshPage("admin") end)
    f.reset:SetPoint("RIGHT", f.free, "LEFT", -6, 0)
    -- Liste
    f.list = K.List(f, 34, function(l)
        local r = K.Row(l)
        r.icon = r:CreateTexture(nil, "ARTWORK") r.icon:SetSize(24, 24) r.icon:SetPoint("LEFT", 10, 0)
        r.play = K.Button(r, ">", 26, 22, "ghost", function(self) if self.key and ns.Sound then ns.Sound.Preview(self.key) end end)
        r.play:SetPoint("LEFT", 8, 0)
        r.code = K.Text(r, 13, C.text) r.code:SetPoint("LEFT", 44, 0) r.code:SetWidth(240) r.code:SetWordWrap(false)
        r.kindT = K.Text(r, 11, C.dim) r.kindT:SetPoint("LEFT", 290, 0) r.kindT:SetWidth(110)
        r.minus = K.Button(r, "-", 24, 22, "ghost", function() local it = r.item if it and canEdit() then setLvl(it, math.max(2, (it.lvl ~= 0 and it.lvl or 2) - 5)) end end)
        r.minus:SetPoint("LEFT", 410, 0)
        r.lvlT = K.Title(r, 13, C.text, "CENTER") r.lvlT:SetPoint("LEFT", 438, 0) r.lvlT:SetWidth(70)
        r.plus = K.Button(r, "+", 24, 22, "ghost", function() local it = r.item if it and canEdit() then setLvl(it, math.min(100, (it.lvl ~= 0 and it.lvl or 2) + 5)) end end)
        r.plus:SetPoint("LEFT", 512, 0)
        r.onoff = K.Button(r, "", 96, 22, "ghost", function() local it = r.item if it and canEdit() then setLvl(it, it.lvl == 0 and (it.file or 2) or 0) end end)
        r.onoff:SetPoint("RIGHT", -10, 0)
        -- 0.6.534: nur Gildenmeister und Offiziere (Blizzard-Gildenrang)
        r.lead = K.Button(r, "", 110, 22, "ghost", function() local it = r.item if it and canEdit() then setLvl(it, it.lvl == 200 and (it.file or 2) or 200) end end)
        r.lead:SetPoint("RIGHT", r.onoff, "LEFT", -6, 0)
        return r
    end, function(r, it)
        r.item = it
        local isSound = it.kind == "sound"
        r.icon:SetShown(not isSound) r.play:SetShown(isSound) r.play.key = it.key
        if not isSound then
            local e = ns.Emoji and ns.Emoji.Entry and ns.Emoji.Entry(":" .. it.key .. ":")
            if e then ns.Emoji.SetIcon(r.icon, e) else r.icon:SetTexture(134400) end
            r.code:SetText(":" .. it.key .. ":")
        else
            r.code:SetText(it.text or it.key)
        end
        r.kindT:SetText(isSound and L["Sound"] or ((it.frames and it.frames > 1) and L["Emoji, animated"] or L["Emoji"]))
        local off, lead = it.lvl == 0, it.lvl == 200
        r.lvlT:SetText(off and "|cff777777-|r" or (lead and ("|cffe8b44a" .. L["Leaders"] .. "|r")) or ((not it.lvl or it.lvl <= 2) and L["open"] or ((L["from %d"]):format(it.lvl))))
        r.onoff:SetLabel(off and L["Switch on"] or L["Switch off"])
        r.lead:SetLabel(lead and L["For everyone"] or L["Leaders only"])
        local ed = canEdit()
        r.minus:SetShown(ed and not off and not lead) r.plus:SetShown(ed and not off and not lead) r.onoff:SetShown(ed) r.lead:SetShown(ed and not off)
        r.code:SetAlpha(off and 0.45 or 1) r.icon:SetAlpha(off and 0.35 or 1)
    end)
    f.list:SetPoint("TOPLEFT", 0, -108)
    f.list:SetPoint("BOTTOMRIGHT", -250, 0)
    -- rechts: wer hat es?
    f.who = CreateFrame("Frame", nil, f)
    f.who:SetPoint("TOPLEFT", f.list, "TOPRIGHT", 12, 0) f.who:SetPoint("BOTTOMRIGHT", 0, 0)
    K.Fill(f.who, { 1, 1, 1, 0.03 })
    f.whoT = K.Title(f.who, 13, C.text) f.whoT:SetPoint("TOPLEFT", 10, -10) f.whoT:SetText(L["Who has it?"])
    f.whoN = K.Text(f.who, 12, C.text) f.whoN:SetPoint("TOPLEFT", 10, -32) f.whoN:SetPoint("RIGHT", -10, 0) f.whoN:SetJustifyH("LEFT")
    f.whoL = K.Text(f.who, 11, C.muted) f.whoL:SetPoint("TOPLEFT", 10, -56) f.whoL:SetPoint("RIGHT", -10, 0)
    f.whoL:SetJustifyH("LEFT") f.whoL:SetJustifyV("TOP") f.whoL:SetWordWrap(true) f.whoL:SetSpacing(3)
end
local function refresh(f)
    local m, o = MP.Mine(), MP.Official()
    local lines = {}
    lines[#lines + 1] = m and ((L["Installed: guild pack %s, version %d (%s) - %d emojis, %d sounds"]):format(m.guild, m.v, m.made, m.emojis, m.sounds))
        or ("|cffe8b44a" .. L["No guild pack installed - build it first (link to the builder), unpack it, restart WoW."] .. "|r")
    if o then
        local same = m and m.v == o.v and MP.Fingerprint() == o.fp
        lines[#lines + 1] = (same and "|cff66db9e" or "|cffe8b44a") .. (L["Officially released: version %d (by %s, %s)"]):format(o.v, ns.short(o.by or "?"), o.made or "") .. "|r"
    else
        lines[#lines + 1] = "|cff888888" .. L["The guild leadership hasn't released a pack yet."] .. "|r"
    end
    if changed() then lines[#lines + 1] = "|cffe8b44a" .. L["Unsaved changes - apply them with Save & release."] .. "|r" end
    if not canEdit() then lines[#lines + 1] = "|cff888888" .. L["Only ranks that may edit guild settings can change this."] .. "|r" end
    f.state:SetText(table.concat(lines, "\n"))
    f.pub:SetShown(canEdit() and m ~= nil)
    f.ann:SetShown(m ~= nil)
    f.free:SetShown(canEdit() and m ~= nil) f.reset:SetShown(canEdit() and changed())
    f.seg:Select(filter)
    local list = m and rows() or {}
    f.list:SetData(list)
    f.list.empty:SetText(m and (#list == 0 and L["Nothing in this selection."] or "") or L["No pack installed yet."])
    -- wer hat es
    local hs, ok, miss = MP.Holders(), 0, {}
    for _, h in ipairs(hs) do if h.ok then ok = ok + 1 else miss[#miss + 1] = ns.short(h.name) .. (h.v and (" |cff666666v" .. h.v .. "|r") or "") end end
    f.whoN:SetText(o and ((L["%d of %d active members have the released pack"]):format(ok, #hs)) or L["Release it first - then you can see here who has it."])
    f.whoL:SetText(#miss > 0 and (L["Missing for:"] .. "\n" .. table.concat(miss, "\n", 1, math.min(#miss, 30)) .. (#miss > 30 and ("\n+" .. (#miss - 30)) or "")) or "")
end
if ns.Admin and ns.Admin.AddTab then
    ns.Admin.AddTab("media", "Emojis & sounds", build, refresh,
        "The guild's custom emojis and sounds: rank per entry, switch on and off, release, see who has the pack.", 6)
end

-- Oasis: guild pack (own emojis & sounds) - 0.6.531/0.6.532
--  * The pack is built on oasisaddon.com (studio in the page header, in the browser - nothing is uploaded):
--    ZIP with Oasis_Emojis + Oasis_Sounds; List.lua sets OasisGuildPack = { guild, v, made, emojis, sounds }.
--  * TAMPER-PROOF (0.6.532): rank locks and version do NOT come from the other players' files but from the
--    official entry of the guild leadership (Store "gpack", only officers with permission guildcfg may write it).
--    It contains: version, fingerprint of the pack and the rank level of each own emoji/sound.
--      - Emojis: Rewards.EmojiLevel uses the official level; unknown own codes count as level 100.
--      - Sounds: another player's online sound only plays if THEIR verified Oasis rank is high enough
--        (otherwise the default sound) - regardless of what is in their file or mine.
--      - Whoever has a pack with a different fingerprint at the same version gets a notice.
--  * Settings > Appearance & Controls > Emojis & Sounds: status, link to the build page, approval (leadership).
-- Caution: do NOT name it ns.GuildPack - that is the marker "guild module loaded" (Oasis_Guild/Guild.lua).
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store
local MP = {}
ns.MediaPack = MP
MP.URL = "oasisaddon.com/#studio"
local OFFICIAL = "gpack-official"

function MP.Mine()
    local p = rawget(_G, "OasisGuildPack")
    if type(p) ~= "table" then return nil end
    return { guild = type(p.guild) == "string" and p.guild:sub(1, 40) or "?", v = tonumber(p.v) or 0, made = type(p.made) == "string" and p.made or "",
        emojis = tonumber(p.emojis) or 0, sounds = tonumber(p.sounds) or 0 }
end
function MP.LegacyInstalled()
    local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or rawget(_G, "IsAddOnLoaded")
    if not loaded then return false end
    return (loaded("Oasis_Emojis") or loaded("Oasis_Sounds")) and true or false
end

-- Contents of the installed pack: codes/keys with their own level (from the files) - only for fingerprint and approval
local function localItems()
    local em, so = {}, {}
    for _, c in ipairs(type(rawget(_G, "OasisEmojiList")) == "table" and OasisEmojiList or {}) do
        for _, e in ipairs(type(c) == "table" and type(c.items) == "table" and c.items or {}) do
            if type(e) == "table" and type(e[1]) == "string" then em[#em + 1] = { e[1], tonumber(e.lvl), tonumber(e.n) } end
        end
    end
    for _, e in ipairs(type(rawget(_G, "OasisSoundsList")) == "table" and OasisSoundsList or {}) do
        if type(e) == "table" and type(e.key) == "string" then so[#so + 1] = { e.key, tonumber(e.lvl) } end
    end
    table.sort(em, function(a, b) return a[1] < b[1] end)
    table.sort(so, function(a, b) return a[1] < b[1] end)
    return em, so
end
-- Fingerprint: codes + levels + number of images (djb2, 2 lanes)
function MP.Fingerprint()
    local em, so = localItems()
    local parts = {}
    for _, e in ipairs(em) do parts[#parts + 1] = "e:" .. e[1] .. ":" .. (e[2] or 0) .. ":" .. (e[3] or 1) end
    for _, s in ipairs(so) do parts[#parts + 1] = "s:" .. s[1] .. ":" .. (s[2] or 0) end
    local str = table.concat(parts, "|")
    local a, b = 5381, 52711
    for i = 1, #str do
        local c = str:byte(i)
        a = (a * 33 + c) % 16777213
        b = (b * 31 + c * 7) % 16777199
    end
    return ("%06x%06x"):format(a, b), #em, #so
end

------------------------------------------------------------------------
-- Official entry of the leadership
------------------------------------------------------------------------
local offEm, offSo, offAt
-- "code:level,..." - level 0 = turned off by the leadership
local function parseMap(s)
    local t = {}
    for k, v in tostring(s or ""):gmatch("([%w_]+):(%d+)") do v = tonumber(v) t[k] = (v == 0 or v == 200) and v or math.max(1, math.min(100, v)) end
    return t
end
MP.OFF = 101   -- turned off: a level nobody reaches (Oasis rank goes up to 100)
MP.LEAD = 200  -- 0.6.534: guild leadership only (guild master + officers by Blizzard guild rank), independent of Oasis rank
-- is the player part of the leadership? (guild rank from the guild roster; myself via Admin.Role)
function MP.IsLead(name)
    local A = ns.Admin
    if not A then return false end
    local role
    if not name or ns.isMe(name) then role = A.Role and A.Role() else role = A.RoleOf and A.RoleOf(name) end
    return role == "lead" or role == "officer" or role == "dev"
end
-- may "who" use an own entry? nil = no leadership setting (then the normal rules apply)
-- need = level from the approval; Oasis rank of the sender/player from Rank.Of (verified)
function MP.MayUse(kind, key, who)
    local need = (kind == "sound") and MP.SoundLock(key) or MP.EmojiLock(key)
    if not need then return nil end
    if need == MP.OFF then return false end
    if need == MP.LEAD then return MP.IsLead(who) end
    if need <= 1 then return true end
    local lvl
    if not who or ns.isMe(who) then lvl = ns.Rank and ns.Rank.Mine and ns.Rank.Mine().level or 1
    else lvl = ns.Rank and ns.Rank.Of and ns.Rank.Of(who) end
    if ns.UnlockAll and ns.UnlockAll() and (not who or ns.isMe(who)) then return true end
    return (lvl or 1) >= need
end
function MP.Official()
    local r = Store.Get("gpack", OFFICIAL)
    if not r or not tonumber(r.v) then return nil end
    if offAt ~= r.u then offAt, offEm, offSo = r.u, parseMap(r.el), parseMap(r.sl) end
    return r
end
-- official level of an own emoji (code without colons) / sound (key x_...): nil = no setting
function MP.EmojiLock(code)
    if not MP.Official() or not code then return nil end
    local v = offEm[code]
    if v == 0 then return MP.OFF end
    if v == 200 then return MP.LEAD end
    return v or 100   -- not in the official pack -> only for the highest
end
-- turned off by the leadership?
function MP.IsOff(kind, key)
    if not MP.Official() then return false end
    return ((kind == "sound") and offSo or offEm)[key] == 0
end
-- official setting per entry (for the leadership tab): level, 0 = off, nil = not approved
function MP.OfficialLevel(kind, key)
    if not MP.Official() then return nil end
    return ((kind == "sound") and offSo or offEm)[key]
end
-- Contents of the installed pack with own level from the files
function MP.Items() local em, so = localItems() return em, so end
function MP.SoundLock(key)
    if not MP.Official() or not key then return nil end
    local v = offSo[key]
    if v == 0 then return MP.OFF end
    if v == 200 then return MP.LEAD end
    return v or 100
end
function MP.CanPublish()
    return ns.Admin and ns.Admin.MayAuthor and ns.Admin.MayAuthor(ns.me(), "guildcfg") == true
end
-- Approve: version, fingerprint and the levels currently in effect for ME (Rewards/Sound compute them)
function MP.Publish(over)
    over = over or {}
    local m = MP.Mine()
    if not m or not MP.CanPublish() then return false end
    local fp = MP.Fingerprint()
    local em, so = localItems()
    MP.publishing = true   -- Levels from the files/rules, not from the old approval
    local el, sl = {}, {}
    local byCode = ns.Emoji and ns.Emoji.Entry
    for _, e in ipairs(em) do
        local entry = byCode and byCode(":" .. e[1] .. ":")
        local lvl = (over.em and over.em[e[1]]) or e[2] or (entry and ns.Rewards and ns.Rewards.EmojiLevel and ns.Rewards.EmojiLevel(entry)) or 2
        el[#el + 1] = e[1] .. ":" .. math.floor(lvl)
    end
    for _, s in ipairs(so) do
        local c = ns.Sound and ns.Sound.byKey and ns.Sound.byKey[s[1]]
        sl[#sl + 1] = s[1] .. ":" .. math.floor((over.so and over.so[s[1]]) or s[2] or (c and c.lvl) or 2)
    end
    MP.publishing = nil
    Store.Put("gpack", { id = OFFICIAL, v = m.v, made = m.made, fp = fp, el = table.concat(el, ","), sl = table.concat(sl, ","),
        ne = #em, ns = #so, by = ns.me(), ts = ns.now() })
    return true
end

-- Notice to members: newer version approved or different content at the same version
local function check()
    local o, m = MP.Official(), MP.Mine()
    if not o or not ns.db then return end
    ns.db.packHint = ns.db.packHint or {}
    local key = tostring(o.v) .. ":" .. tostring(o.fp)
    if ns.db.packHint.last == key then return end
    if not m or m.v < o.v then
        ns.db.packHint.last = key
        K.Toast(L["New guild pack"], (L["The guild leadership released version %d with custom emojis and sounds. Ask for the ZIP and unpack it into the AddOns folder."]):format(o.v),
            C.accent, function() ns.ShowPage("settings") if ns.Settings and ns.Settings.SetTab then pcall(ns.Settings.SetTab, "ownmedia") end end)
    elseif m.v == o.v and MP.Fingerprint() ~= o.fp then
        ns.db.packHint.last = key
        K.Toast(L["Guild pack differs"], L["Your pack has the same version as the official one but different content. Get the ZIP from the guild leadership."], C.amber or C.accent)
    end
end
ns.Listen("STORE", function(name) if name == "gpack" then ns.After(2, function() pcall(check) end) ns.RefreshPage("settings") end end)
ns.Listen("LOGIN", function() C_Timer.After(40, function() pcall(check) end) end)
function MP.ReportMine()
    local m = MP.Mine()
    if not m or not IsInGuild() then return end
    local fp = MP.Fingerprint()
    local id = "gph-" .. ns.NameKey(ns.me())
    local old = Store.Get("gpackhave", id)
    if old and old.v == m.v and old.fp == fp and (old.ts or 0) > ns.now() - 7 * 86400 then return end
    Store.Put("gpackhave", { id = id, v = m.v, fp = fp, by = ns.me(), ts = ns.now() })
end
ns.Listen("LOGIN", function() C_Timer.After(60, function() pcall(MP.ReportMine) end) end)
-- Members (mains) and their pack state: { name, v, ok (= official version + same content) }
function MP.Holders()
    local o = MP.Official()
    local have = {}
    for _, r in ipairs(Store.List("gpackhave")) do if r.by then have[ns.NameKey(r.by)] = r end end
    local out = {}
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        local isAlt = ns.Alts and ns.Alts.IsAlt and ns.Alts.IsAlt(m.name)
        if not isAlt and (m.online or (m.offDays or 99) < 14) then
            local h = have[ns.NameKey(m.name)]
            out[#out + 1] = { name = m.name, v = h and h.v, ok = (o and h and h.v == o.v and h.fp == o.fp) and true or false }
        end
    end
    table.sort(out, function(a, b) if a.ok ~= b.ok then return not a.ok end return a.name < b.name end)
    return out
end

------------------------------------------------------------------------
-- Settings tab
------------------------------------------------------------------------
StaticPopupDialogs["OASIS_PACK_URL"] = {
    text = "%s", button1 = OKAY or "OK", hasEditBox = true, editBoxWidth = 260,
    OnShow = function(self) local eb = self.editBox or self.EditBox if eb then eb:SetText("https://" .. MP.URL) eb:HighlightText() eb:SetFocus() end end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
function MP.ShowUrl() StaticPopup_Show("OASIS_PACK_URL", L["Ctrl+C copies the link - open it in your browser:"]) end
local function build(f)
    local H = ns.SettingsHelpers
    f.noCompact = true
    local c = H.cardH(f, 0, 0, 740, 150, "smile", L["Custom emojis & sounds for your guild"])
    f.how = K.Text(c, 12, C.text)
    f.how:SetPoint("TOPLEFT", 14, -48) f.how:SetPoint("RIGHT", -14, 0)
    f.how:SetJustifyH("LEFT") f.how:SetWordWrap(true) f.how:SetSpacing(4)
    f.how:SetText(L["1. Drop images and sounds onto the website - everything happens in your browser.\n2. Download the guild pack, unpack it into the AddOns folder, restart WoW.\n3. Share the ZIP in your Discord - everyone in the guild unpacks it the same way."])
    f.go = K.Button(c, L["Link to the builder"], 180, 26, "primary", MP.ShowUrl)
    f.go:SetPoint("BOTTOMLEFT", 14, 14)
    f.url = K.Text(c, 12, C.muted) f.url:SetPoint("LEFT", f.go, "RIGHT", 12, 0) f.url:SetText(MP.URL)
    local s = H.cardH(f, 0, -164, 740, 196, "checklist", L["Your status"])
    f.state = K.Text(s, 12, C.text)
    f.state:SetPoint("TOPLEFT", 14, -48) f.state:SetPoint("RIGHT", -14, 0)
    f.state:SetJustifyH("LEFT") f.state:SetWordWrap(true) f.state:SetSpacing(5)
    f.pub = K.Button(s, L["Release as official guild pack"], 270, 24, "ghost", function()
        if MP.Publish() then K.Toast(L["Guild pack"], L["Released: version, content and rank locks now apply to the whole guild."], C.mint) end
        ns.RefreshPage("settings")
    end)
    f.pub:SetPoint("BOTTOMLEFT", 14, 14)
end
local function refresh(f)
    local m, o = MP.Mine(), MP.Official()
    local lines = {}
    if m then
        lines[#lines + 1] = (L["Installed: guild pack %s, version %d (%s) - %d emojis, %d sounds"]):format(m.guild, m.v, m.made, m.emojis, m.sounds)
    elseif MP.LegacyInstalled() then
        lines[#lines + 1] = L["Installed: custom emojis/sounds without a version (old import script). Rebuild them on the builder so the guild sees the version."]
    else
        lines[#lines + 1] = "|cff888888" .. L["No guild pack installed."] .. "|r"
    end
    if o then
        local same = m and m.v == o.v and MP.Fingerprint() == o.fp
        local col = same and "|cff66db9e" or "|cffe8b44a"
        lines[#lines + 1] = col .. (L["Officially released: version %d (by %s, %s)"]):format(o.v, ns.short(o.by or "?"), o.made or "") .. "|r"
        if not same then lines[#lines + 1] = (m and m.v == o.v) and L["Your pack differs from the official one - get the ZIP from the guild leadership."]
            or L["Ask the leadership for the new ZIP, unpack it into the AddOns folder and restart WoW."] end
    else
        lines[#lines + 1] = "|cff888888" .. L["The guild leadership hasn't released a pack yet."] .. "|r"
    end
    lines[#lines + 1] = "|cff888888" .. L["Rank locks follow the leadership's release - editing your own files does not lift them. Without the pack, emojis show as :code: and custom sounds as the default sound."] .. "|r"
    f.state:SetText(table.concat(lines, "\n"))
    f.pub:SetShown(m ~= nil and MP.CanPublish() and IsInGuild())
end
if ns.AddSettingsTab then ns.AddSettingsTab("ownmedia", "Emojis & sounds", build, refresh) end
ns.slash.paket = function() MP.ShowUrl() end
ns.slash.studio = ns.slash.paket

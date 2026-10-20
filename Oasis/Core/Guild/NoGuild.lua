-- Oasis - Startbildschirm ohne Gilde (2026, Glas)
-- Wer in keiner Gilde ist, sieht statt des Dashboards diese Seite: was Oasis trotzdem kann + neutral "Gilde finden".
-- Oeffnet jemand eine Gildenseite (Favorit, Link, Slash), zeigt dieselbe Seite einen Hinweis darueber.
local ADDON, ns = ...
local K, C, L = ns.K, ns.K.C, ns.L

local NoGuild = {}
ns.NoGuild = NoGuild

local function hasGlass() return ns.Insta and ns.Insta.Glass and true or false end
local function glass(f, fill, line, r) if hasGlass() then ns.Insta.Glass(f, fill, line, r) end end
local function round(t, box, r) if K.RoundMask and t then K.RoundMask(t, box or t, r) end end

-- Blizzards Gildensuche oeffnen: der Reihe nach, was dieser Client hat (alles geschuetzt)
function NoGuild.OpenFinder()
    local tries = {
        function() if ToggleGuildFinder then ToggleGuildFinder() return true end end,
        function() if ToggleCommunitiesFrame then ToggleCommunitiesFrame() return true end end,
        function() if CommunitiesFrame and ShowUIPanel then ShowUIPanel(CommunitiesFrame) return true end end,
        function() if GuildFinderFrame and ShowUIPanel then ShowUIPanel(GuildFinderFrame) return true end end,
        function() if ToggleGuildFrame then ToggleGuildFrame() return true end end,
    }
    for _, fn in ipairs(tries) do
        local ok, done = pcall(fn)
        if ok and done then return true end
    end
    ns.print(L["No guild finder found in this client - ask in trade chat or whisper a guild member."])
    return false
end

local function calmBtn(b, primary)
    if not (b and hasGlass()) then return b end
    local ac = C.accent
    local fill = primary and { ac[1], ac[2], ac[3], 0.16 } or { 1, 1, 1, 0.05 }
    local line = primary and { ac[1], ac[2], ac[3], 0.45 } or { 1, 1, 1, 0.10 }
    if b.sheen then b.sheen:Hide() end
    glass(b, fill, line, 9)
    b:SetScript("OnEnter", function(self) glass(self, { fill[1], fill[2], fill[3], fill[4] + 0.05 }, { line[1], line[2], line[3], line[4] + 0.12 }) end)
    b:SetScript("OnLeave", function(self) glass(self, fill, line) end)
    return b
end

-- Glaskarte: Symbol, Titel, kurzer Text, Knopf
local function card(parent, icon, color, title, text, btnText, onClick)
    local c = CreateFrame("Frame", nil, parent)
    c:SetHeight(150)
    glass(c, nil, nil, 12)
    if not hasGlass() then K.Fill(c, C.panel) K.Border(c, C.line) end
    c.disc = c:CreateTexture(nil, "ARTWORK", nil, -1)
    c.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    c.disc:SetSize(36, 36)
    c.disc:SetPoint("TOPLEFT", 16, -16)
    c.disc:SetVertexColor(color[1] * 0.22, color[2] * 0.22, color[3] * 0.22, 1)
    c.icon = K.Glyph(c, 18, ns.MEDIA .. "icons\\" .. icon, color)
    c.icon:SetDrawLayer("ARTWORK", 3)   -- ueber der Scheibe (gleiche Ebene: Reihenfolge zufaellig, Symbol war unsichtbar)
    c.icon:SetPoint("CENTER", c.disc, "CENTER", 0, 0)
    c.title = K.Title(c, 15, C.text)
    c.title:SetPoint("LEFT", c.disc, "RIGHT", 12, 0)
    c.title:SetPoint("RIGHT", c, "RIGHT", -12, 0)
    c.title:SetText(title)
    c.text = K.Text(c, 12, C.muted)
    c.text:SetPoint("TOPLEFT", 16, -62)
    c.text:SetPoint("RIGHT", c, "RIGHT", -16, 0)
    c.text:SetJustifyH("LEFT")
    c.text:SetWordWrap(true)
    c.text:SetText(text)
    c.btn = calmBtn(K.Button(c, btnText, 140, 26, "ghost", onClick))
    c.btn:SetPoint("BOTTOMLEFT", 16, 14)
    return c
end

-- Inhalte (Hero, Karten, Gilde finden, Oasis-Kontakte) in einen Host bauen: Seite "noguild" und Dashboard ohne Gilde
function NoGuild.Fill(p)
        -- Hero
        p.hero = CreateFrame("Frame", nil, p)
        p.hero:SetHeight(112)
        glass(p.hero, nil, nil, 14)
        p.hero.logo = p.hero:CreateTexture(nil, "ARTWORK")
        p.hero.logo:SetTexture(ns.MEDIA .. "logo64")
        p.hero.logo:SetSize(52, 52)
        p.hero.logo:SetPoint("LEFT", 22, 0)
        p.hero.title = K.Title(p.hero, 20, C.text)
        p.hero.title:SetPoint("TOPLEFT", 92, -28)
        p.hero.title:SetPoint("RIGHT", p.hero, "RIGHT", -20, 0)
        p.hero.title:SetText(L["You are not in a guild."])
        p.hero.sub = K.Text(p.hero, 13, C.muted)
        p.hero.sub:SetPoint("TOPLEFT", p.hero.title, "BOTTOMLEFT", 0, -8)
        p.hero.sub:SetPoint("RIGHT", p.hero, "RIGHT", -20, 0)
        p.hero.sub:SetWordWrap(true)
        p.hero.sub:SetText(L["Oasis still works for you: your profile, goals, dungeons and collections are here."])

        p.cards = {
            card(p, "profile", C.accent, L["Profile"], L["Stats, yearbook, daily goal, records and adventures of your character."], L["Open profile"],
                function() ns.ShowPage("insta") end),
            card(p, "checklist", C.mint, L["What to do?"], L["Suggestions for your level and your time."], L["See suggestions"],
                function() ns.profileTab = "todo" ns.ShowPage("insta") end),
            card(p, "dungeons", C.blue, L["Dungeons"], L["The dungeon compass: which dungeon fits, what drops there for you."], L["Open dungeons"],
                function() ns.ShowPage("dungeons") end),
        }
        p.find = card(p, "groups", C.amber, L["Find a guild"],
            L["With a guild you also get the member list, chronicle, raids, crafting and more. WoW's guild finder helps - or ask in trade chat."],
            L["Open guild finder"], function() NoGuild.OpenFinder() end)
        p.find:SetHeight(96)
        -- 0.6.527: bei einer Gilde mit Oasis direkt bewerben (Rekrutierungs-Mappe)
        p.find.apply = calmBtn(K.Button(p.find, L["Write application"], 150, 22, "ghost", function() if ns.Apply then ns.Apply.ShowForm() else ns.print(L["Applying needs the Guild care module."]) end end))
        p.find.apply:SetPoint("RIGHT", p.find.btn, "LEFT", -8, 0)
        p.find.text:ClearAllPoints()
        p.find.text:SetPoint("TOPLEFT", 64, -42)
        p.find.text:SetPoint("RIGHT", p.find, "RIGHT", -180, 0)
        p.find.btn:ClearAllPoints()
        p.find.btn:SetPoint("RIGHT", -16, 0)
        p.find.btn:SetWidth(150)
        -- Beispieldaten: so sieht Oasis mit Gilde aus. Startet nur per Klick und bleibt auf diesem PC.
        if ns.Demo and ns.Demo.Load then
            p.find.btn:SetPoint("RIGHT", -16, 17)
            p.find.demo = calmBtn(K.Button(p.find, L["Show example"], 150, 26, "ghost", function()
                if not ns.Demo.IsActive() then ns.Demo.Load() end
                ns.ShowPage("home")
            end))
            p.find.demo:SetPoint("RIGHT", -16, -17)
            p.find.demo:HookScript("OnEnter", function(self)
                K.ShowTip(self, { L["Show example"], L["This is what Oasis looks like with a guild: sample data on your PC only, nothing is sent. Remove it with /oa demo off."] })
            end)
            p.find.demo:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end

        -- Deine Oasis-Kontakte (Oasis-Nutzer aus Gruppen, auch ausserhalb einer Gilde)
        local MAXR = 5
        p.ct = CreateFrame("Frame", nil, p)
        glass(p.ct, nil, nil, 12)
        if not hasGlass() then K.Fill(p.ct, C.panel) K.Border(p.ct, C.line) end
        p.ct.head = K.Title(p.ct, 14, C.text)
        p.ct.head:SetPoint("TOPLEFT", 16, -14)
        p.ct.head:SetText(L["Your Oasis contacts"])
        p.ct.count = K.Text(p.ct, 11, C.dim)
        p.ct.count:SetPoint("LEFT", p.ct.head, "RIGHT", 8, 0)
        p.ct.empty = K.Text(p.ct, 12, C.muted)
        p.ct.empty:SetPoint("TOPLEFT", 16, -40)
        p.ct.empty:SetPoint("RIGHT", p.ct, "RIGHT", -16, 0)
        p.ct.empty:SetJustifyH("LEFT")
        p.ct.empty:SetWordWrap(true)
        p.ct.empty:SetText(L["No contacts yet. Group up with other Oasis users - Oasis remembers them here, even without a guild."])
        p.ct.rows = {}
        for i = 1, MAXR do
            local r = CreateFrame("Button", nil, p.ct)
            r:SetHeight(30)
            r:SetPoint("TOPLEFT", 10, -36 - (i - 1) * 32)
            r:SetPoint("RIGHT", p.ct, "RIGHT", -10, 0)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetAllPoints()
            r.hl:SetColorTexture(1, 1, 1, 0.04)
            round(r.hl, r, 8)
            r.ring = r:CreateTexture(nil, "ARTWORK")
            r.ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            r.ring:SetSize(24, 24)
            r.ring:SetPoint("LEFT", 6, 0)
            r.disc = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            r.disc:SetSize(21, 21)
            r.disc:SetPoint("CENTER", r.ring)
            r.disc:SetVertexColor(0.06, 0.06, 0.08, 1)
            r.cls = r:CreateTexture(nil, "ARTWORK", nil, 2)
            r.cls:SetSize(16, 16)
            r.cls:SetPoint("CENTER", r.ring)
            r.ini = K.Text(r, 10, C.text, "CENTER")
            r.ini:SetPoint("CENTER", r.ring, "CENTER", 0, 0)
            r.ini:SetWidth(24)
            r.dot = r:CreateTexture(nil, "OVERLAY")
            r.dot:SetTexture(ns.MEDIA .. "dot")
            r.dot:SetSize(8, 8)
            r.dot:SetPoint("CENTER", r.ring, "BOTTOMRIGHT", -2, 2)
            r.dot:SetVertexColor(C.mint[1], C.mint[2], C.mint[3])
            r.name = K.Text(r, 12, C.text)
            r.name:SetPoint("LEFT", 40, 0)
            r.name:SetWidth(170)
            r.name:SetWordWrap(false)
            r.info = K.Text(r, 11, C.dim)
            r.info:SetPoint("LEFT", 214, 0)
            r.info:SetPoint("RIGHT", r, "RIGHT", -180, 0)
            r.info:SetWordWrap(false)
            r.dr = calmBtn(K.Button(r, L["Deathroll"], 90, 22, "ghost"))
            r.dr:SetPoint("RIGHT", 0, 0)
            r.inv = calmBtn(K.Button(r, L["Invite"], 76, 22, "ghost"))
            r.inv:SetPoint("RIGHT", r.dr, "LEFT", -6, 0)
            r:SetScript("OnEnter", function(self)
                local x = self.item
                if not x then return end
                K.ShowTip(self, { ns.colorName(x.name, x.c.cls), "|cff66db9e" .. (ns.Contacts.TipLine(x.c) or "") .. "|r",
                    x.group and L["in your group"] or (x.online and L["online (friends list)"] or (x.friend and L["offline"] or L["not on your friends list - online status unknown"])) })
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            r:SetScript("OnClick", function(self) if self.item and ns.Profile then ns.Profile.Show(self.item.name) end end)
            p.ct.rows[i] = r
        end
        function p:FillContacts()
            local list = ns.Contacts and ns.Contacts.List(true) or {}
            self.ct.count:SetText(#list > 0 and tostring(#list) or "")
            self.ct.empty:SetShown(#list == 0)
            for i, r in ipairs(self.ct.rows) do
                local x = list[i]
                r.item = x
                if x then
                    local c = x.c
                    local cr, cg, cb = ns.classColor(c.cls)
                    r.ring:SetVertexColor(cr or 0.5, cg or 0.5, cb or 0.5, 0.75)
                    local GI = ns.GuildInfo
                    local ok = c.cls and GI and GI.SetClassIcon and GI.SetClassIcon(r.cls, c.cls)
                    r.cls:SetShown(ok and true or false)
                    r.ini:SetShown(not ok)
                    if not ok then r.ini:SetText(((ns.displayName(x.name) or "?"):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"):upper()) end
                    r.dot:SetShown(x.online)
                    r.name:SetText(ns.colorName(x.name, c.cls) .. "  |cff888888" .. (c.lvl or "?") .. "|r")
                    r.info:SetText(L["last"] .. " " .. (ns.ago and ns.ago(c.seen or 0) or "?"))
                    local nm = x.name
                    r.inv:SetShown(x.online and not x.group)
                    r.inv:SetScript("OnClick", function()
                        if C_PartyInfo and C_PartyInfo.InviteUnit then pcall(C_PartyInfo.InviteUnit, ns.ChatName and ns.ChatName(nm) or nm)
                        elseif InviteUnit then pcall(InviteUnit, nm) end
                    end)
                    r.dr:SetShown(x.online and ns.Deathroll ~= nil)
                    r.dr:SetScript("OnClick", function()
                        local viaGroup = ns.Comm.ViaGroup and ns.Comm.ViaGroup(nm)
                        if ns.Deathroll then ns.Deathroll.Challenge(nm, 100, "", not viaGroup) end
                        ns.ShowPage("deathroll")
                    end)
                    r:Show()
                else
                    r:Hide()
                end
            end
            local n = math.min(#list, MAXR)
            self.ct:SetHeight(#list == 0 and 88 or (44 + n * 32))
        end
end

------------------------------------------------------------------------
-- "Zurueck in deine Gilde?": Twink ohne Gilde, andere Charaktere des Accounts sind in einer Gilde
------------------------------------------------------------------------
-- je Charakter Gildenname mitschreiben (Account-weit), damit Twinks ohne Gilde wissen, wo der Main ist
local function noteMyGuild()
    if not ns.db then return end
    ns.db.charGuild = ns.db.charGuild or {}
    local me = ns.me()
    if not me then return end
    if IsInGuild and IsInGuild() then
        local g = ns.safe((GetGuildInfo("player")))
        if g and g ~= "" then ns.db.charGuild[me] = { g = g, t = ns.now() } end
    else
        ns.db.charGuild[me] = nil
    end
end
ns.Listen("LOGIN", function() ns.After(5, noteMyGuild) end)
ns.On("PLAYER_GUILD_UPDATE", function() ns.After(1, noteMyGuild) end)

local function realmOf(name) return (name or ""):match("%-(.+)$") end
local function sameRealm(a, b)
    local ra, rb = realmOf(a), realmOf(b)
    return ra == nil or rb == nil or ra == rb
end

-- liefert { main, guild, officers = { { name, rank, cls, seen, online } } } oder nil
function NoGuild.ReturnInfo()
    if not ns.db or (IsInGuild and IsInGuild()) then return nil end
    local me = ns.me()
    local cg = ns.db.charGuild or {}
    local snap = ns.db.rsnap or {}
    local inSnap = {}
    for k, v in pairs(snap) do if type(v) == "table" and v.n then inSnap[v.n] = v end end
    local function guildOf(name)
        if cg[name] and cg[name].g then return cg[name].g end
        if inSnap[name] and snap.__guild then return snap.__guild end
    end
    local cands = {}
    for name in pairs(ns.db.chars or {}) do
        if name ~= me and sameRealm(name, me) and guildOf(name) then cands[#cands + 1] = name end
    end
    if #cands == 0 then return nil end
    local main = ns.Alts and ns.Alts.MyMain and ns.Alts.MyMain()
    local pick
    for _, n in ipairs(cands) do if n == main then pick = n end end
    if not pick then
        table.sort(cands, function(a, b) return ((ns.db.chars[a] or {}).level or 0) > ((ns.db.chars[b] or {}).level or 0) end)
        pick = cands[1]
    end
    local guild = guildOf(pick)
    local info = { main = pick, guild = guild, officers = {} }
    -- wer einladen darf: Gildenmeister + Offiziere (Rang-Index 0/1) aus der letzten Gildenliste
    if snap.__guild == guild then
        for name, v in pairs(inSnap) do
            local isMine = ns.db.chars and ns.db.chars[name]
            if not isMine and (tonumber(v.ri) or 99) <= 1 and sameRealm(name, me) then
                local pr = ns.db.members and rawget(ns.db.members, name)
                local seen = (pr and (pr.seen or pr.u)) or v.seen or 0
                local on = ns.Contacts and ns.Contacts.FriendOnline and ns.Contacts.FriendOnline(name) or false
                info.officers[#info.officers + 1] = { name = name, rank = v.rank, cls = v.cls, seen = seen, online = on, ri = tonumber(v.ri) or 9 }
            end
        end
    end
    table.sort(info.officers, function(a, b)
        if a.online ~= b.online then return a.online end
        return (a.seen or 0) > (b.seen or 0)
    end)
    return info
end

-- Glaskarte im Dashboard
function NoGuild.BuildBack(parent)
    local f = CreateFrame("Frame", nil, parent)
    local ac = C.accent
    glass(f, { ac[1], ac[2], ac[3], 0.08 }, { ac[1], ac[2], ac[3], 0.45 }, 12)
    if not hasGlass() then K.Fill(f, C.panel) K.Border(f, C.line) end
    f.title = K.Title(f, 15, C.text)
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetText(L["Back to your guild?"])
    f.sub = K.Text(f, 12, C.muted)
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.sub:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.sub:SetWordWrap(false)
    f.none = K.Text(f, 11, C.dim)
    f.none:SetPoint("TOPLEFT", 16, -56)
    f.none:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.none:SetWordWrap(true)
    f.none:SetText(L["Who can invite is not known yet - log in once with your main and Oasis will remember the guild leadership."])
    -- Kopierfeld (nur wenn das Chatfenster nicht vorbereitet werden kann)
    f.copy = CreateFrame("EditBox", nil, f)
    f.copy:SetAutoFocus(false)
    f.copy:SetHeight(22)
    f.copy:SetPoint("BOTTOMLEFT", 16, 10)
    f.copy:SetPoint("RIGHT", f, "RIGHT", -16, 0)
    f.copy:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    glass(f.copy, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.12 }, 6)
    f.copy:SetTextInsets(8, 8, 0, 0)
    f.copy:SetScript("OnEscapePressed", function(self) self:ClearFocus() self:Hide() end)
    f.copy:Hide()    -- "Wer ist online?": /who nach der Gilde (nur per Klick erlaubt - Blizzard verlangt einen Tastendruck/Klick).    -- Ergebnis markiert Offiziere als online und nennt, wie viele aus der Gilde gerade da sind.    -- /who nach der Gilde; minGap = Mindestabstand in Sekunden    function NoGuild.SendWho(minGap)        local info = f.info or NoGuild.ReturnInfo()        local W = C_FriendList        if not (info and info.guild and W and W.SendWho) then return end        if GetTime() - (NoGuild.whoT or 0) < (minGap or 6) then return end        NoGuild.whoT = GetTime()        NoGuild.whoPending = info.guild        if W.SetWhoToUi then pcall(W.SetWhoToUi, true) end        pcall(W.SendWho, 'g-"' .. info.guild .. '"')        if f.check then f.check:SetLabel(L["Searching ..."]) end    end    f.check = K.Button(f, L["Who is online?"], 130, 22, "ghost", function() NoGuild.SendWho(6) end)    f.check:SetPoint("TOPRIGHT", -14, -12)    f.sub:SetPoint("RIGHT", f.check, "LEFT", -10, 0)    if not (C_FriendList and C_FriendList.SendWho) then f.check:Hide() end    NoGuild.EnsureWhoEv()    NoGuild.backCard = f
    f.rows = {}
    for i = 1, 4 do
        local r = CreateFrame("Frame", nil, f)
        r:SetHeight(30)
        r:SetPoint("TOPLEFT", 10, -52 - (i - 1) * 32)
        r:SetPoint("RIGHT", f, "RIGHT", -10, 0)
        r.ring = r:CreateTexture(nil, "ARTWORK")
        r.ring:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        r.ring:SetSize(24, 24)
        r.ring:SetPoint("LEFT", 6, 0)
        r.disc = r:CreateTexture(nil, "ARTWORK", nil, 1)
        r.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        r.disc:SetSize(21, 21)
        r.disc:SetPoint("CENTER", r.ring)
        r.disc:SetVertexColor(0.06, 0.06, 0.08, 1)
        r.cls = r:CreateTexture(nil, "ARTWORK", nil, 2)
        r.cls:SetSize(16, 16)
        r.cls:SetPoint("CENTER", r.ring)
        r.ini = K.Text(r, 10, C.text, "CENTER")
        r.ini:SetPoint("CENTER", r.ring, "CENTER", 0, 0)
        r.ini:SetWidth(24)
        r.dot = r:CreateTexture(nil, "OVERLAY")
        r.dot:SetTexture(ns.MEDIA .. "dot")
        r.dot:SetSize(8, 8)
        r.dot:SetPoint("CENTER", r.ring, "BOTTOMRIGHT", -2, 2)
        r.dot:SetVertexColor(C.mint[1], C.mint[2], C.mint[3])
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("LEFT", 40, 0)
        r.name:SetWidth(220)
        r.name:SetWordWrap(false)
        r.info = K.Text(r, 11, C.dim)
        r.info:SetPoint("LEFT", 264, 0)
        r.info:SetPoint("RIGHT", r, "RIGHT", -120, 0)
        r.info:SetWordWrap(false)
        r.btn = calmBtn(K.Button(r, L["Whisper"], 104, 22, "primary"), true)
        r.btn:SetPoint("RIGHT", 0, 0)
        f.rows[i] = r
    end
    function f:Fill(info)
        self.info = info
        if not info then self:Hide() return 0 end
        self:Show()
        self.sub:SetText((L["Your main %s is in <%s>."]):format(ns.colorName(info.main, (ns.db.chars[info.main] or {}).class), info.guild or "?"))        local wo = NoGuild.whoOnline        if wo then            for _, o in ipairs(info.officers) do                local key = ns.NameKey(o.name)                if wo[key] then o.online = true o.whoOn = true end            end            table.sort(info.officers, function(a2, b2)                if (a2.online and true or false) ~= (b2.online and true or false) then return a2.online and true or false end                return (a2.seen or 0) > (b2.seen or 0)            end)            local wc = NoGuild.whoCount or 0            self.sub:SetText(self.sub:GetText() .. "  " .. (wc > 0 and ("|cff66db9e" .. (L["%d from the guild online"]):format(wc) .. "|r") or ("|cff888888" .. L["nobody from the guild online right now"] .. "|r"))                .. "  |cff666666" .. (L["As of %s"]):format(ns.ago and ns.ago(NoGuild.whoAt or time()) or "") .. "|r")        end        if self.check then self.check:SetLabel(L["Who is online?"]) end
        local twink = ns.ChatName and ns.ChatName(ns.me()) or ns.short(ns.me())
        -- wer laut /who gerade online ist, steht oben (mit Namen); danach die Offiziere        local people, seenP = {}, {}        for _, w in ipairs(NoGuild.whoList or {}) do            local key = ns.NameKey(w.name)            local off            for _, o in ipairs(info.officers) do if ns.NameKey(o.name) == key then off = o end end            people[#people + 1] = off or { name = w.name, cls = w.cls, rank = (L["Level %s"]):format(w.lvl or "?") .. ((w.zone and w.zone ~= "") and ("  ·  " .. w.zone) or ""), online = true, whoOn = true }            seenP[key] = true        end        for _, o in ipairs(info.officers) do            local key = ns.NameKey(o.name)            if not seenP[key] then people[#people + 1] = o end        end        local n = math.min(#people, self.maxRows or #self.rows)
        for i, r in ipairs(self.rows) do
            local o = i <= n and people[i]
            if o then
                local cr, cg, cb = ns.classColor(o.cls)
                r.ring:SetVertexColor(cr or 0.5, cg or 0.5, cb or 0.5, 0.75)
                local GI = ns.GuildInfo
                local ok = o.cls and GI and GI.SetClassIcon and GI.SetClassIcon(r.cls, o.cls)
                r.cls:SetShown(ok and true or false)
                r.ini:SetShown(not ok)
                if not ok then r.ini:SetText(((ns.displayName(o.name) or "?"):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"):upper()) end
                r.dot:SetShown(o.online and true or false)
                r.name:SetText(ns.colorName(o.name, o.cls) .. "  |cff888888" .. (o.rank or "") .. "|r")
                r.info:SetText(o.whoOn and ("|cff66db9e" .. L["online now"] .. "|r") or ((o.seen or 0) > 0 and (L["last online"] .. " " .. (ns.ago and ns.ago(o.seen) or "?")) or ""))
                local target = ns.Comm and ns.Comm.WhisperName and ns.Comm.WhisperName(o.name) or ns.short(o.name)
                local text = (L["Hi! Could you invite my alt %s to the guild? Thanks!"]):format(twink)
                if ChatFrame_SendTell or ChatFrame_OpenChat then
                    r.btn:SetLabel(L["Whisper"])
                    -- ns.Whisper setzt den kompletten Namen als Ziel: "/w Lena Berg Hallo!" las WoW als
                    -- Ziel "Lena Hallo!" (Forever-Doppelnamen); der Text wird danach eingefuegt
                    r.btn:SetScript("OnClick", function() ns.Whisper(o.name, text) end)
                else
                    -- kein vorbereitetes Chatfenster: Text zum Kopieren anbieten (nichts wird automatisch gesendet)
                    r.btn:SetLabel(L["Copy text"])
                    r.btn:SetScript("OnClick", function()
                        self.copy:SetText("/w " .. target .. " " .. text)
                        self.copy:Show()
                        self.copy:SetFocus()
                        self.copy:HighlightText()
                    end)
                end
                r:Show()
            else
                r:Hide()
            end
        end
        self.none:SetShown(n == 0)
        local h = (n == 0 and 96 or (60 + n * 32)) + (self.copy:IsShown() and 30 or 0)
        self:SetHeight(h)
        return h
    end
    return f
end

-- Dashboard ohne Gilde: Karten in einer Reihe, darunter die Kontakte (die Midas-Karte setzt das Dashboard daneben)
function NoGuild.BuildArea(parent)
    local a = CreateFrame("Frame", nil, parent)
    NoGuild.Fill(a)
    a.hero:Hide()
    a.cards[#a.cards + 1] = a.find
    -- im Raster: "Gilde finden" als normale Karte mit kurzem Text
    a.find.text:SetText(L["WoW's guild finder helps - neutral, no ads."])
    a.back = NoGuild.BuildBack(a)
    function a:LayoutDash(W, sideW, avail)
        local gap = 10
        -- ganz oben: "Zurueck in deine Gilde?" (nur fuer Twinks, deren Main in einer Gilde ist)
        avail = avail or 9999
        local CT = 96
        local info = NoGuild.ReturnInfo()
        -- Platz sparen in dieser Reihenfolge: erst nur 2 Offiziere (Online-Offiziere stehen oben), dann kompakte Karten,
        -- dann Kontakte weglassen - die Midas-Karte bleibt
        self.back.maxRows = nil
        local off = self.back:Fill(info)
        if off > 0 and off + gap + 150 + gap + CT > avail then
            self.back.maxRows = 2
            off = self.back:Fill(info)
        end
        if off > 0 then
            self.back:ClearAllPoints()
            self.back:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
            self.back:SetWidth(W)
            off = off + gap
        end
        -- in die verfuegbare Hoehe einpassen: erst kompakte Karten (ohne Beschreibung), dann Kontakte/Midas-Zeile weglassen
        self.cardH = 150
        if off + 150 + gap + CT > avail then self.cardH = 96 end
        self.showBottom = off + self.cardH + gap + CT <= avail
        self.adFits = off + self.cardH + gap + 80 <= avail
        for _, c in ipairs(self.cards) do if c.text then c.text:SetShown(self.cardH > 100) end end
        self.ct:SetShown(self.showBottom)
        local n = #self.cards
        local cw = math.floor((W - gap * (n - 1)) / n)
        for i, c in ipairs(self.cards) do
            c:ClearAllPoints()
            c:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * (cw + gap), -off)
            c:SetSize(cw, self.cardH or 150)
            c.text:ClearAllPoints()
            c.text:SetPoint("TOPLEFT", 16, -62)
            c.text:SetPoint("RIGHT", c, "RIGHT", -16, 0)
            c.btn:ClearAllPoints()
            c.btn:SetPoint("BOTTOMLEFT", 16, 14)
            c.btn:SetWidth(math.max(60, math.min(150, cw - 32)))
        end
        self.ct:ClearAllPoints()
        self.ct:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -off - (self.cardH or 150) - gap)
        self.ct:SetWidth(math.max(200, W - (sideW or 0)))
        return off
    end
    return a
end

ns.RegisterPage({
    key = "noguild", title = "Welcome", order = 0.01, topbar = true,
    sub = "Oasis without a guild",
    visible = function() return not ns.InGuild() end,
    build = function(p)
        -- Hinweis, wenn eine Gildenseite geoeffnet wurde
        p.note = CreateFrame("Frame", nil, p)
        p.note:SetPoint("TOPLEFT", 0, 0)
        p.note:SetPoint("TOPRIGHT", 0, 0)
        p.note:SetHeight(44)
        glass(p.note, { C.amber[1], C.amber[2], C.amber[3], 0.10 }, { C.amber[1], C.amber[2], C.amber[3], 0.40 }, 10)
        p.note.t = K.Text(p.note, 12, C.text)
        p.note.t:SetPoint("LEFT", 14, 0)
        p.note.t:SetPoint("RIGHT", p.note, "RIGHT", -150, 0)
        p.note.t:SetWordWrap(true)
        p.note.btn = calmBtn(K.Button(p.note, L["Find a guild"], 126, 26, "primary", function() NoGuild.OpenFinder() end), true)
        p.note.btn:SetPoint("RIGHT", -10, 0)
        p.note:Hide()

        NoGuild.Fill(p)
        p.hero.logo:SetSize(64, 64)

        function p:Layout()
            local W = self:GetWidth() or 800
            if W < 300 then W = 800 end
            local y = self.note:IsShown() and -54 or 0
            self.hero:ClearAllPoints()
            self.hero:SetPoint("TOPLEFT", 0, y)
            self.hero:SetPoint("TOPRIGHT", 0, y)
            local gap = 12
            local cw = math.floor((W - 2 * gap) / 3)
            for i, c in ipairs(self.cards) do
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", (i - 1) * (cw + gap), y - 112 - 14)
                c:SetWidth(cw)
            end
            self.find:ClearAllPoints()
            self.find:SetPoint("TOPLEFT", 0, y - 112 - 14 - 150 - 14)
            self.find:SetPoint("RIGHT", self, "RIGHT", 0, 0)
            self.ct:ClearAllPoints()
            self.ct:SetPoint("TOPLEFT", 0, y - 112 - 14 - 150 - 14 - 96 - 14)
            self.ct:SetPoint("RIGHT", self, "RIGHT", 0, 0)
        end
        p:SetScript("OnSizeChanged", function(self) self:Layout() end)
    end,
    refresh = function(p)
        local def = ns.PageDef("noguild")
        local blocked = def and def.blocked
        if blocked then
            local bd = ns.PageDef(blocked)
            local name = bd and L[bd.title] or blocked
            p.note.t:SetText((L["\"%s\" needs a guild - without one there is nothing to see here."]):format(name))
        end
        p.note:SetShown(blocked ~= nil)
        p:FillContacts()
        p:Layout()
    end,
})-- automatisch nachsehen, wer online ist: nur aus einem Klick/Tastendruck heraus (Blizzard-Regel fuer /who)-- -> beim Oeffnen von Oasis und bei jedem Navigations-Klick, hoechstens jede Minutefunction NoGuild.AutoWho()    if IsInGuild() then return end    NoGuild.EnsureWhoEv()    if NoGuild.SendWho then NoGuild.SendWho(60) return end    -- Karte noch nicht gebaut (erstes Oeffnen): direkt fragen    local info = NoGuild.ReturnInfo()    local W = C_FriendList    if not (info and info.guild and W and W.SendWho) then return end    if GetTime() - (NoGuild.whoT or 0) < 60 then return end    NoGuild.whoT = GetTime()    NoGuild.whoPending = info.guild    if W.SetWhoToUi then pcall(W.SetWhoToUi, true) end    pcall(W.SendWho, 'g-"' .. info.guild .. '"')endfunction NoGuild.EnsureWhoEv()if not NoGuild.whoEv then    local ev = CreateFrame("Frame")    ev:RegisterEvent("WHO_LIST_UPDATE")    ev:SetScript("OnEvent", function()        local g = NoGuild.whoPending        if not g then return end        NoGuild.whoPending = nil        local W = C_FriendList        local on, n, list = {}, 0, {}        local num = W and W.GetNumWhoResults and select(1, W.GetNumWhoResults()) or 0        for k = 1, num do            local ok, wi = pcall(W.GetWhoInfo, k)            if ok and type(wi) == "table" then                local nm = ns.safe(wi.fullName)                local gn = ns.safe(wi.fullGuildName)                -- nur wer wirklich in DIESER Gilde ist (ohne Gildennamen = andere Treffer, nicht zaehlen)                if nm and gn and gn ~= "" and gn:lower() == g:lower() then                    on[ns.NameKey(nm)] = true                    n = n + 1                    list[#list + 1] = { name = nm, cls = ns.safe(wi.filename), lvl = ns.safe(wi.level), zone = ns.safe(wi.area) }                end            end        end        NoGuild.whoOnline, NoGuild.whoCount, NoGuild.whoAt, NoGuild.whoList = on, n, time(), list        -- die Blizzard-Wer-Liste nicht offen stehen lassen        if FriendsFrame and FriendsFrame:IsShown() and WhoFrame and WhoFrame:IsShown() then pcall(HideUIPanel, FriendsFrame) end        if NoGuild.backCard and NoGuild.backCard.info then NoGuild.backCard:Fill(NoGuild.backCard.info) end    end)    NoGuild.whoEv = evendend
-- Oasis - Soft-Reserve: pro Raidtermin reserviert jeder (Main) ein Item. Sichtbar auf der Seite und im Item-Tooltip.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Raidwerkzeuge", function()   -- Modul Raidwerkzeuge (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C = ns.K, ns.K.C
local Store = ns.Store

local SR = {}
ns.SoftRes = SR
if ns.ICONS then ns.ICONS.softres = ns.MEDIA .. "icons\\wants" end

-- Gilden-Optionen (Gildenleitung legt fest; Standard = bisheriges Verhalten)
ns.GuildOption({ page = "softres", key = "srRank", default = 10, min = 1, max = 10, step = 1,
    label = "Reservieren erlaubt", desc = "Bis zu welchem Gildenrang Mitglieder Items reservieren duerfen. 10 = alle.",
    fmt = function(v) return (ns.L["bis Rang %d"]):format(v) end })
ns.GuildOption({ page = "softres", key = "srDays", default = 7, min = 1, max = 14, step = 1,
    label = "Tooltip-Vorschau", desc = "Reservierungen aus Terminen der naechsten so vielen Tage stehen im Item-Tooltip.",
    fmt = function(v) return v .. " Tg" end })
local function mayReserve()
    local v = tonumber(ns.GuildOpt("srRank")) or 10
    if v >= 10 then return true end
    if ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage() then return true end
    local ri = ns.Admin and ns.Admin.RankOf and ns.Admin.RankOf(ns.me())
    if ri == nil then return true end
    return ri + 1 <= v
end

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local function mainOf(n) return ns.Alts and ns.Alts.Main(n) or n end
local function rid(evId, who) return evId .. "@" .. mainOf(who) end

function SR.Mine(evId) local r = Store.Get("sres", rid(evId, ns.me())) return r and not r.del and r or nil end
function SR.Of(evId) return Store.List("sres", function(r) return r.ev == evId end) end
function SR.Reserve(ev, itemID)
    if not ev or not itemID then return end
    if not mayReserve() then ns.print(L["Reservieren ist bei euch nur fuer hoehere Gildenraenge freigegeben."]) return end
    Store.Put("sres", { id = rid(ev.id, ns.me()), ev = ev.id, item = itemID, who = mainOf(ns.me()), char = ns.me(), ts = ns.now() })
end
function SR.Clear(evId) Store.Delete("sres", rid(evId, ns.me())) end

-- Import von softres.it: dort "CSV" exportieren (Spalten u.a. ItemId, Name) und hier einfuegen.
-- Spielernamen werden ueber die Gildenliste (Vorname) zugeordnet, sonst so uebernommen.
local function splitCSV(line)
    local out, cur, q = {}, "", false
    for ch in line:gmatch(".") do
        if ch == '"' then q = not q
        elseif (ch == "," or ch == ";" or ch == "\t") and not q then out[#out + 1] = cur cur = ""
        else cur = cur .. ch end
    end
    out[#out + 1] = cur
    for i, v in ipairs(out) do out[i] = v:gsub("^%s+", ""):gsub("%s+$", "") end
    return out
end
local function findMember(name)
    local full = ns.ResolveName(name)
    local m = full and ns.Radar and ns.Radar.byName and ns.Radar.byName[full]
    return m and m.name
end
function SR.ImportCSV(ev, text)
    if not ev or not text then return 0, 0 end
    local idCol, nameCol, n, unknown = nil, nil, 0, {}
    local per = {}
    for line in text:gmatch("[^\r\n]+") do
        local f = splitCSV(line)
        if not idCol then
            for i, v in ipairs(f) do
                local l = v:lower():gsub("[%s_]", "")
                if l == "itemid" or l == "item id" or l == "id" then idCol = i end
                if l == "name" or l == "player" or l == "charactername" then nameCol = i end
            end
            if not idCol then idCol, nameCol = 1, 2 end   -- ohne Kopfzeile: ItemId,Name
            if tonumber(f[idCol] or "") == nil then f = nil end   -- war die Kopfzeile
        end
        if f then
            local id, who = tonumber(f[idCol] or ""), f[nameCol or 2]
            if id and who and who ~= "" then
                local full = findMember(who)
                if not full then unknown[#unknown + 1] = who end
                local main = full and mainOf(full) or who
                per[main] = (per[main] or 0) + 1
                -- softres.it erlaubt mehrere Items je Spieler: ab dem zweiten eigene ID
                local id2 = ev.id .. "@" .. main .. (per[main] > 1 and ("#" .. per[main]) or "")
                Store.Put("sres", { id = id2, ev = ev.id, item = id, who = main, char = full or who, ts = ns.now(), src = "softres.it" })
                n = n + 1
            end
        end
    end
    return n, unknown
end
-- Reservierungsseite direkt mit diesem Termin oeffnen (Termin-Karten auf der Raid-Seite)
function SR.Open(ev)
    SR.wantEv = ev
    ns.ShowPage("softres")
    ns.RefreshPage("softres")
end
-- Reservierungen fuer ein Item in anstehenden Terminen (naechste 7 Tage)
function SR.ForItem(itemID)
    local now, out = ns.now(), {}
    local evs = {}
    for _, e in ipairs(Store.List("events")) do if (e.ts or 0) > now - 6 * 3600 and (e.ts or 0) < now + (tonumber(ns.GuildOpt("srDays")) or 7) * 86400 then evs[e.id] = e end end
    for _, r in ipairs(Store.List("sres")) do
        if r.item == itemID and evs[r.ev] then out[#out + 1] = r.who end
    end
    return out
end

-- Item-Tooltip: wer hat es reserviert?
local function onItem(tt)
    local ok, _, link = pcall(tt.GetItem, tt)
    if not ok or not link then return end
    local st = ns.db and ns.db.settings or {}
    if st.srTooltip == false then return end
    if st.srTooltipGroupOnly and not IsInGroup() then return end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return end
    local who = SR.ForItem(id)
    if #who == 0 then return end
    local names = {}
    for i, n in ipairs(who) do if i > 8 then names[#names + 1] = "+" .. (#who - 8) break end names[#names + 1] = ns.displayName(n) end
    tt:AddLine("|cffe8b44a" .. L["Oasis-Reserviert"] .. ":|r " .. table.concat(names, ", "), 1, 1, 1, true)
end
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt)
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        pcall(onItem, tt)
    end)
else
    for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
        if tt and tt.HasScript and tt:HasScript("OnTooltipSetItem") then tt:HookScript("OnTooltipSetItem", function(self) pcall(onItem, self) end) end
    end
end

-- Shift-Klick auf ein Item schreibt den Link ins Eingabefeld der Seite
local linkBox
if hooksecurefunc and ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if linkBox and linkBox:IsVisible() and linkBox:HasFocus() and link then linkBox:SetText(link) end
    end)
end

local page
ns.RegisterPage({
    key = "softres", title = "Reservierungen", order = 5.05,
    sub = "Soft-Reserve: pro Raidtermin ein Item reservieren - alle sehen es im Tooltip",
    build = function(p)
        page = p
        p.evBtns = {}
        local back = K.Button(p, "< " .. L["Raids & Beute"], 150, 22, "ghost", function() ns.ShowPage("raid") end)
        back:Hide()   -- 0.5.847: Reservierungen sind ein Reiter der Raids-Seite, der Zurueck-Knopf ist ueberfluessig
        back:SetPoint("TOPRIGHT", 0, 0)
        local h = K.GameHead(p, L["Raidtermin"], C.amber)
        h:SetPoint("TOPLEFT", 0, 0)
        h:SetWidth(300)
        p.none = K.Text(p, 12, C.muted)
        p.none:SetPoint("TOPLEFT", 0, -30)
        p.none:SetText(L["Keine anstehenden Termine. Sobald unter Termine einer steht, kannst du hier reservieren."])

        local h2 = K.GameHead(p, L["Deine Reservierung"], C.mint)
        h2:SetPoint("TOPLEFT", 0, -78)
        h2:SetWidth(300)
        p.mine = K.Text(p, 13, C.text)
        p.mine:SetPoint("TOPLEFT", 0, -106)
        p.link = K.Input(p, 320, L["Item per Shift-Klick einfuegen oder Item-ID"], nil)
        p.link:SetPoint("TOPLEFT", 0, -132)
        linkBox = p.link
        p.res = K.Button(p, L["Reservieren"], 130, 24, "primary", function()
            local t = p.link:GetText() or ""
            local id = tonumber(t:match("item:(%d+)") or t:match("^%s*(%d+)%s*$"))
            if not id then ns.print(L["Kein Item erkannt - Shift-Klick auf ein Item oder die Item-ID eingeben."]) return end
            SR.Reserve(p.ev, id)
            p.link:SetText("")
            p.link:ClearFocus()
            ns.RefreshPage("softres")
        end)
        p.res:SetPoint("LEFT", p.link, "RIGHT", 8, 0)
        p.clr = K.Button(p, L["Aufheben"], 100, 24, "ghost", function() if p.ev then SR.Clear(p.ev.id) ns.RefreshPage("softres") end end)
        p.clr:SetPoint("LEFT", p.res, "RIGHT", 8, 0)

        -- Import von softres.it (Leitung / Raidleiter)
        p.impBtn = K.Button(p, L["Import (softres.it)"], 150, 22, "ghost", function() p.imp:SetShown(not p.imp:IsShown()) end)
        p.impBtn:SetPoint("TOPRIGHT", -158, 0)
        p.imp = K.Panel(p, C.panel)
        p.imp:SetPoint("TOPLEFT", 0, -176)
        p.imp:SetPoint("BOTTOMRIGHT", 0, 0)
        p.imp:SetFrameLevel(p:GetFrameLevel() + 20)
        p.imp:Hide()
        local ih = K.Text(p.imp, 11, C.muted)
        ih:SetPoint("TOPLEFT", 14, -12)
        ih:SetPoint("RIGHT", p.imp, "RIGHT", -14, 0)
        ih:SetWordWrap(true)
        ih:SetText(L["Auf softres.it beim Raid 'CSV' exportieren, kopieren und hier einfuegen (Strg+V). Die Reservierungen landen beim oben gewaehlten Termin."])
        p.impBox = CreateFrame("EditBox", nil, p.imp)
        p.impBox:SetMultiLine(true)
        p.impBox:SetAutoFocus(false)
        p.impBox:SetFont(K.FONT, 11, "")
        p.impBox:SetTextColor(C.text[1], C.text[2], C.text[3])
        p.impBox:SetMaxLetters(0)
        p.impBox:SetPoint("TOPLEFT", 14, -48)
        p.impBox:SetPoint("BOTTOMRIGHT", -14, 48)
        p.impBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local ibg = p.imp:CreateTexture(nil, "BACKGROUND", nil, 2)
        ibg:SetPoint("TOPLEFT", p.impBox, -6, 6) ibg:SetPoint("BOTTOMRIGHT", p.impBox, 6, -6)
        ibg:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
        p.impState = K.Text(p.imp, 11, C.muted)
        p.impState:SetPoint("BOTTOMLEFT", 14, 18)
        p.impState:SetPoint("RIGHT", p.imp, "RIGHT", -240, 0)
        p.impState:SetWordWrap(false)
        local go = K.Button(p.imp, L["Uebernehmen"], 120, 24, "primary", function()
            if not p.ev then return end
            local n, unknown = SR.ImportCSV(p.ev, p.impBox:GetText() or "")
            if n == 0 then p.impState:SetText("|cffff5a4a" .. L["Nichts erkannt - ist das der CSV-Export von softres.it?"] .. "|r") return end
            p.impState:SetText("|cff66db9e" .. (L["%d Reservierungen uebernommen"]):format(n) .. "|r"
                .. (#unknown > 0 and ("  |cffe8b44a" .. L["nicht in der Gilde"] .. ": " .. table.concat(unknown, ", ") .. "|r") or ""))
            p.impBox:SetText("")
            ns.RefreshPage("softres")
        end)
        go:SetPoint("BOTTOMRIGHT", -14, 12)
        local cancel = K.Button(p.imp, L["Schliessen"], 100, 24, "ghost", function() p.imp:Hide() end)
        cancel:SetPoint("RIGHT", go, "LEFT", -8, 0)

        local h3 = K.GameHead(p, L["Alle Reservierungen"], C.blue)
        h3:SetPoint("TOPLEFT", 0, -176)
        h3:SetWidth(300)
        p.count = K.Text(p, 11, C.dim, "RIGHT")
        p.count:SetPoint("TOPRIGHT", 0, -180)
        p.list = K.List(p, 30, function(l)
            local r = K.Row(l)
            r.icon = r:CreateTexture(nil, "ARTWORK")
            r.icon:SetSize(22, 22)
            r.icon:SetPoint("LEFT", 8, 0)
            r:Col("item", 38, 300, 12)
            r:Col("n", 350, 40, 13, C.amber, "CENTER")
            r:Col("who", 400, 420, 12, C.muted)
            r:SetScript("OnEnter", function(self)
                if not self.e then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.e.item)
                GameTooltip:Show()
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, e)
            r.e = e
            local name, link, _, _, _, _, _, _, _, tex = GetItemInfo(e.item)
            r.icon:SetTexture(tex or (GetItemIcon and GetItemIcon(e.item)))
            r.cols.item:SetText(link or name or ("Item " .. e.item))
            r.cols.n:SetText(#e.who > 1 and ("|cffff5a4a" .. #e.who .. "|r") or #e.who)
            local names = {}
            for _, n in ipairs(e.who) do names[#names + 1] = ns.isMe(n) and ("|cff66db9e" .. ns.displayName(n) .. "|r") or ns.displayName(n) end
            r.cols.who:SetText(table.concat(names, ", "))
        end)
        p.list:SetPoint("TOPLEFT", 0, -202)
        p.list:SetPoint("BOTTOMRIGHT", 0, 0)
        p.list.empty:SetText(L["Noch nichts reserviert."])
    end,
    refresh = function(p)
        local evs = ns.Raid and ns.Raid.Events and ns.Raid.Events() or {}
        if SR.wantEv then p.ev = SR.wantEv SR.wantEv = nil end
        if not p.ev or not Store.Get("events", p.ev.id) then p.ev = evs[1] end
        for _, b in ipairs(p.evBtns) do b:Hide() end
        local x = 0
        for i, ev in ipairs(evs) do
            if i > 6 then break end
            local b = p.evBtns[i]
            if not b then
                b = K.Button(p, "", 0, 26, "ghost", function(self) p.ev = self.ev ns.RefreshPage("softres") end)
                p.evBtns[i] = b
            end
            b.ev = ev
            b.label:SetText((ev.title or "?") .. "  |cff888888" .. date("%d.%m. %H:%M", ev.ts or 0) .. "|r")
            b:SetWidth(b.label:GetStringWidth() + 24)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, -28)
            K.SetBorderColor(b, (p.ev and p.ev.id == ev.id) and C.accent or C.line)
            b:Show()
            x = x + b:GetWidth() + 6
        end
        p.none:SetShown(#evs == 0)
        local has = p.ev ~= nil
        p.link:SetShown(has) p.res:SetShown(has) p.clr:SetShown(has)
        local lead = (ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage()) or (IsInGroup() and ns.isGroupLead())
        p.impBtn:SetShown(has)
        K.LockButton(p.impBtn, function() return (ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage()) or (IsInGroup() and ns.isGroupLead()) end, "grouplead")
        if not has or not lead then p.imp:Hide() end
        if not has then p.mine:SetText("") p.list:SetData({}) p.count:SetText("") return end
        local mine = SR.Mine(p.ev.id)
        if mine then
            local _, link = GetItemInfo(mine.item)
            p.mine:SetText((L["Reserviert: %s"]):format(link or ("Item " .. mine.item)))
        else
            p.mine:SetText("|cff888888" .. L["Noch nichts reserviert - ein Item pro Termin."] .. "|r")
        end
        local by = {}
        for _, r in ipairs(SR.Of(p.ev.id)) do
            by[r.item] = by[r.item] or { item = r.item, who = {} }
            table.insert(by[r.item].who, r.who)
        end
        local out = {}
        for _, e in pairs(by) do out[#out + 1] = e end
        table.sort(out, function(a, b) if #a.who ~= #b.who then return #a.who > #b.who end return a.item < b.item end)
        p.count:SetText((L["%d Items reserviert"]):format(#out))
        p.list:SetData(out)
    end,
})
ns.Listen("STORE", function(coll) if coll == "sres" and ns.CurrentPage and ns.CurrentPage() == "softres" then ns.RefreshPage("softres") end end)
end)

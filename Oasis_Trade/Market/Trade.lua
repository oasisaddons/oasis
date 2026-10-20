-- Oasis: Markt & Handel - Midas fuer die ganze Gilde
-- Midas (AH-Addon von Rebo) ist NICHT Teil von Oasis - wer es selbst installiert, bekommt hier mehr.
-- Ohne Midas laeuft alles wie bisher (Preise nur aus Oasis' eigener AH-Beobachtung). Mit Midas gibt es:
--   Wunschliste-Alarm (guenstige Wunsch-Items im AH), Preisabfrage im Gildenchat ("pc [Item]"),
--   AH-Stand fuer die Gilde (wer hat wann gescannt), Wert-Verlauf der Gildenbank und eine freiwillige
--   Haendler-Rangliste ("Goldmacher der Woche").
local ADDON, ns = ...  ns = Oasis or ns  -- Teil-Addon: Namensraum von Oasis
ns.ModuleFile("Oasis_Market", function()   -- Modul Handel (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L
local K, C, Comm, Store = ns.K, ns.K.C, ns.Comm, ns.Store
-- Sicherheit beim Empfang (Addon-Nachrichten anderer koennen manipuliert sein):
-- Texte entschaerfen, Zahlen begrenzen, Namen pruefen, Flut drosseln
local SEC = {}
do
    local function cut(s, max)
        if not max or #s <= max then return s end
        return (s:sub(1, max):gsub("[\192-\255][\128-\191]*$", ""))
    end
    -- Escape-Sequenzen (|c |r |n |H |T |K |A ...) und Steuerzeichen unschaedlich; links: gueltige Item-/Zauberlinks bleiben
    function SEC.Text(s, max, links)
        if s == nil then return "" end
        s = tostring(s):gsub("[%z\1-\31\127]", " ")
        local keep
        if links then
            keep = {}
            s = s:gsub("(|c([^|]-)|H(%a+):([^|]*)|h(%[[^|%]]*%])|h|r)", function(all, col, kind, data)
                if #keep < 8 and (kind == "item" or kind == "spell") and data:match("^[%d:%-]+$")
                    and (col:match("^%x%x%x%x%x%x%x%x$") or col:match("^n[%w_]+:$")) then
                    keep[#keep + 1] = all
                    return "\1" .. #keep .. "\2"
                end
            end)
        end
        s = cut((s:gsub("|", "/")), max)
        if keep then s = s:gsub("\1%d*$", ""):gsub("\1(%d+)\2", function(i) return keep[tonumber(i)] or "" end) end
        return s
    end
    function SEC.Link(s)
        if type(s) ~= "string" or #s > 300 then return nil end
        local col = s:match("^|c([^|]-)|Hitem:[%d:%-]+|h%[[^|%]]*%]|h|r$")
        if not col or not (col:match("^%x%x%x%x%x%x%x%x$") or col:match("^n[%w_]+:$")) then return nil end
        return s
    end
    function SEC.Num(v, lo, hi, int)
        v = tonumber(v)
        if not v or v ~= v or v < lo or v > hi then return nil end
        if int then v = math.floor(v) end
        return v
    end
    function SEC.Name(s)
        if type(s) ~= "string" or s == "" or #s > 64 or s:find("[|%c]") then return nil end
        return s
    end
    local last, lastN = {}, 0
    function SEC.Rate(key, sec)
        local now = GetTime()
        local t = last[key]
        if t and now - t < sec then return false end
        if not t then lastN = lastN + 1 if lastN > 500 then last, lastN = {}, 0 end end
        last[key] = now
        return true
    end
end

local Trade = {}
ns.Trade = Trade

local function S() return ns.db.settings end
local function api() return _G.MidasAPI end

------------------------------------------------------------------------
-- Hilfen
------------------------------------------------------------------------
-- Gold ohne Farbcodes (Gildenchat erlaubt keine |c-Codes)
function Trade.Plain(copper)
    if not copper then return "?" end
    copper = math.floor(copper + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
    if g > 0 then return s > 0 and (g .. "g " .. s .. "s") or (g .. "g") end
    if s > 0 then return c > 0 and (s .. "s " .. c .. "c") or (s .. "s") end
    return c .. "c"
end
-- +/- mit Farbe
function Trade.Signed(copper)
    if not copper then return "–" end
    local txt = ns.Market.Format(math.abs(copper))
    return copper >= 0 and ("|cff66db9e+|r" .. txt) or ("|cffff5a4a-|r" .. txt)
end

-- Marktdaten eines Items: { cur, fair, floor7, fresh } oder nil
function Trade.Info(itemID)
    if not itemID or itemID == 0 or not ns.Market then return nil end
    local info = ns.Market.Info(itemID)
    if info and (info.fair or info.current) then
        local lastDay = api() and api().GetLastScanDay and select(2, pcall(api().GetLastScanDay))
        return {
            cur = info.current, fair = info.fair or info.median, floor7 = info.floor7, min = info.min,
            fresh = (type(lastDay) == "number" and info.lastDay == lastDay) and true or false,
            src = "midas",
        }
    end
    local p, src, ts = ns.Market.Price(itemID)
    if p then return { cur = p, fair = p, fresh = ts and (ns.now() - ts) < 86400 or false, src = src } end
    return nil
end

------------------------------------------------------------------------
-- 4) AH-Stand: wann wurde zuletzt gescannt und von wem
------------------------------------------------------------------------
function Trade.MyScanTime()
    local a = api()
    if not (a and a.GetLastScanTime) then return nil end
    local ok, t = pcall(a.GetLastScanTime)
    return (ok and type(t) == "number" and t > 0) and t or nil
end
-- neuester Scan in der Gilde -> ts, Name
function Trade.LatestScan()
    local best, who = Trade.MyScanTime(), ns.me()
    for name, p in pairs(ns.db.members) do
        if type(p) == "table" and type(p.ah) == "number" and p.ah <= ns.now() + 300 and (not best or p.ah > best) then
            best, who = p.ah, name
        end
    end
    if not best then return nil end
    return best, who
end
-- Farbe nach Alter: frisch gruen, heute grau, aelter gelb
function Trade.ScanColor(ts)
    if not ts then return C.dim end
    local age = ns.now() - ts
    return age < 6 * 3600 and C.mint or age < 86400 and C.muted or C.amber
end

------------------------------------------------------------------------
-- 1) Wunschliste-Alarm
------------------------------------------------------------------------
ns.GuildOption({ page = "trade", key = "trCheap", default = 85, min = 50, max = 95, step = 5, label = "Want alert at price",
    desc = "A want counts as cheap if it costs at most this share of the fair price",
    fmt = function(v) return v .. " %" end })
ns.GuildOption({ page = "trade", key = "trAlrtH", default = 12, min = 1, max = 48, step = 1, label = "Want alert cooldown",
    desc = "The same want is not reported again for this long",
    fmt = function(v) return v .. " Std" end })
ns.GuildOption({ page = "trade", key = "trPcAns", default = true, label = "Answer price questions in guild chat",
    desc = "Oasis automatically answers pc / price with an item link in guild chat" })
local function CHEAPF() return (tonumber(ns.GuildOpt("trCheap")) or 85) / 100 end   -- Anteil vom fairen Preis
local function ALERTF() return (tonumber(ns.GuildOpt("trAlrtH")) or 12) * 3600 end

local function alerted(key)
    ns.db.ahAlerts = ns.db.ahAlerts or {}
    local t = ns.db.ahAlerts[key]
    if t and ns.now() - t < ALERTF() then return true end
    ns.db.ahAlerts[key] = ns.now()
    -- alte Eintraege aufraeumen
    for k, v in pairs(ns.db.ahAlerts) do if ns.now() - v > 7 * 86400 then ns.db.ahAlerts[k] = nil end end
    return false
end

-- guenstige Wunsch-Items der ganzen Gilde -> { {want, info, pct}, ... }
function Trade.CheapWants()
    local out, seen = {}, {}
    for _, w in ipairs(Store.List("wants")) do
        local id = w.itemID
        if id and id ~= 0 and not w.offer then
            local info = seen[id]
            if info == nil then info = Trade.Info(id) or false seen[id] = info end
            if info and info.src == "midas" and info.fresh and info.cur and info.fair and info.fair > 0 and info.cur <= info.fair * CHEAPF() then
                out[#out + 1] = { want = w, info = info, pct = math.floor((1 - info.cur / info.fair) * 100 + 0.5) }
            end
        end
    end
    table.sort(out, function(a, b) return a.pct > b.pct end)
    return out
end

local function wantToast(itemID, name, cur, fair, finder)
    local pct = (fair and fair > 0) and math.floor((1 - cur / fair) * 100 + 0.5) or 0
    local title = L["Wishlist: cheap in the AH"]
    local body = (name or ("#" .. itemID)) .. "  ~" .. ns.Market.Format(cur)
        .. (pct > 0 and ("  |cff66db9e" .. (L["%d%% below fair"]):format(pct) .. "|r") or "")
        .. (finder and ("  |cff888888- " .. (L["spotted by %s"]):format(ns.displayName(finder)) .. "|r") or "")
    K.Toast(title, body, C.mint, function() ns.ShowPage("trade") end, "announce")
end

-- nach einem eigenen Scan: eigene Wuensche melden, andere Wuenschende per Addon-Nachricht informieren
function Trade.CheckWants()
    if S().wantAlarm == false then return end
    for _, hit in ipairs(Trade.CheapWants()) do
        local w, info = hit.want, hit.info
        if w.demo or tostring(w.id or ""):find("^demo") then
            -- Demo-Wunsch: nie jemanden anfluestern
        elseif ns.isMe(w.who) then
            if not alerted("me-" .. w.itemID) then wantToast(w.itemID, w.link or w.name, info.cur, info.fair) end
        elseif not alerted(w.who .. "-" .. w.itemID) then
            Comm.Whisper(w.who, "WANTAH", w.itemID, math.floor(info.cur), math.floor(info.fair))
        end
    end
end
Comm.On("WANTAH", function(sender, _, id, cur, fair)
    id, cur, fair = SEC.Num(id, 1, 1e8, true), SEC.Num(cur, 0, 1e11), SEC.Num(fair, 0, 1e11)
    if not (id and cur) or S().wantAlarm == false then return end
    -- nur, wenn es wirklich noch auf meiner Wunschliste steht
    local mine
    for _, w in ipairs(Store.List("wants")) do if w.itemID == id and ns.isMe(w.who) and not w.offer then mine = w end end
    if not mine or alerted("me-" .. id) then return end
    wantToast(id, mine.link or mine.name, cur, fair, sender)
end)

------------------------------------------------------------------------
-- 3) Preisabfrage im Gildenchat: "pc [Item]" / "preis [Item]"
-- Genau einer antwortet: jeder mit Preisdaten wartet kurz (frische Daten kuerzer),
-- der Erste meldet per Addon-Nachricht "erledigt", alle anderen lassen es.
------------------------------------------------------------------------
local claimed = {}   -- Frage-Hash -> Zeitpunkt der Antwort (1 Minute gesperrt)
local asked = {}     -- Frage-Hash -> Zeitpunkt, zu dem die Frage im Gildenchat stand
local TRIGGERS = { "pc", "preis", "price", "prix", "precio", "preco", "prezzo", "цена", "?" }

local function isQuestion(msg)
    local first = msg:match("^%s*(%S+)")
    if not first then return false end
    first = first:lower()
    for _, t in ipairs(TRIGGERS) do if first == t or first == t .. ":" then return true end end
    return false
end

function Trade.PriceLine(itemID, link)
    local info = Trade.Info(itemID)
    if not info then return nil end
    local parts = { "[Oasis] " .. (link or ("#" .. itemID)) .. ":" }
    if info.fair then parts[#parts + 1] = L["fair"] .. " ~" .. Trade.Plain(info.fair) end
    if info.cur and info.cur ~= info.fair then parts[#parts + 1] = L["now"] .. " " .. Trade.Plain(info.cur) end
    if info.floor7 then parts[#parts + 1] = L["7-day low"] .. " " .. Trade.Plain(info.floor7) end
    local ts = Trade.LatestScan()
    if ts then parts[#parts + 1] = "(" .. L["Last update"] .. " " .. ns.ago(ts) .. ")" end
    return table.concat(parts, "  ")
end

ns.On("CHAT_MSG_GUILD", function(msg, sender)
    msg = ns.safe(msg)
    if type(msg) ~= "string" or S().priceAnswer == false or ns.GuildOpt("trPcAns") == false or not isQuestion(msg) then return end
    local link = msg:match("|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r") or msg:match("|Hitem:[^|]+|h%[[^%]]+%]|h")
    local id = link and ns.itemID(link)
    if not id then return end
    local key = ns.hash(msg)
    asked[key] = GetTime()
    -- automatische Antwort im Gildenchat drosseln: je Fragendem alle 30 s, insgesamt alle 8 s
    local who = ns.safe(sender) or "?"
    if not SEC.Rate("pcq:" .. who, 30) or not SEC.Rate("pcq-all", 8) then return end
    if claimed[key] and GetTime() - claimed[key] < 60 then return end
    local line = Trade.PriceLine(id, link)
    if not line then return end
    local info = Trade.Info(id)
    -- frische Midas-Daten antworten zuerst, eigene Frage zuletzt
    local base = (info and info.fresh and info.src == "midas") and 0.3 or 1.6
    if ns.isMe(ns.safe(sender) or "") then base = base + 2 end
    local delay = base + (tonumber(ns.hash(ns.me() .. key), 16) % 12) / 10
    ns.After(delay, function()
        if claimed[key] and GetTime() - claimed[key] < 60 then return end
        claimed[key] = GetTime()
        Comm.Guild("PCDONE", key)
        ns.OfferChat(L["Price question in guild chat"], line:sub(1, 250), "GUILD", nil, ns.K.C.amber)
    end)
end)
-- "erledigt" nur fuer eine Frage, die gerade wirklich im Gildenchat stand, und nur von Gildenmitgliedern
-- (sonst koennte ein gefaelschtes PCDONE jede Antwort im Voraus unterdruecken)
Comm.On("PCDONE", function(sender, _, key)
    if not key or not asked[key] or GetTime() - asked[key] > 30 then return end
    if Comm.FromGuild and not Comm.FromGuild(sender) then return end
    claimed[key] = GetTime()
end)

------------------------------------------------------------------------
-- 5) Gildenbank: Wert je Tag (geteilt, damit alle den Verlauf sehen)
------------------------------------------------------------------------
local function dayKey(ts) return date("%Y%m%d", ts or ns.now()) end

function Trade.BankWorth()
    local Bank = ns.GuildBank
    if not (Bank and Bank.Tabs and Bank.TabStats) then return 0 end
    local worth = 0
    for _, t in ipairs(Bank.Tabs()) do
        local ok, _, w = pcall(Bank.TabStats, t)
        if ok and w then worth = worth + w end
    end
    return worth
end
function Trade.RecordBankWorth(worth)
    worth = worth or Trade.BankWorth()
    if not worth or worth <= 0 or not IsInGuild() then return end
    local id = "bw-" .. dayKey()
    local old = Store.Get("bankworth", id)
    if old and old.worth and math.abs(old.worth - worth) <= old.worth * 0.02 then return end
    Store.Put("bankworth", { id = id, day = dayKey(), worth = math.floor(worth), ts = ns.now() })
end
-- Verlauf der letzten n Tage (fehlende Tage = nil) -> Liste, Wert vor 7 Tagen
function Trade.BankHistory(n)
    n = n or 30
    local byDay = {}
    for _, r in ipairs(Store.List("bankworth")) do if r.day then byDay[r.day] = r.worth end end
    local out = {}
    for i = n - 1, 0, -1 do out[#out + 1] = byDay[dayKey(ns.now() - i * 86400)] or false end
    local week
    for i = 7, 13 do
        local v = byDay[dayKey(ns.now() - i * 86400)]
        if v then week = v break end
    end
    return out, week
end

-- kleiner Balkenverlauf (z.B. in einer Kachel)
function Trade.Sparkline(parent, w, h, n)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f.bars = {}
    local bw = w / n
    for i = 1, n do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetPoint("BOTTOMLEFT", (i - 1) * bw, 0)
        t:SetSize(math.max(1, bw - 1), 1)
        f.bars[i] = t
    end
    function f:SetValues(vals)
        local mx, mn = 0, math.huge
        for _, v in ipairs(vals) do if v then mx = math.max(mx, v) mn = math.min(mn, v) end end
        local lo = mn < math.huge and mn * 0.9 or 0
        for i, t in ipairs(self.bars) do
            local v = vals[i]
            if v and mx > lo then
                t:SetHeight(math.max(2, (v - lo) / (mx - lo) * h))
                local c = i == #self.bars and C.accent or C.muted
                t:SetColorTexture(c[1], c[2], c[3], i == #self.bars and 1 or 0.55)
                t:Show()
            else
                t:Hide()
            end
        end
    end
    return f
end

------------------------------------------------------------------------
-- 6) Haendler-Rangliste (freiwillig): Bilanz der letzten 7 Tage aus Midas
------------------------------------------------------------------------
-- liest nur das Handelsprotokoll aus Midas' gespeicherten Daten (MidasDB.trade.log), aendert nichts
local DAY0 = time({ year = 2020, month = 1, day = 1, hour = 0 })   -- Midas' Tageszaehlung
function Trade.HasMidas() return _G.MidasAPI ~= nil end
function Trade.MyWeek()
    local db = _G.MidasDB
    local log = type(db) == "table" and type(db.trade) == "table" and db.trade.log
    if type(log) ~= "table" then return nil end
    local cutoff = math.floor((time() - DAY0) / 86400) - 7
    local net, sold, bought = 0, 0, 0
    for _, e in ipairs(log) do
        if type(e) == "table" and (e.day or 0) >= cutoff then
            if e.kind == "sold" then net, sold = net + (e.net or 0), sold + 1
            elseif e.kind == "bought" then net, bought = net + (e.net or 0), bought + 1
            elseif e.kind == "outbid" then net = net + (e.net or 0) end
        end
    end
    return net, sold, bought
end
-- Felder fuer das eigene Profil (nur, wenn geteilt)
function Trade.ProfileFields(p)
    p.ah = Trade.MyScanTime()
    if S().shareTrade then
        local net, sold = Trade.MyWeek()
        if net then p.gw, p.gws, p.gwt = math.floor(net), sold, ns.now() end
    end
end
-- Rangliste: alle, die teilen und in den letzten 8 Tagen gemeldet haben
function Trade.Ranking()
    local out, seenMain = {}, {}
    for name, p in pairs(ns.db.members) do
        if type(p) == "table" and type(p.gw) == "number" and ns.now() - (p.gwt or 0) < 8 * 86400 then
            local main = ns.Alts and ns.Alts.Main(name) or name
            local cur = seenMain[main]
            if not cur then
                cur = { name = main, net = 0, sold = 0 }
                seenMain[main] = cur
                out[#out + 1] = cur
            end
            cur.net = cur.net + p.gw
            cur.sold = cur.sold + (p.gws or 0)
        end
    end
    table.sort(out, function(a, b) return a.net > b.net end)
    return out
end
function Trade.GoldmakerOfWeek()
    local top = Trade.Ranking()[1]
    return (top and top.net > 0) and top.name or nil
end

------------------------------------------------------------------------
-- Midas-Ereignisse
------------------------------------------------------------------------
ns.Listen("LOGIN", function()
    ns.After(6, function()
        local a = api()
        if a and a.RegisterCallback then
            pcall(a.RegisterCallback, "SCAN_COMPLETE", function()
                -- Gilde ueber den neuen Stand informieren, danach Wuensche pruefen (nach der Analyse)
                ns.After(2, function() if ns.Radar then ns.Radar.SendHello() end end)
                ns.After(4, Trade.CheckWants)
                ns.RefreshPage("trade")
            end)
            pcall(a.RegisterCallback, "ANALYSIS_COMPLETE", function()
                ns.After(1, Trade.CheckWants)
                ns.RefreshPage("trade")
            end)
        end
    end)
    ns.After(30, function() pcall(Trade.RecordBankWorth) end)
end)
ns.Listen("PROFILE", function() ns.RefreshPage("trade") if ns.UpdateAHChip then ns.UpdateAHChip() end end)

-- Midas-Fenster oeffnen und VOR das Oasis-Fenster holen (Midas liegt sonst eine Ebene tiefer,
-- genau dahinter, und man sieht nichts). Ist es schon offen, nur nach vorne holen.
function Trade.OpenMidas()
    if not (SlashCmdList and SlashCmdList.MIDAS) then return end
    local f = _G.MidasFrame
    if not (f and f:IsShown()) then pcall(SlashCmdList.MIDAS, "") end
    f = _G.MidasFrame
    if f then
        f:SetFrameStrata("HIGH")
        f:Raise()
    end
end

------------------------------------------------------------------------
-- Demo-Modus: Beispielpreise, Scan und Rangliste - nur fuer die Anzeige dieser Seite.
-- Nichts davon wird gespeichert oder gesendet; Preisfragen und Wunsch-Alarm nutzen weiter nur echte Daten.
------------------------------------------------------------------------
local function demoOn() return (ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive()) and true or false end
-- ItemID, Name (falls der Client das Item noch nicht kennt), Qualitaet, Kategorie, fair, aktuell (Kupfer)
local DEMO_ITEMS = {
    { 2589, "Linen Cloth", 1, "cloth", 62, 41 },
    { 2592, "Wollstoff", 1, "cloth", 115, 108 },
    { 4306, "Seidenstoff", 1, "cloth", 155, 112 },
    { 4338, "Magiestoff", 1, "cloth", 210, 236 },
    { 14047, "Runenstoff", 1, "cloth", 365, 349 },
    { 2770, "Kupfererz", 1, "ore", 45, 52 },
    { 2771, "Zinnerz", 1, "ore", 70, 61 },
    { 2772, "Eisenerz", 1, "ore", 160, 171 },
    { 3575, "Eisenbarren", 1, "ore", 185, 139 },
    { 3858, "Mithrilerz", 1, "ore", 265, 248 },
    { 12360, "Arkanitbarren", 2, "ore", 145000, 152000 },
    { 2447, "Friedensblume", 1, "herb", 18, 14 },
    { 765, "Silberblatt", 1, "herb", 15, 17 },
    { 3356, "Koenigsblut", 1, "herb", 105, 96 },
    { 3821, "Golddorn", 1, "herb", 125, 139 },
    { 8838, "Sonnengras", 1, "herb", 255, 233 },
    { 929, "Heiltrank", 1, "pot", 78, 55 },
    { 1710, "Grosser Heiltrank", 1, "pot", 185, 172 },
    { 3827, "Manatrank", 1, "pot", 165, 178 },
    { 13452, "Elixir of the Mongoose", 1, "pot", 12500, 11800 },
    { 10940, "Seltsamer Staub", 1, "ench", 105, 92 },
    { 11083, "Seelenstaub", 1, "ench", 260, 281 },
    { 10938, "Geringe Magieessenz", 2, "ench", 155, 149 },
    { 11137, "Visionenstaub", 1, "ench", 410, 355 },
    { 14344, "Grosser gleissender Splitter", 3, "ench", 31000, 33500 },
    { 4245, "Kleiner Seidenrucksack", 1, "gear", 28000, 26500 },
    { 4265, "Schweres Ruestungsset", 1, "gear", 420, 455 },
    { 1482, "Shadowfang", 3, "gear", 165000, 149000 },
    { 7719, "Helm des tobenden Berserkers", 3, "gear", 92000, 98500 },
}
local CATS = { cloth = "Cloth", ore = "Ore & bars", herb = "Herb", pot = "Potion", ench = "Enchant", gear = "Gear" }
-- Demo-Rangliste: Index in Demo.People(), Bilanz (Kupfer), verkaufte Auktionen
local DEMO_RANK = { { 9, 482000, 23 }, { 11, 315500, 17 }, { 14, 221000, 12 }, { 4, 96000, 6 }, { 2, 41000, 4 }, { 16, -28500, 3 } }
local DEMO_NET, DEMO_SOLD = 124000, 9

local demoBy
local function demoData()
    if demoBy then return demoBy end
    demoBy = {}
    for i, d in ipairs(DEMO_ITEMS) do
        local id, fair, cur = d[1], d[5], d[6]
        local hist = {}
        for k = 1, 14 do
            local w = 1 + 0.07 * math.sin(k * 0.8 + id % 7) + 0.03 * math.cos(k * 1.7 + i)
            hist[k] = math.max(1, math.floor(fair * w + 0.5))
        end
        hist[14] = cur
        local lo = cur
        for k = 8, 14 do lo = math.min(lo, hist[k]) end
        demoBy[id] = { cur = cur, fair = fair, floor7 = lo, fresh = true, src = "demo", hist = hist, name = d[2], q = d[3], cat = d[4] }
    end
    return demoBy
end
local function demoPeople()
    if not (ns.Demo and ns.Demo.People) then return {} end
    local ok, p = pcall(ns.Demo.People)
    return (ok and type(p) == "table") and p or {}
end
local function demoScanner()
    local P = demoPeople()
    local e = P[15] or P[1]
    return e and e.name or ns.me()
end
local function demoRanking()
    local P, out = demoPeople(), {}
    for _, r in ipairs(DEMO_RANK) do
        local e = P[r[1]]
        if e then out[#out + 1] = { name = e.name, net = r[2], sold = r[3], class = e.class } end
    end
    out[#out + 1] = { name = ns.me(), net = DEMO_NET, sold = DEMO_SOLD }
    table.sort(out, function(a, b) return a.net > b.net end)
    return out
end

-- Marktdaten fuer die Anzeige: im Demo-Modus die Beispielpreise, sonst echte Daten
function Trade.PageInfo(itemID)
    if demoOn() then
        local d = demoData()[itemID]
        if d then return d end
    end
    return Trade.Info(itemID)
end

-- wie Trade.CheapWants, aber mit Anzeige-Daten (Demo eingeschlossen)
local function pageCheapWants()
    local out, seen = {}, {}
    for _, w in ipairs(Store.List("wants")) do
        local id = w.itemID
        if id and id ~= 0 and not w.offer then
            local info = seen[id]
            if info == nil then info = Trade.PageInfo(id) or false seen[id] = info end
            if info and ((info.src == "midas" and info.fresh) or info.src == "demo") and info.cur and info.fair and info.fair > 0
                and info.cur <= info.fair * CHEAPF() then
                out[#out + 1] = { want = w, info = info, pct = math.floor((1 - info.cur / info.fair) * 100 + 0.5) }
            end
        end
    end
    table.sort(out, function(a, b) return a.pct > b.pct end)
    return out
end

-- Items fuer die Preisliste ohne Demo: Wunschlisten, Gildenbank, eigene AH-Beobachtung
local function realItemIds()
    local ids, seen = {}, {}
    local function add(id)
        id = tonumber(id)
        if id and id > 0 and not seen[id] and #ids < 250 then seen[id] = true ids[#ids + 1] = id end
    end
    for _, w in ipairs(Store.List("wants")) do add(w.itemID) end
    local B = ns.GuildBank
    if B and B.Tabs then
        local ok, tabs = pcall(B.Tabs)
        if ok and type(tabs) == "table" then
            for _, t in ipairs(tabs) do
                if type(t) == "table" and type(t.items) == "string" then
                    for id in t.items:gmatch("%d+:(%d+):%d+") do add(id) end
                end
            end
        end
    end
    for _, r in ipairs(Store.List("prices")) do add(r.itemID) end
    -- eigener Midas-Scan: die interessantesten Items (aktuell gesehen, nach Midas-Wertung), einmal je Scan berechnet
    for _, id in ipairs(Trade.MidasTopIds()) do add(id) end
    return ids
end
local midasTop, midasTopAt = {}, nil
function Trade.MidasTopIds()
    local a = api()
    if not (a and a.GetItemKeys and a.GetMarketInfo) then return {} end
    local okT, scan = pcall(a.GetLastScanTime)
    scan = okT and scan or 0
    if midasTopAt == scan then return midasTop end
    local okK, keys = pcall(a.GetItemKeys)
    if not okK or type(keys) ~= "table" then return {} end
    local okD, lastDay = pcall(a.GetLastScanDay)
    lastDay = okD and lastDay or nil
    local rows = {}
    for i, key in ipairs(keys) do
        if i > 6000 then break end
        if type(key) == "string" and key:match("^%d+$") then
            local ok, info = pcall(a.GetMarketInfo, tonumber(key))
            if ok and info and (info.current or info.fair) and (not lastDay or info.lastDay == lastDay) then
                rows[#rows + 1] = { id = tonumber(key), s = tonumber(info.score) or 0, v = info.fair or info.current or 0 }
            end
        end
    end
    table.sort(rows, function(x, y) if x.s ~= y.s then return x.s > y.s end return x.v > y.v end)
    midasTop = {}
    for i = 1, math.min(200, #rows) do midasTop[i] = rows[i].id end
    midasTopAt = scan
    return midasTop
end

------------------------------------------------------------------------
-- Seite "Markt"
------------------------------------------------------------------------
local ICO = ns.MEDIA .. "icons\\"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local EMBER = ns.MEDIA .. "ember"
local CLASS_SHEET = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local QMARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local ARROW_DOWN = "Interface\\Buttons\\UI-MicroStream-Green"
local ARROW_UP = "Interface\\Buttons\\UI-MicroStream-Red"
local GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
local QCOL = { [0] = { 0.62, 0.62, 0.62 }, [1] = { 0.94, 0.94, 0.94 }, [2] = { 0.12, 1, 0 }, [3] = { 0.1, 0.5, 0.95 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 } }
local MEDAL = { { 1, 0.82, 0.29 }, { 0.79, 0.82, 1 }, { 0.85, 0.54, 0.29 } }
local TABS = {
    { key = "over", text = "Overview", glyph = "home", color = C.accent },
    { key = "prices", text = "Prices", glyph = "stats", color = C.amber },
    { key = "rank", text = "Traders of the week", glyph = "badges", color = C.mint },
    { key = "opts", text = "Settings", glyph = "settings", color = C.blue },
}
local TILES = {
    { key = "scan", label = "Last scan", glyph = "sync", color = C.mint, tip = "Click: overview" },
    { key = "items", label = "Items with price", glyph = "stats", color = C.amber, tip = "Click: all prices" },
    { key = "hits", label = "Wishlist hits", glyph = "wants", color = C.pink, tip = "Click: cheap items only" },
    { key = "gain", label = "Your trade profit 7 days", glyph = "bank", color = C.blue, tip = "Click: traders of the week" },
}
local SORTS = { { key = "save", text = "Savings" }, { key = "name", text = "Name" }, { key = "price", text = "Price" }, { key = "trend", text = "Trend" } }
local FEATURES = {
    { "sync", C.mint, "AH data for everyone", "One person scans with Midas, the whole guild sees the prices." },
    { "wants", C.pink, "Wishlist alert", "If a wish is cheap in the AH, you get a notice." },
    { "announce", C.amber, "Prices in guild chat", "Type 'pc [Item]' - Oasis replies with the price." },
    { "badges", C.blue, "Traders of the week", "Voluntary trade balance, the best one earns a title." },
}
local view, search, onlyCheap, sortBy = "over", "", false, "save"
local page

local function animOn() return not S().noAnim end
-- Glas 2026: ruhige Flaeche + feine Kante
local GLINE = { 1, 1, 1, 0.10 }
local function glass(f, r, a, line)
    local IG = ns.Insta
    if IG and IG.Glass then IG.Glass(f, { 1, 1, 1, a or 0.03 }, line or GLINE, r or 12) return true end
end
local function low(s) return s and tostring(s):lower() or "" end
local function gradient(tex, dir, c, a1, a2, fb)
    if not K.Gradient(tex, dir, { c[1], c[2], c[3], a1 }, { c[1], c[2], c[3], a2 }) then
        tex:SetColorTexture(c[1], c[2], c[3], fb or (a1 + a2) / 2)
    end
end
local function circleMask(owner, tex)
    if not owner.CreateMaskTexture then return end
    local ok, m = pcall(owner.CreateMaskTexture, owner)
    if not ok or not m then return end
    pcall(function()
        m:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(tex)
        tex:AddMaskTexture(m)
    end)
end
local function setClassIcon(tex, class)
    if ns.GuildInfo and ns.GuildInfo.SetClassIcon then
        local ok, r = pcall(ns.GuildInfo.SetClassIcon, tex, class)
        if ok and r then return true end
    end
    local tc = type(class) == "string" and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if not tc then return false end
    tex:SetTexture(CLASS_SHEET)
    tex:SetTexCoord(tc[1] + 0.015, tc[2] - 0.015, tc[3] + 0.015, tc[4] - 0.015)
    return true
end
local function classOf(e)
    if e.class then return e.class end
    if ns.Radar and ns.Radar.ClassOf then
        local ok, c = pcall(ns.Radar.ClassOf, e.name)
        if ok then return c end
    end
    return nil
end
local function colored(name)
    if ns.Radar and ns.Radar.Colored then
        local ok, s = pcall(ns.Radar.Colored, name)
        if ok and s then return s end
    end
    return ns.displayName(name)
end

-- Item-Daten aus dem Client (fehlt etwas, wird es angefordert und kommt per Ereignis nach)
local requested = {}
local function request(id)
    if id and not requested[id] and C_Item and C_Item.RequestLoadItemDataByID then
        requested[id] = true
        pcall(C_Item.RequestLoadItemDataByID, id)
    end
end
local function itemName(id, fb)
    if C_Item and C_Item.GetItemNameByID then
        local ok, n = pcall(C_Item.GetItemNameByID, id)
        n = ok and ns.safe(n) or nil
        if type(n) == "string" and n ~= "" then return n end
    end
    request(id)
    return fb or ("#" .. id)
end
local function itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then
        local ok, t = pcall(C_Item.GetItemIconByID, id)
        t = ok and ns.safe(t) or nil
        if t then return t end
    end
    request(id)
    return QMARK
end
local function itemQuality(id, fb)
    if C_Item and C_Item.GetItemQualityByID then
        local ok, q = pcall(C_Item.GetItemQualityByID, id)
        q = ok and tonumber(ns.safe(q)) or nil
        if q then return q end
    end
    return fb or 1
end
local function itemLink(id, name, q)
    return K.hex(QCOL[q] or QCOL[1]) .. "|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r"
end
local function insertLink(link)
    if ChatEdit_InsertLink then
        local ok, r = pcall(ChatEdit_InsertLink, link)
        if ok and r then return end
    end
    if ns.OpenChat then ns.OpenChat(link) end
end

-- Kupfer -> Gold/Silber/Kupfer mit Muenzsymbolen (kleinste Stelle entfaellt ab 1 Gold)
local function money(copper)
    if not copper then return "–" end
    copper = math.floor(math.abs(copper) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100
    if g > 0 then return g .. GOLD .. (s > 0 and (" " .. s .. SILVER) or "") end
    if s > 0 then return s .. SILVER .. (c > 0 and (" " .. c .. COPPER) or "") end
    return c .. COPPER
end
local function signedMoney(copper)
    if not copper then return "–" end
    return (copper >= 0 and "|cff66db9e+|r" or "|cffff5a4a-|r") .. money(copper)
end
local function shortGold(copper)
    if not copper then return "–" end
    local g = math.floor(math.abs(copper) / 10000 + 0.5)
    return (copper >= 0 and "+" or "-") .. (g > 0 and (g .. "g") or money(copper))
end

-- Datenmodell fuer eine Aktualisierung
local function priceRow(id, info, fbName, fbQ)
    local q = itemQuality(id, (info and info.q) or fbQ)
    local name = itemName(id, (info and info.name) or fbName)
    local cur, fair = info.cur or info.fair, info.fair or info.cur
    local pct = (cur and fair and fair > 0) and (cur - fair) / fair or 0
    return { id = id, info = info, name = name, q = q, cur = cur, fair = fair, pct = pct,
        cheap = (cur and fair and fair > 0 and cur <= fair * CHEAPF()) and true or false,
        cat = info.cat, search = low(name) .. " " .. low(info.cat and L[CATS[info.cat]] or "") }
end
local function gather()
    local m = { demo = demoOn() }
    m.hasMidas = ns.Market and ns.Market.HasMidas and ns.Market.HasMidas() or false
    m.ts, m.who = Trade.LatestScan()
    if not m.ts and m.demo then m.ts, m.who, m.demoScan = ns.now() - 7200, demoScanner(), true end
    local items = {}
    if m.demo then
        local dd = demoData()
        for _, d in ipairs(DEMO_ITEMS) do items[#items + 1] = priceRow(d[1], dd[d[1]]) end
    else
        for _, id in ipairs(realItemIds()) do
            local ok, info = pcall(Trade.Info, id)
            if ok and info and (info.cur or info.fair) then items[#items + 1] = priceRow(id, info) end
        end
    end
    m.items = items
    m.cheapN = 0
    for _, r in ipairs(items) do if r.cheap then m.cheapN = m.cheapN + 1 end end
    m.wants = pageCheapWants()
    m.rank = Trade.Ranking()
    if #m.rank == 0 and m.demo then m.rank, m.demoRank = demoRanking(), true end
    m.net, m.sold = Trade.MyWeek()
    if not m.net and m.demo then m.net, m.sold, m.demoNet = DEMO_NET, DEMO_SOLD, true end
    return m
end

------------------------------------------------------------------------
-- Bausteine
------------------------------------------------------------------------
-- Reiterleiste: Symbol + Text + Zaehler, gleitender Balken in der Reiterfarbe
local function buildTabs(p, onPick)
    local f = CreateFrame("Frame", nil, p)
    f:SetHeight(34)
    f.maxW = 480
    f.base = f:CreateTexture(nil, "BACKGROUND")
    f.base:SetPoint("BOTTOMLEFT", p, "TOPLEFT", 0, -34)
    f.base:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", 0, -34)
    f.base:SetHeight(1)
    f.base:SetColorTexture(C.line[1], C.line[2], C.line[3], 1)
    f.buttons = {}
    for i, d in ipairs(TABS) do
        local b = CreateFrame("Button", nil, f)
        b.key, b.color = d.key, d.color
        b.hov = b:CreateTexture(nil, "BACKGROUND")
        b.hov:SetAllPoints()
        b.hov:SetColorTexture(1, 1, 1, 0.03)
        b.hov:SetAlpha(0)
        b.ico = K.Glyph(b, 14, ICO .. d.glyph, C.muted)
        b.label = K.Text(b, 13, C.muted)
        b.label:SetText(L[d.text])
        b.count = K.Text(b, 10, C.dim)
        b.count:SetText("")
        b:SetScript("OnClick", function() onPick(d.key) end)
        b:SetScript("OnEnter", function(self)
            self.hov:SetAlpha(1)
            if f.value ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end
        end)
        b:SetScript("OnLeave", function(self)
            self.hov:SetAlpha(0)
            if f.value ~= self.key then self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end
        end)
        f.buttons[i] = b
    end
    f.ind = f:CreateTexture(nil, "OVERLAY")
    f.ind:SetHeight(2)
    f.indGlow = f:CreateTexture(nil, "ARTWORK")
    f.indGlow:SetHeight(12)
    f.indGlow:SetPoint("BOTTOMLEFT", f.ind, "TOPLEFT")
    f.indGlow:SetPoint("BOTTOMRIGHT", f.ind, "TOPRIGHT")
    function f:Layout()
        local W = self.maxW or 480
        local nat, sum, withIcon = {}, 0, true
        for pass = 1, 2 do
            sum = 0
            for i, b in ipairs(self.buttons) do
                local cw = (b.count:GetText() or "") ~= "" and ((b.count:GetStringWidth() or 0) + 5) or 0
                nat[i] = (withIcon and 19 or 0) + (b.label:GetStringWidth() or 0) + cw + 22
                sum = sum + nat[i]
            end
            if pass == 1 and sum > W then withIcon = false else break end
        end
        local scale = math.min(1, W / math.max(1, sum))
        local x = 0
        for i, b in ipairs(self.buttons) do
            local bw = math.max(40, math.floor(nat[i] * scale))
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", x, 0)
            b:SetSize(bw, 33)
            b.x, b.w = x, bw
            x = x + bw + 2
            local cw = (b.count:GetText() or "") ~= "" and ((b.count:GetStringWidth() or 0) + 5) or 0
            local iw = withIcon and 19 or 0
            local tw = math.max(10, math.min(b.label:GetStringWidth() or 0, bw - iw - cw - 12))
            local x0 = math.max(4, math.floor((bw - (iw + tw + cw)) / 2))
            b.ico:SetShown(withIcon)
            b.ico:ClearAllPoints()
            b.ico:SetPoint("LEFT", b, "LEFT", x0, 0)
            b.label:ClearAllPoints()
            b.label:SetPoint("LEFT", b, "LEFT", x0 + iw, 0)
            b.label:SetWidth(tw + 1)
            b.count:ClearAllPoints()
            b.count:SetPoint("LEFT", b.label, "RIGHT", 4, 0)
        end
        self:SetWidth(math.max(1, x))
        self:MoveInd(self.value, false)
    end
    function f:SetCounts(t)
        local changed = false
        for _, b in ipairs(self.buttons) do
            local n = t[b.key] or 0
            local s = n > 0 and tostring(n) or ""
            if b.count:GetText() ~= s then b.count:SetText(s) changed = true end
        end
        if changed then self:Layout() end
    end
    function f:MoveInd(key, animate)
        local tb
        for _, b in ipairs(self.buttons) do if b.key == key then tb = b end end
        if not tb or not tb.x then return end
        local c = tb.color
        self.ind:SetColorTexture(c[1], c[2], c[3], 1)
        self.indGlow:Hide()
        local x1, w1 = tb.x + 6, math.max(1, tb.w - 12)
        local x0, w0 = self.indX or x1, self.indW or w1
        self.indX, self.indW = x1, w1
        local function put(x, w)
            self.ind:ClearAllPoints()
            self.ind:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 0)
            self.ind:SetWidth(math.max(1, w))
        end
        if not animate or not animOn() then put(x1, w1) return end
        K.Tween(self.ind, 0.24, function(q) put(x0 + (x1 - x0) * q, w0 + (w1 - w0) * q) end, function() put(x1, w1) end)
    end
    function f:Select(key, animate)
        local changed = self.value ~= key
        self.value = key
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            local c = on and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3])
            local ic = on and b.color or C.muted
            b.ico:SetVertexColor(ic[1], ic[2], ic[3])
            b.hov:SetAlpha(0)
            local cc = on and b.color or C.dim
            b.count:SetTextColor(cc[1], cc[2], cc[3])
        end
        if changed or not self.indX then self:MoveInd(key, animate) end
    end
    return f
end

-- Kennzahl-Kachel (Verlauf, Glow, Hover), Klick = Reiter/Filter
local function buildTile(parent, d, onClick)
    local c = d.color
    local t = CreateFrame("Button", nil, parent)
    t:SetHeight(54)
    t.key = d.key
    t.hov = t:CreateTexture(nil, "BORDER", nil, 2)
    t.hov:SetColorTexture(1, 1, 1, 0)
    t.top = t:CreateTexture(nil, "ARTWORK")
    t.top:Hide()
    t.iconGlow = t:CreateTexture(nil, "BORDER", nil, 3)
    t.iconGlow:Hide()
    glass(t, 12)
    t.col = c
    t.icon = K.Glyph(t, 20, ICO .. d.glyph, c)
    t.icon:SetPoint("RIGHT", -14, 0)
    t.icon:SetAlpha(0.8)
    t.value = K.Title(t, 20, C.text)
    t.value:SetPoint("TOPLEFT", 14, -9)
    t.value:SetText("")
    t.sub = K.Text(t, 10, c)
    t.sub:SetPoint("BOTTOMLEFT", t.value, "BOTTOMRIGHT", 6, 2)
    t.sub:SetPoint("RIGHT", t.icon, "LEFT", -4, 0)
    t.sub:SetText("")
    t.label = K.Text(t, 11, C.muted)
    t.label:SetPoint("BOTTOMLEFT", 14, 9)
    t.label:SetPoint("RIGHT", t.icon, "LEFT", -4, 0)
    t.label:SetText(L[d.label])
    local function hover(on)
        glass(t, 12, (on or t.sel) and 0.06 or 0.03, t.sel and { c[1], c[2], c[3], 0.55 } or GLINE)
    end
    t:SetScript("OnEnter", function(self)
        hover(true)
        K.ShowTip(self, { L[d.label], "|cff888888" .. L[d.tip] .. "|r" })
    end)
    t:SetScript("OnLeave", function() hover(false) GameTooltip:Hide() end)
    t:SetScript("OnClick", function() onClick(d.key) end)
    function t:SetSel(on)
        if self.sel == on then return end
        self.sel = on
        glass(self, 12, on and 0.06 or 0.03, on and { c[1], c[2], c[3], 0.55 } or GLINE)
    end
    return t
end

-- Panel mit Kopfzeile im Spiel-Stil (Farbmarke + Titel + Info rechts)
local function card(parent, title, color)
    local f = CreateFrame("Frame", nil, parent)
    glass(f, 14, 0.025)
    f.mark = f:CreateTexture(nil, "ARTWORK")
    f.mark:SetSize(1, 14)
    f.mark:SetPoint("TOPLEFT", 9, -14)
    f.mark:Hide()
    f.title = K.Title(f, 13, C.text)
    f.title:SetPoint("TOPLEFT", 16, -14)
    f.title:SetText(L[title])
    f.info = K.Text(f, 11, C.dim, "RIGHT")
    f.info:SetPoint("TOPRIGHT", -16, -15)
    f.info:SetText("")
    f.empty = K.Text(f, 12, C.muted, "CENTER")
    f.empty:SetPoint("TOPLEFT", 16, -52)
    f.empty:SetPoint("TOPRIGHT", -16, -52)
    f.empty:SetWordWrap(true)
    f.empty:SetText("")
    f.empty:Hide()
    return f
end

-- rundes Item-Symbol mit Qualitaetsring
local function itemBadge(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.ring = f:CreateTexture(nil, "BORDER")
    f.ring:SetTexture(CIRCLE)
    f.ring:SetAllPoints()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER")
    f.icon:SetSize(size - 4, size - 4)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    circleMask(f, f.icon)
    function f:Set(id, q)
        self.icon:SetTexture(itemIcon(id))
        local c = QCOL[q] or QCOL[1]
        self.ring:SetVertexColor(c[1], c[2], c[3], 1)
    end
    return f
end

-- Mini-Verlauf aus Balken (Farbe nach Trend)
local function miniSpark(parent, w, h, n)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f.bars = {}
    local bw = w / n
    for i = 1, n do
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetPoint("BOTTOMLEFT", (i - 1) * bw, 0)
        t:SetSize(math.max(1, bw - 1), 1)
        f.bars[i] = t
    end
    function f:SetValues(vals, c)
        if type(vals) ~= "table" or #vals == 0 then self:Hide() return end
        local mx, mn = 0, math.huge
        for _, v in ipairs(vals) do mx = math.max(mx, v) mn = math.min(mn, v) end
        local lo = mn * 0.92
        for i, t in ipairs(self.bars) do
            local v = vals[i]
            if v and mx > lo then
                t:SetHeight(math.max(2, (v - lo) / (mx - lo) * h))
                local last = i == #self.bars
                t:SetColorTexture(last and c[1] or C.muted[1], last and c[2] or C.muted[2], last and c[3] or C.muted[3], last and 1 or 0.45)
                t:Show()
            else
                t:Hide()
            end
        end
        self:Show()
    end
    return f
end

-- Trend-Text: Abweichung vom fairen Preis (gruen = guenstiger)
local function trendText(pct)
    local n = math.floor(math.abs(pct) * 100 + 0.5)
    if n == 0 then return "|cff8888880%|r" end
    return pct < 0 and ("|cff66db9e-" .. n .. "%|r") or ("|cffff5a4a+" .. n .. "%|r")
end
local function setArrow(tex, pct)
    if math.floor(math.abs(pct) * 100 + 0.5) == 0 then tex:Hide() return end
    if pct < 0 then
        tex:SetTexture(ARROW_DOWN)
        tex:SetTexCoord(0, 1, 0, 1)
    else
        tex:SetTexture(ARROW_UP)
        tex:SetTexCoord(0, 1, 1, 0)
    end
    tex:Show()
end

-- kleine Item-Zeile (Uebersicht): Symbol, Name, Preis, Zusatz
local function newMiniRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(32)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)
    r.badge = itemBadge(r, 26)
    r.badge:SetPoint("LEFT", 0, 0)
    r.name = K.Text(r, 12, C.text)
    r.name:SetPoint("TOPLEFT", r.badge, "TOPRIGHT", 8, -1)
    r.name:SetPoint("RIGHT", -110, 0)
    r.name:SetWordWrap(false)
    r.name:SetText("")
    r.sub = K.Text(r, 10, C.dim)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", -110, 0)
    r.sub:SetWordWrap(false)
    r.sub:SetText("")
    r.val = K.Text(r, 12, C.text, "RIGHT")
    r.val:SetPoint("TOPRIGHT", 0, -2)
    r.val:SetText("")
    r.pct = K.Text(r, 10, C.mint, "RIGHT")
    r.pct:SetPoint("TOPRIGHT", r.val, "BOTTOMRIGHT", 0, -2)
    r.pct:SetText("")
    r:RegisterForClicks("LeftButtonUp")
    r:SetScript("OnEnter", function(self) if self.id then K.ItemTip(self, "item:" .. self.id) end end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        if self.id and IsShiftKeyDown and IsShiftKeyDown() then insertLink(itemLink(self.id, self.plainName or "?", self.q)) end
    end)
    return r
end

-- Schalter-Zeile: Symbol, Titel, Erklaerung, Schalter rechts
local function optRow(parent, glyph, color, label, desc, get, set)
    local f = CreateFrame("Button", nil, parent)
    f:SetHeight(56)
    glass(f, 12, 0.03)
    f.hl = f:CreateTexture(nil, "HIGHLIGHT")
    f.hl:SetAllPoints()
    f.hl:SetColorTexture(1, 1, 1, 0.04)
    f.disc = f:CreateTexture(nil, "BORDER")
    f.disc:SetTexture(CIRCLE)
    f.disc:SetSize(34, 34)
    f.disc:SetPoint("LEFT", 12, 0)
    f.disc:SetVertexColor(color[1] * 0.25, color[2] * 0.25, color[3] * 0.25)
    f.g = K.Glyph(f, 18, ICO .. glyph, color)
    f.g:SetPoint("CENTER", f.disc)
    f.lbl = K.Text(f, 13, C.text)
    f.lbl:SetPoint("TOPLEFT", f.disc, "TOPRIGHT", 12, -2)
    f.lbl:SetPoint("RIGHT", -70, 0)
    f.lbl:SetText(L[label])
    f.desc = K.Text(f, 11, C.muted)
    f.desc:SetPoint("TOPLEFT", f.lbl, "BOTTOMLEFT", 0, -4)
    f.desc:SetPoint("RIGHT", -70, 0)
    f.desc:SetWordWrap(true)
    f.desc:SetText(L[desc])
    f.tgl = K.Toggle(f, "", get, function(v) set(v) end)
    f.tgl:SetSize(34, 22)
    f.tgl:SetPoint("RIGHT", -14, 0)
    f:SetScript("OnClick", function() set(not get()) f.tgl:Refresh() end)
    function f:Refresh() self.tgl:Refresh() end
    return f
end

-- Sperr-Hinweis ohne Midas: was die Seite kann + Demo / woher Midas kommt
local function buildLock(p)
    local o = CreateFrame("Frame", nil, p)
    o:SetAllPoints()
    o:SetFrameLevel(p:GetFrameLevel() + 40)
    o:EnableMouse(true)
    K.Fill(o, { 0, 0, 0, 0.80 })
    local box = K.Panel(o, C.panel)
    box:SetSize(460, 330)
    box:SetPoint("CENTER", 0, 10)
    box.halo = box:CreateTexture(nil, "BACKGROUND", nil, 1)
    box.halo:SetTexture(EMBER)
    box.halo:SetBlendMode("ADD")
    box.halo:SetSize(110, 110)
    box.halo:SetPoint("TOP", 0, 22)
    box.halo:SetVertexColor(C.amber[1], C.amber[2], C.amber[3])
    box.halo:SetAlpha(0.3)
    box.disc = box:CreateTexture(nil, "BORDER")
    box.disc:SetTexture(CIRCLE)
    box.disc:SetSize(46, 46)
    box.disc:SetPoint("TOP", 0, -14)
    box.disc:SetVertexColor(C.amber[1] * 0.25, C.amber[2] * 0.25, C.amber[3] * 0.25)
    local ic = K.Glyph(box, 24, ns.ICONS.trade, C.amber)
    ic:SetPoint("CENTER", box.disc)
    local t = K.Title(box, 16, C.text, "CENTER")
    t:SetPoint("TOP", box.disc, "BOTTOM", 0, -8)
    t:SetText(L["Midas required"])
    local d = K.Text(box, 11, C.muted, "CENTER")
    d:SetPoint("TOP", t, "BOTTOM", 0, -6)
    d:SetWidth(410)
    d:SetWordWrap(true)
    d:SetText(L["The market uses prices from the AH addon Midas. As soon as you or a guild member scans the AH with Midas, this page unlocks."])
    local head = K.Text(box, 10, C.dim)
    head:SetPoint("TOPLEFT", 26, -128)
    head:SetText(K.Upper and K.Upper(L["What this page does"]) or L["What this page does"]:upper())
    for i, f in ipairs(FEATURES) do
        local y = -146 - (i - 1) * 30
        local dc = box:CreateTexture(nil, "BORDER")
        dc:SetTexture(CIRCLE)
        dc:SetSize(24, 24)
        dc:SetPoint("TOPLEFT", 26, y)
        dc:SetVertexColor(f[2][1] * 0.25, f[2][2] * 0.25, f[2][3] * 0.25)
        local g = K.Glyph(box, 13, ICO .. f[1], f[2])
        g:SetPoint("CENTER", dc)
        local a = K.Text(box, 12, C.text)
        a:SetPoint("TOPLEFT", dc, "TOPRIGHT", 10, 1)
        a:SetText(L[f[3]])
        local b = K.Text(box, 10, C.muted)
        b:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 0, -1)
        b:SetPoint("RIGHT", box, "RIGHT", -20, 0)
        b:SetWordWrap(false)
        b:SetText(L[f[4]])
    end
    o.demoBtn = K.Button(box, L["View demo"], 140, 24, "primary", function()
        if ns.Demo and ns.Demo.Load then ns.Demo.Load() end
        ns.RefreshPage("trade")
    end)
    o.demoBtn:SetPoint("BOTTOM", 0, 16)
    o.where = K.Text(box, 11, C.amber, "CENTER")
    o.where:SetPoint("BOTTOM", 0, 18)
    o.where:SetWidth(410)
    o.where:SetWordWrap(true)
    o.where:SetText(L["Midas is a separate AH addon - install it like any other addon, then click 'Midas Scan' in the AH."])
    function o:Update()
        local dev = ns.IsDev and ns.IsDev() or false
        self.demoBtn:SetShown(dev)
        self.where:SetShown(not dev)
    end
    o:Hide()
    return o
end

------------------------------------------------------------------------
-- Ansichten
------------------------------------------------------------------------
local function switchTo(v, cheap)
    if v == view and cheap == nil then return end
    view = v
    if cheap ~= nil then onlyCheap = cheap end
    if page and page.body and animOn() then
        local b = page.body
        b:SetAlpha(0.15)
        K.Tween(b, 0.2, function(q) b:SetAlpha(0.15 + 0.85 * q) end, function() b:SetAlpha(1) end)
    end
    if page then page.switch = true end
    ns.RefreshPage("trade")
end

local function buildOverview(p, body)
    local v = CreateFrame("Frame", nil, body)
    v:SetAllPoints()
    -- links: guenstig jetzt
    v.cheap = card(v, "Cheap now", C.mint)
    v.cheap.rows = {}
    for i = 1, 9 do
        local r = newMiniRow(v.cheap)
        r:SetPoint("TOPLEFT", 14, -38 - (i - 1) * 36)
        r:SetPoint("RIGHT", -14, 0)
        v.cheap.rows[i] = r
    end
    v.cheap.more = K.Button(v.cheap, L["All prices"], 110, 22, "ghost", function() switchTo("prices", false) end)
    v.cheap.more:SetPoint("BOTTOMRIGHT", -12, 10)
    -- rechts oben: Wunschliste-Treffer
    v.wants = card(v, "Wishlist hits", C.pink)
    v.wants.rows = {}
    for i = 1, 4 do
        local r = newMiniRow(v.wants)
        r:SetPoint("TOPLEFT", 14, -38 - (i - 1) * 36)
        r:SetPoint("RIGHT", -14, 0)
        v.wants.rows[i] = r
    end
    -- rechts unten: Haendler der Woche (Top 3) + AH-Stand
    v.top = card(v, "Traders of the week", C.amber)
    v.top.rows = {}
    for i = 1, 3 do
        local r = CreateFrame("Frame", nil, v.top)
        r:SetHeight(26)
        r:SetPoint("TOPLEFT", 14, -38 - (i - 1) * 28)
        r:SetPoint("RIGHT", -14, 0)
        r.medal = r:CreateTexture(nil, "BORDER")
        r.medal:SetTexture(CIRCLE)
        r.medal:SetSize(20, 20)
        r.medal:SetPoint("LEFT", 0, 0)
        r.num = K.Title(r, 11, { 0.08, 0.08, 0.08 }, "CENTER")
        r.num:SetPoint("CENTER", r.medal, "CENTER", 0, 0)
        r.num:SetText(i)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("LEFT", r.medal, "RIGHT", 8, 0)
        r.name:SetPoint("RIGHT", -96, 0)
        r.name:SetWordWrap(false)
        r.name:SetText("")
        r.val = K.Text(r, 12, C.text, "RIGHT")
        r.val:SetPoint("RIGHT", 0, 0)
        r.val:SetText("")
        local m = MEDAL[i]
        r.medal:SetVertexColor(m[1], m[2], m[3])
        v.top.rows[i] = r
    end
    v.top.tip = K.Text(v.top, 11, C.muted)
    v.top.tip:SetPoint("BOTTOMLEFT", 14, 12)
    v.top.tip:SetPoint("RIGHT", -14, 0)
    v.top.tip:SetWordWrap(true)
    v.top.tip:SetText(L["Tip: type 'pc [Item]' in guild chat - Oasis tells you the price."])
    function v:Layout(W, H)
        local cw = math.floor((W - 10) / 2)
        self.cheap:ClearAllPoints()
        self.cheap:SetPoint("TOPLEFT", 0, 0)
        self.cheap:SetSize(cw, H)
        local wh = math.min(190, math.floor(H * 0.48))
        self.wants:ClearAllPoints()
        self.wants:SetPoint("TOPLEFT", cw + 10, 0)
        self.wants:SetSize(W - cw - 10, wh)
        self.top:ClearAllPoints()
        self.top:SetPoint("TOPLEFT", cw + 10, -(wh + 10))
        self.top:SetSize(W - cw - 10, H - wh - 10)
        -- nur so viele Zeilen wie hineinpassen
        local nc = math.max(0, math.floor((H - 38 - 40) / 36))
        for i, r in ipairs(self.cheap.rows) do r.fits = i <= nc end
        local nw = math.max(0, math.floor((wh - 44) / 36))
        for i, r in ipairs(self.wants.rows) do r.fits = i <= nw end
        local th = H - wh - 10
        for i, r in ipairs(self.top.rows) do r.fits = (38 + i * 28) <= th - 34 end
    end
    function v:Fill(m)
        local list = {}
        for _, r in ipairs(m.items) do if r.cheap or r.pct < 0 then list[#list + 1] = r end end
        table.sort(list, function(a, b) return a.pct < b.pct end)
        local shown = 0
        for i, row in ipairs(self.cheap.rows) do
            local e = list[i]
            if e and row.fits then
                shown = shown + 1
                row.id, row.q, row.plainName = e.id, e.q, e.name
                row.badge:Set(e.id, e.q)
                row.name:SetText(K.hex(QCOL[e.q] or QCOL[1]) .. e.name .. "|r")
                row.sub:SetText(L["fair"] .. " " .. money(e.fair) .. (e.cat and ("  |cff555555·|r  " .. L[CATS[e.cat]]) or ""))
                row.val:SetText(money(e.cur))
                row.pct:SetText(trendText(e.pct) .. (e.cheap and ("  " .. K.hex(C.mint) .. L["cheap"] .. "|r") or ""))
                row:Show()
            else
                row:Hide()
            end
        end
        self.cheap.info:SetText(#list > 0 and (L["%d below fair"]):format(#list) or "")
        self.cheap.empty:SetShown(shown == 0)
        self.cheap.empty:SetText(m.ts and L["Nothing is below the fair price right now."] or L["No scan yet - once someone scans with Midas, bargains show up here."])
        local ws = 0
        for i, row in ipairs(self.wants.rows) do
            local h = m.wants[i]
            if h and row.fits then
                ws = ws + 1
                local id = h.want.itemID
                local q = itemQuality(id, h.info.q)
                local nm = itemName(id, h.want.name)
                row.id, row.q, row.plainName = id, q, nm
                row.badge:Set(id, q)
                row.name:SetText(K.hex(QCOL[q] or QCOL[1]) .. nm .. "|r")
                row.sub:SetText((L["Wished by %s"]):format(colored(h.want.who)))
                row.val:SetText(money(h.info.cur))
                row.pct:SetText("|cff66db9e-" .. h.pct .. "%|r")
                row:Show()
            else
                row:Hide()
            end
        end
        self.wants.info:SetText(#m.wants > 0 and tostring(#m.wants) or "")
        self.wants.empty:SetShown(ws == 0)
        self.wants.empty:SetText(L["Nothing below fair price right now. Checked again after the next scan."])
        local rs = 0
        for i, row in ipairs(self.top.rows) do
            local e = m.rank[i]
            if e and row.fits then
                rs = rs + 1
                row.name:SetText(colored(e.name) .. (i == 1 and e.net > 0 and ("  |cffe8b44a" .. L["Goldmaker of the week"] .. "|r") or ""))
                row.val:SetText(signedMoney(e.net))
                row:Show()
            else
                row:Hide()
            end
        end
        self.top.empty:SetShown(rs == 0)
        self.top.empty:SetText(L["Nobody shares their trade balance yet."])
        self.top.info:SetText(m.demoRank and L["Example"] or "")
    end
    return v
end

local function buildPrices(p, body)
    local v = CreateFrame("Frame", nil, body)
    v:SetAllPoints()
    v.search = K.Input(v, 170, L["Search item …"], function(t)
        local s = low(t):gsub("^%s+", ""):gsub("%s+$", "")
        if s == search then return end
        search = s
        ns.RefreshPage("trade")
    end)
    v.search:SetPoint("TOPLEFT", 0, 0)
    v.sort = K.Button(v, "", 150, 22, "ghost")
    v.sort.isDropdown = true
    K.SetFontSafe(v.sort.label, K.FONT, 11, "", K.FONT)
    v.sort:SetPoint("LEFT", v.search, "RIGHT", 8, 0)
    v.sort:SetScript("OnClick", function(self)
        local items = {}
        for _, s in ipairs(SORTS) do
            items[#items + 1] = { text = L[s.text], checked = sortBy == s.key, fn = function() sortBy = s.key ns.RefreshPage("trade") end }
        end
        K.ShowMenu(self, items, L["Sort by"], 160)
    end)
    v.chip = K.Button(v, L["Cheap only"], 100, 22, "ghost", function()
        onlyCheap = not onlyCheap
        ns.RefreshPage("trade")
    end)
    K.SetFontSafe(v.chip.label, K.FONT, 11, "", K.FONT)
    v.chip:SetWidth(math.max(90, (v.chip.label:GetStringWidth() or 70) + 26))
    v.chip:SetPoint("LEFT", v.sort, "RIGHT", 6, 0)
    v.chip:HookScript("OnLeave", function(self)
        local c = onlyCheap and C.mint or C.muted
        self.label:SetTextColor(c[1], c[2], c[3])
        K.SetBorderColor(self, onlyCheap and C.mint or C.line)
    end)
    v.count = K.Text(v, 11, C.dim, "RIGHT")
    v.count:SetPoint("TOPRIGHT", -4, -6)
    v.count:SetText("")
    -- Spaltenkoepfe
    v.hd = CreateFrame("Frame", nil, v)
    v.hd:SetHeight(18)
    v.hd:SetPoint("TOPLEFT", 0, -30)
    v.hd:SetPoint("TOPRIGHT", 0, -30)
    local function hcol(text, justify)
        local fs = K.Text(v.hd, 10, C.dim, justify)
        fs:SetText(L[text])
        return fs
    end
    v.hName, v.hFair, v.hCur, v.hTrend = hcol("Item"), hcol("Fair", "RIGHT"), hcol("Current", "RIGHT"), hcol("Trend", "RIGHT")
    v.hName:SetPoint("LEFT", 44, 0)
    v.list = K.List(v, 38, function(list)
        local r = K.Row(list)
        r.cheapBg = r:CreateTexture(nil, "BACKGROUND", nil, 1)
        r.cheapBg:SetAllPoints()
        r.cheapBg:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0.04)
        r.cheapBar = r:CreateTexture(nil, "ARTWORK")
        r.cheapBar:SetPoint("TOPLEFT") r.cheapBar:SetPoint("BOTTOMLEFT")
        r.cheapBar:SetWidth(2)
        r.cheapBar:SetColorTexture(C.mint[1], C.mint[2], C.mint[3], 0)
        r.badge = itemBadge(r, 28)
        r.badge:SetPoint("LEFT", 8, 0)
        r.name = K.Text(r, 12, C.text)
        r.name:SetPoint("TOPLEFT", 44, -5)
        r.name:SetWordWrap(false)
        r.name:SetText("")
        r.sub = K.Text(r, 10, C.dim)
        r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
        r.sub:SetWordWrap(false)
        r.sub:SetText("")
        r.fair = K.Text(r, 12, C.muted, "RIGHT")
        r.cur = K.Text(r, 12, C.text, "RIGHT")
        r.trend = K.Text(r, 11, C.text, "RIGHT")
        r.fair:SetText("") r.cur:SetText("") r.trend:SetText("")
        r.arrow = r:CreateTexture(nil, "ARTWORK")
        r.arrow:SetSize(12, 12)
        r.arrow:SetPoint("RIGHT", r.trend, "LEFT", -2, 0)
        r.spark = miniSpark(r, 56, 18, 14)
        r:RegisterForClicks("LeftButtonUp")
        r:SetScript("OnEnter", function(self)
            local e = self.item
            if not e then return end
            K.ItemTip(self, "item:" .. e.id)
            if GameTooltip:IsShown() then
                GameTooltip:AddLine(" ")
                GameTooltip:AddDoubleLine(L["fair"], money(e.fair), 0.7, 0.7, 0.7, 1, 1, 1)
                GameTooltip:AddDoubleLine(L["now"], money(e.cur), 0.7, 0.7, 0.7, 1, 1, 1)
                if e.info.floor7 then GameTooltip:AddDoubleLine(L["7-day low"], money(e.info.floor7), 0.7, 0.7, 0.7, 1, 1, 1) end
                GameTooltip:AddLine(L["Shift-click: link in chat"], 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:SetScript("OnClick", function(self)
            local e = self.item
            if e and IsShiftKeyDown and IsShiftKeyDown() then insertLink(itemLink(e.id, e.name, e.q)) end
        end)
        return r
    end, function(r, e)
        local W = r:GetWidth() or 600
        local wide = W > 560
        r.cheapBg:SetShown(e.cheap)
        r.cheapBar:SetShown(e.cheap)
        r.badge:Set(e.id, e.q)
        r.name:SetText(K.hex(QCOL[e.q] or QCOL[1]) .. e.name .. "|r" .. (e.cheap and ("  " .. K.hex(C.mint) .. L["Cheap now"] .. "|r") or ""))
        r.sub:SetText((e.cat and L[CATS[e.cat]] or "") .. (e.info.floor7 and (((e.cat and "  |cff555555·|r  ") or "") .. L["7-day low"] .. " " .. money(e.info.floor7)) or ""))
        -- Spalten von rechts: Verlauf | Trend | aktuell | fair
        local x = -8
        r.spark:ClearAllPoints()
        if wide and e.info.hist then
            r.spark:SetPoint("RIGHT", x, 0)
            r.spark:SetValues(e.info.hist, e.pct < 0 and C.mint or e.pct > 0 and C.red or C.muted)
            x = x - 64
        else
            r.spark:Hide()
            if wide then x = x - 64 end
        end
        r.trend:ClearAllPoints()
        r.trend:SetPoint("RIGHT", x, 0)
        r.trend:SetWidth(44)
        r.trend:SetText(trendText(e.pct))
        setArrow(r.arrow, e.pct)
        x = x - 62
        r.cur:ClearAllPoints()
        r.cur:SetPoint("RIGHT", x, 0)
        r.cur:SetWidth(96)
        r.cur:SetText(money(e.cur))
        x = x - 100
        r.fair:ClearAllPoints()
        r.fair:SetPoint("RIGHT", x, 0)
        r.fair:SetWidth(96)
        r.fair:SetText(money(e.fair))
        x = x - 100
        r.name:SetPoint("RIGHT", r, "RIGHT", x - 4, 0)
        r.sub:SetPoint("RIGHT", r, "RIGHT", x - 4, 0)
    end)
    v.list:SetPoint("TOPLEFT", 0, -50)
    v.list:SetPoint("BOTTOMRIGHT", 0, 0)
    function v:Layout(W)
        self.search:SetWidth(W < 640 and 130 or 170)
        self.count:SetShown(W > 600)
        -- Spaltenkoepfe wie in den Zeilen
        local x = -16
        if W > 568 then x = x - 64 end
        self.hTrend:ClearAllPoints() self.hTrend:SetPoint("RIGHT", self.hd, "RIGHT", x, 0)
        x = x - 62
        self.hCur:ClearAllPoints() self.hCur:SetPoint("RIGHT", self.hd, "RIGHT", x, 0)
        x = x - 100
        self.hFair:ClearAllPoints() self.hFair:SetPoint("RIGHT", self.hd, "RIGHT", x, 0)
    end
    function v:Fill(m)
        local out = {}
        for _, e in ipairs(m.items) do
            if (not onlyCheap or e.cheap) and (search == "" or e.search:find(search, 1, true)) then out[#out + 1] = e end
        end
        table.sort(out, function(a, b)
            if sortBy == "name" then return low(a.name) < low(b.name) end
            if sortBy == "price" then
                if (a.cur or 0) ~= (b.cur or 0) then return (a.cur or 0) > (b.cur or 0) end
            elseif sortBy == "trend" then
                if a.pct ~= b.pct then return a.pct > b.pct end
            else
                if a.cheap ~= b.cheap then return a.cheap end
                if a.pct ~= b.pct then return a.pct < b.pct end
            end
            return low(a.name) < low(b.name)
        end)
        self.list.empty:SetText(#m.items == 0 and L["No prices yet. Once someone scans the AH with Midas, they show up here."]
            or L["Nothing found - try another search?"])
        self.list:SetData(out)
        self.count:SetText((L["%d items"]):format(#out))
        local sl
        for _, s in ipairs(SORTS) do if s.key == sortBy then sl = L[s.text] end end
        self.sort:SetLabel("|cff888888" .. L["Sort:"] .. "|r " .. (sl or "") .. "  |cff666666v|r")
        self.sort:SetWidth(math.floor((self.sort.label:GetStringWidth() or 120) + 24))
        local c = onlyCheap and C.mint or C.muted
        self.chip.label:SetTextColor(c[1], c[2], c[3])
        K.SetBorderColor(self.chip, onlyCheap and C.mint or C.line)
        if (self.search:GetText() or "") ~= search and not self.search:HasFocus() then self.search:SetText(search) end
    end
    return v
end

local function buildRank(p, body)
    local v = CreateFrame("Frame", nil, body)
    v:SetAllPoints()
    v.head = K.Text(v, 11, C.muted)
    v.head:SetPoint("TOPLEFT", 2, -2)
    v.head:SetPoint("RIGHT", -2, 0)
    v.head:SetWordWrap(true)
    v.head:SetText(L["Voluntary trade balance of the last 7 days from Midas. The leader earns the title 'Goldmaker of the week'."])
    v.list = K.List(v, 46, function(list)
        local r = K.Row(list)
        r.medal = r:CreateTexture(nil, "BORDER")
        r.medal:SetTexture(CIRCLE)
        r.medal:SetSize(24, 24)
        r.medal:SetPoint("LEFT", 8, 0)
        r.num = K.Title(r, 12, C.text, "CENTER")
        r.num:SetPoint("CENTER", r.medal, "CENTER", 0, 0)
        r.num:SetText("")
        r.cls = r:CreateTexture(nil, "ARTWORK")
        r.cls:SetSize(26, 26)
        r.cls:SetPoint("LEFT", r.medal, "RIGHT", 10, 0)
        circleMask(r, r.cls)
        r.name = K.Text(r, 13, C.text)
        r.name:SetPoint("TOPLEFT", r.cls, "TOPRIGHT", 10, 1)
        r.name:SetWordWrap(false)
        r.name:SetText("")
        r.sub = K.Text(r, 10, C.dim)
        r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
        r.sub:SetText("")
        r.barBg = r:CreateTexture(nil, "ARTWORK")
        r.barBg:SetHeight(6)
        r.barBg:SetColorTexture(C.field[1], C.field[2], C.field[3], 1)
        r.bar = r:CreateTexture(nil, "OVERLAY")
        r.bar:SetHeight(6)
        r.val = K.Text(r, 13, C.text, "RIGHT")
        r.val:SetPoint("RIGHT", -12, 0)
        r.val:SetWidth(110)
        r.val:SetText("")
        return r
    end, function(r, e, idx)
        local m = MEDAL[idx]
        if m then
            r.medal:SetVertexColor(m[1], m[2], m[3], 1)
            r.num:SetTextColor(0.08, 0.08, 0.08)
        else
            r.medal:SetVertexColor(C.raised[1] * 1.6, C.raised[2] * 1.6, C.raised[3] * 1.6, 1)
            r.num:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
        end
        r.num:SetText(idx)
        r.cls:SetShown(setClassIcon(r.cls, classOf(e)))
        local mine = ns.isMe(e.name)
        r.name:SetText(colored(e.name) .. (mine and ("  |cff888888(" .. L["you"] .. ")|r") or "")
            .. (idx == 1 and e.net > 0 and ("  |cffe8b44a" .. L["Goldmaker of the week"] .. "|r") or ""))
        r.sub:SetText((L["%d sales"]):format(e.sold or 0))
        r.val:SetText(signedMoney(e.net))
        -- Balken: Anteil am Besten
        local W = r:GetWidth() or 600
        local x0 = 220
        local bw = math.max(40, W - x0 - 140)
        r.name:SetPoint("RIGHT", r, "LEFT", x0 - 8, 0)
        r.barBg:ClearAllPoints()
        r.barBg:SetPoint("LEFT", x0, 0)
        r.barBg:SetWidth(bw)
        local mx = 1
        for _, x in ipairs(r:GetParent().data or {}) do mx = math.max(mx, math.abs(x.net or 0)) end
        local c = e.net >= 0 and (m or C.mint) or C.red
        r.bar:ClearAllPoints()
        r.bar:SetPoint("LEFT", r.barBg, "LEFT", 0, 0)
        r.bar:SetWidth(math.max(2, bw * math.abs(e.net) / mx))
        r.bar:SetColorTexture(c[1], c[2], c[3], 0.9)
    end)
    v.list:SetPoint("TOPLEFT", 0, -38)
    v.list:SetPoint("BOTTOMRIGHT", 0, 34)
    v.mine = K.Text(v, 12, C.muted)
    v.mine:SetPoint("BOTTOMLEFT", 2, 10)
    v.mine:SetText("")
    v.share = K.Button(v, "", 160, 22, "ghost", function()
        S().shareTrade = not S().shareTrade
        if ns.Radar then ns.Radar.SendHello() end
        ns.RefreshPage("trade")
    end)
    K.SetFontSafe(v.share.label, K.FONT, 11, "", K.FONT)
    v.share:SetPoint("BOTTOMRIGHT", 0, 6)
    function v:Layout() end
    function v:Fill(m)
        self.list.empty:SetText(L["Nobody shares their trade balance yet. Turn on 'Share balance' below to get started."])
        self.list:SetData(m.rank)
        self.mine:SetText(m.net and (L["Your balance (7 days): "] .. signedMoney(m.net) .. "  |cff777777" .. (L["%d sales"]):format(m.sold or 0)
            .. (S().shareTrade and "" or ("  ·  " .. L["(only visible to you)"])) .. "|r") or ("|cff777777" .. L["No trade balance without Midas."] .. "|r"))
        self.share:SetLabel(S().shareTrade and L["Share balance: on"] or L["Share balance: off"])
        self.share:SetWidth(math.floor((self.share.label:GetStringWidth() or 120) + 26))
        local c = S().shareTrade and C.mint or C.muted
        self.share.label:SetTextColor(c[1], c[2], c[3])
    end
    return v
end

local function buildOpts(p, body)
    local v = CreateFrame("Frame", nil, body)
    v:SetAllPoints()
    local function get(key, default) return function() local x = S()[key] if x == nil then return default end return x end end
    local function set(key, after) return function(x) S()[key] = x if after then after(x) end ns.RefreshPage("trade") end end
    v.rows = {
        optRow(v, "wants", C.pink, "Wishlist alert", "If something from your wishlist is cheap in the AH, you get a notice - even if someone else scanned.",
            get("wantAlarm", true), set("wantAlarm")),
        optRow(v, "announce", C.amber, "Answer price checks", "When someone types 'pc [item]' in guild chat, exactly one Oasis user answers with the price and 7-day low.",
            get("priceAnswer", true), set("priceAnswer")),
        optRow(v, "badges", C.blue, "Share my trade balance", "Optional: your profit of the last 7 days shows up in the trader ranking.",
            get("shareTrade", false), set("shareTrade", function() if ns.Radar then ns.Radar.SendHello() end end)),
    }
    for i, r in ipairs(v.rows) do
        r:SetPoint("TOPLEFT", 0, -(i - 1) * 64)
        r:SetPoint("RIGHT", 0, 0)
    end
    v.guild = K.Text(v, 11, C.muted)
    v.guild:SetPoint("TOPLEFT", 4, -(#v.rows * 64) - 8)
    v.guild:SetPoint("RIGHT", -4, 0)
    v.guild:SetWordWrap(true)
    v.guild:SetText("")
    v.midas = K.Button(v, L["Open Midas"], 130, 24, "ghost", Trade.OpenMidas)
    v.midas:SetPoint("TOPLEFT", v.guild, "BOTTOMLEFT", -4, -12)
    v.note = K.Text(v, 11, C.dim)
    v.note:SetPoint("TOPLEFT", v.midas, "BOTTOMLEFT", 4, -10)
    v.note:SetPoint("RIGHT", -4, 0)
    v.note:SetWordWrap(true)
    v.note:SetText("")
    function v:Layout() end
    function v:Fill(m)
        for _, r in ipairs(self.rows) do r:Refresh() end
        local pc = tonumber(ns.GuildOpt("trCheap")) or 85
        local hrs = tonumber(ns.GuildOpt("trAlrtH")) or 12
        self.guild:SetText((L["Set by the guild leaders: a wish counts as cheap at %d %% of the fair price or less, the same wish is reported at most every %d h."]):format(pc, hrs)
            .. (ns.GuildOpt("trPcAns") == false and ("\n|cffe8b44a" .. L["Price questions in guild chat are turned off by the guild leaders."] .. "|r") or ""))
        local has = SlashCmdList and SlashCmdList.MIDAS ~= nil
        self.midas:SetShown(has and true or false)
        self.note:ClearAllPoints()
        if has then self.note:SetPoint("TOPLEFT", self.midas, "BOTTOMLEFT", 4, -10)
        else self.note:SetPoint("TOPLEFT", self.guild, "BOTTOMLEFT", 0, -12) end
        self.note:SetPoint("RIGHT", -4, 0)
        self.note:SetText(Trade.HasMidas()
            and L["At the Auction House, click 'Midas Scan' at the top right. The prices go to everyone in the guild automatically."]
            or ("|cffe8b44a" .. L["Midas is not installed."] .. "|r " .. L["Optional: install the AH addon Midas yourself to get prices, wishlist alerts and more here. Oasis works without it too."]))
    end
    return v
end

local TOP_Y, BODY_Y = 0, -44   -- 0.5.853: Kennzahl-Kacheln entfallen, Inhalt beginnt direkt unter den Reitern
ns.RegisterPage({
    key = "trade", title = "Market", order = 2.3,
    sub = "Auction House prices for the guild - one scans, everyone benefits",
    build = function(p)
        page = p
        p.fresh = true
        p:HookScript("OnShow", function(self) self.fresh = true end)
        p.tabs = buildTabs(p, function(k) switchTo(k) end)
        p.tabs:SetPoint("TOPLEFT", 0, TOP_Y)
        -- AH-Stand rechts oben
        p.pill = CreateFrame("Frame", nil, p)
        p.pill:SetHeight(24)
        p.pill:SetPoint("TOPRIGHT", 0, -5)
        glass(p.pill, 10, 0.04)
        p.pill.dot = p.pill:CreateTexture(nil, "ARTWORK")
        p.pill.dot:SetTexture(CIRCLE)
        p.pill.dot:SetSize(8, 8)
        p.pill.dot:SetPoint("LEFT", 10, 0)
        p.pill.text = K.Text(p.pill, 11, C.muted)
        p.pill.text:SetPoint("LEFT", p.pill.dot, "RIGHT", 7, 0)
        p.pill.text:SetWordWrap(false)
        p.pill.text:SetText("")
        p.pill:EnableMouse(true)
        p.pill:SetScript("OnEnter", function(self) if self.tip then K.ShowTip(self, self.tip) end end)
        p.pill:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Kacheln
        p.tileRow = CreateFrame("Frame", nil, p)
        p.tileRow:SetPoint("TOPLEFT", 0, -42)
        p.tileRow:SetPoint("TOPRIGHT", 0, -42)
        p.tileRow:SetHeight(56)
        p.tiles = {}
        local function onTile(k)
            if k == "scan" then switchTo("over")
            elseif k == "items" then switchTo("prices", false)
            elseif k == "hits" then switchTo("prices", true)
            else switchTo("rank") end
        end
        for i, d in ipairs(TILES) do p.tiles[i] = buildTile(p.tileRow, d, onTile) end
        p.tileRow:Hide()
        -- Inhalt
        p.body = CreateFrame("Frame", nil, p)
        p.body:SetPoint("TOPLEFT", 0, BODY_Y)
        p.body:SetPoint("BOTTOMRIGHT", 0, 0)
        p.views = { over = buildOverview(p, p.body), prices = buildPrices(p, p.body), rank = buildRank(p, p.body), opts = buildOpts(p, p.body) }
        p.lock = buildLock(p)

        function p:Layout()
            local W, H = self:GetWidth() or 760, self:GetHeight() or 520
            if W < 50 or H < 50 then return end
            local n, gap = #self.tiles, 8
            local tw = math.floor((W - gap * (n - 1)) / n)
            for i, t in ipairs(self.tiles) do
                t:ClearAllPoints()
                t:SetPoint("TOPLEFT", self.tileRow, "TOPLEFT", (i - 1) * (tw + gap), 0)
                t:SetWidth(tw)
            end
            local pw = math.min(math.floor(W * 0.42), math.floor((self.pill.text:GetStringWidth() or 120) + 30))
            self.pill:SetWidth(pw)
            self.pill.text:SetWidth(pw - 30)
            self.tabs.maxW = math.max(160, W - pw - 16)
            self.tabs:Layout()
            local bh = H + BODY_Y
            for _, v in pairs(self.views) do v:Layout(W, bh) end
        end
        p:HookScript("OnSizeChanged", function(self) self:Layout() end)
    end,
    refresh = function(p)
        local fresh, switch = p.fresh, p.switch
        p.fresh, p.switch = false, nil
        local m = gather()

        -- Sperre nur ohne Midas, ohne Scan in der Gilde und ohne Demo
        local locked = not m.hasMidas and not m.ts and not m.demo
        p.lock:SetShown(locked)
        if locked then p.lock:Update() end

        -- AH-Stand
        local c = m.ts and Trade.ScanColor(m.ts) or C.dim
        p.pill.dot:SetVertexColor(c[1], c[2], c[3])
        p.pill.text:SetText((m.demo and (K.hex(C.amber) .. L["Demo"] .. "|r  |cff555555·|r  ") or "")
            .. (m.ts and (L["AH data"] .. " " .. ns.ago(m.ts) .. "  |cff555555·|r  " .. colored(m.who)) or L["No scan yet"]))
        p.pill.tip = m.ts and { L["Auction House"], (L["scanned by %s"]):format(colored(m.who)) .. "  |cff777777" .. date(L["%m/%d %H:%M"], m.ts) .. "|r",
            "|cff888888" .. L["At the Auction House, click 'Midas Scan' at the top right. The prices go to everyone in the guild automatically."] .. "|r" }
            or { L["No scan yet"], "|cff888888" .. L["As soon as someone with Oasis scans the AH, it shows up here."] .. "|r" }
        if m.demo then p.pill.tip[#p.pill.tip + 1] = K.hex(C.amber) .. L["Demo: sample prices, only visible to you"] .. "|r" end

        -- Kacheln
        local vals = {
            scan = { m.ts and ns.ago(m.ts) or "–", m.ts and ns.displayName(m.who) or "", m.ts and Trade.ScanColor(m.ts) or C.dim },
            items = { #m.items, m.cheapN > 0 and (L["%d cheap"]):format(m.cheapN) or "", #m.items > 0 and C.text or C.dim },
            hits = { #m.wants, "", #m.wants > 0 and C.text or C.dim },
            gain = { m.net and shortGold(m.net) or "–", m.net and (L["%d sales"]):format(m.sold or 0) or "", m.net and (m.net >= 0 and C.mint or C.red) or C.dim },
        }
        for i, t in ipairs(p.tiles) do
            local v = vals[t.key]
            t.value:SetTextColor(v[3][1], v[3][2], v[3][3])
            if fresh and animOn() and type(v[1]) == "number" then K.CountUp(t.value, v[1], 0.8, nil, (i - 1) * 0.05)
            elseif t.shown ~= v[1] then t.value:SetText(v[1]) end
            t.shown = v[1]
            t.sub:SetText(v[2])
            t:SetSel((t.key == "scan" and view == "over") or (t.key == "items" and view == "prices" and not onlyCheap)
                or (t.key == "hits" and view == "prices" and onlyCheap) or (t.key == "gain" and view == "rank"))
        end
        if fresh and animOn() then for i, t in ipairs(p.tiles) do K.FadeIn(t, (i - 1) * 0.05) end end
        p.tabs:SetCounts({ prices = #m.items, rank = #m.rank })
        p.tabs:Select(view, not fresh)

        for k, v in pairs(p.views) do v:SetShown(k == view) end
        p:Layout()
        local cur = p.views[view]
        if cur then cur:Fill(m) end
        if switch then p.views.prices.list.offset = 0 end
    end,
})

-- Item-Daten kommen nach: sichtbare Seite neu zeichnen (gedrosselt)
local itemPend
local function itemsArrived()
    if itemPend or not (page and page.IsVisible and page:IsVisible()) then return end
    itemPend = true
    ns.After(0.6, function()
        itemPend = nil
        if page and page:IsVisible() then ns.RefreshPage("trade") end
    end)
end
pcall(ns.On, "GET_ITEM_INFO_RECEIVED", itemsArrived)
pcall(ns.On, "ITEM_DATA_LOAD_RESULT", itemsArrived)

-- Demo an/aus: Seite sofort umstellen (Beispieldaten liegen nur hier, nichts im Store)
ns.Listen("LOGIN", function()
    local D = ns.Demo
    if D and not D.tradeHooked and D.Load and D.Remove then
        D.tradeHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) ns.RefreshPage("trade") end
        D.Remove = function(...) remove(...) ns.RefreshPage("trade") end
    end
end)

ns.slash.markt = function() ns.ShowPage("trade") end

-- Midas-Auto-Scan: beim Oeffnen des Auktionshauses scannt Midas im Hintergrund (Midas' eigene Funktion,
-- Midas haelt die Server-Sperre von ~15 Min selbst ein). Schalter: Einstellungen > Bereiche > Markt.
function ns.ApplyMidasAutoScan()
    local cfg = _G.MidasDB and _G.MidasDB.config
    if type(cfg) ~= "table" then return end
    cfg.autoScan = ns.db.settings.midasAutoScan ~= false
end
ns.Listen("LOGIN", function() ns.After(2, ns.ApplyMidasAutoScan) end)
ns.On("AUCTION_HOUSE_SHOW", function() pcall(ns.ApplyMidasAutoScan) end)
end)

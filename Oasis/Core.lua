-- Oasis Gildenzentrale - Kern: Datenbank, Ereignisse, Hilfsfunktionen
local ADDON, ns = ...
local L = ns.L
Oasis = ns
ns.version = "0.6.519"
ns.versionDate = "19.10.2026"
ns.SUPPORT_URL = ""   -- Link fuer "Bericht kopieren" (z. B. Discord-Einladung); leer = nur Text
ns.WAGO_ID = ""       -- Wago-Projekt-ID fuer Wago Analytics (leer = aus)   -- Datum der Version: bei JEDER neuen Version mitpflegen (Update-Hinweis im Gildenchat)
ns.MEDIA = "Interface\\AddOns\\Oasis\\Media\\"

------------------------------------------------------------------------
-- Secret-Values (Midnight-Sperre): alles, was geheim ist, wird zu nil
------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
function ns.safe(v)
    if v == nil then return nil end
    if issecret(v) then return nil end
    return v
end
-- mehrere Rueckgabewerte auf einmal entschaerfen
function ns.safeAll(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do t[i] = ns.safe((select(i, ...))) end
    return unpack(t, 1, n)
end

------------------------------------------------------------------------
-- Ausgabe
------------------------------------------------------------------------
-- Farbverlauf ueber einen kurzen ASCII-Text (je Buchstabe ein Farbcode); from/to = { r, g, b } in 0..255
function ns.GradientText(text, from, to)
    local n, out = #text, {}
    for i = 1, n do
        local t = n > 1 and (i - 1) / (n - 1) or 0
        out[i] = ("|cff%02x%02x%02x%s"):format(
            math.floor(from[1] + (to[1] - from[1]) * t + 0.5), math.floor(from[2] + (to[2] - from[2]) * t + 0.5),
            math.floor(from[3] + (to[3] - from[3]) * t + 0.5), text:sub(i, i))
    end
    return table.concat(out) .. "|r"
end
-- Name im Chat: Oasis-Rot nach warmem Orange, davor ein schmaler Strich statt eckiger Klammern
ns.BRAND = ns.GradientText("Oasis", { 255, 40, 20 }, { 255, 170, 70 })
local PREFIX = "|cffff2814|||r " .. ns.BRAND   -- "||" = ein sichtbarer Strich, danach |r (vorher fehlte ein Strich: im Chat stand "|r")
function ns.print(...)
    print(PREFIX, ...)
end
function ns.debug(...)
    if ns.db and ns.db.settings.debug then
        print(L["|cffff3fbf[Oasis-Debug]|r"], ...)
    end
end
local errSeen = {}
-- Fehlerort festhalten (0.5.505): pcall verliert die Aufrufkette, xpcall mit diesem Halter merkt sie sich
-- -> Fehlerberichte zeigen die echte Codezeile statt nur "Core.lua (Timer)".
local function errTrace(e)
    ns.lastErrStack = debugstack and debugstack(2, 10, 0) or nil
    ns.lastErrAt = GetTime and GetTime() or 0
    return e
end
ns.errTrace = errTrace
function ns.err(where, msg)
    local key = tostring(where) .. tostring(msg)
    if errSeen[key] then return end
    errSeen[key] = true
    print(L["|cffff5060[Oasis-Fehler]|r "] .. tostring(where) .. ": " .. tostring(msg))
end

------------------------------------------------------------------------
-- Namen
------------------------------------------------------------------------
-- Beim Laden liefert WoW teils "Unbekannt"/"Unknown" statt des echten Namens -> nie merken
local function validName(n)
    return type(n) == "string" and n ~= "" and n ~= UNKNOWNOBJECT and n ~= UNKNOWN and n ~= "Unknown" and n ~= "Unbekannt"
end
ns.validName = validName

local realmCache
local function myRealm()
    if realmCache then return realmCache end
    local r = ns.safe(GetNormalizedRealmName and GetNormalizedRealmName())
    if not r or r == "" then
        r = ns.safe(GetRealmName())
        r = r and r:gsub("[%s%-]", "") or nil
    end
    if r and r ~= "" then realmCache = r end
    return r or "Realm"
end
function ns.fullName(name)
    name = ns.safe(name)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. myRealm()
end
-- Forever: UnitName liefert Vorname UND Nachname, nicht Name und Realm.
-- Addon-eigener Adapter: keine Blizzard-Globals ersetzen.
function ns.UnitName(unit)
    local name, second = UnitName(unit)
    name, second = ns.safe(name), ns.safe(second)
    if not name then return nil end
    local regional = RegionalUniqueNamesEnabled and ns.safe(RegionalUniqueNamesEnabled())
    if regional then
        local sep = Constants and Constants.CharacterNameSeparatorConsts
            and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
        if second and second ~= "" and not name:find(sep, 1, true) then name = name .. sep .. second end
        return name
    end
    return name, second
end
function ns.UnitFullName(unit)
    local name, realm = ns.UnitName(unit)
    if not name then return nil end
    return name, realm or myRealm()
end
-- Nur fuer FontString:SetText: der Client darf geheime Namen direkt anzeigen.
function ns.UnitDisplayName(unit)
    if NameUtil and NameUtil.FormatUnitNameForDisplay then
        local ok, name = pcall(NameUtil.FormatUnitNameForDisplay, unit, true)
        if ok then return name end
    end
    local name = ns.UnitName(unit)
    if name then return name end
    return UnitName(unit)
end
-- Alte Vorname-Schluessel nur ueber eindeutig verknuepfte Roster-Eintraege aufloesen.
function ns.ResolveName(name, fromGuild)
    local full = ns.fullName(name)
    if not full then return nil end
    local R = ns.Radar
    local member = R and R.byName and R.byName[full]
    if not member and R and R.byNameLower then member = R.byNameLower[full:lower()] end
    -- Forever (regional eindeutige Namen): "Vorname Nachname" ist in der ganzen Region eindeutig, der Realm-Anhang nicht.
    -- Jeder Client haengt an realmlose Namen SEINEN Realm - derselbe Charakter kommt so als "...-ClassicBetaPvE" und
    -- "...-ClassicBetaPvE2" an (Gruppenmeldungen, Profile, Absender). Passt der Realm nicht, ueber den Namen allein
    -- aufloesen - aber nur, wenn genau EIN Gildenmitglied so heisst.
    if not member and R and R.roster and RegionalUniqueNamesEnabled and ns.safe(RegionalUniqueNamesEnabled()) then
        local idx = ns._baseIdx
        if not idx or idx.src ~= R.roster or idx.n ~= #R.roster then
            idx = { src = R.roster, n = #R.roster, map = {}, first = {} }
            for _, m in ipairs(R.roster) do
                local base = type(m.name) == "string" and (m.name:match("^(.*)%-[^%-]+$") or m.name):lower()
                if base and base ~= "" then
                    if idx.map[base] == nil then idx.map[base] = m else idx.map[base] = false end   -- false = mehrdeutig
                    local first = base:match("^(%S+)%s")
                    if first then
                        if idx.first[first] == nil then idx.first[first] = m else idx.first[first] = false end
                    end
                end
            end
            ns._baseIdx = idx
        end
        local base = (full:match("^(.*)%-[^%-]+$") or full):lower()
        local hit = idx.map[base]
        -- Addon-Nachrichten tragen teils nur den VORNAMEN ("Mira-ClassicBetaPvE2"). Der ist regional nicht eindeutig,
        -- darum nur fuer Absender aus dem Gildenkanal (sicher ein Gildenmitglied) und nur bei genau einem Treffer.
        if not hit and fromGuild and not base:find("%s") then hit = idx.first[base] end
        if hit then member = hit end
    end
    return member and member.name or full
end
function ns.NameKey(name)
    return (ns.ResolveName(name) or ""):lower()
end
function ns.SameName(a, b)
    a, b = ns.safe(a), ns.safe(b)
    return type(a) == "string" and type(b) == "string" and a ~= "" and b ~= ""
        and ns.NameKey(a) == ns.NameKey(b)
end

-- 0.5.774: C_GuildInfo.GuildRoster() ist im Forever-Client geschuetzt ("Oasis wurde geblockt ... UNKNOWN()", Spur: GuildRoster direkt davor).
-- Die Gildenliste kommt ohnehin per GUILD_ROSTER_UPDATE vom Server; der Aufruf bleibt nur noch hinter settings.rosterCall = true.
function ns.RequestGuildRoster()
    local s = ns.db and ns.db.settings
    -- 0.5.788: wieder standardmaessig AN - die Blockierung kam nachweislich von den Discord-Abfragen, nicht von hier. Ohne den Aufruf
    -- bleibt die Gildenliste stehen (wer online kommt, wird erst spaet bemerkt). Abschalten nur noch zum Testen: rosterCall = false
    if s and s.rosterCall == false then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        if ns.Trace then ns.Trace("C_GuildInfo.GuildRoster") end
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end
function ns.me()
    if not ns._me then
        local n = ns.UnitName("player")
        if validName(n) and myRealm() ~= "Realm" then ns._me = ns.fullName(n) end
    end
    return ns._me
end
function ns.short(name)
    name = ns.safe(name)
    if type(name) ~= "string" then return "?" end
    return (name:gsub("%-.*$", ""))
end
-- Vollstaendiger Charaktername fuer Fluestern und Einladen (Realm nur intern).
function ns.ChatName(name)
    if not name then return "?" end
    return ns.short(ns.ResolveName(name))
end
-- Anfluestern: "/w Vorname Nachname" versteht WoW nicht (nimmt nur das erste Wort) ->
-- WoWs eigene Funktion setzt den kompletten Namen als Ziel
function ns.Whisper(name, text)
    if not name then return end
    if ns.inCombat() then ns.print(L["Im Kampf nicht moeglich - gleich nochmal."]) return end
    local n = ns.ChatName(name)
    if ChatFrame_SendTell then
        ns.Trace("ChatFrame_SendTell")
        ChatFrame_SendTell(n)
        if text and text ~= "" then
            local eb = (ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow())
            if eb then eb:Insert(text) end
        end
    else
        ns.OpenChat("/w " .. n .. " " .. (text or ""))
    end
end
-- ns._meRoster: eigener Name, wie ihn die Gildenliste fuehrt (Forever: "Vorname Nachname-Realm")
function ns.isMe(name)
    return ns.SameName(name, ns.me()) or ns.SameName(name, ns._meRoster)
end

------------------------------------------------------------------------
-- Zeit
------------------------------------------------------------------------
function ns.now()
    return GetServerTime and GetServerTime() or time()
end
function ns.ago(ts)
    if not ts then return "-" end
    local d = ns.now() - ts
    if d < 0 then d = 0 end
    if d < 60 then return L["gerade eben"] end
    if d < 3600 then return (L["vor %d Min"]):format(d / 60) end
    if d < 86400 then return (L["vor %d Std"]):format(d / 3600) end
    if d < 86400 * 14 then return (L["vor %d Tg"]):format(d / 86400) end
    return date(ns.L["%d.%m.%y"], ts)
end
function ns.fmtDate(ts) return ts and date(ns.L["%d.%m. %H:%M"], ts) or "-" end
-- date() liefert Wochentage immer englisch -> selbst uebersetzen
local WEEKDAYS = { "Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag" }
function ns.weekday(ts, short)
    local w = ns.L[WEEKDAYS[tonumber(date("%w", ts)) + 1]]
    if not short then return w end
    -- kurz: die ersten 2 Zeichen (UTF-8-sicher); Chinesisch "星期二" -> "周二", Koreanisch "화요일" -> "화"
    local chars = {}
    for ch in w:gmatch("[%z\1-\127\194-\244][\128-\191]*") do chars[#chars + 1] = ch end
    if chars[1] and #chars[1] >= 3 then
        if chars[1] == "星" and #chars >= 3 then return "周" .. chars[#chars] end
        return chars[1]
    end
    return table.concat(chars, "", 1, math.min(2, #chars))
end
function ns.fmtWhen(ts) return ns.weekday(ts) .. ", " .. date(ns.L["%d.%m. um %H:%M"], ts) end
-- Gebietsname in der eigenen Sprache (aus der Karten-ID), sonst gespeicherter Text
function ns.zoneName(mapID, fallback)
    if mapID and mapID ~= 0 and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then return info.name end
    end
    return fallback or ""
end
function ns.newId(tag)
    return (tag or "x") .. "-" .. ns.short(ns.me() or "?") .. "-" .. ns.now() .. "-" .. math.random(1000, 9999)
end

------------------------------------------------------------------------
-- Klassenfarben
------------------------------------------------------------------------
function ns.classColor(classFile)
    if classFile and C_ClassColor and C_ClassColor.GetClassColor then
        local c = C_ClassColor.GetClassColor(classFile)
        if c then return c.r, c.g, c.b end
    end
    if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return 0.85, 0.82, 0.95
end
function ns.classHex(classFile)
    local r, g, b = ns.classColor(classFile)
    return ("ff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end
-- Rollen/Gruppen-Log zum Nachvollziehen (liegt nach /reload in SavedVariables: OasisDB.roleLog)
function ns.RoleLog(...)
    if not ns.db then return end
    ns.db.roleLog = ns.db.roleLog or {}
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local l = ns.db.roleLog
    l[#l + 1] = ("%s %.2f %s"):format(date("%H:%M:%S"), GetTime() % 1000, table.concat(parts, " "))
    while #l > 300 do table.remove(l, 1) end
end
-- Anzeige-Name: WoW Forever fuehrt Doppelnamen ("Mira Stern"). Fuer ANZEIGEN immer diesen nehmen,
-- fuer Vergleiche/Schluessel/Fluestern/Einladen weiter ns.short bzw. ns.isMe/Radar.byName.
function ns.displayName(name)
    if not name or name == "" then return name or "?" end
    local full = ns.ResolveName(name)
    return ns.short(full)
end
------------------------------------------------------------------------
-- Gilden-Optionen: Einstellungen, die die Gildenleitung fuer die ganze Gilde festlegt.
-- Module melden sie an (beim Laden der Datei), die Gildenleitung zeigt sie im Zahnrad des Moduls.
-- def = { page = "chat", key = "chPin", default = true, kind = "bool"|"num"|"choice", label = "Text", desc = "Text",
--         min =, max =, step =, fmt = function(v) end, choices = { { key = ..., text = "..." }, ... }, lead = true (nur Gildenmeister) }
-- Lesen: ns.GuildOpt("chPin") -> gespeicherter Gildenwert oder Standard (= bisheriges Verhalten)
------------------------------------------------------------------------
ns.GuildOpts, ns.GuildOptsByKey = {}, {}
function ns.GuildOption(def)
    if not def or not def.key or ns.GuildOptsByKey[def.key] then return end
    def.kind = def.kind or (type(def.default) == "boolean" and "bool") or (type(def.default) == "number" and "num") or "choice"
    ns.GuildOpts[#ns.GuildOpts + 1] = def
    ns.GuildOptsByKey[def.key] = def
    if ns.Admin and ns.Admin.RegisterOptionDefault then ns.Admin.RegisterOptionDefault(def) end
end
function ns.GuildOpt(key)
    local def = ns.GuildOptsByKey[key]
    local v
    if ns.Admin and ns.Admin.Cfg then
        local ok, cfg = pcall(ns.Admin.Cfg)
        if ok and cfg then v = cfg[key] end
    end
    if v == nil and def then v = def.default end
    return v
end
function ns.colorName(name, classFile)
    -- WoW Forever: immer den vollen Namen zeigen ("Mira Stern" statt "Mira")
    local full = ns.ResolveName(name)
    return L["|c"] .. ns.classHex(classFile) .. ns.short(full) .. "|r"
end

------------------------------------------------------------------------
-- Kampf / Instanz
------------------------------------------------------------------------
function ns.inCombat()
    return (InCombatLockdown and InCombatLockdown()) or (ns.safe(UnitAffectingCombat("player")) == true)
end
function ns.inInstance()
    local inInst = IsInInstance()
    return inInst and true or false
end
-- Entwickler-Modus: gibt es nur mit dem Gildenmodul (Oasis_Guild/Dev.lua ersetzt ns.IsDev und meldet /oa entwickler an).
-- In der oeffentlichen Version ist niemand Entwickler: Demo-Daten, Testmodus der Gildenleitung und Entwickler-Abfragen
-- bleiben aus - auch wenn jemand den gespeicherten Schalter von Hand setzt. Immer als ns.IsDev() aufrufen, nie zwischenspeichern.
function ns.IsDev() return false end
-- 0.6.275: eigene Position auf der Karte (mapID, x, y 0..1) - frueher Camp.MyPosition, gebraucht von Karte, Lager u. a.
function ns.MyMapPosition()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    x, y = ns.safe(x), ns.safe(y)
    if not x or not y then return nil end
    return mapID, x, y
end
-- 0.6.272: abschaltbare Module melden sich hier an (vorher in ModuleLoader.lua - Moduldateien mussten in der toc dahinter
-- stehen). ModuleLoader.LoadAll fuehrt beim Start nur die eingeschalteten aus; danach nimmt ns.ModuleFile nichts mehr an.
ns.moduleFiles = {}
ns.moduleOrder = {}   -- 0.6.285: Reihenfolge der toc (Module, die auf anderen aufbauen, laden danach)
function ns.ModuleFile(key, fn)
    local files = ns.moduleFiles
    if not files then return end
    if not files[key] then files[key] = {} table.insert(ns.moduleOrder, key) end
    table.insert(files[key], fn)
end
-- 0.6.254: zeichnet ein anderes Addon den Chat selbst (EllesmereUI-Chat: Blizzard-Fenster laufen unsichtbar mit und
-- werden gespiegelt)? Dann veraendert Oasis die Blizzard-Chatfenster nicht - Umschreiben/Entfernen von Zeilen,
-- Ausblenden, eingefuegter Verlauf und Markieren brachten dessen Fenster durcheinander (nur 2-3 Zeilen, Chat
-- wanderte nach oben weg).
function ns.ForeignChat()
    local E = rawget(_G, "EllesmereUI")
    if type(E) == "table" and type(E._chatCFD) == "function" then return true end
    -- Bereits beim Laden erkennen, bevor die fremde Fensterzuordnung bereitsteht.
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    return loaded and loaded("EllesmereUIChat") and true or false
end
-- Minimap-Symbole von Oasis (0.5.960): die Mitte bleibt frei, damit der eigene Pfeil sichtbar ist, und die Symbole liegen in der
-- Ebene der Minimap selbst (vorher eine Ebene hoeher - dann verdeckten sie Rahmen und Kompass).
-- px/py = Abstand von der Minimap-Mitte in Bildschirm-Pixeln.
function ns.MiniPinVisible(px, py)
    local s = ns.db and ns.db.settings
    if s and s.miniCenterClear == false then return true end
    return (px or 0) * (px or 0) + (py or 0) * (py or 0) >= 20 * 20   -- 0.6.410: groesser, Spielerpfeil bleibt frei
end
function ns.MiniPinLayer(p, add)
    if not (p and Minimap) then return end
    pcall(p.SetFrameStrata, p, Minimap:GetFrameStrata() or "LOW")
    -- 0.6.144: eine Ebene tiefer (hoechstens +1) - Rahmen, Kompassnadel und Spieler-Pfeil bleiben obenauf
    pcall(p.SetFrameLevel, p, (Minimap:GetFrameLevel() or 1) + math.min(add or 1, 1))
end
-- Externe Programme (OasisSync, Export-Skripte, Einlese-Skripte) werden mit der oeffentlichen Version vorerst nicht verteilt
--. Einstellungen und Hinweise, die nur damit Sinn ergeben, gibt es deshalb nur mit dem Gildenmodul.
-- Oasis-Tools (Vorlagen fuer eigene Sounds/Emojis, Export-Programme) liegt als getrennte Datei im Oasis-Discord,
-- nie auf CurseForge/Wago/GitHub. Darum zeigt Oasis die Hinweise und Einstellungen dazu fuer alle.
ns.TOOLS_RELEASED = true
function ns.ExternTools() return (ns.GuildPack or ns.TOOLS_RELEASED) and true or false end
-- alle Sounds/Emojis ohne Rang-Sperre (nur bei mir): Entwicklermodus oder /oa freischalten
function ns.UnlockAll()
    -- 0.5.562: ohne Rang-Sperre der Gilde (Standard) ist alles fuer alle frei - Emojis UND Sounds
    -- 0.6.435: Rang-Sperre gilt immer (alte Gilden-Einstellung "frei" wird nicht mehr beachtet)
    -- 0.6.421: Entwickler-Modus schaltet nicht mehr automatisch frei (zum Testen der Sperre) - nur der eigene Schalter
    return (ns.db and ns.db.settings and ns.db.settings.unlockAll == true) or false
end
function ns.isOfficer()
    if ns.db and ns.db.settings.adminTest ~= false and ns.IsDev() then return true end   -- Testmodus der Gildenleitung (nur Entwickler)
    return C_GuildInfo and C_GuildInfo.IsGuildOfficer and C_GuildInfo.IsGuildOfficer() or false
end
function ns.groupChannel()
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end
function ns.isGroupLead()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
end

------------------------------------------------------------------------
-- Spur: die letzten Oasis-Aktionen (fuer den Fehler-Rekorder "blocked from an action")
------------------------------------------------------------------------
ns.trail = {}
function ns.Trace(what)
    local t = ns.trail
    t[#t + 1] = { t = GetTime(), w = tostring(what), c = ns.inCombat() }
    if #t > 25 then table.remove(t, 1) end
end

------------------------------------------------------------------------
-- Chat sicher benutzen
-- SendChatMessage ist in Chat-Sperren (Boss, Mythisch+, PvP, "geheime" Kampfphasen) geschuetzt:
-- ein Aufruf loest dann "Oasis wurde blockiert" aus - pcall hilft dagegen nicht. Also vorher pruefen.
------------------------------------------------------------------------
function ns.ChatLocked()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, r = pcall(C_ChatInfo.InChatMessagingLockdown)
        -- Beta meldet das teils dauerhaft -> nur ernst nehmen, wenn wir wirklich in Instanz + Kampf sind
        if ok and r == true and ns.inInstance() and ns.inCombat() then return true end
    end
    return false
end
function ns.SendChat(msg, channel, target)
    if type(msg) ~= "string" or msg == "" then return false end
    channel = channel or "GUILD"
    if ns.ChatLocked() then
        ns.debug("Chat gesperrt, nicht gesendet:", channel)
        return false
    end
    ns.Trace("SendChatMessage " .. channel)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    return pcall(send, msg, channel, nil, target)
end
-- Automatische Chat-Nachrichten (ohne Klick) sperrt WoW Forever ("Blockiert: UNKNOWN()", 08.10.):
-- stattdessen ein Hinweis mit der Nachricht - ein Klick darauf sendet (Klick = Eingabe, erlaubt).
function ns.OfferChat(title, msg, channel, target, color)
    if type(msg) ~= "string" or msg == "" then return end
    local K = ns.K
    local preview = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1")
    -- 0.6.236: an Zeichengrenze kuerzen (vorher mitten in UTF-8-Zeichen wie "–" -> kaputte Zeichen),
    -- "Klick: senden" in eine eigene Zeile (ueberlagerte sonst den Text)
    if #preview > 160 then preview = ns.Utf8Cut(preview, 157) .. "..." end
    -- 0.6.410: Nachricht gedaempft in Anfuehrungszeichen, "Klick: senden" als eigener Hinweis unten rechts
    K.toastHint = "|cffe8b44a" .. L["Klick: senden"] .. "|r"
    K.Toast(title, "|cffa8a8ae\226\128\158" .. preview .. "\226\128\156|r", color or K.C.accent,
        function() ns.SendChat(msg, channel, target) end)
    K.toastHint = nil   -- falls der Hinweis stumm war und nicht gezeigt wurde
end
-- Chat-Eingabe oeffnen ("/w Name ") - im Kampf nicht: das beruehrt die Blizzard-Eingabezeile
function ns.OpenChat(text)
    if ns.inCombat() then
        ns.print(L["Im Kampf nicht moeglich - gleich nochmal."])
        return
    end
    ns.Trace("ChatFrame_OpenChat")
    ChatFrame_OpenChat(text)
end

------------------------------------------------------------------------
-- Items
------------------------------------------------------------------------
local QHEX = { [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00", [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000", [6] = "ffe6cc80", [7] = "ff00ccff" }
function ns.fixColors(s)
    if type(s) ~= "string" or not s:find("|cn", 1, true) then return s end
    s = s:gsub("|cnIQ(%d):", function(q) return "|c" .. (QHEX[tonumber(q)] or "ffffffff") end)
    return (s:gsub("|cn[%w_]+:", "|cffffffff"))
end
function ns.itemID(link)
    if type(link) == "number" then return link end
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end
-- ruft cb(link, name, quality, icon, ilvl, equipLoc) sobald das Item im Cache ist
function ns.withItem(idOrLink, cb)
    local id = ns.itemID(idOrLink)
    if not id then return end
    local function done()
        local name, link, quality, ilvl, _, _, _, _, equipLoc, icon = C_Item.GetItemInfo(idOrLink)
        if name then cb(link, name, quality, icon, ilvl, equipLoc) return true end
    end
    if done() then return end
    if Item and Item.CreateFromItemID then
        local item = Item:CreateFromItemID(id)
        item:ContinueOnItemLoad(function() done() end)
    else
        C_Timer.After(1, done)
    end
end

------------------------------------------------------------------------
-- Einfacher Hash (fuer "hat sich was geaendert?")
------------------------------------------------------------------------
function ns.hash(str)
    local h = 5381
    for i = 1, #str do
        -- unter 2^31 bleiben, damit %x auch mit 32-Bit-long sicher formatiert
        h = (h * 33 + str:byte(i)) % 2147483647
    end
    return ("%08x"):format(h)
end

------------------------------------------------------------------------
-- Fremde Texte entschaerfen (Addon-Nachrichten anderer Spieler):
--  * erlaubt: Farben |cAARRGGBB ... |r, Links auf Items/Zauber/Quests/Erfolge/Spieler (sauber geformt),
--    Symbole |T...|t nur bis 64 Pixel (Riesen-Texturen, die den Bildschirm ueberdecken, werden klein)
--  * alles andere (|K, |A, |n, |H anderer Art, kaputte Sequenzen) wird zu "||" = sichtbares "|", ohne Wirkung
--  * Laenge begrenzt (UTF-8-sicher abgeschnitten). Idempotent: zweimal saeubern = einmal saeubern.
------------------------------------------------------------------------
function ns.Utf8Cut(s, maxLen)
    if type(s) ~= "string" or not maxLen or #s <= maxLen then return s end
    local cut = maxLen
    -- nicht mitten in einem Mehrbyte-Zeichen abschneiden
    while cut > 0 do
        local b = s:byte(cut + 1)
        if not b or b < 128 or b >= 192 then break end
        cut = cut - 1
    end
    return s:sub(1, cut)
end
local LINK_OK = { item = true, spell = true, enchant = true, quest = true, achievement = true, currency = true,
    talent = true, player = true, addon = true }
local function texOk(rest)
    if rest == "" then return true end
    if not rest:match("^[%d:%-%.]*$") then return false end
    local n = 0
    for v in rest:gmatch("[^:]+") do
        n = n + 1
        local x = tonumber(v)
        if not x or (n <= 4 and (x > 64 or x < -64)) then return false end
    end
    return true
end
-- Gegenstands-Links: angezeigten Namen und Farbe aus dem echten Gegenstand nehmen
-- (ein manipulierter Client koennte sonst "[Donnerzorn]" auf ein graues Item schreiben)
local itemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
function ns.FixItemLinks(t)
    if type(t) ~= "string" or not t:find("|Hitem:", 1, true) then return t end
    return (t:gsub("|c([^|]-)|Hitem:(%d+)([^|]*)|h%[([^|%]]*)%]|h|r", function(col, id, rest, text)
        local name, link = itemInfo(tonumber(id))
        if name and link then
            local realCol = link:match("^|c([^|]-)|H")
            return "|c" .. (realCol or col) .. "|Hitem:" .. id .. rest .. "|h[" .. name .. "]|h|r"
        end
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, tonumber(id)) end
        -- noch nicht im Cache: neutral grau mit Nummer statt eines ungepruefften Namens
        return "|cff9d9d9d|Hitem:" .. id .. rest .. "|h[#" .. id .. "]|h|r"
    end))
end
function ns.CleanText(s, maxLen)
    if type(s) ~= "string" then return s end
    if maxLen then s = ns.Utf8Cut(s, maxLen) end
    if not s:find("|", 1, true) then return s end
    local out, i, n = {}, 1, #s
    while i <= n do
        local p = s:find("|", i, true)
        if not p then out[#out + 1] = s:sub(i) break end
        if p > i then out[#out + 1] = s:sub(i, p - 1) end
        local c = s:sub(p + 1, p + 1)
        if c == "|" then
            out[#out + 1] = "||"
            i = p + 2
        elseif c == "c" and s:find("^%x%x%x%x%x%x%x%x", p + 2) then
            out[#out + 1] = s:sub(p, p + 9)
            i = p + 10
        elseif c == "r" then
            out[#out + 1] = "|r"
            i = p + 2
        elseif c == "H" then
            local data, text, e = s:match("^|H([^|]*)|h(%[[^|%]]*%])|h()", p)
            local typ = data and data:match("^(%a+):")
            if data and LINK_OK[typ] and #data <= 200 and not data:find("[^%w:%-%._]")
                and (typ ~= "addon" or data:find("^addon:Oasis:")) then
                out[#out + 1] = "|H" .. data .. "|h" .. text .. "|h"
                i = e
            else
                out[#out + 1] = "||"
                i = p + 1
            end
        elseif c == "T" then
            local path, rest, e = s:match("^|T([^:|]+)([^|]*)|t()", p)
            if path and #path <= 200 then
                if not texOk(rest) then rest = ":0" end
                out[#out + 1] = "|T" .. path .. rest .. "|t"
                i = e
            else
                out[#out + 1] = "||"
                i = p + 1
            end
        else
            out[#out + 1] = "||"
            i = p + 1
        end
    end
    -- offene Farbcodes schliessen (sonst faerbt ein Text die nachfolgende Anzeige mit)
    local open = 0
    for _, part in ipairs(out) do
        if part:sub(1, 2) == "|c" then open = open + 1 elseif part == "|r" and open > 0 then open = open - 1 end
    end
    if open > 0 then out[#out + 1] = string.rep("|r", open) end
    return table.concat(out)
end

------------------------------------------------------------------------
-- Ereignisse (WoW) und interne Nachrichten
------------------------------------------------------------------------
local evFrame = CreateFrame("Frame")
local evHandlers = {}
-- Einheiten-Events nur fuer die Einheiten anmelden, die Oasis wirklich braucht (sonst im Raid hunderte pro Sekunde)
local PLAYER_UNIT_EVENTS = { UNIT_SPELLCAST_SENT = "player", UNIT_SPELLCAST_SUCCEEDED = "player", UNIT_HEALTH = "target" }
function ns.On(event, fn)
    local list = evHandlers[event]
    if not list then
        list = {}
        evHandlers[event] = list
        -- unbekannte Events werfen in der Beta Fehler -> abfangen
        -- Zauber-Events nur fuer den eigenen Charakter anmelden (alle Oasis-Handler pruefen ohnehin unit == "player";
-- sonst kommen sie im Raid fuer jede Einheit, hunderte Male pro Sekunde) - Performance 0.5.482
        local ok
        if PLAYER_UNIT_EVENTS[event] and evFrame.RegisterUnitEvent then ok = pcall(evFrame.RegisterUnitEvent, evFrame, event, PLAYER_UNIT_EVENTS[event])
        else ok = pcall(evFrame.RegisterEvent, evFrame, event) end
        if not ok then ns.debug(L["Event nicht verfuegbar: "] .. event) end
    end
    list[#list + 1] = fn
    if not ns.handlerSrc then ns.handlerSrc = setmetatable({}, { __mode = "k" }) end
    ns.handlerSrc[fn] = ns.Caller and ns.Caller() or nil
end
-- Fehlerdiagnose (0.5.504): die letzten Ereignisse, die Oasis verarbeitet hat (Ringpuffer, kaum Kosten).
-- Wird WoW Oasis blockiert, steht im Fehlerbericht automatisch, welches Ereignis kurz davor lief.
local EV_N, evRingE, evRingT, evRingI = 24, {}, {}, 0
function ns.LastEvents(maxAge)
    local now, out, seen = GetTime(), {}, {}
    for k = 0, EV_N - 1 do
        local i = (evRingI - k - 1) % EV_N + 1
        local e, t = evRingE[i], evRingT[i]
        if not e or now - t > (maxAge or 3) then break end
        if not seen[e] and not e:find("^ADDON_ACTION") then
            seen[e] = true
            out[#out + 1] = ("%s (vor %.1fs)"):format(e, now - t)
            if #out >= 8 then break end
        end
    end
    return table.concat(out, ", ")
end
evFrame:SetScript("OnEvent", function(_, event, ...)
    -- vor dem Start (Spielername noch unbekannt) nur Laden/Login verarbeiten
    if not ns.loggedIn and event ~= "ADDON_LOADED" and event ~= "PLAYER_LOGIN" then return end
    local list = evHandlers[event]
    if not list then return end
    evRingI = evRingI % EV_N + 1
    evRingE[evRingI], evRingT[evRingI] = event, GetTime()
    if ns.prof then
        for i = 1, #list do
            local t0 = debugprofilestop()
            local ok, e = xpcall(list[i], errTrace, ...)
            ns.prof.add(list[i], event, debugprofilestop() - t0)
            if not ok then ns.err(event, e) end
        end
        return
    end
    for i = 1, #list do
        local ok, e = xpcall(list[i], errTrace, ...)
        if not ok then ns.err(event, e) end
    end
end)

local listeners = {}
function ns.Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end
function ns.Fire(msg, ...)
    local list = listeners[msg]
    if not list then return end
    for i = 1, #list do
        local ok, e = xpcall(list[i], errTrace, ...)
        if not ok then ns.err(msg, e) end
    end
end

-- Timer mit Fehlerschutz
-- Aufrufer-Zeile fuer die Leistungsmessung (WoW gibt Addons keine Quellzeile einer Funktion heraus)
local function caller()
    local st = debugstack and debugstack(3, 1, 0) or ""
    local f, l = st:match("([%w_]+[/\\][%w_]+%.lua)[\"%]]*:(%d+)")
    if not f then f, l = st:match("([%w_]+%.lua)[\"%]]*:(%d+)") end
    return f and (f:gsub("\\", "/") .. ":" .. l) or nil
end
ns.Caller = caller
local function timed(fn, what)
    if not ns.prof then return xpcall(fn, errTrace) end
    local t0 = debugprofilestop()
    local ok, e = xpcall(fn, errTrace)
    ns.prof.add(fn, what, debugprofilestop() - t0)
    return ok, e
end
function ns.After(sec, fn)
    local lbl = ns.prof and caller() or nil
    sec = tonumber(sec) or 0
    if sec ~= sec or sec < 0 then sec = 0 end   -- 0.5.660: C_Timer.After lehnt negative Zeiten ab (Fehlerbericht Comm GCREQ)
    C_Timer.After(sec, function()
        local ok, e = timed(fn, lbl and ("Timer " .. lbl) or "Timer")
        if not ok then ns.err("Timer", e) end
    end)
end
function ns.Every(sec, fn)
    local lbl = "Ticker " .. (caller() or "?")
    return C_Timer.NewTicker(sec, function()
        local ok, e = timed(fn, lbl)
        if not ok then ns.err("Ticker", e) end
    end)
end
-- Leistung messen (0.5.528): /oa leistung -> 60 s lang Rechenzeit je Oasis-Funktion (Ereignisse, Timer)
do
    local src = setmetatable({}, { __mode = "k" })
    local function where(fn)
        if not fn then return "?" end
        local w = src[fn]
        if w then return w end
        local info = debug and debug.getinfo and debug.getinfo(fn, "S")
        w = info and ((info.short_src or "?"):gsub("^.-AddOns[/\\]Oasis[/\\]", ""):gsub("^%[string \"", ""):gsub("\"%]$", "") .. ":" .. (info.linedefined or 0)) or "?"
        src[fn] = w
        return w
    end
    function ns.PerfStart(sec)
        sec = sec or 60
        local P = { t0 = debugprofilestop(), rows = {} }
        function P.add(fn, what, ms)
            local w = where(fn)
            if w == "?" and ns.handlerSrc and ns.handlerSrc[fn] then w = ns.handlerSrc[fn] end
            local k = (w ~= "?" and (w .. "  ") or "") .. tostring(what)
            local r = P.rows[k]
            if not r then r = { k = k, ms = 0, n = 0, max = 0 } P.rows[k] = r end
            r.ms, r.n = r.ms + ms, r.n + 1
            if ms > r.max then r.max = ms end
        end
        ns.prof = P
        -- 0.5.625: Bildzeiten mitzaehlen (Ruckler = Bild dauert laenger als 33 bzw. 50 ms)
        P.frames, P.h33, P.h50, P.maxEl, P.sumEl = 0, 0, 0, 0, 0
        P.fr = P.fr or CreateFrame("Frame")
        P.fr:SetScript("OnUpdate", function(_, el)
            if ns.prof ~= P then return end
            P.frames, P.sumEl = P.frames + 1, P.sumEl + el
            if el > 0.033 then P.h33 = P.h33 + 1 end
            if el > 0.05 then P.h50 = P.h50 + 1 end
            if el > P.maxEl then P.maxEl = el end
        end)
        local m0
        if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
            pcall(function() m0 = C_AddOnProfiler.GetAddOnMetric(ADDON, Enum.AddOnProfilerMetric.SessionAverageTime) end)
        end
        ns.print(("Leistung: messe %d Sekunden ... (einfach normal weiterspielen)"):format(sec))
        C_Timer.After(sec, function() ns.PerfStop(m0) end)
    end
    function ns.PerfStop()
        local P = ns.prof
        if not P then return end
        ns.prof = nil
        local dur = (debugprofilestop() - P.t0) / 1000
        local list, total = {}, 0
        for _, r in pairs(P.rows) do list[#list + 1] = r total = total + r.ms end
        table.sort(list, function(a, b) return a.ms > b.ms end)
        local out = { ("Oasis-Leistung: %.0f s gemessen, %.1f ms Rechenzeit in Ereignissen/Timern/Listen (%.2f ms pro Sekunde)"):format(dur, total, total / math.max(1, dur)) }
        if P.fr then P.fr:SetScript("OnUpdate", nil) end
        if (P.frames or 0) > 0 then
            out[#out + 1] = ("Bilder: %.0f FPS im Schnitt, Ruckler: %d Bilder ueber 33 ms, %d ueber 50 ms, laengstes %.0f ms"):format(
                P.frames / math.max(0.001, P.sumEl), P.h33, P.h50, P.maxEl * 1000)
        end
        if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
            local M = Enum.AddOnProfilerMetric
            local function m(k) local ok, v = pcall(C_AddOnProfiler.GetAddOnMetric, ADDON, M[k]) return ok and v or nil end
            local ra, pk = m("RecentAverageTime"), m("PeakTime")
            if ra or pk then out[#out + 1] = ("Blizzard-Messung (alles inkl. Fenster): zuletzt %.3f ms je Bild, Spitze %.1f ms"):format(ra or 0, pk or 0) end
        end
        for i = 1, math.min(15, #list) do
            local r = list[i]
            out[#out + 1] = ("%2d. %6.1f ms  %5dx  max %5.1f  %s"):format(i, r.ms, r.n, r.max, r.k)
        end
        ns.db.perfReport = { ts = ns.now(), v = ns.version, lines = out }
        for i = 1, math.min(8, #out) do ns.print(out[i]) end
        if ns.Bugs and ns.Bugs.ShowCopy then pcall(ns.Bugs.ShowCopy, table.concat(out, "\n")) end
    end
end
-- Mehrfach-Aufrufe buendeln: fn laeuft einmal, "sec" nach dem ersten Aufruf (Performance 0.5.482:
-- beim Login-Abgleich kommen hunderte Datensaetze, Zaehler/Seiten wurden vorher fuer jeden neu berechnet)
local debounced = {}
function ns.Debounce(key, sec, fn)
    if debounced[key] then return end
    -- 0.5.876: negative/ungueltige Zeiten abfangen. C_Timer.After wirft sonst einen Fehler - und weil der Merker
    -- dann schon gesetzt war, lief dieses Buendel bis zum naechsten /reload nie wieder.
    sec = tonumber(sec) or 0
    if sec ~= sec or sec < 0 then sec = 0 end
    debounced[key] = true
    C_Timer.After(sec, function()
        debounced[key] = nil
        local ok, e = timed(fn, "Buendel " .. tostring(key))
        if not ok then ns.err(key, e) end
    end)
end

------------------------------------------------------------------------
-- Datenbank
------------------------------------------------------------------------
local DEFAULT_SETTINGS = {
    shareMap = false,       -- 0.5.617 Datenschutz: Standard aus
    shareRep = false,
    wantAlarm = true,       -- Wunschliste-Alarm (Markt)
    xpFloat = true,         -- Oasis-XP als +XP im Bild
    priceAnswer = true,     -- 'pc [Item]' im Gildenchat beantworten
    shareTrade = false,     -- Handelsbilanz fuer die Rangliste teilen (freiwillig)
    mapNames = true,
    minimapDots = true,
    inactiveDays = 30,
    deathToasts = true,
    deathPins = true,
    mapInterval = 8,
    toasts = true,
    announceMilestones = false,
    minimap = true,
    minimapAngle = 215,
    scale = 1.0,
    lootMinQuality = 3,
    radarRange = 300,
    debug = false,
    -- Hinweise & Sound
    toastDur = 7,
    toastHoldCombat = false,
    sound = true,
    soundVol = 14,   -- 0.5.976: doppelt so laut wie bisher (70 %)
    soundQuietCombat = true,
    soundEvents = {},
    music = "off",
    musicTrack = "orc",
    -- Darstellung
    uiFont = "inter",     -- Standardschrift (0.5.379 User-Entscheidung)
    accent = "",          -- eigene Akzentfarbe (leer = wie die Gilde)
    headFont = "friz",
    logoAnim = true,
    chatEmoji = true,     -- Kurzcodes im Chat als Emoji anzeigen
    drSilent = true,      -- Deathroll unter Oasis-Nutzern leise wuerfeln (kein /roll im Chat)
    emojiButton = true,   -- Emoji-Knopf im Chat-Eingabefeld
    emojiHotkey = true,   -- Alt+Leertaste im Chat oeffnet die Emoji-Auswahl
    hiddenPages = {},
    lang = "auto",
}

-- 0.5.727: Einsteiger-Einstellungen - ruhig, wenige Seiten, nichts blinkt. Gilt fuer NEUE Installationen (leere Einstellungen)
-- und per /oa einsteiger fuer bestehende. Alles bleibt in den Einstellungen aenderbar; versteckte Seiten unter Bereiche.
local BEGINNER = {
    soundVol = 10, toastDur = 6, toastHoldCombat = true,
    dashStill = true, dashTicker = false, dashHero = false, hideMidasAd = true, calmStart = true,
    xpFloat = false, priceAnswer = false, announceMilestones = false, lfgAuto = false, greetOn = false,
}
local BEGINNER_HIDDEN = { "raidlead", "loot", "lootrules", "softres", "wipes", "tactics", "raidboard", "raidcheck", "lockouts",
    "buffs", "repplan", "gearmatch", "scout", "fight", "rares", "sammlung", "goals" }
function ns.ApplyBeginner(st)
    for k, v in pairs(BEGINNER) do st[k] = v end
    st.hiddenPages = st.hiddenPages or {}
    for _, k in ipairs(BEGINNER_HIDDEN) do st.hiddenPages[k] = true end
end

local function applyDefaults(t, d)
    for k, v in pairs(d) do
        if t[k] == nil then
            if type(v) == "table" then
                t[k] = {}
                applyDefaults(t[k], v)
            else
                t[k] = v
            end
        end
    end
end

local function initDB()
    OasisDB = OasisDB or {}
    local db = OasisDB
    db.settings = db.settings or {}
    local fresh = next(db.settings) == nil
    ns.DEFAULT_SETTINGS = DEFAULT_SETTINGS   -- fuer "Seite zuruecksetzen" in den Einstellungen
    applyDefaults(db.settings, DEFAULT_SETTINGS)
    -- 0.5.740: Quests teilen soll einfach gehen - einmalig das Ablehnen geteilter Quests ausschalten (Standard war nie an; wer es bewusst wieder
    -- einschaltet, behaelt es). Gruppe, Schlachtzug und Gilde werden ohnehin nie abgelehnt.
    if db.settings.shareQuest740 == nil then
        db.settings.shareQuest740 = true
        db.settings.cfBlockShared = nil
    end
    -- 0.5.976: Oasis-Sounds generell doppelt so laut. Bestehende Installationen: gespeicherte Lautstaerke (und die des
    -- Online-Sounds) einmalig verdoppeln, hoechstens bis 200 % (Stufe 40). Neue Installationen haben schon den neuen Standard.
    if db.settings.soundVolDoubled == nil then
        db.settings.soundVolDoubled = true
        if not fresh then
            for _, k in ipairs({ "soundVol", "soundEntranceVol" }) do
                local v = tonumber(db.settings[k])
                if v and v > 0 then db.settings[k] = math.min(40, math.floor(v * 2)) end
            end
        end
    end
    if db.settings.beginner727 == nil then
        db.settings.beginner727 = true
        if fresh then ns.ApplyBeginner(db.settings) end   -- nur neue Installationen; bestehende behalten ihre Wahl
    end
    -- 0.5.346: neues Standard-Design "Glas 2026" + Schrift Inter (einmalig; wer bewusst etwas anderes gewaehlt hat, behaelt es)
    local st = db.settings
    if not st.glass26 then
        st.glass26 = true
        if st.theme == nil or st.theme == "standard" or st.theme == "modern" or st.theme == "classic" then st.theme = "glass" end   -- 0.6.265: Klassisch, Modern, WoW Classic entfernt
        if st.uiFont == nil or st.uiFont == "arialn" then st.uiFont = "inter" end
    end
    -- 0.5.379: Standardschrift Inter; Arial-Narrow-Rueckstellung von 0.5.378 zuruecknehmen
    if not st.inter379 then
        st.inter379 = true
        if st.uiFont == nil or st.uiFont == "arialn" then st.uiFont = "inter" end
    end
    db.members = db.members or {}      -- Profile der Mitglieder (per Addon geteilt)
    db.recipes = db.recipes or {}      -- [name] = { hash, u, profs = { [prof] = { [id] = name } } }
    db.legacy = db.legacy or {}        -- [name] = { hash, u, done = { [id] = true } }
    db.store = db.store or {}          -- replizierte Sammlungen (Auftraege, Termine, Chronik ...)
    db.chars = db.chars or {}
    db.meta = db.meta or { lastSync = 0 }
    ns.db = db
    local me = ns.me()
    if me then
        db.chars[me] = db.chars[me] or {}
        local c = db.chars[me]
        c.milestones = c.milestones or {}
        c.recipes = c.recipes or {}
        ns.char = c
    end
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    initDB()
    -- persoenliche Sprache und Schriften vor dem Aufbau der Oberflaeche
    local s = ns.db.settings
    if s.lang and ns.langByKey[s.lang] then ns.lang = s.lang end
    if ns.PrepareLang then pcall(ns.PrepareLang) end
    -- 0.5.568: eingeschaltete Module (Zusatz-Addons) laden - vor DB_READY/LOGIN, damit sie alles mitbekommen
    if ns.ModuleLoader then pcall(ns.ModuleLoader.LoadAll) end
    if ns.K then ns.K.ApplyUserFonts() end
    ns.Fire("DB_READY")
end)
-- nach dem ersten Ladebildschirm: Oasis-Texte neu mit ihrer Schrift belegen (siehe K.RefreshFonts in Kit.lua)
do
    local done = false
    ns.On("PLAYER_ENTERING_WORLD", function()
        if done or not (ns.K and ns.K.RefreshFonts) then return end
        done = true
        ns.After(1, function() pcall(ns.K.RefreshFonts) end)
        -- zweiter Durchgang, falls eine Schrift erst spaet fertig war; danach Vorlade-Texte weg
        ns.After(5, function()
            pcall(ns.K.RefreshFonts)
            if ns.K.preloadFrame then ns.K.preloadFrame:Hide() end
        end)
        -- 0.5.770: beim ersten Login des Tages (kalter Schrift-Cache) laedt WoW Schriftdateien oft erst nach Sekunden -> zwei spaete Durchgaenge
        for _, d in ipairs({ 12, 30 }) do
            ns.After(d, function() pcall(ns.K.RefreshFonts) end)
        end
    end)
end

-- Start erst, wenn WoW den Spielernamen kennt (sonst entstuenden Eintraege wie "Unbekannt")
local function start()
    if ns.loggedIn then return true end
    if not ns.me() then return false end
    if not ns.char then initDB() end
    if not ns.char then return false end
    for _, t in ipairs({ ns.db.chars, ns.db.recipes, ns.db.members, ns.db.legacy }) do
        for name in pairs(t) do
            if not validName(ns.short(name)) then t[name] = nil end
        end
    end
    ns.loggedIn = true
    ns.Fire("LOGIN")
    ns.print((L["v%s geladen - |cffffffff/oasis|r oeffnet die Zentrale."]):format("|cffffc98a" .. ns.version .. "|r"))
    return true
end
ns.On("PLAYER_LOGIN", function()
    if start() then return end
    local tries = 0
    local ticker
    ticker = C_Timer.NewTicker(0.5, function()
        tries = tries + 1
        if start() or tries > 120 then ticker:Cancel() end
    end)
end)

------------------------------------------------------------------------
-- Slash-Befehle
------------------------------------------------------------------------
ns.slash = {}
ns.slash.einsteiger = function()
    if not ns.db then return end
    ns.ApplyBeginner(ns.db.settings)
    ns.print(ns.L["Einsteiger-Einstellungen gesetzt: ruhigere Hinweise, weniger Seiten. Seiten wieder einblenden unter Einstellungen > Bereiche. Bitte /reload."])
end
ns.slash.leistung = function(a) if ns.prof then ns.PerfStop() else ns.PerfStart(tonumber(a) or 60) end end
ns.slash.perf = ns.slash.leistung
ns.slash.freischalten = function(arg)
    arg = tostring(arg or ""):lower()
    local on = ns.db.settings.unlockAll == true
    if arg == "an" or arg == "on" then on = true elseif arg == "aus" or arg == "off" then on = false else on = not on end
    ns.db.settings.unlockAll = on or nil
    ns.print(on and "Alle Sounds und Emojis sind bei dir freigeschaltet (nur lokal)." or "Rang-Sperren wieder aktiv.")
    ns.RefreshPage("settings")
end
SLASH_OASIS1 = "/oasis"
SLASH_OASIS2 = "/oa"
SlashCmdList.OASIS = function(msg)
    msg = msg or ""
    local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()
    if not ns.loggedIn then
        ns.print(L["Oasis laedt noch - gleich nochmal versuchen."])
        return
    end
    if cmd == "" then
        ns.Fire("TOGGLE_MAIN")
        return
    end
    local fn = ns.slash[cmd]
    ns.Trace("/oa " .. cmd)
    if fn then
        fn(rest)
    else
        ns.print(L["Befehle: /oa, /oa vergabe <Itemlink>, /oa lagerfeuer [Notiz], /oa sync, /oa debug"])
    end
end
ns.slash.debug = function()
    ns.db.settings.debug = not ns.db.settings.debug
    ns.print(L["Debug: "] .. (ns.db.settings.debug and "an" or "aus"))
end


-- WoW-Systemtext ("%s ist jetzt online.", auch "%1$s") -> Lua-Suchmuster mit Fang je Platzhalter
function ns.GlobalPattern(gs, anchor)
    if type(gs) ~= "string" then return nil end
    gs = gs:gsub("%%(%d)%$", "%%")                                   -- nummerierte Platzhalter entfernen
    local p = gs:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")         -- Sonderzeichen (auch %) schuetzen
    p = p:gsub("%%%%s", "(.-)"):gsub("%%%%d", "(%%d+)")
    if anchor then p = "^" .. p .. "$" end
    local ok = pcall(string.match, "", p)
    return ok and p or nil
end

-- Esc schliesst Oasis-Fenster, OHNE Blizzards Liste UISpecialFrames (die "beruehrt" sonst den Esc-Weg
-- und WoW blockiert danach Zauber-Abbruch und Kamera-Drehen). Eigener Tastenfaenger nur solange etwas offen ist.
do
    local list, stack = {}, {}
    -- 0.5.413: kein Tastenfaenger mehr (Weiterreichen aus Addon-Code sperrte SpellStopCasting/SpellStopTargeting).
    -- Stattdessen: solange ein Oasis-Fenster offen ist (und kein Kampf), liegt ESC per Override auf einem
    -- eigenen Knopf -> Blizzards ESC-Aktion laeuft dann gar nicht, nichts wird "beruehrt".
    local escBtn = CreateFrame("Button", "OasisEscCloseButton", UIParent)
    local bound = false
    local focusOf = setmetatable({}, { __mode = "k" })
    local closeOf = setmetatable({}, { __mode = "k" })
    local function topmost()
        for i = #stack, 1, -1 do
            local f = stack[i]
            if f and f:IsVisible() then
                -- offen, aber ohne Fokus (Hauptfenster, Klick ging in die Welt): Esc gehoert dem Spiel, bleibt im Stapel
                if not (focusOf[f] and not focusOf[f]()) then return f end
            else
                table.remove(stack, i)
            end
        end
    end
    -- liegt Esc wirklich auf unserem Knopf? (0.5.598: nicht nur dem Merker trauen - nach dem ersten Schliessen
    -- war Esc beim zweiten Oeffnen nicht mehr belegt, obwohl der Merker es glaubte)
    local ACTION = "CLICK OasisEscCloseButton:LeftButton"
    local function reallyBound()
        if not GetBindingAction then return bound end
        local ok, a = pcall(GetBindingAction, "ESCAPE", true)
        if not ok then return bound end
        return a == ACTION
    end
    local function update()
        if InCombatLockdown() or not SetOverrideBindingClick then return end
        local want = topmost() ~= nil
        if want and (not bound or not reallyBound()) then
            ClearOverrideBindings(escBtn)
            SetOverrideBindingClick(escBtn, true, "ESCAPE", "OasisEscCloseButton")
            bound = true
        elseif not want and bound then
            ClearOverrideBindings(escBtn)
            bound = false
        end
    end
    -- Selbstheilung: solange etwas offen ist, alle 0,3 s nachsehen (sehr billig: nur bei offenem Fenster aktiv)
    local guard = CreateFrame("Frame")
    guard:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        if self.t < 0.3 then return end
        self.t = 0
        if #stack == 0 and not bound then return end
        update()
    end)
    -- 0.5.596: NUR beim Loslassen reagieren. 0.5.594 reagierte schon beim Druecken -> Oasis zu, Belegung frei,
    -- und das Loslassen derselben Taste oeffnete danach Blizzards Spielmenue.
    escBtn:RegisterForClicks("AnyUp")
    local lastEsc = 0
    escBtn:SetScript("OnClick", function()
        local now = GetTime()
        if now - lastEsc < 0.25 then return end
        lastEsc = now
        local f = topmost()
        -- 0.5.605: eigener Schliess-Weg (z. B. Hauptfenster: wie der X-Knopf, mit Flug-Animation)
        if f then
            if closeOf[f] then
                local ok = pcall(closeOf[f])
                if not ok then f:Hide() end
            else
                f:Hide()
            end
        end
        update()
    end)
    -- vor dem Kampf freigeben (im Kampf darf die Belegung nicht mehr geaendert werden), danach wieder setzen
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_REGEN_DISABLED")
    ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    ev:SetScript("OnEvent", function(_, e)
        if e == "PLAYER_REGEN_DISABLED" then
            if bound and ClearOverrideBindings then ClearOverrideBindings(escBtn) bound = false end
        else
            update()
        end
    end)
    ns.EscUpdate = function() update() end
    -- Diagnose: /oa esc -> welche Fenster liegen im Esc-Stapel, ist Esc gerade belegt?
    function ns.EscDebug()
        local out = {}
        for i, f in ipairs(stack) do
            out[#out + 1] = i .. ": " .. tostring(f.GetName and f:GetName() or "?") .. (f:IsShown() and " shown" or "") .. (f:IsVisible() and " visible" or "")
                .. (" alpha=%.2f"):format(f:GetEffectiveAlpha() or 1) .. ((focusOf[f] and not focusOf[f]()) and " (ohne Fokus)" or "")
        end
        local top = topmost()
        return out, bound, top and (top:GetName() or tostring(top)) or nil
    end
    ns.slash.esc = function()
        local out, b, top = ns.EscDebug()
        ns.print("Esc belegt: " .. tostring(b) .. "  oberstes: " .. tostring(top))
        for _, l in ipairs(out) do ns.print("  " .. l) end
    end
    function ns.EscClose(name, focusFn, closeFn)
        local f = type(name) == "string" and _G[name] or name
        if not f or list[f] then return end
        list[f] = true
        focusOf[f] = focusFn
        closeOf[f] = closeFn
        f:HookScript("OnShow", function(self)
            for i = #stack, 1, -1 do if stack[i] == self then table.remove(stack, i) end end
            stack[#stack + 1] = self
            update()
        end)
        f:HookScript("OnHide", function() update() end)
        -- Klick-Toene: nur eigene Oasis-Fenster (Name mit "Oasis" oder ohne Namen)
        local fname = f.GetName and f:GetName()
        if not fname or fname:find("^Oasis") then
            f:HookScript("OnShow", function(self)
                if C_Timer and ns.K and ns.K.SoundifyTree then C_Timer.After(0.4, function() ns.K.SoundifyTree(self) end) end
            end)
        end
        if f:IsShown() then stack[#stack + 1] = f update() end
    end
end

-- Spieler in die Gruppe einladen (mit Rueckmeldung; volle Gruppe -> Schlachtzug)
function ns.InviteName(name)
    if not name then return false end
    local n = ns.ChatName(name)
    if GetNumGroupMembers and GetNumGroupMembers() >= 5 and not IsInRaid() and C_PartyInfo and C_PartyInfo.ConvertToRaid then
        pcall(C_PartyInfo.ConvertToRaid)
    end
    local ok
    if C_PartyInfo and C_PartyInfo.InviteUnit then ok = pcall(C_PartyInfo.InviteUnit, n) end
    if not ok and InviteUnit then ok = pcall(InviteUnit, n) end
    if not ok and n ~= ns.short(name) and C_PartyInfo and C_PartyInfo.InviteUnit then ok = pcall(C_PartyInfo.InviteUnit, ns.short(name)) end
    ns.print(ok and (L["Einladung an %s geschickt."]):format(ns.short(name)) or (L["Einladen von %s hat nicht geklappt."]):format(ns.short(name)))
    return ok
end

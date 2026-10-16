-- Oasis: Discord-Bruecke (Spielseite)
-- Die eigentliche Bruecke ist OasisSync.exe (Tools\OasisSync.cs, Doku Tools\OasisSync-Format.md, Abschnitt Discord):
--   * Spiel -> Discord: OasisSync liest Logs\WoWChatLog.txt (WoW schreibt sie nur bei aktivem /chatlog) und postet
--     Gildenzeilen per Webhook. Diese Datei kann das Chatlog beim Login automatisch einschalten (Einstellung).
--   * Discord -> Spiel: OasisSync legt Discord-Nachrichten als OasisImport.collections.discord in Oasis\Import.lua.
--     WoW liest die Datei nur beim Login / /reload -> Discord-Nachrichten erscheinen erst danach im Oasis-Gildenchat.
-- Discord-Nachrichten werden NUR angezeigt: nicht in den echten WoW-Chat gesendet und nicht an andere Oasis-Nutzer
-- weitergegeben (GuildChat schickt Eintraege mit src="discord" beim Nachladen verpasster Nachrichten nicht mit).
-- Grund: Wer die Bruecke betreibt, liefert die Nachrichten ohnehin selbst; Weitergabe wuerde mit mehreren
-- Betreibern doppeln, und fremde Discord-Namen sollen nicht als "Gildenchat" an die ganze Gilde wandern.
--
-- Schalter im Chat-Bereich der Einstellungen: ns.AppendPageSettings (Settings.lua), Ladereihenfolge egal.
local ADDON, ns = ...
ns.ModuleFile("Oasis_Discord", function()   -- Modul Discord (abschaltbar, siehe ModuleLoader.lua)
local L = ns.L

local DB = {}
ns.DiscordBridge = DB

local KEEP_DAYS = 30
local function S() return (ns.db and ns.db.settings) or {} end

------------------------------------------------------------------------
-- Chatlog automatisch einschalten (Standard: aus)
------------------------------------------------------------------------
function DB.ChatlogAvailable() return type(LoggingChat) == "function" end

function DB.EnableChatlog(force)
    if not force and S().dcChatlog ~= true then return false end
    if not DB.ChatlogAvailable() then return false end
    local ok, on = pcall(LoggingChat)
    if ok and on then return true end
    local ok2 = pcall(LoggingChat, true)
    if ok2 then ns.print(L["Chatlog eingeschaltet - OasisSync kann den Gildenchat an Discord geben."]) end
    return ok2
end

------------------------------------------------------------------------
-- Discord-Nachrichten aus Import.lua im Oasis-Gildenchat zeigen
------------------------------------------------------------------------
local function prune(seen)
    local cut = (ns.now() - KEEP_DAYS * 86400)
    for id, ts in pairs(seen) do if (tonumber(ts) or 0) < cut then seen[id] = nil end end
end

local function sanitize(s, max)
    s = tostring(s or "")
    s = s:gsub("[%z\1-\9\11-\31]", ""):gsub("|", "||")   -- keine WoW-Steuercodes (Farben, Links, Texturen) aus Discord
    if #s > max then s = s:sub(1, max) end
    return s
end

function DB.ShowImported()
    if S().dcShow == false or not ns.db then return 0 end
    local GC = ns.GuildChat
    local data = _G.OasisImport
    local list = type(data) == "table" and type(data.collections) == "table" and data.collections.discord
    if not GC or not GC.Add or type(list) ~= "table" then return 0 end
    ns.db.dcSeen = ns.db.dcSeen or {}
    local seen = ns.db.dcSeen
    prune(seen)
    local cut, n = ns.now() - KEEP_DAYS * 86400, 0
    GC.bulk = true
    for _, r in ipairs(list) do
        local id = type(r) == "table" and r.id
        local ts = type(r) == "table" and tonumber(r.ts)
        if type(id) == "string" and id ~= "" and not seen[id] and ts and ts > cut and type(r.text) == "string" and r.text ~= "" then
            seen[id] = ts
            local author = sanitize(r.author, 40):gsub("^%s+", ""):gsub("%s+$", "")
            if author == "" then author = "Discord" end
            local ok, added = pcall(GC.Add, { ts = ts, s = author, m = sanitize(r.text, 1000), dc = true, src = "discord", cid = "dc" .. id }, true)
            if ok and added then n = n + 1 end
        end
    end
    GC.bulk = nil
    if n > 0 then
        ns.RefreshPage("chat")
        ns.debug("Discord-Nachrichten uebernommen:", n)
    end
    return n
end

ns.Listen("LOGIN", function()
    ns.After(3, function() pcall(DB.EnableChatlog) end)
    -- nach GuildChat (prune/cleanLog beim Login) und Import.Run (8 s)
    ns.After(10, function() pcall(DB.ShowImported) end)
end)
ns.slash.discord = function()
    local n = DB.ShowImported()
    ns.print((L["Discord-Nachrichten uebernommen: %d (neue erscheinen erst nach /reload)"]):format(n or 0))
end

------------------------------------------------------------------------
-- Einstellungen im Bereich "Chat"
------------------------------------------------------------------------
function DB.BuildSettings(det, y)
    local K = ns.K
    if not K or not K.Toggle then return y end
    if not (ns.ExternTools and ns.ExternTools()) then return y end   -- braucht OasisSync: oeffentlich vorerst nicht angeboten
    y = y - 6
    local t1 = K.Toggle(det, L["Discord-Nachrichten im Gildenchat zeigen (ueber OasisSync, nach /reload)"],
        function() return S().dcShow ~= false end,
        function(v) S().dcShow = v and true or false if v then pcall(DB.ShowImported) end end)
    t1:SetPoint("TOPLEFT", 14, y)
    t1:SetWidth(600)
    det.t[#det.t + 1] = t1
    y = y - 32
    if DB.ChatlogAvailable() then
        local t2 = K.Toggle(det, L["Chatlog beim Login einschalten (Gildenchat -> Discord ueber OasisSync)"],
            function() return S().dcChatlog == true end,
            function(v) S().dcChatlog = v and true or nil if v then pcall(DB.EnableChatlog, true) end end)
        t2:SetPoint("TOPLEFT", 14, y)
        t2:SetWidth(600)
        det.t[#det.t + 1] = t2
        y = y - 32
    end
    return y
end

-- 0.6.289: Discord-Schalter an den Chat-Bereich der Einstellungen anhaengen (Modul laeuft nach Settings.lua)
if ns.AppendPageSettings then ns.AppendPageSettings("chat", function(det, y) return DB.BuildSettings(det, y) end) end
end)

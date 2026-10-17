-- Oasis - Sounds und Musik
-- Eigene Sounds (Media\sounds\<name>\<1-10>.ogg) liegen in 10 Lautstaerkestufen vor, weil WoW
-- Addon-Sounds nicht leiser abspielen kann -> der Oasis-Regler ist unabhaengig vom Spiel.
-- WoW-Sounds (SOUNDKIT) folgen dagegen der Spiel-Lautstaerke.
local ADDON, ns = ...
local L = ns.L

local Sound = {}
ns.Sound = Sound

-- Auswahl: key, Anzeigename, eigene Datei (own) oder WoW-Soundkit (kit + Ersatz-ID)
Sound.CHOICES = {
    { key = "none", text = "Kein Sound" },
    -- neu (06.10.): ohne Rang-Sperre, im Fenster blau als NEU markiert
    -- Oberflaeche: spielt den Ton aus dem gewaehlten UI-Soundpaket (Sound.UI_PACKS)
    { key = "ui_open", text = "Oasis: Fenster auf", own = true, ui = "open", dur = 0.3 },
    { key = "ui_close", text = "Oasis: Fenster zu", own = true, ui = "close", dur = 0.3 },
    { key = "ui_click", text = "Oasis: Klick", own = true, ui = "click", dur = 0.1 },
    { key = "ui_select", text = "Oasis: Auswahl", own = true, ui = "select", dur = 0.1 },
    { key = "ui_toggle", text = "Oasis: Schalter", own = true, ui = "toggle", dur = 0.2 },
    { key = "ui_confirm", text = "Oasis: Bestaetigen", own = true, ui = "confirm", dur = 0.3 },
    { key = "ui_notify", text = "Oasis: Hinweis (Soundpaket)", own = true, ui = "notify", dur = 1.5 },
    -- Clear UI (Ni Sound): Hinweistoene
    { key = "wow_raidwarn", text = "WoW: Raid-Warnung", kit = "RAID_WARNING", id = 8959 },
    { key = "wow_ready", text = "WoW: Bereitschaftscheck", kit = "READY_CHECK", id = 8960 },
    { key = "wow_levelup", text = "WoW: Stufenaufstieg", kit = "LEVELUP", id = 888 },
    { key = "wow_quest", text = "WoW: Quest abgeschlossen", kit = "IG_QUEST_LIST_COMPLETE", id = 878 },
    { key = "wow_whisper", text = "WoW: Fluestern", kit = "TELL_MESSAGE", id = 3081 },
    { key = "wow_invite", text = "WoW: Einladung", kit = "IG_PLAYER_INVITE", id = 880 },
    { key = "wow_toast", text = "WoW: Battle.net-Hinweis", kit = "UI_BNET_TOAST", id = 18019 },
    { key = "wow_auction", text = "WoW: Auktionshaus", kit = "AUCTION_WINDOW_OPEN", id = 5274 },
    { key = "wow_mission", text = "WoW: Erfolg (Mission)", kit = "UI_GARRISON_MISSION_COMPLETE_MISSION_SUCCESS", id = 44294 },
    { key = "wow_open", text = "WoW: Fenster auf", kit = "IG_CHARACTER_INFO_OPEN", id = 839 },
    { key = "wow_close", text = "WoW: Fenster zu", kit = "IG_CHARACTER_INFO_CLOSE", id = 840 },
    { key = "wow_click", text = "WoW: Klick", kit = "IG_MAINMENU_OPTION_CHECKBOX_ON", id = 856 },
}
-- 0.5.716: Toene der UI-Soundpakete einzeln waehlbar (Reiter "Soundpaket"): key = Ordner <kuerzel>_<rolle>
do
    local PK = { { "ke", "Kenney" } }   -- Artlist-Pakete (Klar, Smartphone, Casual, Building, Slick) liegen im Gildenmodul
    local RL = { { "click", "Klick", 0.1 }, { "select", "Auswahl", 0.1 }, { "toggle", "Schalter", 0.2 },
        { "confirm", "Bestaetigen", 0.3 }, { "open", "Fenster auf", 0.3 }, { "close", "Fenster zu", 0.3 }, { "notify", "Hinweis", 1.5 } }
    for _, p in ipairs(PK) do
        do
            for _, r in ipairs(RL) do
                if not (p[1] == "ke" and r[1] == "notify") then   -- Kenney hat keinen eigenen Hinweis-Ton
                    Sound.CHOICES[#Sound.CHOICES + 1] = { key = p[1] .. "_" .. r[1], text = p[2] .. ": " .. r[2], own = true,
                        dur = r[3], free = true, pack = true }
                end
            end
        end
    end
end
Sound.byKey = {}
for _, c in ipairs(Sound.CHOICES) do Sound.byKey[c.key] = c end

-- Ereignisse mit Standard-Sound, in der Reihenfolge der Einstellungen
Sound.EVENTS = {
    { key = "entrance", text = "Dein Online-Sound (hoeren alle mit Oasis)", def = "none" },
    { key = "toast", text = "Allgemeine Hinweise", def = "ui_notify" },
    { key = "announce", text = "Durchsage der Gildenleitung", def = "bahn" },
    { key = "alert", text = "Wichtige Durchsage", def = "alarm" },
    { key = "request", text = "Anfrage an deine Gruppe", def = "huh" },
    { key = "group", text = "Neue Gruppensuche in der Gilde", def = "ni_ton" },
    { key = "order", text = "Handwerks-Auftrag an dich", def = "muenze" },
    { key = "wants", text = "Gesucht / Angebote", def = "muenze" },
    { key = "event", text = "Neuer Termin", def = "trommel" },
    { key = "loot", text = "Beute-Vergabe im Raid", def = "wow_raidwarn" },
    { key = "poll", text = "Neue Umfrage", def = "ni_glockenspiel" },
    { key = "rankup", text = "Oasis-Rangaufstieg", def = "fanfare" },
    { key = "levelup", text = "Charakter-Stufenaufstieg", def = "erfolg" },
    { key = "badge", text = "Abzeichen erhalten", def = "animewow" },
    { key = "welcome", text = "Neues Gildenmitglied", def = "rizz" },
    { key = "birthday", text = "Geburtstag", def = "french" },
    { key = "death", text = "Tod eines Mitglieds", def = "funeralbell" },
    { key = "chronicle", text = "Chronik (Level, Beute, Boss)", def = "none" },
    { key = "camp", text = "Lagerfeuer", def = "ni_sanft" },
    { key = "dr_invite", text = "Deathroll: Herausforderung", def = "run" },
    { key = "dr_turn", text = "Deathroll: du bist dran", def = "wuerfel" },
    { key = "dr_win", text = "Deathroll: gewonnen", def = "drwinner" },
    { key = "dr_lose", text = "Deathroll: verloren", def = "drloser" },
    { key = "open", text = "Oasis-Fenster oeffnen", def = "ui_open" },
    { key = "close", text = "Oasis-Fenster schliessen", def = "ui_close" },
}
Sound.eventByKey = {}
for _, e in ipairs(Sound.EVENTS) do Sound.eventByKey[e.key] = e end

-- Musik (WoW-Datei-IDs aus dem Spielclient), laeuft solange das Oasis-Fenster offen ist
Sound.MUSIC = {
    { key = "orc", text = "Orc-Rastplatz", id = 53756 },
    { key = "tauren", text = "Tauren-Rastplatz", id = 53768 },
    { key = "hordetavern", text = "Horde-Taverne", id = 53744 },
    { key = "undead", text = "Untoten-Taverne", id = 53774 },
    { key = "orgrimmar", text = "Orgrimmar", id = 53198 },
    { key = "thunderbluff", text = "Donnerfels", id = 53213 },
    { key = "pirate", text = "Piraten-Taverne", id = 53762 },
    { key = "dwarf", text = "Zwergen-Taverne", id = 53739 },
    { key = "human", text = "Menschen-Taverne", id = 53748 },
    { key = "theme", text = "WoW-Titelmusik", id = 53223 },
}
Sound.musicByKey = {}
for _, m in ipairs(Sound.MUSIC) do Sound.musicByKey[m.key] = m end

local function S() return ns.db and ns.db.settings end

function Sound.ChoiceFor(event)
    local s = S()
    local c = s and s.soundEvents and s.soundEvents[event]
    -- Entwickler-Sounds (dev) zaehlen nur beim Entwickler als Wahl
    if c and Sound.byKey[c] and (not Sound.byKey[c].dev or ns.IsDev()) then return c end
    local e = Sound.eventByKey[event]
    local d = e and e.def
    if d and not Sound.byKey[d] then d = "ui_notify" end   -- Standard-Sound nur im Gildenmodul -> Soundpaket-Ton
    return d or "glocke"
end
-- weitere Sounds je Ereignis (es wird zufaellig einer gespielt); 0.5.646: keine langen Standard-Extras mehr
local DEFAULT_EXTRA = {}
function Sound.ExtrasFor(event)
    local s = S()
    local x = s and s.soundExtra and s.soundExtra[event]
    if x == nil then x = DEFAULT_EXTRA[event] or {} end
    local out = {}
    for _, k in ipairs(x) do if Sound.byKey[k] then out[#out + 1] = k end end
    return out
end
function Sound.AddExtra(event, key)
    local s = S()
    s.soundExtra = s.soundExtra or {}
    local cur = Sound.ExtrasFor(event)
    for _, k in ipairs(cur) do if k == key then return end end
    if key == Sound.ChoiceFor(event) then return end
    cur[#cur + 1] = key
    s.soundExtra[event] = cur
end
function Sound.ClearExtras(event)
    local s = S()
    s.soundExtra = s.soundExtra or {}
    s.soundExtra[event] = {}
end
function Sound.PickFor(event)
    local pool = { Sound.ChoiceFor(event) }
    for _, k in ipairs(Sound.ExtrasFor(event)) do pool[#pool + 1] = k end
    return pool[math.random(#pool)]
end
-- Vorlagen fuer "Sounds fuer Hinweise": setzt alle Ereignisse auf einmal (map: Ereignis -> Sound, fehlt = Standard)
-- "paket" nutzt die ui_*-Toene und klingt daher immer nach dem gewaehlten Soundpaket
local PAKET = { toast = "ui_notify", announce = "ui_notify", alert = "ui_notify", request = "ui_select", group = "ui_notify",
    order = "ui_confirm", wants = "ui_confirm", event = "ui_notify", loot = "ui_notify", poll = "ui_notify",
    rankup = "ui_confirm", levelup = "ui_confirm", badge = "ui_confirm", welcome = "ui_confirm", birthday = "ui_confirm",
    death = "ui_notify", chronicle = "none", camp = "ui_select", dr_invite = "ui_notify", dr_turn = "ui_select",
    dr_win = "ui_confirm", dr_lose = "ui_close" }
Sound.PRESETS = {
    { key = "default", text = "Oasis-Standard", map = {} },
    { key = "paket", text = "Aus dem Soundpaket (ruhig)", map = PAKET },
    { key = "wow", text = "WoW-Klassiker", map = { toast = "wow_toast", announce = "wow_raidwarn", alert = "wow_raidwarn",
        request = "wow_invite", group = "wow_whisper", order = "wow_auction", wants = "wow_auction", loot = "wow_ready",
        rankup = "wow_mission", levelup = "wow_levelup", badge = "wow_quest", welcome = "wow_invite", dr_invite = "wow_invite",
        dr_turn = "wow_click", dr_win = "wow_mission" } },
}
function Sound.ApplyPreset(key)
    local s = S()
    if not s then return end
    local pr
    for _, p in ipairs(Sound.PRESETS) do if p.key == key then pr = p end end
    if not pr then return end
    s.soundEvents = {}
    for ev, k in pairs(pr.map) do
        if Sound.byKey[k] and Sound.eventByKey[ev] then s.soundEvents[ev] = k end
    end
end
function Sound.SetChoice(event, key)
    local s = S()
    s.soundEvents = s.soundEvents or {}
    local e = Sound.eventByKey[event]
    s.soundEvents[event] = (e and e.def == key) and nil or key
end

-- UI-Soundpakete: Klick, Auswahl, Schalter, Bestaetigen, Fenster auf/zu
-- Dateien: Media\sounds\<prefix><rolle>\<1-10>.ogg; WoW-Paket nutzt Soundkits
Sound.UI_PACKS = {
    { key = "kenney", text = "Kenney", prefix = "ke_", alias = { notify = "confirm" } },
    { key = "wow", text = "WoW", map = { click = "wow_click", select = "wow_click", toggle = "wow_click",
        confirm = "wow_click", open = "wow_open", close = "wow_close", notify = "wow_toast" } },
    { key = "none", text = "Aus" },
}
Sound.uiPackByKey = {}
for _, p in ipairs(Sound.UI_PACKS) do Sound.uiPackByKey[p.key] = p end
function Sound.UiPack()
    local s = S()
    if s and s.uiSounds == false then return "none" end
    local k = s and s.uiPack
    return Sound.uiPackByKey[k] and k or (Sound.uiPackByKey.clear and "clear" or "kenney")
end
function Sound.SetUiPack(k)
    local s = S()
    if not s then return end
    s.uiSounds = k ~= "none"
    if k ~= "none" then s.uiPack = k end
end
-- liefert Datei-Ordner (eigener Sound) bzw. WoW-Choice-Key fuer eine Rolle, nil = Paket aus
-- Rollen der Klick-Toene (Reihenfolge fuer das Zuweisen-Fenster)
Sound.UI_ROLES = { { "click", "Klick" }, { "select", "Auswahl" }, { "toggle", "Schalter" },
    { "confirm", "Bestaetigen" }, { "open", "Fenster auf" }, { "close", "Fenster zu" }, { "notify", "Hinweis" } }
-- eigene Zuweisung je Rolle: settings.uiRole[rolle] = Paket-Key oder "none" (stumm); nil = wie das Paket
function Sound.UiRoleChoice(role)
    local s = S()
    local o = s and s.uiRole and s.uiRole[role]
    if o == "none" or Sound.uiPackByKey[o] then return o end
end
function Sound.SetUiRole(role, packKey)
    local s = S()
    if not s then return end
    s.uiRole = s.uiRole or {}
    s.uiRole[role] = packKey
end
function Sound.UiKey(role, pack)
    local p = Sound.uiPackByKey[pack or Sound.UiPack()]
    if not pack and Sound.UiPack() ~= "none" then
        local o = Sound.UiRoleChoice(role)
        if o == "none" then return nil end
        if o then p = Sound.uiPackByKey[o] end
    end
    if not p or p.key == "none" then
        -- Fenster auf/zu als Ereignis-Sound bleibt hoerbar, auch wenn Klicks aus sind
        if role == "open" or role == "close" or role == "notify" then p = Sound.uiPackByKey[(S() and S().uiPack) or "clear"] or Sound.uiPackByKey.clear or Sound.uiPackByKey.kenney end
        if not p or p.key == "none" then return nil end
    end
    if p.map then return p.map[role] end
    return p.prefix .. ((p.alias and p.alias[role]) or role)
end

-- Lautstaerke-Skala (0.5.799): gespeichert wird in Stufen zu 5 %, 20 = 100 % (das waren vorher "200 %"), 40 = 200 %.
-- Gespeicherte Werte bleiben gueltig und klingen wie bisher - nur die Anzeige und der Hoechstwert haben sich geaendert.
Sound.VOL_MAX = 40
function Sound.VolText(v)
    return (L["%d%%"]):format((tonumber(v) or 0) * 5)
end
-- Sound direkt abspielen (Vorhoeren): ignoriert Stummschaltungen. Liefert die Handles aller Kopien.
function Sound.PlayChoice(key, vol)
    local c = Sound.byKey[key]
    if not c or key == "none" then return end
    if c.ui then
        key = Sound.UiKey(c.ui)
        if not key then return end
        if Sound.byKey[key] then c = Sound.byKey[key] end
    end
    if c.own then
        vol = math.floor(tonumber(vol or (S() and S().soundVol) or 14) or 14)
        if vol <= 0 then return end
        if vol > Sound.VOL_MAX then vol = Sound.VOL_MAX end
        -- Oasis_Sounds ohne ffmpeg eingelesen: nur die Originaldatei, keine Lautstaerkestufen
        if c.file then
            local ok, willPlay, handle = pcall(PlaySoundFile, c.file, "Master")
            return (ok and willPlay) and (handle or true) or nil
        end
        -- 0.5.799: je 10 Stufen eine Kopie gleichzeitig (Dateien gibt es nur bis Stufe 10) -> bis zu vier Kopien bei 200 %
        local path = (c.base or ns.MEDIA) .. "sounds\\" .. key .. "\\"
        local hs = {}
        while vol > 0 do
            local lv = math.min(10, vol)
            vol = vol - lv
            local ok, willPlay, handle = pcall(PlaySoundFile, path .. lv .. ".ogg", "Master")
            if ok and willPlay then hs[#hs + 1] = handle or true end
        end
        return unpack(hs)
    else
        local id = (SOUNDKIT and SOUNDKIT[c.kit]) or c.id
        local ok, willPlay, handle = pcall(PlaySound, id, "Master")
        if ok and willPlay then return handle or true end
        return nil
    end
end

-- Online-Sound: gleiche Skala wie alle Oasis-Sounds (PlayChoice spielt die Kopien selbst)
function Sound.PlayLoud(key, vol)
    return Sound.PlayChoice(key, math.floor(tonumber(vol) or 10))
end
function Sound.PreviewLoud(key, vol)
    if Sound.loudHandles then for _, h in ipairs(Sound.loudHandles) do if h and StopSound then pcall(StopSound, h, 100) end end end
    Sound.loudHandles = { Sound.PlayLoud(key, vol) }
end
local lastPlay = {}
local nextEvent
-- Ereignis-Sound mit allen Regeln (aus, Kampf, Drossel)
function Sound.Play(event)
    local s = S()
    if event == "none" or not s or not s.sound then return end
    if s.soundQuietCombat and ns.inCombat() then return end
    local now = GetTime()
    -- 0.6.405: derselbe Ereignis-Sound hoechstens alle 8 s (Klick-Ereignisse wie Fenster/Deathroll weiter sofort)
    local gap = (event == "open" or event == "close" or event == "death" or tostring(event):find("^dr_")) and 1.2 or 8
    if lastPlay[event] and now - lastPlay[event] < gap then return end
    lastPlay[event] = now
    local key = Sound.PickFor(event)
    -- einmaliger Ersatz-Sound fuer genau dieses Ereignis (eigener Todes-Sound eines Mitglieds)
    local fo = Sound.forced
    if fo and fo.event == event then
        Sound.forced = nil
        if key ~= "none" and Sound.byKey[fo.key] then key = fo.key end
    end
    local h = Sound.PlayChoice(key, s.soundVol)
    -- eigener Sound kam nicht durch (Datei erst nach WoW-Neustart bekannt, zu viele Sounds gleichzeitig ...):
    -- wenigstens den Blizzard-Hinweiston spielen, damit die Benachrichtigung nie stumm bleibt
    if not h and key ~= "none" then
        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.TELL_MESSAGE) or 3081, "Master")
    end
end

-- Der naechste K.Toast spielt diesen Ereignis-Sound statt des allgemeinen
-- gilt nur fuer einen Hinweis in den naechsten 2 Sekunden (sonst bliebe z.B. ein "none" haengen
-- und der naechste, voellig andere Hinweis waere stumm)
local nextAt = 0
function Sound.Next(event) nextEvent, nextAt = event, GetTime() end
-- Der naechste Sound des Ereignisses spielt key (nur Sounds, die fuer diesen Zweck gedacht sind: dev = purpose)
function Sound.Force(event, key, purpose)
    local c = key and Sound.byKey[key]
    Sound.forced = (c and c.dev == purpose) and { event = event, key = key } or nil
end
function Sound.TakeNext()
    local e = nextEvent
    nextEvent = nil
    if e and GetTime() - nextAt > 2 then return nil end
    return e
end

------------------------------------------------------------------------
-- Musik
------------------------------------------------------------------------
local musicOn = false
function Sound.MusicEnabledInGame()
    local v = GetCVar and GetCVar("Sound_EnableMusic")
    return v == nil or v == "1"
end
function Sound.StartMusic(key, force)
    local s = S()
    do return end   -- Fenster-Musik abgeschaltet
    if not force and (not s or s.music ~= "window") then return end
    local m = Sound.musicByKey[key or (s and s.musicTrack) or "orc"] or Sound.MUSIC[1]
    if PlayMusic then
        local ok = pcall(PlayMusic, m.id)
        musicOn = ok
    end
end
function Sound.StopMusic()
    if musicOn and StopMusic then pcall(StopMusic) end
    musicOn = false
end
function Sound.MusicPlaying() return musicOn end

ns.On("PLAYER_REGEN_ENABLED", function() ns.After(1, ns.K.FlushHeldToasts) end)
ns.Listen("MAIN_SHOWN", function() Sound.StartMusic() end)
ns.Listen("MAIN_HIDDEN", function() Sound.StopMusic() end)

-- Charakter-Stufenaufstieg (Blizzards eigener Klang laeuft zusaetzlich)
-- erst ab Stufe 10 (davor geht es zu schnell)
ns.On("PLAYER_LEVEL_UP", function(level)
    if (tonumber(level) or 0) >= 10 then ns.After(0.3, function() Sound.Play("levelup") end) end
end)

------------------------------------------------------------------------
-- Online-Sound: jeder waehlt seinen, die anderen hoeren ihn, wenn er online kommt
------------------------------------------------------------------------
local pop   -- Online-Fenster (weiter unten gebaut)
local onlinePat
local function onlineName(msg)
    if not onlinePat and ERR_FRIEND_ONLINE_SS then
        -- "|Hplayer:%s|h[%s]|h ist jetzt online." -> Muster mit Fang fuer den Namen
        onlinePat = ns.GlobalPattern(ERR_FRIEND_ONLINE_SS) or false
    end
    if not onlinePat then return nil end
    local ok, n = pcall(string.match, msg, onlinePat)
    return ok and n or nil
end
local lastEntrance = 0
ns.Listen("LOGIN", function() ns.loginAt = ns.loginAt or GetTime() end)
-- 0.5.651: Protokoll fuer "jemand kam online, aber nichts passierte" (/oa onlinelog)
Sound.entranceLog = {}
local function elog(name, what)
    local t = Sound.entranceLog
    t[#t + 1] = date("%H:%M:%S") .. "  " .. tostring(name) .. "  " .. what
    if #t > 30 then table.remove(t, 1) end
end
-- 0.5.678: beim Entwickler "Sounds aus dem Chat" einmalig wieder an (war versehentlich aus)
ns.Listen("LOGIN", function()
    local st = S()
    if st and not st.chs678 and ns.IsDev and ns.IsDev() then st.chs678 = true st.chatSounds = nil end
end)
ns.slash.onlinelog = function()
    ns.print(L["Online-Meldungen (neueste unten):"])
    if #Sound.entranceLog == 0 then ns.print("  -") end
    for _, l in ipairs(Sound.entranceLog) do ns.print("  " .. l) end
end
function Sound.PlayEntrance(name, src)
    local s = S()
    if not s or not name or ns.isMe(name) then return end
    if not s.sound then elog(name, "aus: Sounds abspielen ist aus") return end
    if s.soundEntrance == false and s.entrancePopup == false then elog(name, "aus: Online-Sounds und Anzeige sind aus") return end
    if s.soundQuietCombat and ns.inCombat() then elog(name, "aus: im Kampf stumm") return end
    -- Systemmeldung nennt in Forever teils nur den Vornamen oder einen anderen Realm-Anhang: dem Gildenmitglied zuordnen
    local full = (ns.ResolveName and ns.ResolveName(name, true)) or ns.fullName(name)
    -- Profil auch bei Namen mit Akzenten/Realm finden
    local alias = ns.Radar and ns.Radar.AliasOf and ns.Radar.AliasOf(full)
    local p = ns.db.members[full] or (alias and ns.db.members[alias])
    if not p then
        local short = ns.short(full):lower()
        for n, pr in pairs(ns.db.members) do if type(pr) == "table" and ns.short(n):lower() == short then p, full = pr, n break end end
    end
    -- nur Gildenmitglieder (Freunde ausserhalb der Gilde nicht)
    local inGuild = ns.Radar and ns.Radar.byName and rawget(ns.Radar.byName, full)
    if not (p or inGuild) and ns.Radar and ns.Radar.roster then
        -- Namen mit Leerzeichen/Realm (WoW Forever): ueber den Kurznamen in der Gildenliste suchen
        local sh = ns.short(full):lower()
        for _, m in ipairs(ns.Radar.roster) do
            if m.name and ns.short(m.name):lower() == sh then inGuild, full = true, m.name break end
        end
    end
    if not (p or inGuild) then elog(name, "nicht in der Gildenliste (" .. tostring(src) .. ")") return end
    -- doppelt (Systemmeldung UND Gildenliste melden dasselbe Einloggen): einmal je 2 Minuten
    Sound.entranceSeen = Sound.entranceSeen or {}
    local seenKey = ns.short(full):lower()
    if Sound.entranceSeen[seenKey] and GetTime() - Sound.entranceSeen[seenKey] < 120 then return end   -- schon gemeldet
    local key = p and p.es
    if key == "none" or (key and not Sound.byKey[key]) then key = nil end
    if key and Sound.byKey[key].dev and Sound.byKey[key].dev ~= "entrance" then key = nil end
    s.muteEntrance = s.muteEntrance or {}
    local who = ns.short(full)
    local muted = s.muteEntrance[who]
    -- nicht mehrere gleichzeitig: statt zu verwerfen der Reihe nach zeigen (max. 6 warten; nach eigenem Login
    -- kommen alle auf einmal -> die ersten 20 s nach dem Login gar nicht)
    local now = GetTime()
    if ns.loginAt and now - ns.loginAt < 5 then elog(name, "uebersprungen: eigener Login") return end   -- nur der Schwall direkt beim eigenen Login
    if now - lastEntrance < 8 then
        Sound.entranceQueue = Sound.entranceQueue or {}
        local q = Sound.entranceQueue
        for _, n in ipairs(q) do if n.name == full then return end end
        if #q < 6 then
            q[#q + 1] = { name = full, at = now }
            if not Sound.entranceTimer then
                Sound.entranceTimer = true
                local function nextOne()
                    local n = table.remove(q, 1)
                    while n and GetTime() - n.at > 15 do n = table.remove(q, 1) end
                    if not n then Sound.entranceTimer = nil return end
                    lastEntrance = 0
                    pcall(Sound.PlayEntrance, n.name, "Warteschlange")
                    C_Timer.After(8.2, nextOne)
                end
                C_Timer.After(math.max(0, 8.2 - (now - lastEntrance)), nextOne)
            end
        end
        return
    end
    lastEntrance = now
    Sound.entranceSeen[seenKey] = now
    -- Anzeige immer (abschaltbar), Sound nur mit gewaehltem Sound und nicht stumm; eigene Lautstaerke
    -- 0.5.651: hat die Person keinen eigenen Online-Sound, spielt ein kurzer Standard-Ton (vorher: stumm)
    if not key and not muted and s.soundEntrance ~= false then key = s.entranceDefault or (s.entranceLoud ~= false and Sound.byKey["ni_zweiklang"] and "ni_zweiklang") or "ni_ton" end
    if s.soundEntrance == false then key = nil end
    elog(name, "gemeldet (" .. tostring(src) .. ")" .. (key and (", Sound " .. key) or ", ohne Sound") .. (s.entrancePopup ~= false and ", Anzeige" or ""))
    if s.entrancePopup == false and (not key or muted) then return end
    local hs = {}
    if key and not muted then hs = { Sound.PlayLoud(key, s.soundEntranceVol or 10) } end
    if s.entrancePopup ~= false then
        -- Fehler in der Anzeige nicht verschlucken: ins Protokoll (/oa onlinelog)
        local okP, errP = pcall(Sound.EntrancePopup, full, key or "none", hs[1])
        if not okP then elog(name, "FEHLER Anzeige: " .. tostring(errP)) end
        if pop then pop.handle2 = hs end
    end
end

-- kleines Fenster: "X ist online" + Sound-Name; Lautsprecher = stoppen und diese Person stummschalten
function Sound.EntrancePopup(name, key, handle, isTest)
    local K, C = ns.K, ns.K.C
    if not pop then
        pop = CreateFrame("Frame", "OasisEntrancePopup", UIParent)
        pop:SetSize(340, 62)
        -- sitzt im Hinweis-Stapel (oberster Platz), damit nichts ueberlappt
        K.toastExtra = K.toastExtra or {}
        table.insert(K.toastExtra, pop)
        pop:SetScript("OnShow", function() K.LayoutToasts() end)
        pop:SetScript("OnHide", function() K.LayoutToasts() end)
        pop:SetFrameStrata("DIALOG")
        pop.fillTex = K.Fill(pop, { 0.04, 0.04, 0.05, 0.96 })
        K.Border(pop, { C.accent[1] * 0.7, C.accent[2] * 0.7, C.accent[3] * 0.7, 1 })
        -- 0.6.151: gleiche Bild-Box wie die uebrigen Hinweise (K.Toast, Gildenmodul) statt Flaeche und Oasis-Rand
        if ns.GuildPack then
            pop.boxBase = pop:CreateTexture(nil, "BACKGROUND", nil, 3)
            pop.boxBase:SetAllPoints()
            pop.boxBase:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\toast_box_base")
            if pop.fillTex then pop.fillTex:SetAlpha(0) end
            pop.imgBox = true
        end
        pop.glow = pop:CreateTexture(nil, "BORDER")
        pop.glow:SetAllPoints()
        if not K.Gradient(pop.glow, "HORIZONTAL", { C.accent[1], C.accent[2], C.accent[3], 0.22 }, { C.accent[1], C.accent[2], C.accent[3], 0 }) then pop.glow:Hide() end
        -- Klassensymbol rund mit Ring
        pop.ring = pop:CreateTexture(nil, "ARTWORK")
        pop.ring:SetTexture(ns.MEDIA .. "ring")
        pop.ring:SetSize(44, 44)
        pop.ring:SetPoint("LEFT", 10, 1)
        pop.cls = pop:CreateTexture(nil, "ARTWORK", nil, -1)
        pop.cls:SetSize(40, 40)
        pop.ring:SetAlpha(0)   -- Ring ueber dem Klassensymbol weg
        pop.cls:SetPoint("CENTER", pop.ring, "CENTER")
        pop.cls:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        pop.name = K.Title(pop, 15, C.text)
        pop.name:SetPoint("TOPLEFT", pop.ring, "TOPRIGHT", 10, -3)
        pop.name:SetPoint("RIGHT", pop, "RIGHT", -70, 0)
        pop.name:SetWordWrap(false)
        pop.sub = K.Text(pop, 11, C.muted)
        pop.sub:SetPoint("TOPLEFT", pop.name, "BOTTOMLEFT", 0, -5)
        pop.sub:SetPoint("RIGHT", pop, "RIGHT", -70, 0)
        pop.sub:SetWordWrap(false)
        -- Zeitbalken unten (bis das Fenster verschwindet)
        pop.time = pop:CreateTexture(nil, "OVERLAY")
        pop.time:SetPoint("BOTTOMLEFT", 1, 1)
        pop.time:SetHeight(2)
        pop.timePad = 2
        if pop.imgBox then
            -- wie bei den Hinweisen: Balken in der Box rechts neben dem Symbol, mit Verlauf und dezentem Schein
            pop.time:ClearAllPoints()
            pop.time:SetPoint("BOTTOMLEFT", 60, 9)
            pop.time:SetTexture("Interface\\Buttons\\WHITE8X8")
            pop.timePad = 60 + 34
            pop.timeGlow = pop:CreateTexture(nil, "ARTWORK", nil, -1)
            pop.timeGlow:SetPoint("TOPLEFT", pop.time, "TOPLEFT", -2, 3)
            pop.timeGlow:SetPoint("BOTTOMRIGHT", pop.time, "BOTTOMRIGHT", 2, -3)
            pop.timeGlow:SetTexture("Interface\\Buttons\\WHITE8X8")
            pop.timeGlow:SetBlendMode("ADD")
        end
        pop.time:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
        -- Lautsprecher: Klick stoppt den Sound und schaltet diese Person stumm (nochmal: wieder an)
        pop.mute = CreateFrame("Button", nil, pop)
        pop.mute:SetSize(26, 26)
        pop.mute:SetPoint("RIGHT", -36, 0)
        pop.mute.bg = K.Fill(pop.mute, { 1, 1, 1, 0.06 })
        pop.mute.icon = pop.mute:CreateTexture(nil, "ARTWORK")
        pop.mute.icon:SetPoint("TOPLEFT", 4, -4)
        pop.mute.icon:SetPoint("BOTTOMRIGHT", -4, 4)
        pop.mute:SetScript("OnEnter", function(self)
            self.bg:SetColorTexture(1, 1, 1, 0.14)
            K.ShowTip(self, { pop.muted and L["Wieder anschalten"] or L["Stummschalten"],
                pop.muted and L["Der Online-Sound dieser Person ist bei dir aus."] or L["Stoppt den Sound und spielt ihn bei dieser Person nicht mehr ab."] })
        end)
        pop.mute:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.06) GameTooltip:Hide() end)
        pop.mute:SetScript("OnClick", function()
            local st = S()
            st.muteEntrance = st.muteEntrance or {}
            if pop.handle and StopSound then pcall(StopSound, pop.handle, 300) end
            -- handle2: alle Kopien des Sounds (bei hoher Lautstaerke laufen mehrere gleichzeitig)
            if pop.handle2 and StopSound then for _, h in ipairs(pop.handle2) do pcall(StopSound, h, 300) end end
            pop.muted = not pop.muted
            if not pop.isTest then st.muteEntrance[pop.who] = pop.muted or nil end
            pop:Paint()
        end)
        local x = K.CloseButton(pop, function()
            if pop.handle and StopSound then pcall(StopSound, pop.handle, 300) end
            pop:Hide()
        end)
        x:SetPoint("RIGHT", -8, 0)
        function pop:Paint()
            local c = self.muted and C.red or C.text
            self.mute.icon:SetTexture(ns.MEDIA .. (self.muted and "icons\\speaker_off" or "icons\\speaker"))
            self.mute.icon:SetVertexColor(c[1], c[2], c[3])
        end
        pop:SetScript("OnUpdate", function(self, el)
            self.t = (self.t or 0) + el
            local w = (self:GetWidth() - (self.timePad or 2)) * math.max(0, 1 - self.t / 12)
            self.time:SetWidth(math.max(1, w))
            if self.t > 12 and not self:IsMouseOver() then self:Hide() end
        end)
    end
    -- Klassensymbol + Ringfarbe
    local cf = ns.Radar and ns.Radar.ClassOf(name)
    if not cf and ns.isMe(name) then cf = select(2, UnitClass("player")) end
    local tc = cf and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cf]
    if tc then pop.cls:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) pop.cls:Show() else pop.cls:Hide() end
    local cr, cg, cb = ns.classColor(cf)
    cr, cg, cb = cr or 0.6, cg or 0.6, cb or 0.6
    pop.ring:SetVertexColor(cr, cg, cb)
    -- Rahmen, Verlauf und Zeitbalken in Klassenfarbe
    K.SetBorderColor(pop, { cr * 0.75, cg * 0.75, cb * 0.75, 1 })
    if not K.Gradient(pop.glow, "HORIZONTAL", { cr, cg, cb, 0.24 }, { cr, cg, cb, 0 }) then pop.glow:SetColorTexture(cr, cg, cb, 0.08) end
    pop.time:SetColorTexture(cr, cg, cb, 0.95)
    if pop.imgBox then
        K.SetBorderColor(pop, { 0, 0, 0, 0 })
        pop.glow:SetAlpha(0.5)
        pop.time:SetTexture("Interface\\Buttons\\WHITE8X8")
        if not K.Gradient(pop.time, "HORIZONTAL", { cr, cg, cb, 0.35 }, { cr, cg, cb, 1 }) then pop.time:SetVertexColor(cr, cg, cb, 0.9) end
        if not K.Gradient(pop.timeGlow, "HORIZONTAL", { cr, cg, cb, 0.05 }, { cr, cg, cb, 0.22 }) then pop.timeGlow:SetVertexColor(cr, cg, cb, 0.15) end
    end
    pop.who, pop.handle, pop.isTest, pop.muted, pop.t = ns.short(name), handle, isTest, false, 0
    local c = Sound.byKey[key]
    pop.name:SetText((ns.colorName and ns.colorName(name, ns.Radar and ns.Radar.ClassOf(name)) or ns.displayName(name)) .. "  |cff66db9e" .. L["ist online"] .. "|r")
    if key == "none" then
        pop.sub:SetText(L["ist jetzt online"] .. (isTest and ("   |cffe8b44a" .. L["Test"] .. "|r") or ""))
    else
        pop.sub:SetText("|T" .. ns.MEDIA .. "icons\\speaker:12:12|t  " .. (c and L[c.text] or key) .. (isTest and ("   |cffe8b44a" .. L["Test"] .. "|r") or ""))
    end
    pop:Paint()
    pop:Show()
    -- neu gebaute Fenster sind schon "sichtbar": OnShow feuert dann nicht und das Fenster hatte beim ersten Mal keinen Platz
    K.LayoutToasts()
    pop:SetAlpha(1)
end

-- Test: so klingt/aussieht es, wenn jemand online kommt (eigener gewaehlter Sound, sonst ein Beispiel)
function Sound.TestEntrance()
    local key = Sound.ChoiceFor("entrance")
    if not key or key == "none" then key = "hallo" end
    local hs = { Sound.PlayLoud(key, (S() and S().soundEntranceVol) or 10) }
    Sound.EntrancePopup(ns.me(), key, hs[1], true)
    if pop then pop.handle2 = hs end
end
ns.slash.onlinetest = function() Sound.TestEntrance() end
ns.On("CHAT_MSG_SYSTEM", function(msg)
    msg = ns.safe(msg)
    if type(msg) ~= "string" then return end
    local n = onlineName(msg)
    if n then ns.After(0.5, function() pcall(Sound.PlayEntrance, n, "Systemmeldung") end) end
end)
-- Zweiter Weg: Gildenliste. Die Systemmeldung "ist jetzt online" kommt nur, wenn in den WoW-Optionen
-- "Gildenmitglieder-Hinweis" an ist (und fehlt manchmal ganz) -> neu online gegangene aus der Liste erkennen.
local wasOnline
ns.Listen("ROSTER", function()
    local R = ns.Radar
    if not (R and R.roster) or #R.roster == 0 then return end
    local now = {}
    for _, m in ipairs(R.roster) do if m.online and m.name and not m.demo then now[m.name] = true end end
    if wasOnline then
        for name in pairs(now) do
            if not wasOnline[name] then ns.After(1.5, function() pcall(Sound.PlayEntrance, name, "Gildenliste") end) end
        end
    end
    wasOnline = now
end)


------------------------------------------------------------------------
-- Kategorien, Laenge und Freischaltung (Oasis-Rang): kurze Sounds frueh, lange Sounds und Musik spaeter
------------------------------------------------------------------------
local DUR = { glocke = 1, ping = 0.5, blubb = 0.6, zweiton = 0.8, nein = 0.8, alarm = 1.5, erfolg = 1.5, fanfare = 2.5,
    horn = 3, trommel = 2.5, muenze = 1, wuerfel = 2, arbeitszeit = 10.5, dexter = 10.7, run = 8.3, rizz = 1.9, lostconn = 2.7,
    french = 12, animewow = 4.2, huh = 0.6, haltstop = 1.3, hallo = 0.5, uwu = 1, peitsche = 1, shutdown = 3.2, befehl = 2.2,
    quack = 1.1, ritter = 1.1, chinarap = 12, bahn = 2.3 }
local MUSIC = { french = true, chinarap = true }
Sound.TABS = {
    { key = "all", text = "Alle" }, { key = "oasis", text = "Oasis" }, { key = "german", text = "German" }, { key = "meme", text = "Memes" },
    { key = "music", text = "Musik" }, { key = "wow", text = "WoW" }, { key = "pack", text = "Soundpaket" },
    { key = "guild", text = "Discord" },   -- 0.5.802: Sounds aus dem Gilden-Discord (im Chat-Auswahlfenster der Reiter "OASIS")
}
-- 0.5.682: deutschsprachige Sounds im eigenen Reiter "German"
local GERMAN = { arbeitszeit = true, haltstop = true, hallo = true, ritter = true, bahn = true, wasistdennhierlo = true,
    auchdasistprivat = true, nichtdenfalschen = true, wasgehtaaaaaaaab = true, heutistwiederfre = true, ichmussraus = true,
    gutenmorgensport = true, neindochohh = true, franzosengrrrrfe = true, dasgibtneanzeige = true, kannesseindasdud = true,
    ichhabganisgemak = true, kannessein = true, drachenlordmotor = true, soleudeforza = true, hagebuddnefmrcw6 = true,
    dasistgenaudiesc = true, ultrageil = true, waszitterstnso = true, kasigermichael = true, meinechickennugg = true, erdbeerkaese = true,
    eyverrueckter = true, feuerball = true, wallahkrise = true, unangenehm = true, befehl = true }
Sound.GERMAN = GERMAN
local function finish(c)
    if c.key == "none" then c.cat = "all"
    elseif c.pack then c.cat = "pack"
    elseif c.guild then c.cat = "guild"
    elseif c.kit then c.cat = "wow"
    elseif GERMAN[c.key] then c.cat = "german"
    elseif MUSIC[c.key] or c.music or c.text:find("^Musik") then c.cat = "music"   -- "Musik: ..." gehoert immer zur Musik (sonst fehlte es beim Verschicken)
    elseif c.text:find("^Meme") or (DUR[c.key] or c.dur or 0) > 6 then c.cat = "meme"
    else c.cat = "oasis" end
    c.dur = DUR[c.key] or c.dur
    -- Rang nach Laenge: bis 1,5 s ab Rang 3, bis 3 s ab 6, bis 5 s ab 10, bis 9 s ab 16, laenger/Musik ab 22
    local d = c.dur or 0
    if c.ownLvl then c.lvl = c.ownLvl   -- eigener Sound einer Gilde mit festem Rang ("@20" im Dateinamen)
    elseif c.key == "none" then c.lvl = 1
    elseif c.kit then c.lvl = 2   -- 0.6.434: auch WoW-Klaenge und Oasis-Toene nicht mehr ab Rang 1
    elseif c.cat == "oasis" then c.lvl = 2
    -- 0.6.430: deutlich strenger - kurze ab 10, neue Gilden-Sounds ab 18, lange/Musik erst spaet
    -- 0.6.437: "free"/"neu" machen nicht mehr frei (galt fuer viele Gilden-Sounds) - es zaehlt die Laenge
    elseif MUSIC[c.key] or c.music then c.lvl = 45
    elseif d <= 1.5 then c.lvl = 2
    elseif d <= 3 then c.lvl = 6
    elseif d <= 5 then c.lvl = 12
    elseif d <= 9 then c.lvl = 20
    else c.lvl = 30 end   -- 0.6.439: Start ab Rang 2, dann 6/12/20/30, Musik 45
end
for _, c in ipairs(Sound.CHOICES) do finish(c) end
-- 0.5.728: Erweiterung durch das Gildenmodul (Oasis_Guild): zusaetzliche Sounds (eigene Dateien unter base) und UI-Soundpakete
function Sound.AddChoices(list, base)
    for _, c in ipairs(list) do
        if not Sound.byKey[c.key] then
            c.base = base
            Sound.CHOICES[#Sound.CHOICES + 1] = c
            Sound.byKey[c.key] = c
            finish(c)
        end
    end
end
function Sound.AddUiPack(pack, before)
    if Sound.uiPackByKey[pack.key] then return end
    local at = #Sound.UI_PACKS + 1
    for i, p in ipairs(Sound.UI_PACKS) do if p.key == before then at = i break end end
    table.insert(Sound.UI_PACKS, at, pack)
    Sound.uiPackByKey[pack.key] = pack
end
function Sound.MyRank()
    if ns.UnlockAll and ns.UnlockAll() then return 100 end
    local r = ns.Rank and ns.Rank.Mine() return r and r.level or 1
end
function Sound.Unlocked(key)
    local c = Sound.byKey[key]
    return c and Sound.MyRank() >= (c.lvl or 1)
end

-- Auswahlfenster: Reiter, Liste mit Symbol, Laenge, Schloss, Vorhoeren
local picker
-- zuletzt benutzt + Favoriten (pro Charakter-Account)
function Sound.Remember(key)
    local s = S()
    if not s or not key or key == "none" then return end
    s.soundRecent = s.soundRecent or {}
    for i = #s.soundRecent, 1, -1 do if s.soundRecent[i] == key then table.remove(s.soundRecent, i) end end
    table.insert(s.soundRecent, 1, key)
    while #s.soundRecent > 12 do table.remove(s.soundRecent) end
    -- "Haeufig": wie oft selbst benutzt (0.5.592)
    s.soundCount = s.soundCount or {}
    s.soundCount[key] = (s.soundCount[key] or 0) + 1
end
local function isFav(key) local s = S() return s and s.soundFav and s.soundFav[key] end
-- Favoriten-Reihenfolge (zum Umsortieren per Ziehen); alte Favoriten ohne Platz werden hinten angehaengt
function Sound.FavOrder()
    local s = S()
    if not s then return {} end
    s.soundFav = s.soundFav or {}
    s.soundFavOrder = s.soundFavOrder or {}
    local o, seen = {}, {}
    for _, k in ipairs(s.soundFavOrder) do if s.soundFav[k] and not seen[k] then seen[k] = true o[#o + 1] = k end end
    for k in pairs(s.soundFav) do if not seen[k] then o[#o + 1] = k end end
    s.soundFavOrder = o
    return o
end

------------------------------------------------------------------------
-- "Beliebt in der Gilde" (0.5.592): was im Gildenchat benutzt wird - Sounds (SND) und Emojis (Codes im Text).
-- Jeder zaehlt selbst mit, was er sieht (alle sehen denselben Gildenchat, nichts muss geteilt werden).
-- Halbwertszeit 7 Tage; je Absender und Eintrag hoechstens einmal pro Minute (gegen Spam-Verzerrung).
------------------------------------------------------------------------
local Pop = {}
ns.Popular = Pop
local HALF = 7 * 86400
local popSeen = {}
local function popStore(kind)
    if not ns.db then return nil end
    ns.db.popular = ns.db.popular or {}
    ns.db.popular[kind] = ns.db.popular[kind] or {}
    return ns.db.popular[kind]
end
local function decayed(e, now) return (e.s or 0) * 0.5 ^ ((now - (e.t or now)) / HALF) end
function Pop.Add(kind, key, who)
    local st = popStore(kind)
    if not st or type(key) ~= "string" or key == "" then return end
    local now = time()
    local sk = kind .. "|" .. tostring(who or "") .. "|" .. key
    if popSeen[sk] and now - popSeen[sk] < 60 then return end
    popSeen[sk] = now
    local e = st[key] or {}
    e.s, e.t = decayed(e, now) + 1, now
    st[key] = e
end
-- beliebteste Eintraege: { {key, score}, ... } absteigend; sehr alte/kleine Eintraege werden aufgeraeumt
function Pop.Top(kind, n)
    local st = popStore(kind)
    if not st then return {} end
    local now, out = time(), {}
    for k, e in pairs(st) do
        local v = decayed(e, now)
        if v < 0.05 then st[k] = nil else out[#out + 1] = { k, v } end
    end
    table.sort(out, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    while n and #out > n do table.remove(out) end
    return out
end

------------------------------------------------------------------------
-- Abklingzeit sichtbar machen (0.5.592): Knoepfe, die Sounds verschicken, zeigen die Wartezeit
------------------------------------------------------------------------
Sound.cdButtons = setmetatable({}, { __mode = "k" })
function Sound.CooldownLeft() return math.max(0, (Sound.SEND_CD or 30) - (GetTime() - (Sound.lastSend or -999))) end
function Sound.AttachCooldown(btn)
    if not btn or Sound.cdButtons[btn] then return end
    local ok, cd = pcall(CreateFrame, "Cooldown", nil, btn, "CooldownFrameTemplate")
    if not ok or not cd then return end
    cd:SetAllPoints()
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
    if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.65) end
    cd.txt = cd:CreateFontString(nil, "OVERLAY")
    ns.K.SetFontSafe(cd.txt, ns.K.FONT_HEAD, 10, "OUTLINE", ns.K.FONT)
    cd.txt:SetPoint("CENTER", 0, 0)
    cd.txt:SetTextColor(1, 0.85, 0.4)
    Sound.cdButtons[btn] = cd
    if Sound.CooldownLeft() > 0 then Sound.UpdateCooldowns() end
end
local cdTick = CreateFrame("Frame")
cdTick:Hide()
cdTick:SetScript("OnUpdate", function(self, el)
    self.e = (self.e or 0) + el
    if self.e < 0.25 then return end
    self.e = 0
    local left = Sound.CooldownLeft()
    for _, cd in pairs(Sound.cdButtons) do cd.txt:SetText(left > 0 and math.ceil(left) or "") end
    if left <= 0 then self:Hide() end
end)
function Sound.UpdateCooldowns()
    local left = Sound.CooldownLeft()
    for _, cd in pairs(Sound.cdButtons) do
        if left > 0 then pcall(cd.SetCooldown, cd, Sound.lastSend, Sound.SEND_CD) cd.txt:SetText(math.ceil(left))
        else pcall(cd.Clear, cd) cd.txt:SetText("") end
    end
    cdTick:SetShown(left > 0)
end
local CATCOL = { oasis = { 0.38, 0.6, 1 }, meme = { 0.95, 0.72, 0.25 }, music = { 0.8, 0.45, 1 }, wow = { 0.4, 0.86, 0.62 } }
local CATSHORT = { oasis = "OASIS", meme = "MEME", music = "MUSIK", wow = "WOW" }
local function cleanName(c) return (L[c.text]:gsub("^Oasis: ", ""):gsub("^Meme: ", ""):gsub("^Musik: ", ""):gsub("^WoW: ", "")) end

-- Titel des Auswahlfensters passend zum Ziel ("Sound an Mira schicken" ...)
function Sound.SetSendTarget(channel, target)
    local lbl = {
        GUILD = L["Sound in den Gildenchat schicken"], OFFICER = L["Sound an die Offiziere schicken"],
        PARTY = L["Sound an die Gruppe schicken"], RAID = L["Sound an den Schlachtzug schicken"], INSTANCE_CHAT = L["Sound an die Gruppe schicken"],
    }
    if (channel == "WHISPER" or channel == "BN_WHISPER") and target then
        Sound.sendLabel = (L["Sound an %s schicken"]):format(ns.short(target))
    else
        Sound.sendLabel = lbl[channel or "GUILD"] or lbl.GUILD
    end
    -- 0.5.882: nach dem Schicken oeffnet sich KEINE Chat-Eingabe mehr von selbst (vorher bei Gruppe/Fluestern: es ging "Sagen" auf).
    -- Nur der Lautsprecher an der Chat-Eingabe setzt restoreChat, und nur wenn dort gerade Text stand.
    -- Vorauswahl im Fenster (oben umschaltbar)
    Sound.chOverride = { ch = channel or "GUILD", tgt = target }
    Sound.chPending = true
end
function Sound.OpenPicker(anchor, current, onPick, title)
    local K, C = ns.K, ns.K.C
    if not picker then
        local f = CreateFrame("Frame", "OasisSoundPicker", UIParent)
        picker = f
        f:SetSize(680, 520)   -- 0.6.411: Soundboard groesser
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetClampedToScreen(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        -- 0.5.590: Glas-Karte (runde Ecken) + leichter Akzent-Verlauf im Kopf
        local G = ns.Insta and ns.Insta.Glass
        if not (G and pcall(G, f, { 0.035, 0.035, 0.045, 0.96 }, { 1, 1, 1, 0.1 }, 14)) then
            K.Fill(f, { 0.04, 0.04, 0.05, 0.97 })
            K.Border(f, C.line)
        end
        f.headGrad = f:CreateTexture(nil, "BACKGROUND", nil, 3)
        f.headGrad:SetPoint("TOPLEFT", 3, -3) f.headGrad:SetPoint("TOPRIGHT", -3, -3) f.headGrad:SetHeight(92)
        if not K.Gradient(f.headGrad, "VERTICAL", { C.accent[1], C.accent[2], C.accent[3], 0 }, { C.accent[1], C.accent[2], C.accent[3], 0.10 }) then f.headGrad:Hide() end
        ns.EscClose("OasisSoundPicker")
        f.head = K.GameHead(f, L["Sounds"], C.accent)
        f.head:SetPoint("TOPLEFT", 12, -10)
        f.head:SetWidth(230)
        -- 0.6.411: Kopf "OASIS SOUNDBOARD" mit Lautsprecher (Ziel steht in den Kanal-Knoepfen)
        f.head:Hide()
        f.logo = K.Glyph(f, 22, ns.MEDIA .. "icons\\speaker", C.accent)
        f.logo:SetPoint("TOPLEFT", 16, -14)
        f.title = K.Title(f, 17, C.text)
        f.title:SetPoint("LEFT", f.logo, "RIGHT", 10, 0)
        f.title:SetText("OASIS  |cffb8b8bc" .. K.Upper(L["Soundboard"]) .. "|r")
        local x = K.CloseButton(f, function() f:Hide() end)
        x:SetPoint("TOPRIGHT", -6, -6)
        -- Zahnrad: Einstellungen des Fensters
        local gear = CreateFrame("Button", nil, f)
        gear:SetSize(20, 20)
        gear.icon = K.Glyph(gear, 14, ns.MEDIA .. "icons\\settings", C.muted)
        gear.icon:SetPoint("CENTER")
        gear:SetScript("OnEnter", function(self) self.icon:SetVertexColor(C.text[1], C.text[2], C.text[3]) K.ShowTip(self, { L["Einstellungen"], L["Verhalten, Favoriten, Zuletzt benutzte"] }) end)
        gear:SetScript("OnLeave", function(self) self.icon:SetVertexColor(C.muted[1], C.muted[2], C.muted[3]) GameTooltip:Hide() end)
        gear:SetScript("OnClick", function() Sound.ShowPickerOptions() end)
        f.gear = gear
        -- Suche (Enter = ersten Treffer nehmen)
        f.search = K.Input(f, 548, L["Sound suchen ..."], function(t) f.q = (t or ""):lower() f.sel = nil f:Fill() end)
        f.search:SetScript("OnEnterPressed", function(self)
            local pick = f:SelItem() or f.firstHit
            self:ClearFocus()
            if pick then f:PickItem(pick) end
        end)
        -- Pfeiltasten im Suchfeld: Auswahl wandert durch die Liste (links/rechts = Spalte, hoch/runter = Zeile)
        if f.search.SetAltArrowKeyMode then pcall(f.search.SetAltArrowKeyMode, f.search, false) end
        f.search:SetScript("OnArrowPressed", function(_, key)
            local n = #(f.shown or {})
            if n == 0 then return end
            local i = f.sel or 0
            if key == "LEFT" then i = i - 1 elseif key == "RIGHT" then i = i + 1
            elseif key == "UP" then i = i - 2 elseif key == "DOWN" then i = i + 2 end
            if i < 1 then i = 1 elseif i > n then i = n end
            f.sel = i
            -- in den sichtbaren Bereich scrollen
            local l = f.list
            local row, vis = (f.rowOf and f.rowOf[i]) or math.ceil(i / 2), l:Visible()
            if row <= l.offset then l.offset = row - 1 elseif row > l.offset + vis then l.offset = row - vis end
            l:Refresh()
        end)
        f.search:HookScript("OnTabPressed", function()
            -- Tab: naechster Reiter
            local order = f.noNone and { "fav", "recent", "often", "popular", "guild", "music" } or { "fav", "recent", "often", "popular", "guild", "music", "pack" }
            for i, k in ipairs(order) do if k == f.tab then f.tab = order[i % #order + 1] break end end
            f.sel = nil
            f:Fill()
        end)
        function f:SelItem() return self.sel and self.shown and self.shown[self.sel] or nil end
        -- Zufall: ein freigeschalteter Sound aus dem aktuellen Reiter
        f.rand = K.Button(f, L["Zufall"], 96, 24, "ghost", function()
            local pool = {}
            for _, it in ipairs(f.shown or {}) do if it.key ~= "none" and Sound.Unlocked(it.key) then pool[#pool + 1] = it end end
            if #pool == 0 then return end
            f:PickItem(pool[math.random(#pool)])
        end)
        f.rand:SetPoint("LEFT", f.search, "RIGHT", 10, 0)
        f.rand:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Zufall"], L["Schickt einen zufaelligen Sound aus diesem Reiter"] }) end)
        f.rand:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Ziel waehlen (nur beim Verschicken): Gilde / Gruppe / Raid / letzter Fluesterpartner
        f.chans = {}
        -- Farben wie im Spiel: Gilde gruen, Gruppe blau, Raid orange, Fluestern rosa
        local CHCOL = { GUILD = { 0.25, 1, 0.25 }, PARTY = { 0.67, 0.67, 1 }, RAID = { 1, 0.5, 0 }, WHISPER = { 1, 0.5, 1 } }
        local CH = { { "GUILD", "Gilde" }, { "PARTY", "Gruppe" }, { "RAID", "Raid" }, { "WHISPER", "Fluestern" } }
        for i, d in ipairs(CH) do
            local b = K.Button(f, L[d[2]], 86, 26, "ghost", function()
                local tgt
                if d[1] == "WHISPER" then
                    tgt = Sound.chOverride and Sound.chOverride.tgt
                    if not tgt and ChatEdit_GetLastTellTarget then tgt = ns.safe(ChatEdit_GetLastTellTarget()) end
                    if not tgt or tgt == "" then ns.print(L["Noch niemand angefluestert."]) return end
                end
                Sound.chOverride = { ch = d[1], tgt = tgt }
                f:MarkChan()
            end)
            b.ch = d[1]
            b.col = CHCOL[d[1]]
            b.tint = b:CreateTexture(nil, "BACKGROUND", nil, 2)
            b.tint:SetAllPoints()
            b.tint:SetColorTexture(b.col[1], b.col[2], b.col[3], 0)
            b:SetPoint("TOPRIGHT", -62 - (#CH - i) * 92, -12)
            f.chans[i] = b
        end
        function f:MarkChan()
            local cur = Sound.chOverride and Sound.chOverride.ch or "GUILD"
            if cur == "INSTANCE_CHAT" then cur = "PARTY" elseif cur == "BN_WHISPER" then cur = "WHISPER" end
            for _, b in ipairs(self.chans) do
                b:SetShown(self.noNone)
                local on = b.ch == cur
                K.SetBorderColor(b, on and b.col or { b.col[1] * 0.45, b.col[2] * 0.45, b.col[3] * 0.45 })
                b.tint:SetColorTexture(b.col[1], b.col[2], b.col[3], on and 0.28 or 0.06)
                b.label:SetTextColor(b.col[1], b.col[2], b.col[3], on and 1 or 0.7)
                if b.ch == "WHISPER" then
                    local o = Sound.chOverride
                    b.label:SetText((on and o and o.tgt) and ns.short(o.tgt) or L["Fluestern"])
                end
            end
            local o = Sound.chOverride
            local lbl = { GUILD = L["Sound in den Gildenchat schicken"], PARTY = L["Sound an die Gruppe schicken"], RAID = L["Sound an den Schlachtzug schicken"] }
            if self.noNone then
                self.head.text:SetText(K.Upper((o and o.tgt and (o.ch == "WHISPER" or o.ch == "BN_WHISPER")) and (L["Sound an %s schicken"]):format(ns.short(o.tgt)) or lbl[cur] or lbl.GUILD))
            end
            if self.title then self.title:SetText("OASIS  |cffb8b8bc" .. K.Upper(L["Soundboard"]) .. "|r") end
        end
        f.gear:SetPoint("RIGHT", x, "LEFT", -6, 0)
        f.search:SetPoint("TOPLEFT", 14, -52)
        -- Reiter: Favoriten, Zuletzt, Memes, Musik (0.5.590)
        local items = { { key = "fav", text = L["Favoriten"] }, { key = "recent", text = L["Zuletzt"] },
            { key = "often", text = L["Haeufig"] }, { key = "popular", text = L["Beliebt"] },
            -- ein einziger Reiter OASIS fuer alle eigenen Sounds (Gilde, German, Memes, Musik zusammengelegt)
            { key = "guild", text = "OASIS" }, { key = "music", text = L["OASIS Musik"] }, { key = "pack", text = L["Soundpaket"] } }
        f.tabs = K.Segments(f, items, function(k)
            f.tab = k
            local s = S() if s then s.soundTab = k end
            if K.TabAnim then K.TabAnim(f.tabs, k) end
            f:Fill()
        end)
        f.tabs:SetPoint("TOPLEFT", 10, -88)
        -- zwei Spalten: jede Listenzeile traegt zwei Kacheln (Sound links / rechts)
        local function cell(r)
            local c = CreateFrame("Button", nil, r)
            c.bg = c:CreateTexture(nil, "BACKGROUND")
            c.bg:SetAllPoints()
            c.bg:SetColorTexture(1, 1, 1, 0.035)
            if K.RoundMask then pcall(K.RoundMask, c.bg, c, 6) end
            c.hl = c:CreateTexture(nil, "HIGHLIGHT")
            c.hl:SetAllPoints()
            c.hl:SetColorTexture(1, 1, 1, 0.06)
            -- gewaehlter Sound: Akzentbalken links + leichte Flaeche
            c.pickBg = c:CreateTexture(nil, "BACKGROUND", nil, 1)
            c.pickBg:SetAllPoints()
            c.pickBg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.12)
            c.pickBar = c:CreateTexture(nil, "ARTWORK")
            c.pickBar:SetPoint("TOPLEFT") c.pickBar:SetPoint("BOTTOMLEFT") c.pickBar:SetWidth(2)
            c.pickBar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
            -- Abspielen
            c.play = CreateFrame("Button", nil, c)
            c.play:SetSize(28, 28)
            c.play:SetPoint("LEFT", 6, 0)
            c.play.bg = K.Fill(c.play, { 1, 1, 1, 0.06 })
            if K.RoundMask then pcall(K.RoundMask, c.play.bg, c.play, 5) end
            c.play.icon = c.play:CreateTexture(nil, "ARTWORK")
            c.play.icon:SetPoint("TOPLEFT", 6, -6)
            c.play.icon:SetPoint("BOTTOMRIGHT", -6, 6)
            c.play.icon:SetTexture(ns.MEDIA .. "icons\\speaker")
            c.play:SetScript("OnClick", function() if c.item then Sound.Preview(c.item.key) end end)
            if ns.K.NoUiSound then ns.K.NoUiSound(c.play) end
            c.play:SetScript("OnEnter", function(self) self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.25) K.ShowTip(self, L["Anhoeren"]) end)
            c.play:SetScript("OnLeave", function(self) self.bg:SetColorTexture(1, 1, 1, 0.05) GameTooltip:Hide() end)
            -- Equalizer (laeuft gerade)
            c.eq = {}
            for i = 1, 3 do
                local b = c:CreateTexture(nil, "OVERLAY")
                b:SetWidth(3)
                b:SetPoint("BOTTOMLEFT", c.play, "BOTTOMRIGHT", 3 + (i - 1) * 4, 4)
                b:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
                b:Hide()
                c.eq[i] = b
            end
            c.name = K.Text(c, 13, C.text)
            c.name:SetPoint("LEFT", 50, 0)
            -- 0.6.411: "NEU" als kleines Abzeichen hinter dem Namen
            c.newTag = CreateFrame("Frame", nil, c)
            c.newTag:SetSize(30, 15)
            c.newTag.bg = c.newTag:CreateTexture(nil, "BACKGROUND")
            c.newTag.bg:SetAllPoints()
            c.newTag.bg:SetColorTexture(0.25, 0.55, 1, 0.22)
            c.newTag.t = K.Text(c.newTag, 9, { 0.6, 0.8, 1 }, "CENTER")
            c.newTag.t:SetPoint("CENTER")
            c.newTag.t:SetText(K.Upper(L["NEU"]))
            c.newTag:Hide()
            c.name:SetPoint("RIGHT", c, "RIGHT", -52, 0)
            c.name:SetWordWrap(false)
            c.meta = K.Text(c, 10, C.dim, "RIGHT")
            c.meta:SetPoint("RIGHT", -30, 0)
            -- Favorit: Stern rechts (gesetzt = Akzent, sonst nur beim Ueberfahren sichtbar)
            c.star = CreateFrame("Button", nil, c)
            c.star:SetSize(18, 18)
            c.star:SetPoint("RIGHT", -10, 0)
            c.star.icon = c.star:CreateTexture(nil, "ARTWORK")
            c.star.icon:SetAllPoints()
            c.star:SetScript("OnClick", function() if c.item then f:ToggleFav(c.item.key, c) end end)
            c.star:SetScript("OnEnter", function(self)
                c:GetScript("OnEnter")(c)
                K.ShowTip(self, { L["Favorit"], L["Klick: als Favorit merken / entfernen"] })
            end)
            c.star:SetScript("OnLeave", function() c:GetScript("OnLeave")(c) end)
            function c:PaintStar(hover)
                local fav = self.item and isFav(self.item.key)
                self.star.icon:SetTexture(ns.MEDIA .. "icons\\" .. (fav and "star_on" or "star_off"))
                if fav then self.star.icon:SetVertexColor(1, 0.82, 0.3, 1)
                else self.star.icon:SetVertexColor(1, 1, 1, hover and 0.7 or 0.3) end   -- 0.6.411: Umriss immer zu sehen
                self.star:SetShown(self.item ~= nil and self.item.key ~= "none")
            end
            -- Fortschritt beim Abspielen
            c.prog = c:CreateTexture(nil, "OVERLAY")
            c.prog:SetPoint("BOTTOMLEFT", 0, 0)
            c.prog:SetHeight(2)
            c.prog:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
            c.prog:Hide()
            -- Tastatur-Auswahl (Pfeiltasten im Suchfeld): Akzentflaeche + Linie unten
            c.kb = c:CreateTexture(nil, "BACKGROUND", nil, 2)
            c.kb:SetAllPoints()
            c.kb:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.16)
            c.kbLine = c:CreateTexture(nil, "ARTWORK", nil, 1)
            c.kbLine:SetPoint("BOTTOMLEFT") c.kbLine:SetPoint("BOTTOMRIGHT") c.kbLine:SetHeight(1)
            c.kbLine:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
            -- Favoriten umsortieren: im Reiter Favoriten ziehen und auf einem anderen Sound loslassen
            c:RegisterForDrag("LeftButton")
            c:SetScript("OnDragStart", function(self) f:StartDrag(self) end)
            c:SetScript("OnDragStop", function() f:EndDrag() end)
            c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            c:SetScript("OnClick", function(self, btn)
                local it = self.item
                if not it then return end
                if btn == "RightButton" then f:ToggleFav(it.key, self) return end
                f:PickItem(it, self)
            end)
            c:SetScript("OnEnter", function(self)
                local it = self.item
                if not it then return end
                self.bg:SetColorTexture(1, 1, 1, 0.07)
                self:PaintStar(true)
                if not Sound.Unlocked(it.key) then
                    K.ShowTip(self, { cleanName(it), (L["Ab Oasis-Rang %d"]):format(it.lvl or 1) })
                elseif it.key ~= "none" then
                    K.ShowTip(self, { cleanName(it), "|cff888888" .. (it.dur and (("%.1f s"):format(it.dur) .. "  ·  ") or "") .. L["Klick: auswaehlen  ·  Rechtsklick: Favorit"] .. "|r" })
                    -- auf Wunsch beim Ueberfahren kurz vorhoeren (mit Verzoegerung, sonst plaerrt es beim Durchfahren)
                    local s = S()
                    if s and s.soundHoverPreview then
                        self.hoverAt = GetTime()
                        local at = self.hoverAt
                        C_Timer.After(0.45, function()
                            if self.hoverAt == at and self:IsMouseOver() and self.item == it then Sound.Preview(it.key) end
                        end)
                    end
                end
            end)
            c:SetScript("OnLeave", function(self)
                self.hoverAt = nil
                self.bg:SetColorTexture(1, 1, 1, 0.03)
                self:PaintStar(false)
                GameTooltip:Hide()
            end)
            c:SetScript("OnUpdate", function(self)
                local it = self.item
                local playing = it and Sound.previewKey == it.key and it.dur and (GetTime() - (Sound.previewAt or 0)) < it.dur
                for i, b in ipairs(self.eq) do
                    b:SetShown(playing and true or false)
                    if playing then b:SetHeight(4 + math.abs(math.sin(GetTime() * (6 + i * 2.3))) * 11) end
                end
                self.prog:SetShown(playing and true or false)
                if playing then self.prog:SetWidth(math.max(1, self:GetWidth() * (GetTime() - Sound.previewAt) / it.dur)) end
            end)
            function c:Set(it)
                self.item = it
                if not it then self:Hide() return end
                self:Show()
                local un = Sound.Unlocked(it.key)
                local sel = it.key == picker.current
                self.name:SetText(it.key == "none" and L["Kein Sound"] or cleanName(it))
                self.name:SetTextColor(un and 0.94 or 0.5, un and 0.94 or 0.5, un and 0.94 or 0.5)
                self.newTag:SetShown(it.new and true or false)
                if it.new then
                    self.newTag:ClearAllPoints()
                    self.newTag:SetPoint("RIGHT", self, "RIGHT", -64, 0)   -- 0.6.416: rechtsbuendig vor der Dauer
                end
                self.pickBar:SetShown(sel)
                self.pickBg:SetShown(sel)
                if un then
                    self.meta:SetText(it.dur and ("%.1f s"):format(it.dur) or "")
                else
                    self.meta:SetText("|cffe8b44a" .. (L["Rang %d"]):format(it.lvl or 1) .. "|r")
                end
                self.play:SetShown(it.key ~= "none")
                self:SetAlpha(un and 1 or 0.6)
                self:PaintStar(false)
                local kb = picker:SelItem() == it
                self.kb:SetShown(kb) self.kbLine:SetShown(kb)
            end
            return c
        end
        -- Ziehen im Favoriten-Reiter: Geisterkarte folgt der Maus, Loslassen auf einem Sound = dorthin verschieben
        f.ghost = CreateFrame("Frame", nil, UIParent)
        f.ghost:SetSize(180, 26)
        f.ghost:SetFrameStrata("TOOLTIP")
        f.ghost.bg = f.ghost:CreateTexture(nil, "BACKGROUND")
        f.ghost.bg:SetAllPoints()
        f.ghost.bg:SetColorTexture(C.accent[1] * 0.5, C.accent[2] * 0.5, C.accent[3] * 0.5, 0.9)
        f.ghost.t = K.Text(f.ghost, 12, C.text)
        f.ghost.t:SetPoint("LEFT", 10, 0)
        f.ghost:Hide()
        f.ghost:SetScript("OnUpdate", function(self)
            local x, y = GetCursorPosition()
            local sc = UIParent:GetEffectiveScale()
            self:ClearAllPoints()
            self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / sc + 12, y / sc)
        end)
        function f:StartDrag(cell)
            local it = cell.item
            if self.tab ~= "fav" or (self.q or "") ~= "" or not it or it.key == "none" then return end
            self.dragKey = it.key
            self.ghost.t:SetText(cleanName(it))
            self.ghost:Show()
            cell:SetAlpha(0.35)
        end
        function f:EndDrag()
            local key = self.dragKey
            self.dragKey = nil
            self.ghost:Hide()
            if not key then return end
            local target
            for _, r in ipairs(self.list.rows) do
                for _, c in ipairs({ r.left, r.right }) do
                    if c and c:IsShown() and c.item and c:IsMouseOver() then target = c.item.key end
                end
            end
            local o = Sound.FavOrder()
            if target and target ~= key then
                local from, to
                for i, k in ipairs(o) do if k == key then from = i end if k == target then to = i end end
                if from and to then table.remove(o, from) table.insert(o, to, key) end
            end
            self:Fill()
        end
        -- Favorit umschalten (mit kleinem Aufploppen des Sterns)
        function f:ToggleFav(key, cell)
            local s = S()
            if not s or key == "none" then return end
            s.soundFav = s.soundFav or {}
            s.soundFav[key] = (not s.soundFav[key]) and true or nil
            local o = Sound.FavOrder()
            if s.soundFav[key] then
                -- neu gemerkt: vorne einreihen
                for i = #o, 1, -1 do if o[i] == key then table.remove(o, i) end end
                table.insert(o, 1, key)
            end
            if cell and cell.star then
                local st = cell.star
                if not (ns.db.settings.noAnim) then
                    K.Tween(st, 0.35, function(p) local k = 1 + 0.6 * math.sin(p * math.pi) st:SetSize(18 * k, 18 * k) end, function() st:SetSize(18, 18) end)
                end
            end
            if self.tab == "fav" then self:Fill() else for _, r in ipairs(self.list.rows or {}) do if r.left then r.left:PaintStar(false) r.right:PaintStar(false) end end end
        end
        -- Sound nehmen: merken, Fenster je nach Einstellung schliessen, an den Aufrufer geben
        function f:PickItem(it, cell)
            if not it then return end
            if not Sound.Unlocked(it.key) then
                K.Toast(L["Noch gesperrt"], (L["Ab Oasis-Rang %d"]):format(it.lvl), C.dim)
                return
            end
            Sound.Remember(it.key)
            local s = S()
            local keep = s and s.soundKeepOpen and self.noNone
            -- mitgeschickte Emojis: nach dem Sound in die Chat-Eingabe (abschicken muss man selbst - Forever
            -- sperrt automatisches Senden); nur wenn der Sound wirklich rausging (keine Abklingzeit)
            local att = self.noNone and Sound.attach and #Sound.attach > 0 and Sound.CooldownLeft() <= 0 and Sound.attach or nil
            if keep then
                -- offen lassen: kurzes Aufleuchten als Rueckmeldung
                if cell and cell.pickBg and not ns.db.settings.noAnim then
                    cell.pickBg:Show()
                    K.Tween(cell.pickBg, 0.6, function(p) cell.pickBg:SetAlpha(1 - p) end, function() cell.pickBg:SetAlpha(1) cell:Set(cell.item) end)
                end
                if self.tab == "recent" then C_Timer.After(0.65, function() if self:IsShown() then self:Fill() end end) end
            else
                self:Hide()
            end
            if self.onPick then self.onPick(it.key) end
            if att and ns.Emoji and ns.Emoji.Insert then
                local codes = {}
                for i, c in ipairs(att) do codes[i] = c if ns.Emoji.Remember then pcall(ns.Emoji.Remember, c) end end
                C_Timer.After(0.15, function() pcall(ns.Emoji.Insert, table.concat(codes, " ")) end)
            end
        end
        f.list = K.List(f, 40, function(l)
            local r = K.Row(l)
            if r.hl then r.hl:SetAlpha(0) end
            if r.sel then r.sel:SetAlpha(0) end   -- Auswahl zeigt die Kachel selbst
            -- 0.6.411: Zwischenueberschrift (Gruppe + Anzahl) ueber die ganze Breite
            r.hd = K.Text(r, 11, C.muted)
            r.hd:SetPoint("BOTTOMLEFT", 6, 6)
            r.hdLine = r:CreateTexture(nil, "ARTWORK")
            r.hdLine:SetHeight(1)
            r.hdLine:SetPoint("LEFT", r.hd, "RIGHT", 10, 0)
            r.hdLine:SetPoint("RIGHT", r, "RIGHT", -6, 0)
            r.hdLine:SetColorTexture(1, 1, 1, 0.08)
            r.left, r.right = cell(r), cell(r)
            r.left:SetPoint("TOPLEFT", 2, -2)
            r.left:SetPoint("BOTTOMRIGHT", r, "BOTTOM", -3, 2)
            r.right:SetPoint("TOPLEFT", r, "TOP", 3, -2)
            r.right:SetPoint("BOTTOMRIGHT", -2, 2)
            r:EnableMouse(false)
            return r
        end, function(r, pair)
            local hd = pair.header
            r.hd:SetShown(hd ~= nil) r.hdLine:SetShown(hd ~= nil)
            if hd then
                r.hd:SetText(K.Upper(hd) .. "  |cff666666" .. (pair.n or "") .. "|r")
                r.left:Set(nil) r.right:Set(nil)
                return
            end
            r.left:Set(pair[1])
            r.right:Set(pair[2])
        end)
        f.listBottom = 28
        function f:PlaceList(dy)
            dy = dy or 0
            self.list:ClearAllPoints()
            self.list:SetPoint("TOPLEFT", 8, -122 - dy)
            self.list:SetPoint("BOTTOMRIGHT", -6, self.listBottom + dy)
        end
        f:PlaceList()
        f.foot = K.Text(f, 10, C.dim)
        f.foot:SetPoint("BOTTOMLEFT", 12, 9)
        f.foot:SetPoint("RIGHT", f, "RIGHT", -12, 0)
        -- Wartezeit bis zum naechsten Sound: duenner Balken unter den Reitern + Text in der Fusszeile
        f.cdBar = f:CreateTexture(nil, "ARTWORK")
        f.cdBar:SetPoint("TOPLEFT", 8, -118)
        f.cdBar:SetHeight(2)
        f.cdBar:SetColorTexture(1, 0.75, 0.3, 0.85)
        f.cdBar:Hide()
        f.cdT = 0
        f:HookScript("OnUpdate", function(self, el)
            self.cdT = self.cdT + el
            if self.cdT < 0.1 then return end
            self.cdT = 0
            local left = self.noNone and Sound.CooldownLeft() or 0
            if left > 0 then
                self.cdBar:SetWidth(math.max(1, (self:GetWidth() - 16) * left / (Sound.SEND_CD or 30)))
                self.cdBar:Show()
                self.foot:SetText("|cffe8b44a" .. (L["Naechster Sound in %d s"]):format(math.ceil(left)) .. "|r")
                self.cdShown = true
            elseif self.cdShown then
                self.cdShown = nil
                self.cdBar:Hide()
                self.foot:SetText(self.footText or "")
            end
        end)
        -- "Emoji dazu" (nur beim Verschicken): ausgewaehlte Emojis landen nach dem Sound in der Chat-Eingabe
        f.att = CreateFrame("Frame", nil, f)
        f.att:SetPoint("BOTTOMLEFT", 10, 30)
        f.att:SetPoint("BOTTOMRIGHT", -10, 30)
        f.att:SetHeight(28)
        f.att.lbl = K.Text(f.att, 11, C.muted)
        f.att.lbl:SetPoint("LEFT", 2, 0)
        f.att.lbl:SetText(L["Emoji dazu:"])
        f.att.slots = {}
        for i = 1, 12 do
            local b = CreateFrame("Button", nil, f.att)
            b:SetSize(26, 26)
            b:SetPoint("LEFT", f.att.lbl, "RIGHT", 8 + (i - 1) * 30, 0)
            b.bg = b:CreateTexture(nil, "BACKGROUND")
            b.bg:SetAllPoints()
            b.bg:SetColorTexture(1, 1, 1, 0.05)
            b.sel = b:CreateTexture(nil, "BORDER")
            b.sel:SetAllPoints()
            b.sel:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.35)
            b.sel:Hide()
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetPoint("TOPLEFT", 2, -2) b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
            b.num = K.Text(b, 9, C.text)
            b.num:SetPoint("TOPRIGHT", 1, 1)
            b:SetScript("OnClick", function(self)
                local a = Sound.attach or {}
                Sound.attach = a
                for j = #a, 1, -1 do if a[j] == self.code then table.remove(a, j) f:PaintAttach() return end end
                if #a < 5 then a[#a + 1] = self.code end
                if not (ns.db and ns.db.settings.noAnim) then
                    local ic = self.icon
                    K.Tween(ic, 0.22, function(p) local d = 2 - 3 * math.sin(p * math.pi) ic:ClearAllPoints() ic:SetPoint("TOPLEFT", d, -d) ic:SetPoint("BOTTOMRIGHT", -d, d) end,
                        function() ic:ClearAllPoints() ic:SetPoint("TOPLEFT", 2, -2) ic:SetPoint("BOTTOMRIGHT", -2, 2) end)
                end
                f:PaintAttach()
            end)
            b:SetScript("OnEnter", function(self) K.ShowTip(self, { self.code or "", L["Klick: mitschicken (bis zu 5, in Klick-Reihenfolge)"] }) end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
            f.att.slots[i] = b
        end
        f.att.empty = K.Text(f.att, 10, C.dim)
        f.att.empty:SetPoint("LEFT", f.att.lbl, "RIGHT", 8, 0)
        f.att.empty:SetText(L["Noch keine Emojis benutzt - Favoriten aus der Emoji-Auswahl erscheinen hier."])
        function f:PaintAttach()
            local E = ns.Emoji
            local codes = (E and E.QuickCodes) and E.QuickCodes(12) or {}
            local a = Sound.attach or {}
            for i, b in ipairs(self.att.slots) do
                local c = codes[i]
                b.code = c
                b:SetShown(c ~= nil)
                if c then
                    E.SetIcon(b.icon, E.Entry(c))
                    local pos
                    for j, x in ipairs(a) do if x == c then pos = j end end
                    b.sel:SetShown(pos ~= nil)
                    b.num:SetText(pos and #a > 1 and pos or "")
                end
            end
            self.att.empty:SetShown(#codes == 0)
        end
        function f:Fill()
            local s = S() or {}
            local out, total, unl = {}, 0, 0
            local q = self.q or ""
            local recentPos = {}
            for i, k in ipairs(s.soundRecent or {}) do recentPos[k] = i end
            local favPos = {}
            for i, k in ipairs(Sound.FavOrder()) do favPos[k] = i end
            local count = s.soundCount or {}
            local popScore = {}
            if self.tab == "popular" then for _, e in ipairs(Pop.Top("sound", 40)) do popScore[e[1]] = e[2] end end
            local dev = ns.IsDev()
            for _, c in ipairs(Sound.CHOICES) do
                if c.key ~= "none" and (not c.dev or dev) then
                    total = total + 1
                    if Sound.Unlocked(c.key) then unl = unl + 1 end
                end
                local ok
                local pickable = c.cat == "meme" or c.cat == "music" or c.cat == "german" or c.cat == "pack" or c.cat == "guild"
                if q ~= "" then ok = pickable   -- Suche ueber alles Waehlbare
                elseif self.tab == "fav" then ok = pickable and isFav(c.key) and true or false
                elseif self.tab == "recent" then ok = pickable and recentPos[c.key] ~= nil
                elseif self.tab == "often" then ok = pickable and (count[c.key] or 0) > 0
                elseif self.tab == "popular" then ok = pickable and popScore[c.key] ~= nil
                -- 0.5.873: Musik hat einen eigenen Reiter "OASIS Musik" (faellt unten in den allgemeinen Zweig c.cat == self.tab)
                elseif self.tab == "guild" then ok = c.cat == "guild" or c.cat == "german" or c.cat == "meme" or c.key == "none"
                else ok = c.cat == self.tab or c.key == "none" end
                if ok and self.noNone and c.key == "none" then ok = false end
                -- Entwickler-Sounds: nur beim Entwickler und nie beim Verschicken
                if ok and c.dev and (self.noNone or not dev) then ok = false end
                -- beim Verschicken keine Oberflaechen-Toene (Soundpaket): die schickt man nicht in den Chat
                if ok and self.noNone and c.cat == "pack" then ok = false end
                if ok and q ~= "" then ok = c.key ~= "none" and (cleanName(c):lower():find(q, 1, true) ~= nil) end
                if ok then out[#out + 1] = c end
            end
            local favFirst = s.soundFavFirst ~= false and q == "" and (self.tab == "meme" or self.tab == "music" or self.tab == "german" or self.tab == "pack" or self.tab == "guild")
            table.sort(out, function(a, b)
                if a.key == "none" then return true elseif b.key == "none" then return false end
                if self.tab == "recent" and q == "" then return recentPos[a.key] < recentPos[b.key] end
                if self.tab == "fav" and q == "" then return (favPos[a.key] or 999) < (favPos[b.key] or 999) end
                if self.tab == "often" and q == "" and (count[a.key] or 0) ~= (count[b.key] or 0) then return (count[a.key] or 0) > (count[b.key] or 0) end
                if self.tab == "popular" and q == "" and popScore[a.key] ~= popScore[b.key] then return (popScore[a.key] or 0) > (popScore[b.key] or 0) end
                if favFirst then
                    local fa, fb = isFav(a.key) and 1 or 0, isFav(b.key) and 1 or 0
                    if fa ~= fb then return fa > fb end
                end
                if (a.new and 1 or 0) ~= (b.new and 1 or 0) then return a.new and true or false end   -- neue zuerst
                local ua, ub = Sound.Unlocked(a.key), Sound.Unlocked(b.key)
                if ua ~= ub then return ua end
                if (a.lvl or 1) ~= (b.lvl or 1) then return (a.lvl or 1) < (b.lvl or 1) end
                return cleanName(a) < cleanName(b)
            end)
            -- paarweise fuer zwei Spalten; 0.6.411: im Reiter OASIS nach Gruppen (Gilde, Deutsch, Memes) mit Ueberschrift
            local pairs2 = {}
            self.rowOf = {}
            if self.tab == "guild" and q == "" then
                local GROUPS = { { "guild", L["Gilde"] }, { "german", L["Deutsch"] }, { "meme", L["Memes"] } }
                local by = {}
                for _, it in ipairs(out) do local k = it.cat or "meme" by[k] = by[k] or {} table.insert(by[k], it) end
                local ordered = {}
                for _, g in ipairs(GROUPS) do
                    local l = by[g[1]]
                    if l and #l > 0 then
                        pairs2[#pairs2 + 1] = { header = g[2], n = #l }
                        for i = 1, #l, 2 do
                            pairs2[#pairs2 + 1] = { l[i], l[i + 1] }
                            ordered[#ordered + 1] = l[i] self.rowOf[#ordered] = #pairs2
                            if l[i + 1] then ordered[#ordered + 1] = l[i + 1] self.rowOf[#ordered] = #pairs2 end
                        end
                    end
                end
                if #ordered > 0 then out = ordered end
            else
                for i = 1, #out, 2 do pairs2[#pairs2 + 1] = { out[i], out[i + 1] } end
            end
            self.shown = out
            if self.sel and self.sel > #out then self.sel = nil end
            if self.lastTab ~= self.tab then self.sel = nil end
            self.list:SetData(pairs2)
            self.firstHit = nil
            for _, it in ipairs(out) do if it.key ~= "none" and Sound.Unlocked(it.key) then self.firstHit = it break end end
            local EMPTY = { often = L["Noch nichts benutzt."], popular = L["In der Gilde wurden noch keine Sounds geschickt."] }
            self.list.empty:SetText(q ~= "" and L["Nichts gefunden."] or EMPTY[self.tab] or (self.tab == "recent" and L["Noch nichts benutzt."]
                or (self.tab == "fav" and L["Noch keine Favoriten - Stern oder Rechtsklick auf einen Sound."] or L["Nichts gefunden."])))
            self.tabs:Select(self.tab)
            -- Reiterwechsel: Liste weich einblenden und leicht von unten hereinschieben
            if self.lastTab ~= self.tab and not (ns.db and ns.db.settings.noAnim) then
                local l = self.list
                l:SetAlpha(0)
                K.Tween(l, 0.28, function(p)
                    l:SetAlpha(p)
                    self:PlaceList(10 * (1 - p))
                end, function()
                    l:SetAlpha(1)
                    self:PlaceList()
                end)
            end
            self.lastTab = self.tab
            self.footText = ""   -- 0.5.664: Fusszeile (freigeschaltet / Tastenhinweis) weg - nur noch Abklingzeit-Hinweise
            if not self.cdShown then self.foot:SetText(self.footText) end
        end
    end
    -- ohne vorheriges SetSendTarget (z.B. Oasis-Gildenchat): keine alte Auswahl uebernehmen
    if not Sound.chPending then Sound.chOverride = nil end
    Sound.chPending = nil
    picker.current, picker.onPick = current, onPick
    picker.noNone = title == "send"
    -- Emoji-Leiste nur beim Verschicken; Liste macht ihr Platz
    Sound.attach = nil
    picker.att:SetShown(false)   -- 0.5.669: Leiste "Emoji dazu" entfernt
    picker.listBottom = picker.att:IsShown() and 62 or 28
    picker:PlaceList()
    if picker.att:IsShown() then picker:PaintAttach() end
    picker.sel = nil
    picker.head.text:SetText(ns.K.Upper(title == "send" and (Sound.sendLabel or L["Sound in den Gildenchat schicken"]) or (title or L["Sounds"])))
    Sound.sendLabel = nil
    picker:MarkChan()
    -- beim Schliessen die Chat-Eingabe (z.B. Fluestern) wieder oeffnen - die Suche hatte ihr den Fokus genommen
    if not picker.restoreHooked then
        picker.restoreHooked = true
        picker:HookScript("OnHide", function()
            if Sound.restoreChat then
                Sound.restoreChat = nil
                if ns.Emoji and ns.Emoji.RestoreChat then C_Timer.After(0.05, function() pcall(ns.Emoji.RestoreChat) end) end
            end
        end)
    end
    local s = S()
    -- zuletzt gewaehlter Reiter; leere Favoriten/Zuletzt -> Memes
    local want = picker.tab or (s and s.soundTab) or "guild"
    if want == "german" or want == "meme" then want = "guild" end   -- alte Reiter -> OASIS
    if want == "fav" and not (s and s.soundFav and next(s.soundFav)) then want = "guild" end
    if want == "recent" and not (s and s.soundRecent and #s.soundRecent > 0) then want = "guild" end
    if want ~= "fav" and want ~= "recent" and want ~= "often" and want ~= "popular" and want ~= "pack" and want ~= "guild" and want ~= "music" then want = "guild" end
    -- Reiter "Soundpaket" nur beim Aussuchen eines Tons, nicht beim Verschicken
    if picker.noNone and want == "pack" then want = "guild" end
    for _, b in ipairs(picker.tabs.buttons or {}) do if b.key == "pack" then b:SetShown(not picker.noNone) end end
    picker.tab = want
    picker.lastTab = nil
    picker.q = ""
    picker.search:SetText("")
    picker:ClearAllPoints()
    if anchor then picker:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 6) else picker:SetPoint("CENTER") end
    picker:Fill()
    picker:Show()
end

-- Einstellungen des Sound-Fensters (Zahnrad): klappt rechts an der Glaskarte auf
function Sound.ShowPickerOptions()
    if not picker then return end
    local K, C = ns.K, ns.K.C
    local o = picker.opts
    if not o then
        local st = S()
        o = CreateFrame("Frame", nil, picker)
        picker.opts = o
        o:SetSize(260, 236)
        o:SetPoint("TOPLEFT", picker, "TOPRIGHT", 8, 0)
        o:SetFrameLevel(picker:GetFrameLevel() + 20)
        o:EnableMouse(true)
        local G = ns.Insta and ns.Insta.Glass
        if not (G and pcall(G, o, { 0.035, 0.035, 0.045, 0.96 }, { 1, 1, 1, 0.1 }, 12)) then K.Fill(o, C.bg) K.Border(o, C.line) end
        local t = K.Title(o, 13, C.text)
        t:SetPoint("TOPLEFT", 14, -12)
        t:SetText(L["Einstellungen"])
        local x = K.CloseButton(o, function() o:Hide() end)
        x:SetPoint("TOPRIGHT", -4, -4)
        local y = -42
        o.toggles = {}
        local function tog(label, get, set)
            local tg = K.Toggle(o, label, get, set)
            tg:SetWidth(232)
            tg:SetPoint("TOPLEFT", 14, y)
            y = y - 30
            o.toggles[#o.toggles + 1] = tg
        end
        tog(L["Fenster nach dem Schicken offen lassen"], function() return st.soundKeepOpen and true or false end, function(v) st.soundKeepOpen = v and true or nil end)
        tog(L["Beim Ueberfahren vorhoeren"], function() return st.soundHoverPreview and true or false end, function(v) st.soundHoverPreview = v and true or nil end)
        tog(L["Favoriten zuerst zeigen"], function() return st.soundFavFirst ~= false end, function(v) st.soundFavFirst = v and true or false picker:Fill() end)
        o.clearRecent = K.Button(o, L["Zuletzt benutzte leeren"], 232, 24, "ghost", function()
            st.soundRecent = {}
            picker:Fill()
            K.Toast(L["Sounds"], L["Zuletzt benutzte geleert."], C.mint)
        end)
        o.clearRecent:SetPoint("BOTTOMLEFT", 14, 44)
        o.clearFav = K.Button(o, L["Favoriten leeren"], 232, 24, "ghost", function()
            st.soundFav = {}
            picker:Fill()
            K.Toast(L["Sounds"], L["Favoriten geleert."], C.mint)
        end)
        o.clearFav:SetPoint("BOTTOMLEFT", 14, 14)
        function o:Refresh() for _, tg in ipairs(self.toggles) do tg:Refresh() end end
        picker:HookScript("OnHide", function() o:Hide() end)
        o:Hide()
    end
    if o:IsShown() then o:Hide() return end
    o:Refresh()
    o:Show()
    if not (ns.db and ns.db.settings.noAnim) then
        o:SetAlpha(0)
        K.Tween(o, 0.2, function(p) o:SetAlpha(p) end, function() o:SetAlpha(1) end)
    end
end

------------------------------------------------------------------------
-- Sounds im Gildenchat verschicken: Code {s:key}; mit Abklingzeit gegen Spam
------------------------------------------------------------------------
-- Sound dort zeigen, wo er hingeschickt wurde: Gilde / Fluestern / Gruppe / Schlachtzug
-- (im WoW-Chat in der Farbe dieses Chats, dazu im Oasis-Gildenchat bzw. Privatchat)
local CH_TYPE = { GUILD = "GUILD", OFFICER = "OFFICER", PARTY = "PARTY", RAID = "RAID", INSTANCE_CHAT = "INSTANCE_CHAT",
    WHISPER = "WHISPER", BN_WHISPER = "WHISPER" }
local function playerLink(name)
    local short = ns.short(name)
    local col = ns.Radar and ns.Radar.Colored and ns.Radar.Colored(name) or short
    return "|Hplayer:" .. tostring(name) .. "|h[" .. col .. "]|h"
end
function Sound.ShowInChat(channel, who, key, outgoing)
    local link = Sound.RenderCodes and Sound.RenderCodes("{s:" .. key .. "}") or key
    local ct = CH_TYPE[channel] or "GUILD"
    local msgType = (ct == "WHISPER" and outgoing) and "WHISPER_INFORM" or ct
    local fmt = ({ GUILD = CHAT_GUILD_GET, OFFICER = CHAT_OFFICER_GET, PARTY = CHAT_PARTY_GET, RAID = CHAT_RAID_GET,
        INSTANCE_CHAT = CHAT_INSTANCE_CHAT_GET, WHISPER = CHAT_WHISPER_GET, WHISPER_INFORM = CHAT_WHISPER_INFORM_GET })[msgType] or "%s: "
    local line = fmt:format(playerLink(who)) .. link
    local info = ChatTypeInfo and ChatTypeInfo[msgType] or { r = 1, g = 1, b = 1 }
    local shown = false
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        local has = cf and ChatFrame_ContainsMessageGroup and ChatFrame_ContainsMessageGroup(cf, msgType == "WHISPER_INFORM" and "WHISPER" or msgType)
        if has then pcall(cf.AddMessage, cf, line, info.r, info.g, info.b) shown = true end
    end
    if not shown and DEFAULT_CHAT_FRAME then pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, line, info.r, info.g, info.b) end
    -- Oasis-eigene Chats
    if ct == "GUILD" and ns.GuildChat and ns.GuildChat.AddSound then pcall(ns.GuildChat.AddSound, outgoing and ns.me() or who, key) end
    if ct == "WHISPER" and ns.WhisperLog and ns.WhisperLog.AddSound then pcall(ns.WhisperLog.AddSound, who, key, outgoing) end
end
------------------------------------------------------------------------
Sound.SEND_CD = 30          -- Sekunden zwischen zwei eigenen Sounds
Sound.RECV_CD = 20          -- je Absender hoechstens alle 20 s abspielen
-- channel/target: wohin (Gilde = Standard; Fluestern, Gruppe, Schlachtzug ... = nur dort zu hoeren)
function Sound.SendInChat(key, channel, target)
    local s = S()
    if not Sound.Unlocked(key) or Sound.byKey[key].dev then return end
    -- von der Gildenleitung fuer Soundeffekte gesperrt
    if ns.SoundMuted and ns.SoundMuted(ns.me()) then
        ns.K.Toast(L["Soundeffekte gesperrt"], L["Die Gildenleitung hat Soundeffekte fuer dich gesperrt."], ns.K.C.dim)
        return
    end
    local left = Sound.SEND_CD - (GetTime() - (Sound.lastSend or -999))
    if left > 0 then
        ns.K.Toast(L["Kurz warten"], (L["Naechster Sound in %d s"]):format(math.ceil(left)), ns.K.C.dim)
        return
    end
    Sound.lastSend = GetTime()
    Sound.Remember(key)
    pcall(Sound.UpdateCooldowns)
    -- Ueber Addon-Nachrichten statt Chat-Text: Chat senden ist im Beta-Client fuer Addons gesperrt
    -- ("Interface-Aktion fehlgeschlagen"). Nur Oasis-Nutzer hoeren den Sound ohnehin.
    channel = channel or "GUILD"
    -- oben im Fenster umgestellt?
    if Sound.chOverride and Sound.chOverride.ch then channel, target = Sound.chOverride.ch, Sound.chOverride.tgt end
    if (channel == "PARTY" and not IsInGroup()) or (channel == "RAID" and not IsInRaid()) then
        ns.print(channel == "RAID" and L["Du bist in keinem Schlachtzug."] or L["Du bist in keiner Gruppe."])
        return
    end
    local Comm = ns.Comm
    if not Comm then return end
    if channel == "BN_WHISPER" and target then
        -- Battle.net-Freund: direkt an sein WoW-Spielkonto (BNSendGameData), nur wenn er gerade WoW spielt
        local gid
        local bid = BNet_GetBNetIDAccount and ns.safe(BNet_GetBNetIDAccount(target))
        local acc = bid and C_BattleNet and C_BattleNet.GetAccountInfoByID and C_BattleNet.GetAccountInfoByID(bid)
        local g = acc and acc.gameAccountInfo
        if g and g.isOnline and g.clientProgram == (BNET_CLIENT_WOW or "WoW") then gid = g.gameAccountID end
        if gid and BNSendGameData then
            pcall(BNSendGameData, gid, "OASISND", key)
        else
            ns.print(L["Sound geht nicht: dein Battle.net-Freund ist gerade nicht in WoW."])
            return
        end
    elseif channel == "WHISPER" and target then
        if ns.Radar and ns.Radar.byName and rawget(ns.Radar.byName, ns.fullName(target)) then Comm.Whisper(ns.fullName(target), "SND", key)
        else Comm.SendEx({ ch = "WHISPER", target = Comm.WhisperName(target) }, "SND", key) end
    elseif channel == "PARTY" or channel == "RAID" or channel == "INSTANCE_CHAT" then
        Comm.SendEx({ ch = channel }, "SND", key)
    else
        Comm.Guild("SND", key)
        Pop.Add("sound", key, ns.me())
    end
    -- selbst auch hoeren
    -- 0.5.678: eigene Sounds immer hoeren - "Sounds aus dem Chat" gilt nur fuer Sounds anderer
    if s and s.sound then
        local ok, h = pcall(Sound.PlayChoice, key, s.soundVol)
        -- 0.5.670: WoW spielt die Datei nicht (neu dazugekommen -> erst nach WoW-Neustart bekannt)
        if not (ok and h) and (tonumber(s.soundVol) or 14) > 0 then ns.print(L["Sound nicht abspielbar - neue Sound-Dateien kennt WoW erst nach einem kompletten Neustart."]) end
    elseif s and s.sound == false then
        ns.print(L["Du hoerst den Sound nicht selbst: Sounds sind ausgeschaltet (Einstellungen > Klang & Hinweise > Sound)."])
    end
    -- bei mir selbst als Zeile im Chat zeigen (klickbar zum Anhoeren)
    -- bei mir im passenden Chat zeigen (klickbar zum Anhoeren)
    local whisperTo = (channel == "WHISPER" or channel == "BN_WHISPER") and target
    pcall(Sound.ShowInChat, channel, whisperTo or ns.me(), key, true)
end
-- Battle.net-Sounds empfangen
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, "OASISND") end
ns.On("BN_CHAT_MSG_ADDON", function(prefix, text, _, gid)
    if ns.safe(prefix) ~= "OASISND" then return end
    local key = ns.safe(text)
    if type(key) ~= "string" or not Sound.byKey[key] then return end
    if GetTime() - (Sound.bnPrintAt or -999) < 2 then return end
    Sound.bnPrintAt = GetTime()
    local info = C_BattleNet and C_BattleNet.GetGameAccountInfoByID and C_BattleNet.GetGameAccountInfoByID(ns.safe(gid) or 0)
    local who = info and (info.characterName or info.accountName) or "Battle.net"
    pcall(Sound.OnChatSound, who, "{s:" .. key .. "}")
    pcall(Sound.ShowInChat, "WHISPER", who, key, false)
end)
local sndPrintAt, sndPrintAny = {}, 0
if ns.Comm then
    ns.Comm.On("SND", function(sender, channel, key)
        if type(key) ~= "string" or ns.isMe(sender) then return end
        if ns.SoundMuted and ns.SoundMuted(sender) then return end   -- Sound-Sperre der Gildenleitung
        -- nur bekannte Sounds, und gebremst: sonst kann ein manipulierter Client den Chat mit Zeilen fluten
        if not Sound.byKey[key] or Sound.byKey[key].dev then return end
        local now = GetTime()
        if now - (sndPrintAt[sender] or -999) < 3 or now - sndPrintAny < 1 then return end
        -- Derselbe Sound desselben Charakters nur einmal; gleiche Vornamen bleiben getrennt.
        local dk = ns.NameKey(sender) .. "|" .. key
        if now - (sndPrintAt[dk] or -999) < 8 then return end
        sndPrintAt[dk] = now
        sndPrintAt[sender], sndPrintAny = now, now
        if (channel or "GUILD") == "GUILD" then Pop.Add("sound", key, sender) end
        pcall(Sound.OnChatSound, sender, "{s:" .. key .. "}")
        pcall(Sound.ShowInChat, channel or "GUILD", sender, key, false)
    end)
end
-- Sounds auch aus Fluestern, Gruppe und Schlachtzug abspielen (nur wer dort mitliest, hoert sie)
for _, ev in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    ns.On(ev, function(msg, sender)
        msg = ns.safe(msg)
        if msg and msg:find("{s:", 1, true) then pcall(Sound.OnChatSound, ns.safe(sender) or "", msg) end
    end)
end
local recvAt, recvAny = {}, 0
function Sound.OnChatSound(sender, text)
    local s = S()
    if not s or not s.sound or s.chatSounds == false or ns.isMe(sender) then return end
    if ns.SoundMuted and sender ~= "" and ns.SoundMuted(sender) then return end
    if s.soundQuietCombat and ns.inCombat() then return end
    local key = type(text) == "string" and text:match("{s:([%w_]+)}")
    local c = key and Sound.byKey[key]
    if not c or c.key == "none" or c.dev then return end
    local who = ns.short(sender)
    if s.muteEntrance and s.muteEntrance[who] then return end
    local now = GetTime()
    if now - (recvAt[who] or -999) < Sound.RECV_CD or now - recvAny < 3 then return end
    recvAt[who], recvAny = now, now
    Sound.PlayChoice(key, s.soundVol)
end
-- Anzeige im Chat: {s:key} -> Lautsprecher + Name
function Sound.RenderCodes(text)
    if type(text) ~= "string" or not text:find("{s:", 1, true) then return text end
    return (text:gsub("{s:([%w_]+)}", function(k)
        local c = Sound.byKey[k]
        if not c then return nil end
        local name = L[c.text]:gsub("^Meme: ", ""):gsub("^Oasis: ", "")
        return "|cffe8b44a|Haddon:Oasis:snd:" .. k .. "|h|T" .. ns.MEDIA .. "icons\\speaker:14:14|t " .. name .. "|h|r"
    end))
end
-- Sound-Link angeklickt (Oasis-Chat und Blizzard-Chat): nochmal abspielen
function Sound.OnLink(link)
    local k = type(link) == "string" and link:match("^addon:Oasis:snd:([%w_]+)")
    if not k then return false end
    if Sound.byKey[k] then Sound.Preview(k) end
    return true
end
if hooksecurefunc and SetItemRef then
    hooksecurefunc("SetItemRef", function(link) pcall(Sound.OnLink, link) end)
end
-- Blizzard-Chat: {s:...} als klickbaren Sound-Link zeigen
do
    local function filter(_, _, msg, ...)
        msg = ns.safe(msg)
        if not msg or not msg:find("{s:", 1, true) then return false end
        local new = Sound.RenderCodes(msg)
        if new ~= msg then return false, new, ... end
        return false
    end
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if add then
        for _, ev in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM" }) do
            pcall(add, ev, filter)
        end
    end
end

-- Vorhoeren: der vorherige Probe-Sound stoppt, wenn man den naechsten anklickt
local previewHandle
function Sound.Preview(key, vol)
    if previewHandle and StopSound then for _, h in ipairs(previewHandle) do pcall(StopSound, h, 150) end end
    previewHandle = { Sound.PlayChoice(key, vol) }
    Sound.previewKey, Sound.previewAt = key, GetTime()
end

-- Oasis: Todeswuerfeln (Deathroll)
-- Abwechselnd /roll 1-N, das Ergebnis ist das neue N. Wer die 1 wuerfelt, verliert.
-- Gezaehlt werden die echten Wuerfe aus dem Systemchat (vom Server gewuerfelt).
local ADDON, ns = ...
ns.ModuleFile("Oasis_Deathroll", function()   -- Modul Deathroll (abschaltbar, siehe ModuleLoader.lua)
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

local DR = {}
ns.Deathroll = DR
DR.game = nil

-- Gilden-Optionen (Gildenleitung): Einsaetze, offene Einladungen an die Gilde, Chronik
-- 0.5.912: Standard AUS (Spiele um Gold koennen gegen Blizzard-/Realm-Regeln verstossen) - die Gildenleitung schaltet es bewusst ein
ns.GuildOption({ page = "deathroll", key = "drStake", default = false,
    label = "Einsaetze erlauben", desc = "Spieler duerfen einen Einsatz (z.B. Gold) angeben. Aus: alle Spiele laufen ohne Einsatz. Bitte die Regeln eures Realms zu Gluecksspiel beachten." })
ns.GuildOption({ page = "deathroll", key = "drLobby", default = true,
    label = "Offene Einladungen an die Gilde", desc = "Spieler duerfen sich in die Warteschlange stellen, die die ganze Gilde als Hinweis sieht. Aus: nur direkte Herausforderungen." })
ns.GuildOption({ page = "deathroll", key = "drChron", default = true,
    label = "Siege in die Chronik", desc = "Gewonnene Spiele werden in der Gilden-Chronik eingetragen." })
local function stakeOK(stake)
    if ns.GuildOpt("drStake") ~= true then return "" end
    return SEC.Text(stake, 40)
end

------------------------------------------------------------------------
-- Wurf-Erkennung aus "Mira wuerfelt. Ergebnis: 57 (1-100)"
------------------------------------------------------------------------
local rollPats
local function toPat(fmt)
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)")
    return "^" .. p .. "$"
end
local function buildPattern()
    rollPats = {}
    local seen = {}
    for _, fmt in ipairs({ RANDOM_ROLL_RESULT or "", "%s rolls %d (%d-%d)", "%s würfelt. Ergebnis: %d (%d-%d)" }) do
        if fmt ~= "" and not seen[fmt] then
            seen[fmt] = true
            rollPats[#rollPats + 1] = toPat(fmt)
        end
    end
end

------------------------------------------------------------------------
-- Spielablauf
------------------------------------------------------------------------
local function other(g, name) return name == g.a and g.b or g.a end
-- Ablauf je Spiel (g.state): invite_out/invite_in -> live -> done
--   Nebenwege: invite_out -> noanswer (keine Antwort), live/invite_* -> aborted (Gegner weg, ohne Wertung)
-- Jede Herausforderung hat eine eigene Spiel-ID (g.id); auch Revanche = neue Herausforderung mit neuer ID.
local INVITE_TTL = 60      -- so lange wartet eine Einladung auf Antwort
local TURN_TTL = 90        -- so lange darf der Gegner fuer einen Wurf brauchen, dann Abbruch ohne Wertung
local invPop               -- das eine Einladungs-Fenster (wird wiederverwendet)
DR.seenInv = {}            -- [Spiel-ID] = Zeit: doppelt zugestellte Einladungen verwerfen
DR.scored = {}             -- [Spiel-ID] = true: Wertung (Abzeichen/Chronik/Rangliste) nur einmal
-- angelegte Ausruestung (Item-IDs) fuer das Modell beim Gegner
local GEAR = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18, 19 }
local function myGear()
    local t = {}
    for _, slot in ipairs(GEAR) do
        local id = ns.safe(GetInventoryItemID("player", slot))
        if id then t[#t + 1] = id end
    end
    return table.concat(t, ",")
end
local function sendLook(g, to)
    local raceID, sex = DR.myLook()
    Comm.Whisper(to, "DRLOOK", g.id, raceID, sex, myGear())
end
-- gleicher Spieler? WoW Forever: Systemchat/Gildenliste kennen "Vorname Nachname", Oasis oft nur "Vorname"
local function sameName(a, b) return ns.SameName(a, b) end
DR.SameName = sameName

-- Spiel ohne Wertung beenden (Gegner offline/weg, keine Wuerfe mehr); tell = Gegner Bescheid geben
local function abort(g, why, tell)
    if not g or g.state == "done" or g.state == "aborted" then return end
    local was = g.state
    g.state = "aborted"
    g.abortWhy = why
    if g.watch then g.watch:Cancel() g.watch = nil end
    if tell and not g.bot and not g.manual then Comm.Whisper(other(g, ns.me()), "DRABORT", g.id) end
    C_Timer.After(0, DR.MusicUpdate)
    if was == "invite_in" and invPop and invPop:IsShown() then invPop:Hide() end
    K.Toast(L["Deathroll abgebrochen"], why or L["Das Spiel zaehlt nicht."], C.amber)
    DR.Update()
    ns.RefreshPage("deathroll")
end
DR.Abort = abort
-- Wache fuer laufende Spiele: kommt vom Gegner zu lange nichts, Spiel ohne Wertung beenden
local function watch(g)
    if g.bot or g.manual or g.watch then return end
    g.lastMove = GetTime()
    g.watch = C_Timer.NewTicker(5, function()
        if DR.game ~= g or g.state ~= "live" then
            if g.watch then g.watch:Cancel() g.watch = nil end
            return
        end
        if not ns.isMe(g.turn) and GetTime() - (g.lastMove or GetTime()) > TURN_TTL then
            abort(g, (L["%s wuerfelt nicht mehr - Spiel ohne Wertung beendet."]):format(ns.displayName(other(g, ns.me()))), true)
        end
    end)
end
DR.Watch = watch

local function finish(g)
    if g.state == "done" or g.state == "aborted" then return end
    g.state = "done" C_Timer.After(0, DR.MusicUpdate)
    if g.watch then g.watch:Cancel() g.watch = nil end
    -- Seite sofort aktualisieren (sonst steht dort weiter "Zurueck in den Kampf")
    C_Timer.After(0.1, function() ns.RefreshPage("deathroll") end)
    g.winner = other(g, g.loser)
    local iWon = ns.isMe(g.winner)
    if g.bot then
        ns.Sound.Play(iWon and "dr_win" or "dr_lose")
        DR.Update()
        return
    end
    -- Wuerfe des Gegners kamen nur per Addon-Nachricht (nicht im Systemchat, nicht gegengeprueft):
    -- Ergebnis zaehlt nicht fuer Abzeichen, Chronik und Rangliste.
    -- Leises Wuerfeln: zaehlt nur mit starker Zusage auf beiden Seiten (alte Clients -> ungewertet),
    -- leise Spiele zaehlen, wenn beide Seiten die starke Zusage benutzt haben (sonst ungewertet)
    if g.silent and g.seedsReady and g.weakSeeds then g.unverified = true end
    -- jede Spiel-ID nur einmal werten (Saison/Elo/Abzeichen)
    if DR.scored[g.id] then g.unverified = g.unverified or "twice" end
    DR.scored[g.id] = true
    if g.unverified == true then
        ns.print(L["Deathroll: Ergebnis nicht gewertet - Wuerfe des Gegners waren nicht im Systemchat zu sehen."])
    end
    if ns.Badges and not g.unverified then
        ns.Badges.Add("drPlays", 1)
        if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("drPlays", other(g, ns.me())) end
        if iWon then ns.Badges.Add("drWins", 1) end
        if not iWon then ns.Badges.Add("drLosses", 1) end
        if iWon and (g.start or 0) >= 1000 then ns.Badges.Add("bigWins", 1) end
    end
    if iWon and not g.unverified then
        Store.Put("duels", {
            id = g.id, winner = g.winner, loser = g.loser, start = g.start, stake = g.stake or "", rolls = g.n, ts = ns.now(),
        })
        if ns.Chronicle and ns.GuildOpt("drChron") ~= false then
            local hasStake = (g.stake or "") ~= ""
            ns.Chronicle.Add("duel", "chr-" .. g.id,
                hasStake and "gewinnt Todeswuerfeln gegen %s (ab %s, Einsatz %s)" or "gewinnt Todeswuerfeln gegen %s (ab %s)",
                { ns.short(g.loser), g.start, g.stake })
        end
    end
    ns.Sound.Play(iWon and "dr_win" or "dr_lose") ns.Sound.Next("none")
    K.Toast(iWon and L["Gewonnen!"] or L["Verloren ..."], (iWon and ns.displayName(g.loser) or L["Du"]) .. L[" hat die 1 gewuerfelt."], iWon and C.mint or C.red)
    DR.Update()
    ns.RefreshPage("deathroll")
end

local function apply(who, roll, max, fromNet)
    local g = DR.game
    if not g or g.state ~= "live" then return end
    if not sameName(who, g.turn) or max ~= g.max then return end
    g.n = g.n + 1
    g.lastMove = GetTime()
    table.insert(g.hist, 1, { who = g.turn, roll = roll, max = max })
    if ns.isMe(g.turn) and not fromNet and not g.manual then
        Comm.Whisper(other(g, g.turn), "DRROLL", g.id, g.n, roll, max)
    end
    if DR.AnimRoll then DR.AnimRoll(g, g.turn, max, roll) end
    if roll <= 1 then
        g.loser = g.turn
        g.max = 1
        finish(g)
        return
    end
    g.max = roll
    g.turn = other(g, g.turn)
    if ns.isMe(g.turn) then ns.Sound.Play("dr_turn") end
    DR.Update()
    if g.bot and DR.BotMove then DR.BotMove() end
end
DR.Apply = apply

local offPat
ns.On("CHAT_MSG_SYSTEM", function(text)
    local g = DR.game
    if not g then return end
    text = ns.safe(text)
    if not text then return end
    -- Gegner geht offline -> laufendes Spiel/offene Anfrage ohne Wertung beenden
    if not g.bot and (g.state == "live" or g.state == "invite_out" or g.state == "invite_in") then
        offPat = offPat or toPat(ERR_FRIEND_OFFLINE_S or "%s has gone offline.")
        local who = text:match(offPat)
        if who then
            who = who:gsub("|H.-|h%[?(.-)%]?|h", "%1")
            if sameName(who, other(g, ns.me())) then
                abort(g, (L["%s ist offline gegangen - Spiel ohne Wertung beendet."]):format(ns.displayName(other(g, ns.me()))), false)
                return
            end
        end
    end
    if g.state ~= "live" then return end
    if not rollPats then buildPattern() end
    local who, roll, lo, hi
    for _, pat in ipairs(rollPats) do
        who, roll, lo, hi = text:match(pat)
        if who then break end
    end
    roll, lo, hi = tonumber(roll), tonumber(lo), tonumber(hi)
    if not who then
        -- sieht nach einem Wurf aus, passt aber zu keinem Muster -> fuer die Fehlersuche merken
        if text:find("%(1%-%d+%)") then DR.lastUnmatched = text end
        return
    end
    if not roll or lo ~= 1 then return end
    -- merken; wird der Wurf niemandem zugeordnet, zeigt die Sicherung in DR.Roll den Text an
    DR.lastUnmatched = text
    apply(who, roll, hi, false)
end)

function DR.Challenge(target, start, stake, manual, look)
    if DR.game and (DR.game.state == "live" or DR.game.state == "invite_in") then
        ns.print(L["Es laeuft schon ein Spiel."]) DR.Show() return
    end
    target = ((target or ""):gsub("^%s+", ""):gsub("%s+$", ""))   -- WoW Forever: Leerzeichen im Namen behalten ("Anna Berg")
    if target == "" then target = ns.safe(ns.UnitName("target")) or "" end
    if target == "" then ns.print(L["Gegner angeben oder anvisieren."]) return end
    target = ns.fullName(target)
    -- Addon-Nachrichten kommen unter "Vorname-Realm" an -> Gegner unter dieser Form fuehren, sonst passt der Zug nicht
    do
        local m = ns.Radar and ns.Radar.byName and ns.Radar.byName[target]
        if m then target = m.name end
    end
    if ns.isMe(target) then ns.print(L["Gegen dich selbst? Mutig, aber nein."]) return end
    -- nur eine Anfrage gleichzeitig: offene eigene Anfrage an jemand anderen sperrt
    if DR.game and DR.game.state == "invite_out" and not sameName(DR.game.b, target) then
        ns.print((L["Warte auf Antwort von %s - Klick auf %s zieht zurueck"]):format(ns.displayName(DR.game.b), ns.displayName(DR.game.b)))
        return
    end
    if DR.game and DR.game.state == "invite_out" then return end   -- an denselben schon unterwegs
    -- alte, noch offene eigene Anfrage sauber zuruecknehmen (sonst nimmt der andere ein totes Spiel an)
    do
        local old = DR.game
        if old and not old.manual and not old.bot and (old.state == "invite_out" or old.state == "noanswer") then
            Comm.Whisper(old.b, "DRNO", old.id)
        end
    end
    start = math.max(2, math.min(1000000, tonumber(start) or 100))
    local g = {
        id = ns.newId("dr"), a = ns.me(), b = target, start = start, max = start, turn = ns.me(), n = 0,
        hist = {}, stake = stakeOK(stake), manual = manual and true or false,
        state = manual and "live" or "invite_out", t = GetTime(), look = {},
        silent = (not manual) and DR.SilentWanted(),
    }
    g.look[target] = look
    g.viaGroup = Comm.ViaGroup and Comm.ViaGroup(target) and true or nil
    DR.game = g
    if not manual then
        local race, sex = DR.myLook()
        Comm.Whisper(target, "DRINV", g.id, start, g.stake, race, sex, g.silent and "1" or "0")
        sendLook(g, target)
        ns.After(INVITE_TTL, function()
            if (DR.game == g or DR.outgoing == g) and g.state == "invite_out" then
                g.state = "noanswer"
                DR.Update()
            end
        end)
    end
    DR.Show()
end

function DR.Accept()
    local g = DR.game
    -- nur einmal (Doppelklick, Popup- und Arena-Knopf): danach ist der Zustand "live"
    if not g or g.state ~= "invite_in" then return end
    g.state = "live" C_Timer.After(0, DR.MusicUpdate)
    local race, sex = DR.myLook()
    Comm.Whisper(g.a, "DRACC", g.id, race, sex)
    sendLook(g, g.a)
    -- eigene, geparkte Anfrage an jemand anderen zurueckziehen (nur ein Spiel gleichzeitig)
    local og = DR.outgoing
    if og then
        DR.outgoing = nil
        if og.state == "invite_out" or og.state == "noanswer" then Comm.Whisper(og.b, "DRNO", og.id) end
    end
    DR.StartSeeds(g)
    watch(g)
    if invPop and invPop:IsShown() then invPop:Hide() end
    DR.Update()
end
function DR.Decline()
    local g = DR.game
    if not g then return end
    if g.state == "invite_in" then Comm.Whisper(g.a, "DRNO", g.id) end
    -- eigene Anfrage zurueckziehen: der andere soll sein Einladungsfenster schliessen
    if (g.state == "invite_out" or g.state == "noanswer") and not g.manual and not g.bot then Comm.Whisper(g.b, "DRNO", g.id) end
    if g.watch then g.watch:Cancel() g.watch = nil end
    DR.game = nil
    if invPop and invPop:IsShown() then invPop:Hide() end
    if DR.frame and DR.frame:IsShown() then DR.frame.allowHide = true DR.frame:Hide() end
    if g.state == "invite_in" then DR.RestoreOutgoing() end
end
-- eingehende Einladung erledigt (abgelehnt/zurueckgezogen): eigene geparkte Anfrage wieder aufnehmen
function DR.RestoreOutgoing()
    local og = DR.outgoing
    DR.outgoing = nil
    if og and not DR.game and (og.state == "invite_out" or og.state == "noanswer") then DR.game = og end
end
-- Revanche = neue, normale Herausforderung an denselben Gegner (neue Spiel-ID). Haengt nicht davon ab,
-- ob beim Gegner das Kampffenster noch offen ist: dort erscheint ganz normal das Einladungsfenster.
function DR.Rematch(g)
    g = g or DR.game
    if not g then return end
    if DR.game ~= g and DR.Running() then ns.print(L["Es laeuft schon ein Spiel."]) return end
    local opp = other(g, ns.me())
    local look = g.look and g.look[opp]
    if g.bot then
        DR.game = nil
        DR.StartBot(opp, g.start, g.stake, look and look.race, look and look.sex)
        return
    end
    if not g.manual and ns.Radar and ns.Radar.IsOnline and ns.Radar.IsOnline(opp) == false then
        ns.print((L["%s ist offline - Revanche nicht moeglich."]):format(ns.displayName(opp)))
        return
    end
    if g.state == "invite_out" then return end   -- laeuft schon
    -- DR.game bleibt bis hier stehen: Challenge zieht eine noch offene alte Anfrage (noanswer) sauber zurueck
    DR.Challenge(opp, g.start, g.stake, g.manual, look and { race = look.race, sex = look.sex })
    if DR.game and DR.game ~= g then DR.game.rematch = true DR.Update() end
end
function DR.GoManual()
    local g = DR.game
    if not g then return end
    g.manual, g.state = true, "live"
    DR.Update()
end
------------------------------------------------------------------------
-- Leises Wuerfeln (beide mit Oasis): faire Zufallszahlen ganz ohne /roll im Chat.
-- Jeder waehlt zu Beginn geheim eine Zahl, schickt erst nur ihren Fingerabdruck (Hash), dann die Zahl.
-- Alle Wuerfe = Hash(ZahlA:ZahlB:Wurfnummer) -> keiner kann etwas steuern, jeder Wurf wird gegengeprueft.
------------------------------------------------------------------------
local function newSeed()
    local a = tostring(GetTime()) .. ":" .. tostring(math.random(1, 2147483646)) .. ":" .. tostring(time and time() or 0)
    local b = tostring(debugprofilestop and debugprofilestop() or 0) .. ":" .. tostring(math.random()) .. ":" .. tostring(ns.me())
    return ns.hash(a) .. ns.hash(b)
end
-- Zusage-Pruefsumme fuer leises Wuerfeln: 96 Bit, nichtlinear gemischt (bit.bxor), viele Runden.
-- ns.hash (31 Bit, linear) liess sich faelschen: zwei Seeds mit gleicher Zusage -> nach dem Aufdecken
-- des Gegners den guenstigeren waehlen. Mit dieser Summe ist das praktisch ausgeschlossen.
local bxor = bit and bit.bxor
local function strongHash(str)
    if not bxor then return nil end
    local a, b, c = 0x2545F491, 0x6C078965, 0x5BD1E995
    local M = 4294967296
    for r = 1, 24 do
        for i = 1, #str do
            local x = str:byte(i) + r * 131
            a = (bxor(a, x) * 1000003 + c) % M
            b = (bxor(b, a % 65536) * 999983 + x) % M
            c = (bxor(c, math.floor(b / 65536)) * 1048573 + a) % M
        end
        a, b, c = b, c, a
    end
    return ("%08x%08x%08x"):format(a, b, c)
end
local function commitOf(seed)
    return strongHash("c2:" .. seed) or ns.hash("c:" .. seed)
end
local function silentRoll(g, n)
    local h = tonumber(ns.hash(g.seedA .. ":" .. g.seedB .. ":" .. n), 16) or 0
    return (h % g.max) + 1
end
function DR.SilentWanted() return not ns.db or ns.db.settings.drSilent ~= false end
function DR.StartSeeds(g)
    if not g.silent or g.mySeed then return end
    g.mySeed = newSeed()
    Comm.Whisper(other(g, ns.me()), "DRCOMMIT", g.id, commitOf(g.mySeed))
    -- Gegenseite antwortet nicht (aeltere Oasis-Version) -> ganz normal mit /roll weiter
    ns.After(8, function()
        if DR.game == g and g.state == "live" and not g.seedsReady then g.silent = false DR.Update() end
    end)
end
local function tryReveal(g)
    if g.theirCommit and g.mySeed and not g.revealed then
        g.revealed = true
        Comm.Whisper(other(g, ns.me()), "DRSEED", g.id, g.mySeed)
    end
end
-- Nachricht zu einem Spiel nur vom Gegner selbst (die Spiel-ID laeuft ueber den Gildenkanal und ist nicht geheim)
local function fromOpp(g, sender)
    return g and sender and not g.bot and sameName(sender, other(g, ns.me())) or false
end
DR.FromOpp = fromOpp
Comm.On("DRCOMMIT", function(sender, _, id, commit)
    local g = DR.game
    if not g or g.id ~= id or not g.silent or not fromOpp(g, sender) then return end
    if type(commit) ~= "string" or #commit > 64 or g.theirCommit then return end
    g.theirCommit = commit
    DR.StartSeeds(g)
    tryReveal(g)
end)
Comm.On("DRSEED", function(sender, _, id, seed)
    local g = DR.game
    if not g or g.id ~= id or not g.silent or not g.theirCommit or not fromOpp(g, sender) or g.seedsReady then return end
    if type(seed) ~= "string" or #seed > 128 then return end
    -- alte Gegenseite (kurze, schwache Zusage): Spiel laeuft, zaehlt aber nicht fuer die Rangliste
    local weak = #g.theirCommit <= 8
    local expect = weak and ns.hash("c:" .. (seed or "")) or strongHash("c2:" .. (seed or ""))
    if expect ~= g.theirCommit then
        ns.print(L["Deathroll: Die Wuerfel des Gegners passen nicht - es geht mit /roll weiter."])
        g.silent = false
        DR.Update()
        return
    end
    tryReveal(g)
    local iAmA = ns.isMe(g.a)
    g.seedA = iAmA and g.mySeed or seed
    g.seedB = iAmA and seed or g.mySeed
    g.seedsReady = true
    g.weakSeeds = weak or (#commitOf(g.mySeed) <= 8)
    DR.Update()
end)
DR.SilentRoll = silentRoll

function DR.Roll()
    local g = DR.game
    if DR.anim and GetTime() - (DR.anim.start or 0) > 1.6 then DR.anim = nil end
    if not g or g.state ~= "live" or not ns.isMe(g.turn) or DR.anim then return end
    -- leise: Wurf aus den abgestimmten Zahlen, nichts im Chat
    if g.silent then
        if not g.seedsReady then ns.print(L["Wuerfel werden noch abgestimmt - gleich nochmal."]) return end
        apply(g.turn, silentRoll(g, g.n + 1), g.max, false)
        return
    end
    -- Uebungsspiel leise: einfach selbst wuerfeln (niemand sonst beteiligt)
    if g.bot and DR.SilentWanted() then
        apply(g.turn, DR.BotRandom(g.max), g.max, false)
        return
    end
    local n, max = g.n, g.max
    DR.lastUnmatched = nil
    local roll = RandomRoll or (C_RandomRoll and C_RandomRoll.RandomRoll)
    if not roll then ns.print(L["Wuerfeln ist in diesem Client nicht verfuegbar."]) return end
    ns.Trace("RandomRoll 1-" .. max)
    local ok, e = pcall(roll, 1, max)
    if not ok then ns.err("Deathroll", e) return end
    -- Sicherung: kam kein erkannter Wurf an, Grund im Chat zeigen (hilft bei neuen Sprachen/Namensformen)
    ns.After(3, function()
        if DR.game == g and g.state == "live" and g.n == n and ns.isMe(g.turn) then
            if DR.lastUnmatched then
                ns.print(L["Wurf nicht erkannt:"] .. " |cffffffff" .. DR.lastUnmatched .. "|r")
            else
                ns.print(L["Kein Wurf im Chat angekommen - bitte nochmal wuerfeln."])
            end
        end
    end)
end
function DR.GiveUp()
    local g = DR.game
    if not g or g.state ~= "live" then return end
    if not g.manual and not g.bot then Comm.Whisper(other(g, ns.me()), "DRGIVEUP", g.id) end
    g.loser = ns.me()
    finish(g)
end

Comm.On("DRINV", function(sender, _, id, start, stake, race, sex, silent)
    if type(id) ~= "string" or id == "" or #id > 40 then return end
    if Comm.FromGuild and not Comm.FromGuild(sender) then return end   -- nur Herausforderungen aus der Gilde
    local g = DR.game
    -- dieselbe Einladung doppelt zugestellt (z. B. Gilden- und Gruppenkanal, erneut gesendet): nur einmal auswerten
    if DR.seenInv[id] or (g and g.id == id) then return end
    -- Einladungs-Flut: je Absender hoechstens 1 pro Sekunde (Revanche direkt nach einem kurzen Spiel muss durchgehen;
    -- frueher 15 s -> eine schnelle Revanche wurde still verworfen)
    if not SEC.Rate("drinv:" .. sender, 1) then return end
    DR.seenInv[id] = GetTime()
    -- 0.5.688: Revanche vom letzten Gegner, waehrend das Ergebnis-Fenster offen ist -> direkt dort anzeigen (kein Extra-Fenster)
    local inFrame = g and (g.state == "done" or g.state == "aborted") and sameName(other(g, ns.me()), sender)
        and DR.frame and DR.frame:IsShown() and true or false
    local autoAccept
    -- Kreuzung: beide fordern sich gleichzeitig (z. B. beide klicken Revanche) -> die kleinere Spiel-ID gilt
    if g and (g.state == "invite_out" or g.state == "noanswer") and not g.manual and sameName(g.b, sender) then
        if g.id < id then return end          -- meine Anfrage gilt, der Gegner nimmt sie gleich an
        if g.watch then g.watch:Cancel() g.watch = nil end
        DR.game, g, autoAccept = nil, nil, true   -- seine gilt: meine fallen lassen und seine annehmen
    end
    -- eigene offene Anfrage an jemand anderen: Einladung trotzdem zeigen; wer annimmt, zieht die eigene zurueck
    if g and g.state == "invite_out" and not g.manual and not DR.outgoing then
        DR.outgoing = g
        DR.game, g = nil, nil
    end
    -- laufendes Spiel/schon eine Einladung offen: automatisch ablehnen ("ist gerade in einem Spiel")
    if g and (g.state == "live" or g.state == "invite_in" or g.state == "invite_out") then
        if SEC.Rate("drbusy:" .. sender, 15) then Comm.Whisper(sender, "DRBUSY", id) end
        return
    end
    start = SEC.Num(start, 2, 1000000, true) or 100
    stake = stakeOK(stake)
    DR.game = {
        id = id, a = sender, b = ns.me(), start = start, max = start, turn = sender, n = 0,
        hist = {}, stake = stake or "", state = "invite_in", t = GetTime(),
        look = { [sender] = { race = SEC.Num(race, 0, 200, true), sex = SEC.Num(sex, 0, 3, true) } },
        silent = silent == "1",
        viaGroup = Comm.rawChannel ~= "GUILD" and Comm.rawChannel ~= "OFFICER" or nil,
    }
    DR.LeaveQueue()
    if autoAccept then DR.Accept() DR.Show() return end
    if inFrame then
        DR.game.rematchIn = true
        ns.Sound.Play("dr_invite")
        DR.Update()
        return
    end
    -- selbst ueber die Lobby beigetreten: sofort los
    if DR.pendingJoin and ns.fullName(DR.pendingJoin) == ns.fullName(sender) then
        DR.pendingJoin = nil
        DR.Accept()
        DR.Show()
        return
    end
    -- kleines Fenster: erst annehmen oder ablehnen (das Kampffenster oeffnet sich erst danach)
    ns.Sound.Play("dr_invite")
    -- genau EIN Fenster: ein offenes Kampffenster (z. B. altes Ergebnis) weicht der Einladung
    if DR.frame and DR.frame:IsShown() then DR.frame.allowHide = true DR.frame:Hide() end
    DR.InvitePopup(sender, start, stake)
end)
function DR.InvitePopup(sender, start, stake)
    if not invPop then
        local f = CreateFrame("Frame", "OasisDRInvite", UIParent)
        f:SetSize(340, 128)
        f:SetPoint("TOP", 0, -170)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        K.Fill(f, { 0.05, 0.03, 0.035, 0.97 })
        K.Border(f, C.line)
        f.top = f:CreateTexture(nil, "ARTWORK")
        f.top:SetPoint("TOPLEFT") f.top:SetPoint("TOPRIGHT") f.top:SetHeight(3)
        f.top:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)
        f.glow = f:CreateTexture(nil, "BORDER")
        f.glow:SetAllPoints()
        if not K.Gradient(f.glow, "VERTICAL", { C.red[1], C.red[2], C.red[3], 0 }, { C.red[1], C.red[2], C.red[3], 0.14 }) then f.glow:Hide() end
        f.icon = f:CreateTexture(nil, "ARTWORK")
        f.icon:SetSize(36, 36)
        f.icon:SetPoint("TOPLEFT", 14, -16)
        f.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Dice-Up")
        f.title = K.Title(f, 14, C.text)
        f.title:SetPoint("TOPLEFT", 60, -16)
        f.title:SetPoint("RIGHT", -12, 0)
        f.title:SetWordWrap(false)
        f.sub = K.Text(f, 11, C.muted)
        f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
        f.sub:SetPoint("RIGHT", -12, 0)
        f.timer = K.Bar(f, 312, 2)
        f.timer:SetPoint("BOTTOM", 0, 50)
        f.yes = K.Button(f, L["Annehmen"], 150, 28, "primary", function()
            -- Doppelklick: nur der erste zaehlt
            if f.clicked then return end
            f.clicked = true
            if f.yes.SetEnabledState then f.yes:SetEnabledState(false) end
            local g = DR.game
            if not g or g.id ~= f.gameId or g.state ~= "invite_in" then f:Hide() return end
            DR.Accept()
            f:Hide()
            DR.Show()
        end)
        f.yes:SetPoint("BOTTOMLEFT", 14, 12)
        f.no = K.Button(f, L["Ablehnen"], 150, 28, "ghost", function()
            DR.Decline()
            f:Hide()
        end)
        f.no:SetPoint("BOTTOMRIGHT", -14, 12)
        f:SetScript("OnUpdate", function(self, el)
            local g = DR.game
            -- Restzeit an der Einladung selbst (nicht am Fenster) -> Wiederverwenden setzt nichts falsch
            self.left = g and g.id == self.gameId and (INVITE_TTL - (GetTime() - (g.t or GetTime()))) or 0
            self.timer:Set(math.max(0, self.left / INVITE_TTL))
            -- Herausforderung zurueckgezogen/abgelaufen/andere Einladung
            if self.left <= 0 or not g or g.id ~= self.gameId or g.state ~= "invite_in" then self:Hide() end
        end)
        -- Schliessen (ESC, Zeit abgelaufen) = ablehnen - aber nur genau diese Einladung
        f:SetScript("OnHide", function(self)
            local g = DR.game
            if g and g.id == self.gameId and g.state == "invite_in" then DR.Decline() end
        end)
        ns.EscClose("OasisDRInvite")
        invPop = f
    end
    local f = invPop
    local g = DR.game
    f.gameId = g and g.id
    f.left = INVITE_TTL
    f.clicked = nil
    if f.yes.SetEnabledState then f.yes:SetEnabledState(true) end
    f.title:SetText(ns.displayName(sender) .. L[" fordert dich heraus!"])
    f.sub:SetText(L["Todeswuerfeln ab "] .. start .. ((stake or "") ~= "" and (L[" um "] .. stake) or ""))
    f:Show()
    f:Raise()
    if K.FadeIn then K.FadeIn(f, 0) end
end
Comm.On("DRACC", function(sender, _, id, race, sex)
    -- meine geparkte Anfrage wird angenommen, waehrend eine fremde Einladung offen ist:
    -- die fremde ablehnen, meine Anfrage gilt (nur ein Spiel gleichzeitig)
    local og = DR.outgoing
    if og and og.id == id and fromOpp(og, sender) and (og.state == "invite_out" or og.state == "noanswer") then
        local cur = DR.game
        DR.outgoing = nil
        if cur and cur.state == "invite_in" then
            Comm.Whisper(cur.a, "DRNO", cur.id)
            DR.game = nil
            if invPop and invPop:IsShown() then invPop:Hide() end
        end
        if not DR.game then DR.game = og end
    end
    local g = DR.game
    if not g or g.id ~= id or g.state ~= "invite_out" and g.state ~= "noanswer" then return end
    if not fromOpp(g, sender) then return end
    g.state = "live" C_Timer.After(0, DR.MusicUpdate)
    g.look = g.look or {}
    if race and SEC.Num(race, 0, 200, true) and not (g.look[g.b] and g.look[g.b].race) then
        g.look[g.b] = { race = SEC.Num(race, 0, 200, true), sex = SEC.Num(sex, 0, 3, true) }
        if DR.frame and DR.frame:IsShown() then DR.frame.gameId = nil end
    end
    K.Toast(ns.displayName(sender) .. L[" nimmt an!"], L["Du faengst an: wuerfle 1-"] .. g.max, C.mint)
    DR.StartSeeds(g)
    watch(g)
    -- eigenes Kampffenster inzwischen geschlossen (z. B. bei Revanche)? -> wieder oeffnen
    DR.Show()
end)
Comm.On("DRNO", function(sender, _, id)
    local og = DR.outgoing
    if og and og.id == id and fromOpp(og, sender) then
        DR.outgoing = nil
        K.Toast(ns.displayName(sender) .. L[" kneift"], L["Herausforderung abgelehnt."], C.dim)
        return
    end
    local g = DR.game
    if not g or g.id ~= id or not fromOpp(g, sender) or g.state == "live" or g.state == "done" or g.state == "aborted" then return end
    if g.state == "invite_in" then
        K.Toast(ns.displayName(sender) .. L[" zieht zurueck"], L["Herausforderung zurueckgezogen."], C.dim)
    else
        K.Toast(ns.displayName(sender) .. L[" kneift"], L["Herausforderung abgelehnt."], C.dim)
    end
    local wasIn = g.state == "invite_in"
    DR.game = nil
    if invPop and invPop:IsShown() then invPop:Hide() end
    if DR.frame and DR.frame:IsShown() then DR.frame.allowHide = true DR.frame:Hide() end
    if wasIn then DR.RestoreOutgoing() end
end)
Comm.On("DRBUSY", function(sender, _, id)
    local og = DR.outgoing
    if og and og.id == id and fromOpp(og, sender) then
        DR.outgoing = nil
        K.Toast(ns.displayName(sender) .. L[" spielt gerade schon"], L["Versuch es gleich nochmal."], C.dim)
        return
    end
    local g = DR.game
    if g and g.id == id and fromOpp(g, sender) and (g.state == "invite_out" or g.state == "noanswer") then
        K.Toast(ns.displayName(sender) .. L[" spielt gerade schon"], L["Versuch es gleich nochmal."], C.dim)
        DR.game = nil
        if DR.frame and DR.frame:IsShown() then DR.frame.allowHide = true DR.frame:Hide() end
    end
end)
-- Gegner bricht ab (seine Wache: von mir kam zu lange nichts) -> hier ebenfalls ohne Wertung beenden
Comm.On("DRABORT", function(sender, _, id)
    local g = DR.game
    if not g or g.id ~= id or not fromOpp(g, sender) then return end
    abort(g, (L["%s hat das Spiel abgebrochen - ohne Wertung."]):format(ns.displayName(sender)), false)
end)
-- Gegner verlaesst die Gruppe (Spiel lief ueber den Gruppenkanal) -> Abbruch ohne Wertung
ns.On("GROUP_ROSTER_UPDATE", function()
    local g = DR.game
    if not g or not g.viaGroup or g.bot or g.manual then return end
    if g.state ~= "live" and g.state ~= "invite_out" and g.state ~= "invite_in" then return end
    local opp = other(g, ns.me())
    local s = Comm.WhisperName(opp)
    local inGroup = (UnitInParty and UnitInParty(s)) or (UnitInRaid and UnitInRaid(s))
    local inGuild = ns.Admin and ns.Admin.InGuildList and ns.Admin.InGuildList(opp) == true
    if not inGroup and not inGuild then
        abort(g, (L["%s hat die Gruppe verlassen - Spiel ohne Wertung beendet."]):format(ns.displayName(opp)), false)
    end
end)
-- Sicherung, falls der Systemchat den Wurf nicht zeigt (zu weit weg)
Comm.On("DRROLL", function(sender, _, id, n, roll, max)
    local g = DR.game
    if not g or g.id ~= id or g.state ~= "live" or not fromOpp(g, sender) then return end
    if not sameName(sender, g.turn) then return end
    n, roll, max = SEC.Num(n, 1, 100000, true), SEC.Num(roll, 1, 1000000, true), SEC.Num(max, 1, 1000000, true)
    if not n or not roll or not max or n ~= g.n + 1 or max ~= g.max or roll > max then return end
    if g.silent then
        -- leises Spiel: nur Wuerfe, die zu den abgestimmten Zahlen passen
        if not g.seedsReady then return end
        if roll ~= DR.SilentRoll(g, g.n + 1) then
            ns.print(L["Deathroll: Der Wurf des Gegners stimmt nicht - wird ignoriert."])
            return
        end
        apply(sender, roll, max, true)
        return
    end
    -- normales Spiel: der echte Wurf kommt im Systemchat (vom Server). Nur wenn er dort nicht ankommt
    -- (zu weit weg), die Meldung des Gegners nehmen - dann zaehlt das Spiel nicht fuer Chronik/Rangliste
    local turnN = g.n
    ns.After(3, function()
        if DR.game ~= g or g.state ~= "live" or g.n ~= turnN or not sameName(sender, g.turn) then return end
        g.unverified = true
        apply(sender, roll, max, true)
    end)
end)
Comm.On("DRGIVEUP", function(sender, _, id)
    local g = DR.game
    if not g or g.id ~= id or g.state ~= "live" or not fromOpp(g, sender) then return end
    g.loser = other(g, ns.me())
    finish(g)
end)

------------------------------------------------------------------------
-- Lobby: "Ich will spielen" - wer mag, klickt "Mitspielen" (immer 1 gegen 1)
------------------------------------------------------------------------
DR.queue = {}      -- [name] = { name, start, stake, t, race, sex, demo }
DR.inQueue = nil   -- eigener Eintrag { start, stake, t }
local QUEUE_TTL = 120   -- 0.6.213: 2 Min ohne Lebenszeichen -> raus (Lebenszeichen alle 60 s)

local function myLook()
    local raceID, sex
    if UnitRace then raceID = select(3, UnitRace("player")) end
    if UnitSex then sex = UnitSex("player") end
    return ns.safe(raceID) or 0, (ns.safe(sex) == 3) and 1 or 0
end
DR.myLook = myLook

local function busy()
    local g = DR.game
    return g and (g.state == "live" or g.state == "invite_in" or g.state == "invite_out") or false
end
DR.Running = busy

local function sendQueue()
    if not DR.inQueue then return end
    local race, sex = myLook()
    Comm.Guild("DRQ", DR.inQueue.start, DR.inQueue.stake or "", race, sex)
    if DR.NetBroadcast then DR.NetBroadcast("Q", DR.inQueue.start, DR.inQueue.stake or "", race, sex) end   -- 0.6.213
end
function DR.JoinQueue(start, stake)
    if busy() then ns.print(L["Es laeuft schon ein Spiel."]) return end
    if ns.GuildOpt("drLobby") == false then ns.print(L["Die Gildenleitung hat offene Einladungen abgeschaltet - fordere jemanden direkt heraus."]) return end
    DR.inQueue = { start = math.max(2, math.min(1000000, tonumber(start) or 100)), stake = stakeOK(stake), t = ns.now() }
    if DR.NetJoin then DR.NetJoin(DR.inQueue.start) end   -- 0.6.213: Stufen-Kanal passend zum Startwert (aus dem Klick)
    sendQueue()
    K.Toast(L["Du wartest auf einen Gegner"], L["Die Gilde sieht deine Einladung. Sobald jemand mitspielt, geht es los."], C.accent)
    ns.RefreshPage("deathroll")
end
function DR.LeaveQueue(silent)
    if not DR.inQueue then return end
    DR.inQueue = nil
    if not silent then Comm.Guild("DRQX") if DR.NetBroadcast then DR.NetBroadcast("X") end end
    ns.RefreshPage("deathroll")
end
function DR.Waiting()
    local out, now = {}, ns.now()
    for name, q in pairs(DR.queue) do
        if now - q.t < QUEUE_TTL or q.demo then out[#out + 1] = q else DR.queue[name] = nil end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

local function onQueue(sender, start, stake, race, sex, viaNet)
    if ns.GuildOpt("drLobby") == false then return end
    stake = stakeOK(stake)
    start = SEC.Num(start, 2, 1000000, true) or 100
    -- Warteschlange begrenzen (verwaiste Eintraege raus, hoechstens 40 Wartende)
    if not DR.queue[sender] then
        local n = #DR.Waiting()
        if n >= 40 then return end
    end
    -- Hinweis/Ton je Absender hoechstens alle 2 Minuten (DRQX + DRQ im Wechsel waere sonst eine Toast-Flut)
    local isNew = not DR.queue[sender] and SEC.Rate("drq:" .. sender, 120)
    local inGuild = not viaNet or (Comm.FromGuild and Comm.FromGuild(sender))
    DR.queue[sender] = { name = sender, start = tonumber(start) or 100, stake = stake or "", t = ns.now(), race = SEC.Num(race, 0, 200, true), sex = SEC.Num(sex, 0, 3, true), net = (viaNet and not inGuild) or nil }
    -- Hinweis/Ton nur fuer Gildenmitglieder - Fremde aus dem Netz stehen still in der Liste (keine Toast-Flut)
    if isNew and inGuild and not busy() and not DR.inQueue and ns.db.settings.drOpenInvites ~= false then
        ns.Sound.Next("dr_invite")
        K.Toast(ns.displayName(sender) .. L[" will Deathroll spielen"], (L["ab %s - klick zum Mitspielen"]):format(start or "100"), C.accent,
            function() DR.JoinGame(sender) end)
    end
    ns.RefreshPage("deathroll")
end
Comm.On("DRQ", function(sender, _, start, stake, race, sex) onQueue(sender, start, stake, race, sex, false) end)
Comm.On("DRQX", function(sender)
    DR.queue[sender] = nil
    ns.RefreshPage("deathroll")
end)

------------------------------------------------------------------------
-- 0.6.213: Todeswuerfel-Netz - gildenuebergreifende Lobby ueber einen versteckten Kanal je Einsatzstufe.
-- Sparsam fuer viele Spieler: gesendet wird nur bei Aenderung (suche / fertig) plus ein Lebenszeichen alle 60 s;
-- jeder fuehrt die Liste selbst (2 Min ohne Lebenszeichen -> raus). Wer neu im Kanal ist, fragt EINMAL "wer sucht?",
-- antworten tun nur die Suchenden selbst, per Fluestern. Man ist immer nur in EINEM Stufen-Kanal (Kanal-Grenze 10).
-- Die Gilden-Lobby (DRQ ueber den Gildenkanal) laeuft zusaetzlich weiter. Abschaltbar: Einstellung drNet.
------------------------------------------------------------------------
local NET_PREFIX, NET_PASS = "OASDR1", "oasisdr"
local NET_TIERS = { { max = 1000, ch = "OasisDRklein" }, { max = 10000, ch = "OasisDRmittel" }, { max = math.huge, ch = "OasisDRhoch" } }
DR.net = { chan = nil, sent = 0, recv = 0, kinds = {} }
local function netOn() return ns.db and ns.db.settings.drNet ~= false and ns.GuildOpt("drLobby") ~= false end
local function tierChan(start)
    start = tonumber(start) or 100
    for _, t in ipairs(NET_TIERS) do if start <= t.max then return t.ch end end
    return NET_TIERS[1].ch
end
DR.NetTierChan = tierChan
local function chanIdOf(name)
    local id = GetChannelName and ns.safe((GetChannelName(name)))
    return (type(id) == "number" and id > 0) and id or nil
end
-- eigene Drossel: hoechstens 1 Nachricht je 1,2 s, Schlange max. 20; im Kampf nichts senden
local netQ = {}
local function netPack(kind, ...)
    local t = { kind }
    for i = 1, select("#", ...) do t[#t + 1] = (tostring((select(i, ...)) or ""):gsub("\t", " ")) end
    return table.concat(t, "\t"):sub(1, 240)
end
local function netPush(item) if #netQ >= 20 then table.remove(netQ, 1) end netQ[#netQ + 1] = item end
C_Timer.NewTicker(1.2, function()
    local it = netQ[1]
    if not it or (ns.inCombat and ns.inCombat()) then return end
    table.remove(netQ, 1)
    local ok
    if it.to then
        ok = pcall(C_ChatInfo.SendAddonMessage, NET_PREFIX, it.msg, "WHISPER", it.to)
    else
        local id = DR.net.chan and chanIdOf(DR.net.chan)
        if id then ok = pcall(C_ChatInfo.SendAddonMessage, NET_PREFIX, it.msg, "CHANNEL", id) end
    end
    if ok then DR.net.sent = DR.net.sent + 1 DR.net.lastSent = GetTime() DR.net.lastSentMsg = it.msg:sub(1, 1) .. (it.to and " (Fluestern)" or "") end
end)
local function netBroadcast(kind, ...) if DR.net.chan and netOn() then netPush({ msg = netPack(kind, ...) }) end end
local function netWhisper(to, kind, ...) if netOn() then netPush({ msg = netPack(kind, ...), to = (Comm.WhisperName and Comm.WhisperName(to)) or to }) end end
DR.NetBroadcast = netBroadcast
-- in den passenden Stufen-Kanal (alten verlassen); nach dem Beitritt einmal "wer sucht?"
function DR.NetJoin(start)
    if not netOn() or not JoinTemporaryChannel or (IsLoggedIn and not IsLoggedIn()) then return end
    local want = tierChan(start)
    if DR.net.chan == want and chanIdOf(want) then return true end
    -- 0.6.216: Kanal besteht schon (bleibt ueber /reload erhalten) -> sofort uebernehmen statt neu beitreten
    if chanIdOf(want) and DR.net.chan ~= want then
        for n, q in pairs(DR.queue) do if q.net then DR.queue[n] = nil end end
        DR.net.chan = want
        DR.net.joinTry = { ch = want, t = GetTime(), had = true }
        netBroadcast("W")
        if DR.inQueue then
            local race, sex = myLook()
            netBroadcast("Q", DR.inQueue.start, DR.inQueue.stake or "", race, sex)
        end
        return true
    end
    if DR.net.joinTry and DR.net.joinTry.ch == want and GetTime() - DR.net.joinTry.t < 20 then return end
    for _, t in ipairs(NET_TIERS) do
        if t.ch ~= want and chanIdOf(t.ch) and LeaveChannelByName then pcall(LeaveChannelByName, t.ch) end
    end
    DR.net.joinTry = { ch = want, t = GetTime() }
    if not chanIdOf(want) then pcall(JoinTemporaryChannel, want, NET_PASS) end
    C_Timer.After(3, function()
        if chanIdOf(want) then
            local fresh = DR.net.chan ~= want
            DR.net.chan = want
            -- neue Stufe: Netz-Eintrage der alten Stufe weg
            if fresh then for n, q in pairs(DR.queue) do if q.net then DR.queue[n] = nil end end end
            netBroadcast("W")
            if DR.inQueue then
                local race, sex = myLook()
                netBroadcast("Q", DR.inQueue.start, DR.inQueue.stake or "", race, sex)
            end
        end
    end)
end
DR.NetQueueLen = function() return #netQ end
DR.NetChanId = chanIdOf
DR.NET_TIERS = NET_TIERS
function DR.NetLeave()
    for _, t in ipairs(NET_TIERS) do if chanIdOf(t.ch) and LeaveChannelByName then pcall(LeaveChannelByName, t.ch) end end
    DR.net.chan = nil
    for n, q in pairs(DR.queue) do if q.net then DR.queue[n] = nil end end
end
pcall(C_ChatInfo.RegisterAddonMessagePrefix, NET_PREFIX)
-- Empfang (ausgelagert, damit er sich testen laesst)
function DR.NetReceive(text, sender)
    if not netOn() then return end
    sender, text = ns.safe(sender), ns.safe(text)
    if type(sender) ~= "string" or type(text) ~= "string" or ns.isMe(sender) then return end
    if not SEC.Rate("drnet:" .. sender, 1) then return end   -- hoechstens 1 Nachricht je Sekunde je Absender
    local kind, a, b, c, d = strsplit("\t", text)
    DR.net.recv = DR.net.recv + 1
    DR.net.lastRecv, DR.net.lastFrom = GetTime(), sender
    DR.net.kinds[kind or "?"] = (DR.net.kinds[kind or "?"] or 0) + 1
    if kind == "Q" then
        onQueue(sender, a, b, c, d, true)
    elseif kind == "X" then
        if DR.queue[sender] then DR.queue[sender] = nil ns.RefreshPage("deathroll") end
    elseif kind == "W" then
        -- nur Suchende antworten, per Fluestern an den Fragenden (keine Flut im Kanal)
        if DR.inQueue and SEC.Rate("drnetw:" .. sender, 30) then
            local race, sex = myLook()
            netWhisper(sender, "Q", DR.inQueue.start, DR.inQueue.stake or "", race, sex)
        end
    end
end
ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
    if ns.safe(prefix) == NET_PREFIX then DR.NetReceive(text, sender) end
end)
-- Kanal-Meldungen ("Kanal betreten" ...) nicht im Chat zeigen
do
    local function ours(...)
        for i = 1, select("#", ...) do
            local v = ns.safe((select(i, ...)))
            if type(v) == "string" and v:find("OasisDR", 1, true) then return true end
        end
        return false
    end
    local add = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if add then
        for _, ev in ipairs({ "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "CHAT_MSG_CHANNEL", "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE" }) do
            pcall(add, ev, function(_, _, ...) return ours(...) end)
        end
    end
end
ns.On("PLAYER_ENTERING_WORLD", function() C_Timer.After(10, function() DR.NetJoin(DR.inQueue and DR.inQueue.start or 100) end) end)
-- 0.6.216: das Modul wird oft erst NACH dem Einloggen geladen (PLAYER_ENTERING_WORLD schon vorbei) -> selbst anstossen
C_Timer.After(8, function() DR.NetJoin(DR.inQueue and DR.inQueue.start or 100) end)

-- 0.6.214: /oa drnetz - zeigt, ob der Kanal verbunden ist und wer drin sucht.
-- /oa drnetz join = jetzt beitreten (Tastatur-Eingabe zaehlt als Klick), /oa drnetz frag = "wer sucht?" senden
ns.slash.drnetz = function(rest)
    rest = tostring(rest or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local function out(t) ns.print("|cffe8b44a[DR-Netz]|r " .. t) end
    if rest == "join" then
        DR.net.joinTry = nil
        DR.NetJoin(DR.inQueue and DR.inQueue.start or 100)
        out("Beitritt angestossen - in 3 Sekunden nochmal /oa drnetz")
        return
    elseif rest == "frag" then
        if not DR.net.chan then out("Nicht verbunden - erst /oa drnetz join") return end
        DR.NetBroadcast("W")
        out("\"Wer sucht?\" gesendet - Antworten kommen per Fluestern")
        return
    end
    local now = GetTime()
    local function ago(t) return t and ("vor %d s"):format(now - t) or "nie" end
    out(("Schalter: %s   Gilden-Lobby erlaubt: %s"):format(netOn() and "|cff66db9ean|r" or "|cffe06060aus|r", tostring(ns.GuildOpt("drLobby") ~= false)))
    local want = tierChan(DR.inQueue and DR.inQueue.start or 100)
    local parts = {}
    for _, t in ipairs(NET_TIERS) do
        local id = chanIdOf(t.ch)
        parts[#parts + 1] = (id and "|cff66db9e" or "|cff888888") .. t.ch .. (id and (" #" .. id) or " -") .. "|r"
    end
    out("Kanaele: " .. table.concat(parts, "   "))
    out(("Verbunden mit: %s   gewuenscht: %s   letzter Beitrittsversuch: %s"):format(
        DR.net.chan and ("|cff66db9e" .. DR.net.chan .. "|r") or "|cffe06060keinem|r", want,
        DR.net.joinTry and (DR.net.joinTry.ch .. " " .. ago(DR.net.joinTry.t)) or "nie"))
    local k = {}
    for kk, v in pairs(DR.net.kinds) do k[#k + 1] = kk .. "=" .. v end
    out(("Gesendet: %d (zuletzt %s %s)   Empfangen: %d (zuletzt %s von %s)   Arten: %s   Warteschlange: %d"):format(
        DR.net.sent, DR.net.lastSentMsg or "", ago(DR.net.lastSent), DR.net.recv, ago(DR.net.lastRecv),
        DR.net.lastFrom and ns.displayName(DR.net.lastFrom) or "-", #k > 0 and table.concat(k, " ") or "-", #netQ))
    out(DR.inQueue and ("Du suchst selbst: ab %s%s"):format(DR.inQueue.start, (DR.inQueue.stake or "") ~= "" and (", Einsatz " .. DR.inQueue.stake) or "") or "Du suchst gerade nicht.")
    local list = DR.Waiting()
    if #list == 0 then out("Niemand sucht gerade (weder Gilde noch Netz).") return end
    out(("%d suchen:"):format(#list))
    for _, q in ipairs(list) do
        out(("  %s  ab %s%s  |cff888888%s, %s|r"):format(ns.displayName(q.name), q.start, (q.stake or "") ~= "" and (", " .. q.stake) or "",
            q.demo and "Demo" or (q.net and "Netz" or "Gilde"), ("vor %d s"):format(ns.now() - (q.t or ns.now()))))
    end
end
ns.slash.drnet = ns.slash.drnetz

-- einem Wartenden beitreten
function DR.JoinGame(host)
    local q = DR.queue[host]
    if not q then ns.print(L["Die Einladung ist nicht mehr da."]) return end
    if busy() then ns.print(L["Es laeuft schon ein Spiel."]) return end
    DR.LeaveQueue()
    if q.demo then
        DR.queue[host] = nil
        DR.StartBot(host, q.start, q.stake, q.race, q.sex)
        return
    end
    DR.pendingJoin = host
    local race, sex = myLook()
    Comm.Whisper(host, "DRJOIN", race, sex)
    K.Toast(L["Anfrage gesendet"], (L["Warte auf %s ..."]):format(ns.displayName(host)), C.dim)
    ns.After(20, function() if DR.pendingJoin == host then DR.pendingJoin = nil end end)
end
Comm.On("DRJOIN", function(sender, _, race, sex)
    if not DR.inQueue or busy() then Comm.Whisper(sender, "DRFULL") return end
    local q = DR.inQueue
    DR.LeaveQueue()
    DR.Challenge(sender, q.start, q.stake, false, { race = SEC.Num(race, 0, 200, true), sex = SEC.Num(sex, 0, 3, true) })
end)
Comm.On("DRFULL", function(sender)
    if DR.pendingJoin == sender then
        DR.pendingJoin = nil
        DR.queue[sender] = nil
        K.Toast(ns.displayName(sender) .. L[" spielt schon"], L["Jemand anderes war schneller."], C.dim)
        ns.RefreshPage("deathroll")
    end
end)

-- Uebungsspiel gegen einen Demo-Gegner (wuerfelt selbst, nichts wird gespeichert oder gesendet)
function DR.StartBot(name, start, stake, race, sex)
    if busy() then return end
    local opp = ns.fullName(L[name or "Uebungspuppe"])
    local g = {
        id = ns.newId("drb"), a = ns.me(), b = opp, start = tonumber(start) or 100, max = tonumber(start) or 100, turn = ns.me(), n = 0,
        hist = {}, stake = stake or "", manual = true, bot = true, state = "live", t = GetTime(),
        look = { [opp] = { race = race or 2, sex = sex or 0, f = DR.FIGHTERS[math.random(2, #DR.FIGHTERS)].key } },
    }
    DR.game = g
    DR.Show()
end
local seed = (time and time() or 0) + math.floor((GetTime() % 1) * 1e6)
local function botRandom(max)
    seed = (seed * 1103515245 + 12345) % 2147483648
    local r = (math.random() + seed / 2147483648 + (GetTime() * 7.13) % 1) % 1
    return math.min(max, 1 + math.floor(r * max))
end
DR.BotRandom = botRandom
function DR.BotMove()
    local g = DR.game
    if not g or not g.bot or g.state ~= "live" or ns.isMe(g.turn) then return end
    ns.After(1.2 + math.random() * 0.8, function()
        if DR.game == g and g.state == "live" and not ns.isMe(g.turn) then
            DR.Apply(g.turn, botRandom(g.max), g.max, true)
        end
    end)
end

------------------------------------------------------------------------
-- Kaempferauswahl (wie bei Tekken): jeder waehlt eine Figur, der Gegner sieht genau dieses Modell.
-- "me" = der eigene Charakter. Sonst bekannte Figuren aus Classic (Kreatur-IDs, im Spiel vorhanden).
-- zoom/dist/y: Kamera je Figur (grosse Modelle weiter weg).
------------------------------------------------------------------------
DR.FIGHTERS = {
    { key = "me", name = "Dein Charakter", sub = "So wie du gerade aussiehst" },
    { key = "thrall", npc = 4949, disp = 4527, name = "Thrall", sub = "Kriegshaeuptling der Horde" },
    { key = "cairne", npc = 3057, disp = 4307, name = "Cairne Bluthuf", sub = "Hochhaeuptling der Tauren", dist = 1.2 },
    { key = "sylvanas", npc = 10181, disp = 11657, name = "Sylvanas", sub = "Die Bansheekoenigin" },
    { key = "voljin", npc = 10540, disp = 10357, name = "Vol'jin", sub = "Anfuehrer der Dunkelspeere", zoom = 0, dist = 1.1, y = 0 },
    { key = "grunt", npc = 3296, disp = 4259, name = "Grunzer", sub = "Wache von Orgrimmar" },
    { key = "mankrik", npc = 3432, disp = 3855, name = "Mankrik", sub = "Sucht immer noch seine Frau" },
    { key = "hogger", npc = 448, disp = 384, name = "Hogger", sub = "Schrecken des Waldes von Elwynn" },
    { key = "vancleef", npc = 639, disp = 2029, name = "Edwin VanCleef", sub = "Boss der Defias" },
    { key = "murloc", npc = 285, disp = 617, name = "Murloc", sub = "Mrrglglglgl!" },
    { key = "kobold", npc = 6, disp = 10913, name = "Kobold", sub = "Du nix Kerze nehmen!" },
    -- (Gnoll sah aus wie Hogger -> ersetzt)
    { key = "theradras", npc = 12201, name = "Prinzessin Theradras", sub = "Maraudon", zoom = 0, dist = 1.1, y = 0, fdist = 1.9 },
    { key = "ogre", npc = 2562, disp = 1052, name = "Oger", sub = "Felsfaust-Oger", dist = 1.3 },
    { key = "rattlegore", npc = 11622, disp = 12073, name = "Blutrippe", sub = "Scholomance", dist = 1.4, fdist = 1.6 },
    { key = "onyxia", npc = 10184, disp = 8570, name = "Onyxia", sub = "Brutmutter der Schwarzdrachen", zoom = 0, dist = 1, y = 0, fdist = 1.8 },
    { key = "ragnaros", npc = 11502, disp = 11121, name = "Ragnaros", sub = "Der Feuerfuerst", zoom = 0, dist = 1, y = 0, fdist = 1.8 },
    -- ab hier: per Gildenrang (Oasis-Rang 1-100) freigeschaltet - je hoeher, desto absurder
    { key = "chicken", npc = 620, name = "Huhn", sub = "Gack. Gack gack.", rank = 3, zoom = 0, dist = 1, y = 0 },
    { key = "sheep", npc = 1933, name = "Schaf", sub = "Hat schon mal einen Magier getroffen", rank = 6, zoom = 0, dist = 1, y = 0 },
    { key = "rabbit", npc = 721, name = "Kaninchen", sub = "Toedlicher als es aussieht", rank = 9, zoom = 0, dist = 1, y = 0 },
    { key = "cow", npc = 2442, name = "Kuh", sub = "Muuuh.", rank = 12, zoom = 0, dist = 1, y = 0 },
    { key = "frog", npc = 1420, name = "Kroete", sub = "Wartet auf einen Kuss", rank = 15, zoom = 0, dist = 1, y = 0 },
    { key = "prairiedog", npc = 2620, name = "Praeriehund", sub = "Schaut nur kurz raus", rank = 18, zoom = 0, dist = 1, y = 0 },
    { key = "gazlowe", npc = 3391, name = "Gazlowe", sub = "Boss von Ratschet - alles hat seinen Preis", rank = 22 },
    { key = "leper", npc = 6223, name = "Lepragnom", sub = "Gnomeregan war mal schoen", rank = 26 },
    { key = "mukla", npc = 1559, name = "Koenig Mukla", sub = "Herrscher der Schlingendorn-Affen", rank = 30, dist = 1.1 },
    { key = "golem", npc = 36, name = "Erntegolem", sub = "Westfall, Ernte 1. Klasse", rank = 35, dist = 1.1 },
    { key = "bigglesworth", npc = 16998, name = "Mr. Bigglesworth", sub = "Kel'Thuzads Katze. Wehe dir.", rank = 40, zoom = 0, dist = 1, y = 0 },
    { key = "hakkar", npc = 14834, name = "Hakkar", sub = "Der Seelenschinder", rank = 50, zoom = 0, dist = 1, y = 0, fdist = 1.6 },
    { key = "kazzak", npc = 12397, name = "Lord Kazzak", sub = "Hoellenfeuer und gute Laune", rank = 60, zoom = 0, dist = 1, y = 0, fdist = 1.6 },
    { key = "nefarian", npc = 11583, name = "Nefarian", sub = "Herr des Pechschwingenhorts", rank = 70, zoom = 0, dist = 1, y = 0, fdist = 1.8 },
    { key = "cthun", npc = 15727, name = "C'Thun", sub = "Du wirst sterben.", rank = 80, zoom = 0, dist = 1, y = 0, fdist = 1.8 },
    { key = "kelthuzad", npc = 15990, name = "Kel'Thuzad", sub = "Erzlich von Naxxramas", rank = 90, zoom = 0, dist = 1, y = 0, fdist = 1.5 },
    -- Hoechster Rang: ein Stuhl. Wer alles erreicht hat, muss niemandem mehr etwas beweisen.
    { key = "chair", name = "Ein Stuhl", sub = "Hoechster Rang. Du hast es dir verdient: Hinsetzen.", rank = 100, zoom = 0, dist = 1, y = 0, fdist = 1.2,
      -- Datei-IDs (wago.tools): Gasthaus-Stuhl, einfacher Stuhl, Zwergenstuhl, Tauren-Holzstuhl
      model = { 198114, 198116, 198115, 197300, 200393 } },
}
-- Figur freigeschaltet? (rank = noetiger Oasis-Rang)
function DR.Unlocked(fi)
    if not fi or not fi.rank then return true end
    local ok, me = pcall(function() return ns.Rank and ns.Rank.Mine() end)
    return ok and me and (me.level or 0) >= fi.rank or false
end
local FBY = {}
for _, fi in ipairs(DR.FIGHTERS) do FBY[fi.key] = fi end
function DR.Fighter(key) return FBY[key or "me"] or FBY.me end
function DR.MyFighter()
    local k = (ns.db and ns.db.settings.drFighter) or "me"
    if FBY[k] and not DR.Unlocked(FBY[k]) then return "me" end
    return k
end
function DR.SetMyFighter(key)
    if not FBY[key] or not DR.Unlocked(FBY[key]) then return end
    ns.db.settings.drFighter = key
    local g = DR.game
    if g then
        g.look = g.look or {}
        g.look[ns.me()] = g.look[ns.me()] or {}
        g.look[ns.me()].f = key
        if not g.bot and not g.manual and (g.state == "live" or g.state == "invite_out" or g.state == "invite_in") then
            Comm.Whisper(other(g, ns.me()), "DRFIGHT", g.id, key)
        end
        if DR.frame and DR.frame:IsShown() then DR.frame.gameId = nil DR.Show() end
    end
    ns.RefreshPage("deathroll")
end
Comm.On("DRFIGHT", function(sender, _, id, key)
    local g = DR.game
    if not g or g.id ~= id or not FBY[key] or not fromOpp(g, sender) then return end
    local opp = other(g, ns.me())
    g.look = g.look or {}
    g.look[opp] = g.look[opp] or {}
    g.look[opp].f = key
    if DR.frame and DR.frame:IsShown() then DR.frame.gameId = nil DR.Show() end
end)
-- Figur in ein Modell laden: erst ueber die Display-ID (geht immer), sonst ueber die Kreatur
function DR.LoadFighter(m, fi)
    pcall(m.ClearModel, m)
    if fi.key == "me" then pcall(m.SetUnit, m, "player") return end
    if fi.model then
        for _, path in ipairs(fi.model) do
            if pcall(m.SetModel, m, path) then
                local okm, id = pcall(m.GetModelFileID, m)
                if okm and id and id ~= 0 then return end
            end
        end
        -- kein Stuhl gefunden: ein sitzender Zwerg tut es auch
        pcall(m.SetCreature, m, 1872)
        return
    end
    local ok = fi.disp and m.SetDisplayInfo and pcall(m.SetDisplayInfo, m, fi.disp)
    if not ok and fi.npc then pcall(m.SetCreature, m, fi.npc) end
    -- nichts geladen? Kreatur nachschieben (aeltere Clients ohne SetDisplayInfo)
    C_Timer.After(0.3, function()
        local okm, id = pcall(m.GetModelFileID, m)
        if (not okm or not id or id == 0) and fi.npc then pcall(m.SetCreature, m, fi.npc) end
    end)
end
-- Kamera fuer eine Figur einstellen
function DR.ApplyCam(m, fi, facing, full)
    -- full = ganze Figur (Kampffenster), sonst Portrait-Ausschnitt; zoom = 0 bei der Figur: immer ganz
    if full then
        pcall(m.SetPortraitZoom, m, 0)
        pcall(m.SetCamDistanceScale, m, (fi and (fi.fdist or fi.dist) or 1) * 1.1)
        pcall(m.SetPosition, m, 0, 0, fi and fi.fy or 0)
        if facing then pcall(m.SetFacing, m, facing) end
        return
    end
    pcall(m.SetPortraitZoom, m, (fi and fi.zoom) or 0.55)
    pcall(m.SetCamDistanceScale, m, fi and fi.dist or 1)
    pcall(m.SetPosition, m, 0, 0, fi and fi.y or -0.08)
    if facing then pcall(m.SetFacing, m, facing) end
end

------------------------------------------------------------------------
-- Auswahl-Fenster: links grosse Vorschau, rechts Raster mit allen Kaempfern
------------------------------------------------------------------------
local picker
-- Musik: im Menue leise Hintergrundmusik, im Kampf eine von vier Kampfmusiken (Schleife)
-- Kampfmusik liegt nur lokal in Media\music (nicht im Paket) - fehlt sie, bleibt es still
local GM = "Interface\\AddOns\\Oasis_Guild\\Media\\"   -- 0.5.728: Kampfmusik liegt im Gildenmodul (Oasis_Guild); fehlt es, bleibt es still
local MUSIC_BG = { file = GM .. "sounds\\drmusic.ogg", len = 105 }
local FIGHT = {
    { file = GM .. "music\\fight1.ogg", len = 233 }, { file = GM .. "music\\fight2.ogg", len = 179 },
    { file = GM .. "music\\fight3.ogg", len = 214 }, { file = GM .. "music\\fight4.ogg", len = 97 },
    { file = GM .. "sounds\\amoktime.ogg", len = 9.03 },   -- Kampfmusik aus dem Gildenmodul (laeuft in Schleife)
}
local AMOK = FIGHT[#FIGHT]
local musicHandle, musicTimer, musicPage, musicMode, fightTrack
local musicHandle2   -- zweite Kopie der Kaempferwahl-Musik (lauter)
local function stopMusic(fade)
    if type(musicHandle) == "number" and StopSound then StopSound(musicHandle, fade or 800) end
    if type(musicHandle2) == "number" and StopSound then StopSound(musicHandle2, fade or 800) end
    musicHandle, musicHandle2 = nil, nil
    if musicTimer then musicTimer:Cancel() musicTimer = nil end
end
function DR.MusicUpdate()
    local s = ns.db and ns.db.settings
    -- Musik-Lautstaerke 0-5: 0 aus, 1-3 leisere Dateien (_1.._3), 4 normal, 5 normal doppelt (Standard)
    local mv = tonumber(s and s.drMusicVol) or 5
    local on = s and s.sound ~= false and s.drMusic ~= false and mv > 0
    local g = DR.game
    local mode
    if on and DR.frame and DR.frame:IsShown() and g and g.state == "live" then mode = "fight"
    -- Hintergrundmusik nur noch in der Kaempferwahl, Fenster zu = aus
    elseif on and picker and picker:IsShown() then mode = "bg" end
    if mode ~= musicMode then stopMusic(mode and 400 or 800) musicMode = mode end
    if mode and not musicHandle then
        local tr = MUSIC_BG
        if mode == "fight" then
            fightTrack = fightTrack or FIGHT[math.random(#FIGHT)]
            tr = fightTrack
        end
        local file = mv >= 4 and tr.file or tr.file:gsub("%.ogg$", "_" .. mv .. ".ogg")
        local ok, willPlay, h = pcall(PlaySoundFile, file, "Master")
        -- lokale Kampfmusik fehlt (nicht im Paket): statt Stille "Amok Time" nehmen
        if mode == "fight" and tr ~= AMOK and not (ok and willPlay) then
            fightTrack, tr = AMOK, AMOK
            file = mv >= 4 and tr.file or tr.file:gsub("%.ogg$", "_" .. mv .. ".ogg")
            ok, willPlay, h = pcall(PlaySoundFile, file, "Master")
        end
        if ok and willPlay then
            musicHandle = h or true
            -- Stufe 5: zweite Kopie gleichzeitig = deutlich lauter
            if mv >= 5 then
                local ok2, w2, h2 = pcall(PlaySoundFile, file, "Master")
                if ok2 and w2 then musicHandle2 = h2 end
            end
            -- Fenster verlassen (Alt-Tab) stoppt bei manchen Einstellungen alle Toene: dann neu starten
            if not DR.musicWatch and C_Sound and C_Sound.IsPlaying then
                DR.musicWatch = C_Timer.NewTicker(2, function()
                    if musicMode and type(musicHandle) == "number" then
                        local okP, playing = pcall(C_Sound.IsPlaying, musicHandle)
                        if okP and playing == false then stopMusic(0) DR.MusicUpdate() end
                    end
                end)
            end
            musicTimer = C_Timer.NewTimer(tr.len, function() musicHandle = nil DR.MusicUpdate() end)
        else
            -- Datei fehlt (z.B. noch kein Neustart nach dem Update): in 30 s nochmal versuchen
            musicHandle = true
            musicTimer = C_Timer.NewTimer(30, function() musicHandle = nil DR.MusicUpdate() end)
        end
    end
    if mode ~= "fight" then fightTrack = nil end
end
function DR.RestartMusic() stopMusic(200) musicMode = nil DR.MusicUpdate() end
local function buildPicker()
    local f = CreateFrame("Frame", "OasisFighterSelect", UIParent)
    f:SetSize(784, 576)
    f:SetPoint("CENTER", 0, 30)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true) f:EnableMouse(true) f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    K.Fill(f, { 0.02, 0.02, 0.025, 0.98 })
    K.Border(f, C.line)
    local top = f:CreateTexture(nil, "ARTWORK")
    top:SetPoint("TOPLEFT", 1, -1) top:SetPoint("TOPRIGHT", -1, -1) top:SetHeight(3)
    top:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)
    f.title = K.Title(f, 20, C.text)
    f.title:SetPoint("TOPLEFT", 20, -16)
    f.title:SetText(K.Upper(L["Waehle deinen Kaempfer"]))
    local close = K.CloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    -- Vorschau links (Buehne mit Lichtkegel)
    local stage = CreateFrame("Frame", nil, f)
    stage:SetPoint("TOPLEFT", 16, -50)
    stage:SetSize(270, 510)
    K.Fill(stage, { 0.05, 0.02, 0.02, 1 })
    local light = stage:CreateTexture(nil, "BACKGROUND", nil, 2)
    light:SetTexture(ns.MEDIA .. "shine")
    light:SetPoint("CENTER", 0, -20) light:SetSize(380, 380)
    light:SetVertexColor(C.red[1], C.red[2], C.red[3])
    light:SetAlpha(0.35)
    f.big = CreateFrame("PlayerModel", nil, stage)
    f.big:SetPoint("TOPLEFT", 0, -10) f.big:SetPoint("BOTTOMRIGHT", 0, 76)
    -- leuchtende Plattform unter der Figur
    local plat = stage:CreateTexture(nil, "BACKGROUND", nil, 3)
    plat:SetTexture(ns.MEDIA .. "dr\\platform")
    plat:SetSize(280, 110)
    plat:SetPoint("BOTTOM", 0, 52)
    plat:SetBlendMode("ADD")
    plat:SetVertexColor(1, 0.35, 0.25, 0.8)
    -- 0.6.209: Gildenmodul: Ritualkreis im Thronsaal als Buehne, Figur steht auf dem Kreis; Lichtkegel/Plattform aus
    if ns.GuildPack then
        stage.art = stage:CreateTexture(nil, "BACKGROUND", nil, 1)
        if K.BgImg then K.BgImg(stage.art) end   -- 0.6.227: Helligkeit einstellbar
        stage.art:SetAllPoints()
        stage.art:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\dr_pick_bg")
        light:Hide() plat:Hide()
        f.big:ClearAllPoints()
        -- 0.6.238: Figur 70 tiefer, damit sie auf dem Ritualkreis steht (schwebte darueber)
        f.big:SetPoint("TOPLEFT", 0, -80) f.big:SetPoint("BOTTOMRIGHT", 0, 26)
    end
    f.bigName = K.Title(stage, 20, C.text, "CENTER")
    f.bigName:SetPoint("BOTTOM", 0, 40)
    f.bigName:SetWidth(260)
    f.bigSub = K.Text(stage, 11, C.muted, "CENTER")
    f.bigSub:SetPoint("TOP", f.bigName, "BOTTOM", 0, -4)
    f.bigSub:SetWidth(260)
    for _, fs in ipairs({ f.bigName, f.bigSub }) do if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) fs:SetShadowOffset(1, -1) end end
    f.big:SetScript("OnUpdate", function(self, el) self.r = ((self.r or 0) + el * 0.6) % (math.pi * 2) pcall(self.SetFacing, self, self.r) end)
    -- Raster rechts: 6 Spalten, freigeschaltete Figuren zuerst sortiert wie in DR.FIGHTERS
    f.tiles = {}
    local TW, TH, GAP = 72, 70, 6
    for i, fi in ipairs(DR.FIGHTERS) do
        local col, row = (i - 1) % 6, math.floor((i - 1) / 6)
        local t = CreateFrame("Button", nil, f)
        t:SetSize(TW, TH)
        t:SetPoint("TOPLEFT", 302 + col * (TW + GAP), -50 - row * (TH + GAP))
        K.Fill(t, { 0.07, 0.07, 0.08, 1 })
        K.Border(t, C.line)
        t:SetClipsChildren(true)
        t.glow = t:CreateTexture(nil, "BORDER")
        t.glow:SetTexture(ns.MEDIA .. "shine")
        t.glow:SetPoint("CENTER", 0, 6) t.glow:SetSize(150, 150)
        t.glow:SetBlendMode("ADD")
        t.glow:SetVertexColor(C.red[1], C.red[2], C.red[3])
        t.glow:SetAlpha(0)
        t.nameBg = t:CreateTexture(nil, "ARTWORK")
        t.nameBg:SetPoint("BOTTOMLEFT", 1, 1) t.nameBg:SetPoint("BOTTOMRIGHT", -1, 1) t.nameBg:SetHeight(18)
        t.nameBg:SetColorTexture(0, 0, 0, 0.55)
        t.m = CreateFrame("PlayerModel", nil, t)
        t.m:SetPoint("TOPLEFT", 2, -2) t.m:SetPoint("BOTTOMRIGHT", -2, 18)
        t.n = K.Text(t, 10, C.text, "CENTER")
        t.n:SetPoint("BOTTOM", 0, 4)
        t.n:SetWidth(TW - 6)
        t.n:SetText(L[fi.name])
        t.fi = fi
        -- gesperrt: abgedunkelt, Schloss + noetiger Rang
        if fi.rank then
            t.lock = CreateFrame("Frame", nil, t)
            t.lock:SetAllPoints()
            t.lock:SetFrameLevel(t.m:GetFrameLevel() + 5)
            t.lock.bg = t.lock:CreateTexture(nil, "BACKGROUND")
            t.lock.bg:SetPoint("TOPLEFT", 1, -1) t.lock.bg:SetPoint("BOTTOMRIGHT", -1, 19)
            t.lock.bg:SetColorTexture(0.02, 0.02, 0.025, 0.78)
            t.lock.ico = t.lock:CreateTexture(nil, "ARTWORK")
            t.lock.ico:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
            t.lock.ico:SetSize(18, 22)
            t.lock.ico:SetPoint("CENTER", 0, 8)
            t.lock.txt = K.Text(t.lock, 10, C.muted, "CENTER")
            t.lock.txt:SetPoint("TOP", t.lock.ico, "BOTTOM", 0, -3)
            t.lock.txt:SetText((L["ab Rang %d"]):format(fi.rank))
        end
        t:SetScript("OnEnter", function(self) f:Preview(self.fi) K.SetBorderColor(self, C.amber) self.glow:SetAlpha(0.35) end)
        t:SetScript("OnLeave", function(self) f:Preview(DR.Fighter(DR.MyFighter())) f:Mark() end)
        t:SetScript("OnClick", function(self)
            if not DR.Unlocked(self.fi) then
                pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_ABANDON_QUEST) or 846, "SFX")
                return
            end
            DR.SetMyFighter(self.fi.key)
            f:Mark()
            pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856, "SFX")
            f:Hide()   -- ein Klick = gewaehlt
        end)
        f.tiles[i] = t
    end
    f.ok = K.Button(f, L["Bereit!"], 200, 34, "primary", function() f:Hide() end)
    f.ok:Hide()   -- Auswahl per Klick auf eine Figur
    f.ok:SetPoint("BOTTOMRIGHT", -16, 16)
    f.hint = K.Text(f, 10, C.dim)
    f.hint:SetPoint("BOTTOMLEFT", 302, 26)
    f.hint:SetPoint("RIGHT", -16, 0)
    f.hint:SetWordWrap(true)
    f.hint:SetText(L["Klick auf eine Figur waehlt sie. Dein Gegner sieht genau diese Figur."])
    function f:Load(m, fi, facing, full)
        m.fi, m.facing, m.full = fi, facing, full
        DR.LoadFighter(m, fi)
        DR.ApplyCam(m, fi, facing, full)
        if not m.hooked then
            m.hooked = true
            m:SetScript("OnModelLoaded", function(self) DR.ApplyCam(self, self.fi, self.facing, self.full) end)
        end
    end
    function f:Preview(fi)
        -- grosse Vorschau: immer die ganze Figur (Kopf bis Fuss), grosse Kreaturen weiter weg
        self:Load(self.big, fi, nil, true)
        C_Timer.After(0.35, function() if self.big.fi == fi then DR.ApplyCam(self.big, fi, nil, true) end end)
        self.bigName:SetText(K.Upper(L[fi.name]))
        if DR.Unlocked(fi) then self.bigSub:SetText(L[fi.sub])
        else self.bigSub:SetText("|cffff6655" .. (L["Gesperrt - freigeschaltet ab Oasis-Rang %d"]):format(fi.rank) .. "|r") end
    end
    function f:Mark()
        local cur = DR.MyFighter()
        for _, t in ipairs(self.tiles) do
            local on = t.fi.key == cur
            K.SetBorderColor(t, on and C.red or C.line)
            t.glow:SetAlpha(on and 0.45 or 0)
            if t.lock then t.lock:SetShown(not DR.Unlocked(t.fi)) end
        end
    end
    f:HookScript("OnShow", function(self) self:Mark() end)
    ns.EscClose("OasisFighterSelect")
    picker = f
    -- 0.6.210: derselbe Bild-Rahmen wie Hauptfenster und /oa start (abschaltbar ueber "Verzierter Fensterrahmen")
    if ns.GuildPack and K.ImageFrame then
        local ok, fr = pcall(K.ImageFrame, f, 0.3)
        if ok and fr then f.imageFrame = fr if K.ApplyFrameStyle then K.ApplyFrameStyle(f) end end
    end
    -- 0.6.208: 3D-Modelle verschiedener Fenster stoeren sich, wenn sie uebereinander liegen (das obere wirkt
    -- loechrig/durchsichtig, besonders beim Verschieben). Solange die Auswahl offen ist, Modelle im Hauptfenster aus.
    local hidden = {}
    local function walk(fr, depth)
        if not fr or depth > 14 or not fr.GetChildren then return end
        for _, c in ipairs({ fr:GetChildren() }) do
            local t = c.GetObjectType and c:GetObjectType()
            if (t == "PlayerModel" or t == "DressUpModel" or t == "CinematicModel" or t == "ModelScene") and c:IsShown() then
                c:Hide()
                hidden[#hidden + 1] = c
            else
                walk(c, depth + 1)
            end
        end
    end
    -- 0.6.211: auch direkt aus DR.ShowPicker (ein neu erzeugter Frame ist schon "sichtbar" -> erstes OnShow fehlt)
    function f.HideBehind()
        if #hidden > 0 then return end
        -- bekannte Figur der Todeswuerfel-Seite immer, dazu alle weiteren Modelle im Hauptfenster
        local pg = ns.PageDef and ns.PageDef("deathroll")
        local fm = pg and pg.frame and pg.frame.fcard and pg.frame.fcard.m
        if fm and fm:IsShown() then fm:Hide() hidden[#hidden + 1] = fm end
        local m = ns.MainFrame and ns.MainFrame()
        if m then walk(m, 0) end
    end
    f:HookScript("OnShow", f.HideBehind)
    f:HookScript("OnHide", function()
        for _, c in ipairs(hidden) do c:Show() end
        wipe(hidden)
    end)
    f:HookScript("OnShow", function() C_Timer.After(0, DR.MusicUpdate) end)
    f:HookScript("OnHide", function() C_Timer.After(0, DR.MusicUpdate) end)
    return f
end
function DR.ShowPicker()
    -- vor dem Bauen pruefen: ein neu erzeugter Frame ist sofort "sichtbar" -> sonst nie Sound beim ersten Oeffnen
    local was = picker ~= nil and picker:IsShown()
    local f = picker or buildPicker()
    f:Show()
    if f.HideBehind then f.HideBehind() end
    -- wie bei Smash Bros: "Choose your character!" beim Oeffnen der Kaempferwahl
    if not was and ns.Sound and ns.Sound.PlayChoice then
        local s = ns.db and ns.db.settings
        if s and s.sound ~= false then
            -- immer laut: volle Lautstaerke plus zweite Kopie gleichzeitig (Stufe 20 = doppelt)
            local ok, h = pcall(ns.Sound.PlayLoud or ns.Sound.PlayChoice, "smash", 20)
            if not (ok and h) then
                pcall(PlaySound, (SOUNDKIT and SOUNDKIT.PVP_THROUGH_QUEUE) or 8459, "Master")
                if not DR.smashHint then
                    DR.smashHint = true
                    ns.print(L["Kaempferwahl-Sound konnte nicht abgespielt werden - neue Sound-Dateien kennt WoW erst nach einem kompletten Neustart (nicht /reload)."])
                end
            end
        end
    end
    f:Raise()
    -- ein neu gebauter Frame ist schon "sichtbar" -> OnShow kommt beim ersten Oeffnen nicht: Musik direkt starten
    C_Timer.After(0, DR.MusicUpdate)
    for _, t in ipairs(f.tiles) do f:Load(t.m, t.fi, 0.4) end
    f:Preview(DR.Fighter(DR.MyFighter()))
    f:Mark()
end
ns.slash.kaempfer = function() DR.ShowPicker() end

------------------------------------------------------------------------
-- Arena: das Spielfenster (Modelle links/rechts, HP-Balken, fallende Wuerfel)
------------------------------------------------------------------------
local W, H = 780, 460
local ANIM = { roll = 2, win = 64, lose = 1, stand = 0, ready = 26 }

-- Einheit fuer einen Namen suchen (Ziel, Gruppe, Maus) - dann zeigt das Modell die echte Ausruestung
local function unitFor(name)
    if ns.isMe(name) then return "player" end
    local toks = { "target", "focus", "mouseover" }
    for i = 1, 4 do toks[#toks + 1] = "party" .. i end
    if IsInRaid and IsInRaid() then for i = 1, 40 do toks[#toks + 1] = "raid" .. i end end
    for _, t in ipairs(toks) do
        if UnitExists(t) and UnitIsPlayer(t) then
            local n = ns.safe(GetUnitName(t, true))
            if n and (ns.fullName(n) == ns.fullName(name) or Comm.whoKey(n) == Comm.whoKey(name)) then return t end   -- Vorname reicht (Doppelnamen)
        end
    end
end

-- Ersatzfigur je Volk (Stadtwachen aus Classic), wenn der Gegner nicht als Einheit greifbar ist
local RACE_NPC = { [1] = 68, [2] = 3296, [3] = 5595, [4] = 4262, [5] = 5624, [6] = 3084, [7] = 5595, [8] = 3296 }
local DUMMY_NPC = 3296   -- Grunzer von Orgrimmar

local function hasModel(m)
    local ok, id = pcall(m.GetModelFileID, m)
    return ok and id and id ~= 0
end

-- Klassensymbol statt Modell (wenn WoW kein Modell liefert)
local function showClassIcon(side, name)
    side.model:Hide()
    side.noModel:Show()
    local cls = ns.Radar.ClassOf(name)
    local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
    if tc then
        side.noModel:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
        side.noModel:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        side.noModel:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        side.noModel:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end
local function setModel(side, name, look, bot)
    local m = side.model
    m:Show()
    side.noModel:Hide()
    pcall(m.ClearModel, m)
    -- gewaehlte Figur (Kaempferauswahl) hat Vorrang
    local fi = look and look.f and look.f ~= "me" and DR.Fighter(look.f)
    if fi and fi.npc then
        DR.LoadFighter(m, fi)
        side.fi = fi
        DR.ApplyCam(m, fi, side.facing, true)
        side.name = name
        if not side.hooked then
            side.hooked = true
            m:SetScript("OnModelLoaded", function(self)
                if side.fi then DR.ApplyCam(self, side.fi, side.facing, true) return end
                pcall(self.SetPortraitZoom, self, 0)
                pcall(self.SetPosition, self, 0, 0, 0)
                pcall(self.SetFacing, self, side.facing)
            end)
        end
        return
    end
    side.fi = nil
    local unit = not bot and unitFor(name)
    local npc = (look and RACE_NPC[look.race or 0]) or DUMMY_NPC
    if unit then
        pcall(m.SetUnit, m, unit)
    elseif bot then
        pcall(m.SetCreature, m, npc)
    elseif look and look.race and look.race > 0 then
        if m.SetCustomRace then pcall(m.SetCustomRace, m, look.race, look.sex or 0) end
        -- KEINE Ausruestung anziehen: laedt WoW statt des Charakters ein anderes Modell, stuerzt das Spiel ab
        -- (ASSERT "armor2 on non-armor2 model", 30.09.)
        -- klappt das Volksmodell nicht, Ersatzfigur nehmen
        ns.After(0.2, function()
            if side.name ~= name or hasModel(m) then return end
            pcall(m.SetCreature, m, npc)
            -- auch die Ersatzfigur fehlt (z.B. Forever-Client): Klassensymbol zeigen
            ns.After(0.4, function() if side.name == name and not hasModel(m) then showClassIcon(side, name) end end)
        end)
    elseif m.SetCreature then
        pcall(m.SetCreature, m, DUMMY_NPC)
    else
        m:Hide()
        side.noModel:Show()
        local cls = ns.Radar.ClassOf(name)
        local tc = cls and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls]
        if tc then
            side.noModel:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
            side.noModel:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        else
            side.noModel:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            side.noModel:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    -- Oberkoerper: leicht herangezoomt, Kamera etwas tiefer
    pcall(m.SetPortraitZoom, m, 0.55)
    pcall(m.SetCamDistanceScale, m, 1)
    pcall(m.SetPosition, m, 0, 0, -0.08)
    pcall(m.SetFacing, m, side.facing)
    side.name = name
    if not side.hooked then
        side.hooked = true
        m:SetScript("OnModelLoaded", function(self)
            if side.fi then DR.ApplyCam(self, side.fi, side.facing) return end
            pcall(self.SetPortraitZoom, self, 0.55)
            pcall(self.SetPosition, self, 0, 0, -0.08)
            pcall(self.SetFacing, self, side.facing)
        end)
    end
end

local function anim(side, id)
    if side.model:IsShown() then pcall(side.model.SetAnimation, side.model, id) end
end

-- 0.5.698: Spannung / Farben fuer den Kampfbildschirm
-- TENSION-BEGIN
-- Spannung 0..1 aus dem verbleibenden Wurfbereich: ab 30 % der Startzahl steigend, unter 10 sehr hoch
local function tension(max, start)
    max, start = tonumber(max) or 100, math.max(1, tonumber(start) or 100)
    local t = math.max(0, math.min(1, (0.30 - max / start) / 0.27))
    if max <= 10 then t = math.max(t, 0.75 + (10 - max) / 40) end
    return math.min(1, t)
end
local function lerpc(a, b, k) return a + (b - a) * k end
-- Zahlenfarbe: weiss -> bernstein -> rot mit der Spannung
local function numColor(max, start)
    if (tonumber(max) or 100) <= 1 then return 1, 0.25, 0.25 end
    local t = tension(max, start)
    if t < 0.5 then local k = t / 0.5 return 1, lerpc(1, 0.78, k), lerpc(1, 0.35, k) end
    local k = (t - 0.5) / 0.5
    return 1, lerpc(0.78, 0.28, k), lerpc(0.35, 0.22, k)
end
-- Balkenfarbe: Klassenfarbe, bei wenig Leben (unter 45 %) Richtung Rot, unter 25 % pulsierend
local function hpColor(base, ratio, t)
    local d = math.max(0, math.min(1, (0.45 - ratio) / 0.30))
    if d <= 0 then return base[1], base[2], base[3] end
    local pulse = d > 0.8 and (0.88 + 0.12 * math.sin(t * 9)) or 1
    return lerpc(base[1], 0.95, d) * pulse, lerpc(base[2], 0.2, d) * pulse, lerpc(base[3], 0.18, d) * pulse
end
-- TENSION-END
DR.Tension, DR.NumColor, DR.HpColor = tension, numColor, hpColor
-- Sprueche der Uebungspuppe, wenn sie eine Revanche will (je nachdem, wer gewonnen hat)
local BOT_TAUNT_WIN = { "Das war nur Glueck! Nochmal!", "Noch eine Runde - ich will meine Ehre zurueck!",
    "Revanche! Diesmal gewinne ich.", "Beim naechsten Wurf siehst du alt aus!" }
local BOT_TAUNT_LOSS = { "Zu leicht. Traust du dich nochmal?", "Hihi - noch eine Runde?",
    "Schon fertig? Ich will Revanche!", "Gewinnen ist einfach. Nochmal?" }
DR.BOT_TAUNTS = { win = BOT_TAUNT_WIN, loss = BOT_TAUNT_LOSS }

local function sideFrame(f, left)
    -- Modell als Hintergrund: gross, Oberkoerper, links schaut nach rechts, rechts nach links
    local s = CreateFrame("Frame", nil, f)
    s:SetFrameLevel(f:GetFrameLevel() + 1)
    s:SetPoint("TOP", f, "TOP", 0, -30)
    s:SetPoint("BOTTOM", f, "BOTTOM", 0, 1)
    s:SetPoint(left and "LEFT" or "RIGHT", f, left and "LEFT" or "RIGHT", left and 1 or -1, 0)
    s:SetWidth(330)
    s.glow = s:CreateTexture(nil, "BACKGROUND", nil, 1)
    s.glow:SetTexture(ns.MEDIA .. "shine")
    s.glow:SetPoint("CENTER", 0, -20)
    s.glow:SetSize(420, 420)
    s.glow:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    s.glow:SetAlpha(0)
    -- leuchtende Plattform unter dem Kaempfer (Farbe je Seite)
    s.plat = s:CreateTexture(nil, "BACKGROUND", nil, 3)
    s.plat:SetTexture(ns.MEDIA .. "dr\\platform")
    s.plat:SetSize(250, 110)
    s.plat:SetPoint("BOTTOM", 0, 28)
    s.plat:SetBlendMode("ADD")
    local pc = left and { 0.35, 0.6, 1 } or { 1, 0.35, 0.3 }
    s.plat:SetVertexColor(pc[1], pc[2], pc[3], 0.85)
    s.platT = 0
    s:HookScript("OnUpdate", function(self, el)
        self.platT = self.platT + el
        self.plat:SetAlpha(0.55 + 0.25 * math.sin(self.platT * 2.2 + (left and 0 or 1.5)))
    end)
    s.model = CreateFrame("PlayerModel", nil, s)
    s.model:SetAllPoints()
    -- Treffer-Blitz: rote Flaeche ueber der Seite, blendet in 0,4 s aus
    s.hit = s:CreateTexture(nil, "OVERLAY", nil, 1)
    s.hit:SetAllPoints()
    s.hit:SetColorTexture(1, 0.15, 0.1, 1)
    s.hit:SetAlpha(0)
    -- zur Mitte hin ausblenden, damit Wuerfel und Zahl frei stehen
    s.fade = s:CreateTexture(nil, "OVERLAY")
    s.fade:SetColorTexture(1, 1, 1, 1)
    s.fade:SetPoint("TOP")
    s.fade:SetPoint("BOTTOM")
    s.fade:SetPoint(left and "RIGHT" or "LEFT")
    s.fade:SetWidth(120)
    local ok = CreateColor and pcall(function()
        local dark, clear = CreateColor(0.025, 0.025, 0.028, 1), CreateColor(0.025, 0.025, 0.028, 0)
        if left then s.fade:SetGradient("HORIZONTAL", clear, dark) else s.fade:SetGradient("HORIZONTAL", dark, clear) end
    end)
    if not ok then s.fade:Hide() end
    if f.artMode then
        s.plat:Hide() s.plat.SetAlpha = function() end
        s.fade:Hide()
        s.model:ClearAllPoints()
        s.model:SetPoint("TOPLEFT", 0, 0) s.model:SetPoint("BOTTOMRIGHT", 0, 112)   -- Fuesse auf dem Leuchtkreis
    end
    s.noModel = s:CreateTexture(nil, "ARTWORK")
    s.noModel:SetSize(110, 110)
    s.noModel:SetPoint("CENTER", left and -20 or 20, 10)
    s.noModel:SetAlpha(0.5)
    s.noModel:Hide()
    s.facing = left and 0.7 or -0.7
    -- Namensschild + HP-Balken oben
    local top = CreateFrame("Frame", nil, f)
    top:SetFrameLevel(f:GetFrameLevel() + 10)
    top:SetSize(290, 50)
    top:SetPoint(left and "TOPLEFT" or "TOPRIGHT", left and 20 or -20, -48)
    s.top = top
    s.nameText = K.Title(top, 16, C.text, left and "LEFT" or "RIGHT")
    s.nameText:SetPoint(left and "TOPLEFT" or "TOPRIGHT", 0, 0)
    s.turn = K.Text(top, 11, C.accent, left and "RIGHT" or "LEFT")
    s.turn:SetPoint(left and "TOPRIGHT" or "TOPLEFT", 0, -3)
    s.bar = CreateFrame("Frame", nil, top)
    s.bar:SetPoint("TOPLEFT", 0, -22)
    s.bar:SetPoint("TOPRIGHT", 0, -22)
    s.bar:SetHeight(18)
    K.Fill(s.bar, C.field)
    K.Border(s.bar, C.line)
    s.lag = s.bar:CreateTexture(nil, "ARTWORK", nil, 1)
    s.lag:SetColorTexture(1, 0.85, 0.4, 0.9)
    s.fill = s.bar:CreateTexture(nil, "ARTWORK", nil, 2)
    for _, t in ipairs({ s.lag, s.fill }) do
        t:SetPoint("TOP", 0, -1)
        t:SetPoint("BOTTOM", 0, 1)
        t:SetPoint(left and "LEFT" or "RIGHT", left and 1 or -1, 0)
    end
    s.hpText = K.Title(s.bar, 12, C.text, "CENTER")
    s.hpText:SetPoint("CENTER", 0, 0)
    s.hpText:SetDrawLayer("OVERLAY", 7)
    s.left = left
    s.hp, s.shown, s.lagV = 1, 1, 1
    -- schwebende Schadenszahl
    s.dmg = K.Title(top, 22, C.red, "CENTER")
    s.dmg:SetPoint("TOP", top, "BOTTOM", left and -40 or 40, -6)
    s.dmg:SetAlpha(0)
    return s
end

local function setBar(s, v, instant)
    s.hp = math.max(0, math.min(1, v))
    if instant then s.shown, s.lagV = s.hp, s.hp end
end


-- 0.6.224: Seite im Ornament-Stil: kein "Am Zug"-Text - stattdessen leuchtet die Namensplatte des Spielers am Zug;
-- HP-Balken mit Leistentextur (Farbe per Vertexfarbe), wanderndem Glanz und leichtem Schimmer an der Kante
function DR.ArtSide(f, sd)
    if not (f and f.artMode and sd and sd.top) then return end
    local top = sd.top
    -- "Am Zug" + Pille weg
    sd.turn:SetAlpha(0) sd.turn.SetAlpha = function() end
    sd.turn:SetText("") sd.turn.SetText = function() end
    if sd.turnPill then sd.turnPill:Hide() sd.turnPill.Show = function() end end
    -- leuchtende Platte (dieselbe Platte additiv darueber), pulsiert sanft, solange diese Seite am Zug ist
    if not top.glowBg and top.bg then
        top.glowBg = top:CreateTexture(nil, "BACKGROUND", nil, -1)
        top.glowBg:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\" .. "dr_plate")
        top.glowBg:SetAllPoints(top.bg)
        top.glowBg:SetBlendMode("ADD")
        top.glowBg:SetAlpha(0)
        top.halo = top:CreateTexture(nil, "BACKGROUND", nil, -3)
        top.halo:SetTexture(ns.MEDIA .. "softglow")
        top.halo:SetBlendMode("ADD")
        top.halo:SetPoint("TOPLEFT", top.bg, "TOPLEFT", -30, 22) top.halo:SetPoint("BOTTOMRIGHT", top.bg, "BOTTOMRIGHT", 30, -22)
        top.halo:SetVertexColor(1, 0.45, 0.15)
        top.halo:SetAlpha(0)
        local cur, t = 0, 0
        top:HookScript("OnUpdate", function(self, el)
            t = t + el
            local want = sd.active and 1 or 0
            cur = cur + (want - cur) * math.min(1, el * 5)
            local pulse = (ns.db and ns.db.settings.noAnim) and 1 or (0.75 + 0.25 * math.sin(t * 3))
            self.glowBg:SetAlpha(0.55 * cur * pulse)
            self.halo:SetAlpha(0.5 * cur * pulse)
        end)
    end
    -- HP-Balken: Textur statt Flaeche; Farbe kommt weiter aus der Spiel-Logik (SetColorTexture -> Vertexfarbe)
    if not sd.bar.artDone then
        sd.bar.artDone = true
        for _, t in ipairs({ sd.fill, sd.lag }) do
            t:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
            t.SetColorTexture = function(self, r, g, b, a) self:SetVertexColor(r, g, b, a or 1) end
        end
        sd.fill:SetVertexColor(0.9, 0.3, 0.35, 1)
        sd.lag:SetVertexColor(1, 0.85, 0.4, 0.9)
        -- Glanz, der durch die Fuellung wandert
        local clip = CreateFrame("Frame", nil, sd.bar)
        clip:SetPoint("TOPLEFT", sd.fill, "TOPLEFT") clip:SetPoint("BOTTOMRIGHT", sd.fill, "BOTTOMRIGHT")
        if clip.SetClipsChildren then clip:SetClipsChildren(true) end
        clip:SetFrameLevel(sd.bar:GetFrameLevel() + 1)
        local sh = clip:CreateTexture(nil, "OVERLAY")
        sh:SetTexture(ns.MEDIA .. "shine") sh:SetBlendMode("ADD")
        sh:SetSize(60, 30) sh:SetVertexColor(1, 0.95, 0.85) sh:SetAlpha(0.35)
        -- heller Saum an der Kante der Fuellung
        local edge = sd.bar:CreateTexture(nil, "OVERLAY", nil, 6)
        edge:SetTexture(ns.MEDIA .. "softglow") edge:SetBlendMode("ADD")
        edge:SetSize(18, 26) edge:SetVertexColor(1, 0.8, 0.6)
        edge:SetPoint("CENTER", sd.fill, sd.left and "RIGHT" or "LEFT", 0, 0)
        local t = 0
        clip:SetScript("OnUpdate", function(self, el)
            if ns.db and ns.db.settings.noAnim then sh:Hide() edge:SetAlpha(0.5) return end
            t = (t + el) % 3
            local w = self:GetWidth() or 0
            sh:Show()
            sh:ClearAllPoints()
            local x = -60 + (w + 120) * (t / 3)
            if sd.left then sh:SetPoint("CENTER", self, "LEFT", x, 0) else sh:SetPoint("CENTER", self, "RIGHT", -x, 0) end
            edge:SetAlpha(0.45 + 0.25 * math.sin(t * 4))
        end)
        sd.hpText:SetDrawLayer("OVERLAY", 7)
        if sd.hpText.SetShadowColor then sd.hpText:SetShadowColor(0, 0, 0, 1) sd.hpText:SetShadowOffset(1, -1) end
    end
end
local function build()
    local f = CreateFrame("Frame", "OasisDeathrollFrame", UIParent)
    f:SetSize(W, H)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    K.Fill(f, { 0.025, 0.025, 0.028, 0.98 })
    K.Border(f, C.line)
    -- Arena: Steinwand mit Fackeln, Bodenplatten, Lichtkegel (eigene Grafik)
    f.arena = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    if K.BgImg then K.BgImg(f.arena) end   -- 0.6.227: Helligkeit einstellbar
    f.arena:SetPoint("TOPLEFT", 1, -1)
    f.arena:SetPoint("BOTTOMRIGHT", -1, 1)
    f.arena:SetTexture(ns.MEDIA .. "dr\\arena")
    f.arena:SetAlpha(0.95)
    -- 0.6.219: Gildenmodul: Thronsaal-Arena mit eigenem Rahmen (aussen transparent), zwei Leuchtkreise fuer die Kaempfer
    if ns.GuildPack then
        f.arena:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\dr_game_bg")
        f.arena:ClearAllPoints() f.arena:SetAllPoints()
        f.arena:SetAlpha(1)
        f.artMode = true
        for _, r in ipairs({ f:GetRegions() }) do
            if r ~= f.arena and r.GetObjectType and r:GetObjectType() == "Texture" and r:GetDrawLayer() == "BACKGROUND" then r:SetAlpha(0) end
        end
        if f.borders then for _, b in ipairs(f.borders) do b:SetAlpha(0) end end
    end
    -- Fackeln flackern leicht (Helligkeit der Arena schwankt)
    f.flick = CreateFrame("Frame", nil, f)
    f.flick:SetScript("OnUpdate", function()
        local t = GetTime()
        local v = 0.88 + 0.07 * math.sin(t * 7.3) + 0.04 * math.sin(t * 13.1)
        f.arena:SetVertexColor(v, v * 0.97, v * 0.95)
    end)
    -- Buehne: dunkler Verlauf + Lichtkegel in der Mitte
    f.stageLight = f:CreateTexture(nil, "BACKGROUND", nil, 2)
    f.stageLight:SetTexture(ns.MEDIA .. "shine")
    f.stageLight:SetPoint("CENTER", 0, -30)
    f.stageLight:SetSize(520, 420)
    f.stageLight:SetVertexColor(C.accent[1], C.accent[2], C.accent[3])
    f.stageLight:SetAlpha(0.10)
    -- Spannungs-Rand: rote Raender, werden mit sinkendem Wurfbereich staerker und schlagen im Herzschlag
    f.vigF = CreateFrame("Frame", nil, f)
    f.vigF:SetAllPoints()
    f.vigF:SetFrameLevel(f:GetFrameLevel() + 22)
    f.vigF:SetAlpha(0)
    local R0, R1 = { C.red[1], C.red[2], C.red[3], 0 }, { C.red[1], C.red[2], C.red[3], 0.55 }
    local function vig(point1, point2, w, h, orient, a, b)
        local t = f.vigF:CreateTexture(nil, "OVERLAY")
        t:SetPoint(point1, 1, point1:find("TOP") and -1 or 1)
        t:SetPoint(point2, point2:find("RIGHT") and -1 or 1, point2:find("TOP") and -1 or 1)
        if w then t:SetWidth(w) end
        if h then t:SetHeight(h) end
        if not K.Gradient(t, orient, a, b) then t:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.12) end
    end
    vig("TOPLEFT", "TOPRIGHT", nil, 90, "VERTICAL", R0, R1)
    vig("BOTTOMLEFT", "BOTTOMRIGHT", nil, 90, "VERTICAL", R1, R0)
    vig("TOPLEFT", "BOTTOMLEFT", 90, nil, "HORIZONTAL", R1, R0)
    vig("TOPRIGHT", "BOTTOMRIGHT", 90, nil, "HORIZONTAL", R0, R1)
    local title = K.Title(f, 13, C.muted, "CENTER")
    title:SetPoint("TOP", 0, -14)
    title:SetText(L["DEATHROLL"])
    f.titleFS = title
    f.stake = K.Text(f, 11, C.amber, "CENTER")
    f.stake:SetPoint("TOP", title, "BOTTOM", 0, -3)
    -- Schliessen waehrend eines laufenden Spiels = aufgeben (mit Rueckfrage)
    local close = K.CloseButton(f, function()
        local g = DR.game
        if g and g.state == "live" then DR.AskGiveUp() return end
        f.allowHide = true
        f:Hide()
        if g and g.state == "invite_in" then
            K.Toast(L["Deathroll laeuft weiter"], L["Nur ausgeblendet - klick hier, um zurueckzukehren."], C.accent, function() DR.Show() end)
        end
    end, L["Schliessen - im laufenden Spiel heisst das aufgeben"])
    close:SetFrameLevel(f:GetFrameLevel() + 20)
    close:SetPoint("TOPRIGHT", -8, -8)

    f.A = sideFrame(f, true)
    f.B = sideFrame(f, false)

    -- Groesse aendern: Griff unten rechts ziehen (skaliert das ganze Fenster, Anordnung bleibt)
    local S = ns.db.settings
    f:SetScale(math.max(0.6, math.min(1.8, S.drScale or 1)))
    if S.drPos and S.drPos[1] then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", S.drPos[1], S.drPos[2])
    end
    f:HookScript("OnDragStop", function(self)
        S.drPos = { self:GetLeft(), self:GetTop() }
    end)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(18, 18)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(f:GetFrameLevel() + 40)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnEnter", function(self) K.ShowTip(self, { L["Groesse aendern"], L["Ziehen: groesser/kleiner  ·  Doppelklick: Standard"] }) end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    grip:SetScript("OnMouseDown", function(self)
        local x = GetCursorPosition()
        self.drag = { x = x, scale = f:GetScale(), left = f:GetLeft(), top = f:GetTop() }
        self:SetScript("OnUpdate", function(s)
            local cx = GetCursorPosition()
            local ui = UIParent:GetEffectiveScale()
            -- Breitenaenderung in Fenster-Einheiten -> neue Skalierung
            local dw = (cx - s.drag.x) / ui
            local sc = math.max(0.6, math.min(1.8, s.drag.scale * (1 + dw / (W * s.drag.scale))))
            local l, t = s.drag.left * s.drag.scale, s.drag.top * s.drag.scale
            f:SetScale(sc)
            -- obere linke Ecke bleibt stehen
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l / sc, t / sc)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        S.drScale = f:GetScale()
        S.drPos = { f:GetLeft(), f:GetTop() }
    end)
    grip:SetScript("OnDoubleClick", function()
        S.drScale, S.drPos = 1, nil
        f:SetScale(1)
        f:ClearAllPoints()
        f:SetPoint("CENTER", 0, 40)
    end)

    -- Mitte: Wuerfel + Zahl
    f.center = CreateFrame("Frame", nil, f)
    f.center:SetFrameLevel(f:GetFrameLevel() + 10)
    f.center:SetSize(220, 220)
    f.center:SetPoint("CENTER", 0, 10)
    f.dice = {}
    for i = 1, 2 do
        local d = f.center:CreateTexture(nil, "OVERLAY")
        d:SetTexture(i == 1 and "Interface\\Icons\\INV_Misc_Dice_01" or "Interface\\Icons\\INV_Misc_Dice_02")
        d:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d:SetSize(54, 54)
        d:SetAlpha(0)
        f.dice[i] = d
    end
    f.numF = CreateFrame("Frame", nil, f.center)
    f.numF:SetSize(220, 90)
    f.numF:SetPoint("CENTER", 0, -6)
    f.num = f.numF:CreateFontString(nil, "OVERLAY")
    f.num:SetFont(K.FONT_HEAD, 64, "OUTLINE")
    f.num:SetPoint("CENTER")
    f.num:SetTextColor(1, 1, 1)
    f.numLbl = K.Text(f.center, 11, C.muted, "CENTER")
    f.numLbl:SetPoint("TOP", f.numF, "BOTTOM", 0, 4)
    f.front = CreateFrame("Frame", nil, f)
    f.front:SetAllPoints()
    f.front:SetFrameLevel(f:GetFrameLevel() + 12)
    f.status = K.Title(f.front, 18, C.text, "CENTER")
    f.status:SetPoint("TOP", f.center, "BOTTOM", 0, 6)
    f.status:SetWidth(300)

    -- unten: Knoepfe + Verlauf
    f.b1 = K.Button(f.front, "", 240, 40, "primary")
    f.b1:SetPoint("BOTTOM", 0, 58)
    f.b1.label:SetFont(K.FONT_HEAD, 15, "")
    f.b2 = K.Button(f.front, "", 120, 24, "ghost")
    f.b2:SetPoint("BOTTOM", 0, 26)
    f.b2.label:SetFont(K.FONT, 11, "")
    f.hint = K.Text(f.front, 11, C.amber, "CENTER")
    f.hint:SetPoint("BOTTOM", f.b1, "TOP", 0, 8)
    f.hist = K.Text(f.front, 11, C.muted, "CENTER")
    f.hist:SetPoint("BOTTOM", 0, 8)
    f.hist:SetWidth(W - 40)

    -- Kaempfer waehlen (vor dem ersten Wurf)
    f.pick = K.Button(f.front, L["Kaempfer waehlen"], 140, 22, "ghost", function() DR.ShowPicker() end)
    f.pick:SetPoint("TOPLEFT", 12, -12)
    -- Lautstaerke: Musik (0-5) und Sound (0-10, gilt fuer alle Oasis-Toene)
    if K.Slider then
        local function S2() return ns.db.settings end
        f.mLbl = K.Text(f.front, 9, C.dim)
        f.mLbl:SetPoint("BOTTOMLEFT", 12, 34)
        f.mLbl:SetText(K.Upper(L["Musik"]))
        f.mVol = K.Slider(f.front, 110, 0, 5, 1, function() return tonumber(S2().drMusicVol) or 5 end,
            function(v) S2().drMusicVol = v DR.RestartMusic() end, function(v) return v == 0 and L["aus"] or tostring(v) end)
        f.mVol:SetPoint("LEFT", f.mLbl, "RIGHT", 8, 0)
        f.sLbl = K.Text(f.front, 9, C.dim)
        f.sLbl:SetPoint("BOTTOMLEFT", 12, 12)
        f.sLbl:SetText(K.Upper(L["Sound"]))
        f.sVol = K.Slider(f.front, 110, 0, ns.Sound and ns.Sound.VOL_MAX or 10, 1, function() return tonumber(S2().soundVol) or 7 end,
            function(v) S2().soundVol = v end, function(v) return v == 0 and L["aus"] or (ns.Sound and ns.Sound.VolText and ns.Sound.VolText(v) or tostring(v)) end)
        f.sVol:SetPoint("LEFT", f.mLbl, "RIGHT", 8, -22)
    end
    -- VS-Einblendung zu Beginn (wie bei Tekken)
    f.vs = CreateFrame("Frame", nil, f)
    f.vs:SetAllPoints()
    f.vs:SetFrameLevel(f:GetFrameLevel() + 30)
    f.vs.bg = f.vs:CreateTexture(nil, "BACKGROUND")
    f.vs.bg:SetPoint("LEFT") f.vs.bg:SetPoint("RIGHT") f.vs.bg:SetHeight(120)
    f.vs.bg:SetColorTexture(0, 0, 0, 0.75)
    -- Blitz-Emblem hinter dem VS (pulsiert)
    f.vs.burst = f.vs:CreateTexture(nil, "ARTWORK")
    f.vs.burst:SetTexture(ns.MEDIA .. "dr\\burst")
    f.vs.burst:SetSize(200, 200)
    f.vs.burst:SetPoint("CENTER", 0, 0)
    f.vs.burst:SetBlendMode("ADD")
    f.vs.burst:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 0.7)
    f.vs:HookScript("OnUpdate", function(self)
        local t = GetTime()
        local k = 1 + 0.08 * math.sin(t * 9)
        self.burst:SetSize(200 * k, 200 * k)
    end)
    f.vs.word = f.vs:CreateFontString(nil, "OVERLAY")
    f.vs.word:SetFont(K.FONT_HEAD, 72, "THICKOUTLINE")
    f.vs.word:SetPoint("CENTER", 0, 0)
    f.vs.word:SetText("VS")
    f.vs.word:SetTextColor(C.red[1], C.red[2], C.red[3])
    f.vs.a = f.vs:CreateFontString(nil, "OVERLAY")
    f.vs.a:SetFont(K.FONT_HEAD, 24, "OUTLINE")
    f.vs.b = f.vs:CreateFontString(nil, "OVERLAY")
    f.vs.b:SetFont(K.FONT_HEAD, 24, "OUTLINE")
    f.vs.fa = K.Text(f.vs, 12, C.muted, "RIGHT")
    f.vs.fb = K.Text(f.vs, 12, C.muted, "LEFT")
    f.vs:Hide()

    -- Ergebnis-Schriftzug
    f.result = f.front:CreateFontString(nil, "OVERLAY")
    f.result:SetFont(K.FONT_HEAD, 46, "OUTLINE")
    f.result:SetPoint("CENTER", 0, 70)
    f.result:SetAlpha(0)

    f.t = 0
    f:SetScript("OnUpdate", function(self, el)
        self.t = self.t + el
        -- HP-Balken gleiten, gelber "Schaden" zieht langsam nach
        for _, s in ipairs({ self.A, self.B }) do
            s.shown = s.shown + (s.hp - s.shown) * math.min(1, el * 10)
            if s.lagV > s.shown then s.lagV = math.max(s.shown, s.lagV - el * 0.5) else s.lagV = s.shown end
            local bw = s.bar:GetWidth() - 2
            s.fill:SetWidth(math.max(0.01, bw * s.shown))
            s.lag:SetWidth(math.max(0.01, bw * s.lagV))
            s.fill:SetShown(s.shown > 0.002)
            if s.base then s.fill:SetColorTexture(hpColor(s.base, s.shown, self.t)) end
            -- Rampenlicht: wer nicht dran ist, wird leicht abgedunkelt
            local want = (self.liveGame and not s.active) and 0.72 or 1
            s.ma = (s.ma or 1) + (want - (s.ma or 1)) * math.min(1, el * 5)
            s.model:SetAlpha(s.ma)
            if s.hitT then
                s.hitT = s.hitT + el
                local k = 1 - s.hitT / 0.4
                if k <= 0 then s.hitT = nil s.hit:SetAlpha(0) else s.hit:SetAlpha((s.hitA or 0.3) * k) end
            end
            if s.dmgT then
                s.dmgT = s.dmgT + el
                s.dmg:SetAlpha(math.max(0, 1 - s.dmgT / 1.4))
                s.dmg:ClearAllPoints()
                s.dmg:SetPoint("TOP", s.top, "BOTTOM", s.left and -40 or 40, -6 + s.dmgT * 30)
                if s.dmgT > 1.4 then s.dmgT = nil end
            end
            -- wer dran ist, leuchtet
            local on = s.active and (0.25 + 0.15 * math.sin(self.t * 4)) or 0
            s.glowA = (s.glowA or 0) + (on - (s.glowA or 0)) * math.min(1, el * 6)
            s.glow:SetAlpha(s.glowA)
        end
        -- Wuerfel fallen
        local a = DR.anim
        if a then
            a.t = a.t + el
            local T = 0.85
            local k = math.min(1, a.t / T)
            -- Wuerfel-Design (Belohnung Oasis-Rang)
            local dc = ns.Rewards and ns.Rewards.DiceColor()
            for i, d in ipairs(self.dice) do
                if dc then d:SetVertexColor(dc[1], dc[2], dc[3]) else d:SetVertexColor(1, 1, 1) end
                local off = (i == 1) and -34 or 34
                -- Fall mit Aufprall (einfacher Bounce)
                local y
                if k < 0.6 then y = 150 * (1 - (k / 0.6) ^ 2)
                else local b = (k - 0.6) / 0.4 y = 26 * math.sin(b * math.pi) * (1 - b) end
                d:ClearAllPoints()
                d:SetPoint("CENTER", self.center, "CENTER", off + (i == 1 and -1 or 1) * (1 - k) * 30, y + 58)
                d:SetRotation((1 - k) * (i == 1 and 9 or -11))
                d:SetAlpha(k < 0.95 and 1 or math.max(0, 1 - (a.t - T * 0.95) * 3))
            end
            if a.t < T then
                self.num:SetText(math.random(1, math.max(1, a.from)))
                self.num:SetTextColor(0.6, 0.6, 0.6)
                self.numF:SetScale(0.8)
            else
                if not a.landed then
                    a.landed = true
                    self.num:SetText(a.to)
                    self.num:SetTextColor(numColor(a.to, DR.game and DR.game.start))
                    local s = a.side
                    if s and not (ns.db and ns.db.settings.noAnim) then
                        s.hitT, s.hitA = 0, (a.to <= 1) and 0.55 or math.min(0.30, 0.08 + 0.25 * (a.from - a.to) / math.max(1, a.from))
                    end
                    if s then
                        setBar(s, a.hp)
                        s.dmg:SetText("-" .. (a.from - a.to))
                        s.dmg:SetTextColor(unpack(a.to <= 1 and C.red or C.amber))
                        s.dmgT = 0
                    end
                    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN) or 875, "SFX")
                end
                local p = math.min(1, (a.t - T) / 0.25)
                self.numF:SetScale(1.35 - 0.35 * p)
                if a.t > T + 0.6 then
                    for _, d in ipairs(self.dice) do d:SetAlpha(0) end
                    DR.anim = nil
                    self.numF:SetScale(1)
                    DR.Update()
                end
            end
        end
        -- Spannung: roter Rand + Herzschlag der Zahl (nur im laufenden Spiel, ohne "Animationen reduzieren")
        do
            local g = DR.game
            local noA = ns.db and ns.db.settings and ns.db.settings.noAnim
            local ten = (g and g.state == "live" and not noA) and tension(g.max, g.start) or 0
            self.tenS = (self.tenS or 0) + (ten - (self.tenS or 0)) * math.min(1, el * 3)
            local beat = 0.5 + 0.5 * math.sin(self.t * (4 + 6 * self.tenS))
            self.vigF:SetAlpha(self.tenS > 0.02 and (self.tenS * (0.35 + 0.35 * beat)) or 0)
            if not DR.anim then
                self.numF:SetScale(1 + ((self.tenS > 0.6) and (0.05 * beat * (self.tenS - 0.6) / 0.4) or 0))
            end
        end
        -- VS-Einblendung: Namen fliegen herein, VS knallt, dann ausblenden
        if self.vsT then
            self.vsT = self.vsT + el
            local t = self.vsT
            local slide = math.min(1, t / 0.35)
            local e = 1 - (1 - slide) ^ 3
            self.vs.a:ClearAllPoints() self.vs.a:SetPoint("RIGHT", self.vs, "CENTER", -70 - (1 - e) * 400, 10)
            self.vs.b:ClearAllPoints() self.vs.b:SetPoint("LEFT", self.vs, "CENTER", 70 + (1 - e) * 400, 10)
            self.vs.fa:ClearAllPoints() self.vs.fa:SetPoint("TOPRIGHT", self.vs.a, "BOTTOMRIGHT", 0, -4)
            self.vs.fb:ClearAllPoints() self.vs.fb:SetPoint("TOPLEFT", self.vs.b, "BOTTOMLEFT", 0, -4)
            local pop = math.max(0, math.min(1, (t - 0.3) / 0.2))
            self.vs.word:SetScale(2.2 - 1.2 * pop)
            self.vs.word:SetAlpha(pop)
            local fade = t > 1.7 and math.max(0, 1 - (t - 1.7) / 0.4) or 1
            self.vs:SetAlpha(fade)
            if t > 2.1 then self.vsT = nil self.vs:Hide() end
        end
        -- Ergebnis einblenden
        if self.resultT then
            self.resultT = self.resultT + el
            local p = math.min(1, self.resultT / 0.4)
            self.result:SetAlpha(p)
            self.result:SetScale(1.6 - 0.6 * p)
        end
    end)
    ns.EscClose("OasisDeathrollFrame")
    -- auch Esc: im laufenden Spiel erst fragen, Fenster bleibt offen
    f:HookScript("OnHide", function(self)
        if self.allowHide then self.allowHide = nil return end
        local g = DR.game
        if g and g.state == "live" then
            ns.After(0, function() if DR.game == g and g.state == "live" then self:Show() DR.AskGiveUp() end end)
        end
    end)
    -- 0.6.220: Spielfenster im Ornament-Stil (nur mit Thronsaal-Bild): goldener Titel, Zahl mit Ornament-Ring,
    -- "Du bist dran" auf einer Bronze-Platte, Knoepfe als Bild-Platten, Namensplatten mit Medaillon, Figuren ganz
    if f.artMode then
        local MED = "Interface\\AddOns\\Oasis_Guild\\Media\\"
        local GOLD = { 1, 0.82, 0.45 }
        local function shadow(fs) if fs and fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) fs:SetShadowOffset(1, -1) end end
        -- Titel
        f.titleFS:SetText(L["Todeswuerfeln"])
        K.SetFontSafe(f.titleFS, K.FONT_HEAD or K.FONT, 26, "", K.FONT)
        f.titleFS:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        f.titleFS:ClearAllPoints() f.titleFS:SetPoint("TOP", 0, -16)
        shadow(f.titleFS)
        f.stake:SetTextColor(0.8, 0.76, 0.72) shadow(f.stake)
        -- Zahl mit Ornament-Ring
        f.numRing = f.center:CreateTexture(nil, "BACKGROUND")
        f.numRing:SetTexture(MED .. "badge_ring")
        -- 0.6.221: Mitte neu: Ring kleiner und hoeher, Unterschrift darunter, Platte und Knoepfe mit Abstand
        f.center:ClearAllPoints() f.center:SetPoint("CENTER", f, "CENTER", 0, 34)
        f.numRing:SetSize(150, 150)
        f.numRing:SetPoint("CENTER", f.numF, "CENTER", 0, 2)
        f.numRing:SetVertexColor(0.95, 0.55, 0.25, 0.9)
        f.numDisc = f.center:CreateTexture(nil, "BACKGROUND", nil, -1)
        f.numDisc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        f.numDisc:SetSize(108, 108)
        f.numDisc:SetPoint("CENTER", f.numRing)
        f.numDisc:SetVertexColor(0.08, 0.02, 0.02, 0.75)
        f.num:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        f.numLbl:SetTextColor(0.85, 0.8, 0.75) shadow(f.numLbl)
        f.numLbl:ClearAllPoints() f.numLbl:SetPoint("TOP", f.numRing, "BOTTOM", 0, -2)
        f.num:SetFont(K.FONT_HEAD, 52, "OUTLINE")
        -- "Du bist dran" auf Bronze-Platte
        f.statusBg = f.front:CreateTexture(nil, "BACKGROUND")
        f.statusBg:SetTexture(MED .. "dr_plate")
        f.status:ClearAllPoints() f.status:SetPoint("TOP", f.numLbl, "BOTTOM", 0, -14)
        f.statusBg:SetSize(220, 38)
        f.statusBg:SetPoint("CENTER", f.status, "CENTER", 0, 0)
        f.status:SetTextColor(GOLD[1], GOLD[2], GOLD[3]) shadow(f.status)
        -- Knoepfe als Bild-Platten (eigene Flaechen unsichtbar, Hover leuchtet)
        -- 0.6.226: Bild-Knopf als eigener, schlanker Knopf UEBER dem Original. Das Original wird ganz unsichtbar
        -- und klickfest (seine Design-Flaechen schienen sonst immer wieder durch); Text, Klick, Sichtbarkeit und
        -- Aktiv-Zustand werden vom Original uebernommen - die Spiel-Logik bleibt unveraendert.
        local function imgBtn(orig, file, w, h, fontSize)
            if not orig then return end
            orig.imgSkin = true
            local nb = CreateFrame("Button", nil, orig:GetParent())
            nb:SetFrameLevel(orig:GetFrameLevel() + 5)
            nb:SetAllPoints(orig)
            nb.img = nb:CreateTexture(nil, "ARTWORK", nil, 1)
            nb.img:SetTexture(MED .. file) nb.img:SetSize(w, h) nb.img:SetPoint("CENTER")
            nb.glowImg = nb:CreateTexture(nil, "ARTWORK", nil, 2)
            nb.glowImg:SetTexture(MED .. file) nb.glowImg:SetAllPoints(nb.img) nb.glowImg:SetBlendMode("ADD") nb.glowImg:SetAlpha(0)
            nb.label = nb:CreateFontString(nil, "OVERLAY")
            K.SetFontSafe(nb.label, K.FONT_HEAD or K.FONT, fontSize or 12, "", K.FONT)
            nb.label:SetPoint("CENTER", 0, 1)
            nb.label:SetTextColor(1, 0.92, 0.82)
            shadow(nb.label)
            orig:SetAlpha(0) orig.SetAlpha = function() end
            orig:EnableMouse(false)
            nb:SetScript("OnClick", function()
                local fn = orig:GetScript("OnClick")
                if orig:IsEnabled() and fn then fn(orig, "LeftButton") end
            end)
            local target, cur, acc = 0, 0, 1
            nb:SetScript("OnEnter", function(self)
                if orig:IsEnabled() then target = 0.45 end
                local fn = orig:GetScript("OnEnter")
                if fn then pcall(fn, orig) end
            end)
            nb:SetScript("OnLeave", function() target = 0 GameTooltip:Hide() end)
            nb:SetScript("OnUpdate", function(self, el)
                acc = acc + el
                if acc > 0.1 then
                    acc = 0
                    self:SetShown(orig:IsShown())
                    local txt = orig.label and orig.label:GetText() or ""
                    if self.label:GetText() ~= txt then self.label:SetText(txt) end
                    local en = orig:IsEnabled()
                    self.img:SetDesaturated(not en)
                    self.label:SetAlpha(en and 1 or 0.55)
                    self.img:SetAlpha(en and 1 or 0.6)
                end
                if cur ~= target then
                    cur = (cur < target) and math.min(target, cur + el * 3) or math.max(target, cur - el * 3)
                    self.glowImg:SetAlpha(cur)
                end
            end)
            orig:HookScript("OnShow", function() nb:Show() end)
            orig:HookScript("OnHide", function() nb:Hide() end)
            orig.proxy = nb
            return nb
        end
        f.b1:SetSize(230, 44)
        f.b1:ClearAllPoints() f.b1:SetPoint("BOTTOM", 0, 56)
        imgBtn(f.b1, "dr_roll_btn", 250, 70, 18)   -- 0.6.221: eigene Wuerfeln-Plakette
        f.b2:SetSize(150, 28)
        f.b2:ClearAllPoints() f.b2:SetPoint("BOTTOM", 0, 16)
        imgBtn(f.b2, "dr_giveup_btn", 180, 46, 11)   -- 0.6.222: eigene Platte fuer Aufgeben
        f.pick:SetSize(140, 24)
        imgBtn(f.pick, "dr_plate", 160, 32, 10)
        -- Namensplatten mit Medaillon aussen, HP-Balken darin
        for _, sd in ipairs({ f.A, f.B }) do
            local top, left = sd.top, sd.left
            top:ClearAllPoints()
            top:SetPoint(left and "TOPLEFT" or "TOPRIGHT", left and 66 or -66, -70)
            top:SetSize(270, 56)
            top.bg = top:CreateTexture(nil, "BACKGROUND", nil, -2)
            top.bg:SetTexture(MED .. "dr_plate")
            top.bg:SetPoint("TOPLEFT", -14, 10) top.bg:SetPoint("BOTTOMRIGHT", 14, -10)
            sd.nameText:ClearAllPoints()
            sd.nameText:SetPoint(left and "TOPLEFT" or "TOPRIGHT", left and 6 or -6, -2)
            K.SetFontSafe(sd.nameText, K.FONT_HEAD or K.FONT, 17, "", K.FONT)
            shadow(sd.nameText)
            sd.turn:ClearAllPoints() sd.turn:SetPoint(left and "TOPRIGHT" or "TOPLEFT", left and -6 or 6, -5)
            shadow(sd.turn)
            sd.bar:ClearAllPoints()
            sd.bar:SetPoint("TOPLEFT", 6, -26) sd.bar:SetPoint("TOPRIGHT", -6, -26)
            -- Medaillon: Ornament-Ring in der Seitenfarbe, Wuerfel-Symbol darin
            local medal = CreateFrame("Frame", nil, top)
            medal:SetSize(62, 62)
            medal:SetPoint("CENTER", top, left and "LEFT" or "RIGHT", left and -30 or 30, -4)
            medal.disc = medal:CreateTexture(nil, "BACKGROUND")
            medal.disc:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
            medal.disc:SetSize(44, 44) medal.disc:SetPoint("CENTER") medal.disc:SetVertexColor(0.06, 0.03, 0.03, 0.95)
            medal.ico = medal:CreateTexture(nil, "ARTWORK")
            medal.ico:SetTexture(ns.MEDIA .. "icons\\deathroll")
            medal.ico:SetSize(26, 26) medal.ico:SetPoint("CENTER")
            medal.ring = medal:CreateTexture(nil, "OVERLAY")
            medal.ring:SetTexture(MED .. "online_ring") medal.ring:SetAllPoints()
            local mc = left and { 1, 0.45, 0.35 } or { 0.7, 0.6, 1 }
            medal.ring:SetVertexColor(mc[1], mc[2], mc[3])
            medal.ico:SetVertexColor(mc[1], mc[2], mc[3])
            sd.medal = medal
            DR.ArtSide(f, sd)
            -- Figur ganz zeigen (weiter weg), nach jedem Laden neu
            local function zoomOut(m)
                if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 0) end
                if m.SetCamDistanceScale then pcall(m.SetCamDistanceScale, m, 1.6) end
            end
            sd.model:ClearAllPoints()
            sd.model:SetPoint("TOPLEFT", 0, -128) sd.model:SetPoint("BOTTOMRIGHT", 0, 104)
            zoomOut(sd.model)
            sd.model:HookScript("OnModelLoaded", zoomOut)
            sd.model:HookScript("OnShow", zoomOut)
        end
    end
    DR.frame = f
    f:HookScript("OnShow", function() C_Timer.After(0, DR.MusicUpdate) end)
    f:HookScript("OnHide", function() C_Timer.After(0, DR.MusicUpdate) end)
    return f
end
-- Rueckfrage: wirklich aufgeben?
function DR.AskGiveUp()
    if not StaticPopupDialogs then DR.GiveUp() return end
    StaticPopupDialogs.OASIS_DR_GIVEUP = StaticPopupDialogs.OASIS_DR_GIVEUP or {
        text = L["Deathroll wirklich aufgeben?\nDann hast du verloren."],
        button1 = L["Aufgeben"],
        button2 = L["Weiterspielen"],
        OnAccept = function()
            DR.GiveUp()
            if DR.frame then DR.frame.allowHide = true DR.frame:Hide() end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("OASIS_DR_GIVEUP")
end

-- Stand je Seite: letzter eigener Wurf = "Lebenspunkte"
local function hpOf(g, name)
    for _, h in ipairs(g.hist) do if sameName(h.who, name) then return h.roll end end
    return g.start
end

function DR.Show()
    local f = DR.frame or build()
    local g = DR.game
    f:Show()
    if g and f.gameId ~= g.id then
        f.gameId = g.id
        DR.anim = nil
        f.resultT = nil
        f.result:SetAlpha(0)
        for _, d in ipairs(f.dice) do d:SetAlpha(0) end
        g.look = g.look or {}
        local race, sex = myLook()
        g.look[ns.me()] = { race = race, sex = sex, f = DR.MyFighter() }
        local opp = other(g, ns.me())
        if not g.bot and not g.manual and not g.fightSent then
            g.fightSent = true
            Comm.Whisper(opp, "DRFIGHT", g.id, DR.MyFighter())
        end
        -- VS-Einblendung
        if not g.vsShown and g.state ~= "done" then
            g.vsShown = true
            local fa, fb = DR.Fighter(g.look[g.a] and g.look[g.a].f), DR.Fighter(g.look[g.b] and g.look[g.b].f)
            f.vs.a:SetText(K.Upper(ns.displayName(g.a)))
            f.vs.b:SetText(K.Upper(ns.displayName(g.b)))
            local r1, g1, b1 = ns.classColor(ns.Radar.ClassOf(g.a))
            local r2, g2, b2 = ns.classColor(ns.Radar.ClassOf(g.b))
            f.vs.a:SetTextColor(r1 or 1, g1 or 1, b1 or 1)
            f.vs.b:SetTextColor(r2 or 1, g2 or 1, b2 or 1)
            f.vs.fa:SetText(fa.key ~= "me" and L[fa.name] or "")
            f.vs.fb:SetText(fb.key ~= "me" and L[fb.name] or "")
            f.vs:SetAlpha(1) f.vs:Show()
            f.vsT = 0
            pcall(PlaySound, (SOUNDKIT and SOUNDKIT.PVP_THROUGH_QUEUE) or 8459, "SFX")
        end
        -- Fenster springt auf (leicht vergroessert -> normal, weich eingeblendet) und Countdown 3-2-1-FIGHT
        if g.state ~= "done" and not (ns.db and ns.db.settings.noAnim) then
            f.baseScale = f.baseScale or f:GetScale()
            local bs = f.baseScale
            f:SetAlpha(0)
            K.Tween(f, 0.35, function(p) f:SetAlpha(p) f:SetScale(bs * (0.85 + 0.15 * (1 - (1 - p) * (1 - p)))) end, function() f:SetAlpha(1) f:SetScale(bs) end)
            if not f.cd then
                f.cd = CreateFrame("Frame", nil, f)
                f.cd:SetAllPoints()
                f.cd:SetFrameLevel(f:GetFrameLevel() + 60)
                f.cd.t = K.Title(f.cd, 72, C.text, "CENTER")
                f.cd.t:SetPoint("CENTER", 0, 20)
                f.cd.t:SetShadowOffset(3, -3)
                f.cd:Hide()
            end
            local steps = { "3", "2", "1", L["KAMPF!"] }
            f.cd:Show()
            for i, txt in ipairs(steps) do
                ns.After(0.6 + (i - 1) * 0.7, function()
                    if not f:IsShown() then return end
                    f.cd.t:SetText(txt)
                    local c = (i == #steps) and C.accent or C.text
                    f.cd.t:SetTextColor(c[1], c[2], c[3])
                    if i == #steps then
                        -- Kampfbeginn: "Fighting!" (Oasis-Sound, Lautstaerke wie eingestellt); sonst Blizzard-Signal
                        local sv = tonumber(ns.db.settings.soundVol) or 7
                        local okF, hF = false, nil
                        if ns.db.settings.sound ~= false and sv > 0 and ns.Sound and ns.Sound.PlayChoice then okF, hF = pcall(ns.Sound.PlayChoice, "fighting", sv) end
                        if not (okF and hF) then pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "SFX") end
                    else
                        pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856, "SFX")
                    end
                    K.Tween(f.cd.t, 0.6, function(p) f.cd.t:SetAlpha(1 - p * p) f.cd.t:SetScale(1.6 - 0.6 * p) end, function() f.cd.t:SetAlpha(0) end)
                    if i == #steps then ns.After(0.7, function() f.cd:Hide() end) end
                end)
            end
        end
        C_Timer.After(0, DR.MusicUpdate)
        setModel(f.A, g.a, g.look[g.a], g.bot and not ns.isMe(g.a))
        setModel(f.B, g.b, g.look[g.b], g.bot and not ns.isMe(g.b))
        setBar(f.A, hpOf(g, g.a) / g.start, true)
        setBar(f.B, hpOf(g, g.b) / g.start, true)
        ns.After(0.3, function() anim(f.A, ANIM.ready) anim(f.B, ANIM.ready) end)
    end
    DR.Update()
end

-- Wurf-Animation starten (aus apply)
function DR.AnimRoll(g, who, from, to)
    local f = DR.frame
    if not f or not f:IsShown() then return end
    local s = sameName(who, g.a) and f.A or f.B
    DR.anim = { from = from, to = to, t = 0, start = GetTime(), side = s, hp = to <= 1 and 0 or to / g.start }
    anim(s, ANIM.roll)
    -- Treffer-Effekt: kurzes Wackeln + fliegende Zahl ueber dem Wuerfelnden (das neue Maximum)
    if not (ns.db and ns.db.settings.noAnim) then
        local p1, rel, p2, x0, y0 = f:GetPoint(1)
        if p1 then
            local t0 = GetTime()
            f.shake = f.shake or CreateFrame("Frame", nil, f)
            f.shake:SetScript("OnUpdate", function(self)
                local d = GetTime() - t0
                if d > 0.35 then f:ClearAllPoints() f:SetPoint(p1, rel, p2, x0, y0) self:SetScript("OnUpdate", nil) return end
                local a = 6 * (1 - d / 0.35)
                f:ClearAllPoints()
                f:SetPoint(p1, rel, p2, x0 + math.random(-10, 10) / 10 * a, y0 + math.random(-10, 10) / 10 * a)
            end)
        end
        f.dmg = f.dmg or {}
        local fl = table.remove(f.dmg) or f:CreateFontString(nil, "OVERLAY")
        fl:SetFont(K.FONT_HEAD, 30, "THICKOUTLINE")
        fl:SetText(tostring(to))
        local low = to <= 1
        fl:SetTextColor(low and 1 or 1, low and 0.25 or 0.85, low and 0.25 or 0.3)
        fl:ClearAllPoints()
        fl:SetPoint("BOTTOM", s, "CENTER", 0, 40)
        fl:Show()
        K.Tween(fl, 1.1, function(q)
            fl:ClearAllPoints()
            fl:SetPoint("BOTTOM", s, "CENTER", 0, 40 + q * 70)
            fl:SetAlpha(1 - q * q)
        end, function() fl:Hide() table.insert(f.dmg, fl) end)
    end
    -- Wuerfel-Geraeusch bei jedem Wurf
    local st = ns.db and ns.db.settings
    if st and st.sound ~= false and ns.Sound and ns.Sound.PlayChoice then pcall(ns.Sound.PlayChoice, "wuerfel", st.soundVol) end
end

function DR.Update()
    local f = DR.frame
    local g = DR.game
    if not f or not f:IsShown() or not g then return end
    local ca, cb = ns.Radar.ClassOf(g.a), ns.Radar.ClassOf(g.b)
    f.A.nameText:SetText(ns.colorName(g.a, ca))
    f.B.nameText:SetText(ns.colorName(g.b, cb))
    for _, pair in ipairs({ { f.A, ca }, { f.B, cb } }) do
        local r, gg, b = ns.classColor(pair[2])
        pair[1].fill:SetColorTexture(r or 0.8, gg or 0.2, b or 0.1, 1)
        pair[1].base = { r or 0.8, gg or 0.2, b or 0.1 }
    end
    local live = g.state == "live"
    f.liveGame = live
    f.A.active = live and sameName(g.turn, g.a)
    f.B.active = live and sameName(g.turn, g.b)
    f.A.turn:SetText(f.A.active and L["AM ZUG"] or "")
    f.B.turn:SetText(f.B.active and L["AM ZUG"] or "")
    local hA, hB = hpOf(g, g.a), hpOf(g, g.b)
    if g.state == "done" then
        if sameName(g.loser, g.a) then hA = 0 else hB = 0 end
    end
    f.A.hpText:SetText(hA .. " / " .. g.start)
    f.B.hpText:SetText(hB .. " / " .. g.start)
    if not DR.anim then
        setBar(f.A, hA / g.start)
        setBar(f.B, hB / g.start)
        f.num:SetText(g.max)
        f.num:SetTextColor(numColor(g.max, g.start))
    end
    f.numLbl:SetText(g.state == "done" and L["Endstand"] or (L["wuerfeln von 1 bis %d"]):format(g.max))
    f.stake:SetText(((g.stake or "") ~= "" and (L["Einsatz: "] .. g.stake) or "") .. (g.bot and ("  |cff888888" .. L["(Uebungsspiel)"] .. "|r") or ""))
    local myTurn = live and ns.isMe(g.turn)
    local c = C.text
    local st = ""
    if g.state == "invite_out" then st, c = L["Warte auf "] .. ns.displayName(g.b) .. " ...", C.muted
    elseif g.state == "noanswer" and g.rematch then st, c = (L["Keine Antwort von %s auf die Revanche."]):format(ns.displayName(g.b)), C.amber
    elseif g.state == "noanswer" then st, c = ns.displayName(g.b) .. L[" antwortet nicht (kein Oasis?)"], C.amber
    elseif g.state == "aborted" then st, c = g.abortWhy or L["Spiel abgebrochen - ohne Wertung."], C.amber
    elseif g.state == "invite_in" and g.rematchIn then st, c = (L["%s will Revanche!"]):format(ns.displayName(g.a)), C.pink
    elseif g.state == "invite_in" then st, c = ns.displayName(g.a) .. L[" fordert dich heraus!"], C.pink
    elseif live then
        if myTurn then st, c = L["Du bist dran!"], C.mint else st, c = ns.displayName(g.turn) .. L[" wuerfelt ..."], C.muted end
    elseif g.state == "done" then
        local won = ns.isMe(g.winner)
        st, c = won and L["Gewonnen!"] or (ns.displayName(g.winner) .. L[" gewinnt"]), won and C.mint or C.red
        -- Uebungspuppe: meldet sich nach dem Ergebnis mit einem Spruch und will Revanche
        if g.bot and not g.botSched then
            g.botSched = true
            ns.After(2.6, function()
                if DR.game ~= g or g.state ~= "done" then return end
                local list = won and BOT_TAUNT_WIN or BOT_TAUNT_LOSS
                g.botWants, g.botTaunt = true, list[math.random(#list)]
                if ns.Sound and ns.Sound.Play then ns.Sound.Play("dr_invite") end
                DR.Update()
            end)
        end
        if not f.resultT then
            f.resultT = 0
            f.result:SetText(won and L["SIEG!"] or L["NIEDERLAGE"])
            f.result:SetTextColor(unpack(won and C.mint or C.red))
            local winSide = sameName(g.winner, g.a) and f.A or f.B
            local loseSide = winSide == f.A and f.B or f.A
            ns.After(DR.anim and 1 or 0.1, function() anim(loseSide, ANIM.lose) anim(winSide, ANIM.win) end)
        end
    end
    f.status:SetText(st)
    f.status:SetTextColor(c[1], c[2], c[3])
    f.status:SetShown(g.state ~= "done")
    if g.state == "done" and g.bot and g.botWants and g.botTaunt then
        f.status:SetText(ns.displayName(g.b) .. ": " .. L[g.botTaunt])
        f.status:SetTextColor(C.pink[1], C.pink[2], C.pink[3])
        f.status:Show()
    end

    local function set(btn, label, fn, enabled)
        btn:SetLabel(label)
        btn:SetScript("OnClick", fn)
        btn:SetEnabledState(enabled ~= false)
        btn:Show()
    end
    if g.state == "invite_in" then
        set(f.b1, g.rematchIn and L["Revanche annehmen"] or L["Annehmen"], DR.Accept)
        set(f.b2, L["Ablehnen"], DR.Decline)
    elseif g.state == "noanswer" and g.rematch then
        set(f.b1, L["Revanche erneut senden"], function() DR.Rematch(g) end)
        set(f.b2, L["Abbrechen"], DR.Decline)
    elseif g.state == "noanswer" then
        set(f.b1, L["Ohne Addon spielen"], DR.GoManual)
        set(f.b2, L["Abbrechen"], DR.Decline)
    elseif g.state == "invite_out" then
        set(f.b1, g.rematch and L["Revanche gesendet ..."] or L["WUERFELN"], DR.Roll, false)
        set(f.b2, L["Abbrechen"], DR.Decline)
    elseif live then
        -- 0.6.220: im Ornament-Stil nur "Wuerfeln" (Bereich steht unter der Zahl)
        set(f.b1, myTurn and (f.artMode and L["Wuerfeln"] or (L["WUERFELN  1-%d"]):format(g.max)) or L["Gegner ist dran ..."], DR.Roll, myTurn)
        set(f.b2, L["Aufgeben"], DR.GiveUp)
    else
        set(f.b1, (g.bot and g.botWants) and L["Revanche annehmen"] or L["Revanche"], function() DR.Rematch(g) end)
        set(f.b2, L["Schliessen"], function()
            if DR.game == g then DR.game = nil end
            f.allowHide = true
            f:Hide()
        end)
    end
    f.pick:SetShown(g.state ~= "done" and g.state ~= "aborted" and g.n == 0)
    f.hint:SetText((g.manual and live and not g.bot) and (L["Ohne Addon: "] .. ns.displayName(other(g, ns.me())) .. L[" muss /roll "] .. g.max .. L[" tippen."]) or "")

    -- Verlauf als Kette: 100 > 57 > 12 ...
    local chain = { "|cff666666" .. g.start .. "|r" }
    for i = #g.hist, 1, -1 do
        local h = g.hist[i]
        local col = h.roll <= 1 and "|cffff4040" or (ns.isMe(h.who) and "|cff66db9e" or "|cffd8d8d8")
        chain[#chain + 1] = col .. h.roll .. "|r"
    end
    f.hist:SetText(#g.hist > 0 and table.concat(chain, "  |cff444444>|r  ") or "")
end

------------------------------------------------------------------------
-- Rangliste, Serien, Bilanz gegeneinander
------------------------------------------------------------------------
-- Main eines Charakters (Twinks zusammenfassen). Duelle speichern oft die Addon-Form "Vorname-Realm",
-- die Twink-Zuordnung kennt aber die Gildenlisten-Form -> bei keinem Treffer ueber SameChar nachschlagen.
local mainMemo, mainMemoT = {}, 0
-- 0.5.692: eine Schreibweise je Spieler - Forever speichert mal "Mira-Realm", mal "Mira Stern-Realm"
-- (Charakter- vs. Gildenlisten-Name). Schluessel = Vorname + Realm, angezeigt wird die volle Form.
local fullForm, fullFormT = {}, -999
local function nameKey(n) return ns.NameKey(n) end
local function fullOf(n)
    if not n then return n end
    if GetTime() - fullFormT > 5 then
        fullForm, fullFormT = {}, GetTime()
        local function note(x)
            if type(x) ~= "string" or x == "" then return end
            local k, cur = nameKey(x), fullForm[nameKey(x)]
            -- volle Form (mit Nachname) gewinnt, sonst die laengere
            if not cur or (#ns.short(x) > #ns.short(cur)) then fullForm[k] = x end
        end
        for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do note(m.name) end
        for _, d in ipairs(Store.List("duels")) do note(d.winner) note(d.loser) end
    end
    return fullForm[nameKey(n)] or n
end
local function mainOf(name)
    local A = ns.Alts
    if not name then return name end
    name = fullOf(name)
    if not A then return name end
    local now = GetTime()
    if now - mainMemoT > 5 then mainMemo, mainMemoT = {}, now end
    if mainMemo[name] then return mainMemo[name] end
    local m = A.Main(name)
    if A.SameChar and A.SameChar(m, name) then
        for _, src in ipairs({ ns.db.alts or {}, ns.db.altNotes or {} }) do
            for alt in pairs(src) do
                if A.SameChar(alt, name) then
                    local x = A.Main(alt)
                    if x and not A.SameChar(x, alt) then m = x break end
                end
            end
        end
    end
    m = fullOf((A.Canon and A.Canon(m)) or m)
    mainMemo[name] = m
    return m
end
DR.MainOf = mainOf
-- Anteil eines Charakters an einem Ranglisten-Eintrag merken (Tooltip: welche Charaktere zaehlen mit)
local function addChar(s, name, won)
    s.chars = s.chars or {}
    local c = (ns.Alts and ns.Alts.Canon and ns.Alts.Canon(name)) or name
    for _, x in ipairs(s.chars) do
        if x.name == c or (ns.Alts and ns.Alts.SameChar and ns.Alts.SameChar(x.name, c)) then
            if won then x.w = x.w + 1 else x.l = x.l + 1 end
            return
        end
    end
    s.chars[#s.chars + 1] = { name = c, w = won and 1 or 0, l = won and 0 or 1 }
end

-- Ranglisten-Reset der Gildenleitung (Gildeneinstellung drReset = Zeitpunkt): aeltere Spiele zaehlen nicht mehr
-- (Admin.lua laedt erst nach diesem Modul -> als Gildenoption anmelden, Seite "_intern" = ohne Bedienelement)
ns.GuildOption({ page = "_intern", key = "drReset", default = 0, kind = "num" })
function DR.Duels()
    local since = tonumber(ns.GuildOpt and ns.GuildOpt("drReset")) or 0
    local out = {}
    for _, x in ipairs(Store.List("duels")) do
        if (x.ts or x.u or 0) >= since then out[#out + 1] = x end
    end
    return out
end
function DR.ResetRanking()
    local A = ns.Admin
    if not (A and A.CanManage and A.CanManage()) then ns.print(L["Nur die Gildenleitung kann die Deathroll-Rangliste zuruecksetzen."]) return end
    local cfg = {}
    for k, v in pairs(A.Cfg() or {}) do cfg[k] = v end
    cfg.drReset = ns.now()
    if A.Save(cfg) then
        ns.print(L["Deathroll-Rangliste zurueckgesetzt - fuer die ganze Gilde."])
        ns.RefreshPage("deathroll")
    end
end
local function sortedDuels()
    local d = DR.Duels()
    table.sort(d, function(a, b) return (a.ts or a.u or 0) < (b.ts or b.u or 0) end)
    return d
end

-- Saison = Kalendermonat. offset 0 = dieser Monat, -1 = Vormonat -> von, bis (Unix-Zeit)
function DR.MonthRange(offset)
    local t = date("*t", ns.now())
    t.day, t.hour, t.min, t.sec = 1, 0, 0, 0
    t.month = t.month + (offset or 0)
    local from = time(t)
    t.month = t.month + 1
    return from, time(t)
end
-- Monatsname in der Oasis-Sprache
local MONTHS = { "Januar", "Februar", "Maerz", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" }
function DR.MonthName(offset)
    local from = DR.MonthRange(offset)
    return L[MONTHS[tonumber(date("%m", from))]]
end
-- Sieger einer Saison (mind. 3 Siege), fuer den Titel "Wuerfelkoenig des Monats"
function DR.MonthChampion(offset)
    local top = DR.Ranking(DR.MonthRange(offset or -1))[1]
    if top and top.w >= 3 then return top.name, top.w end
end

-- je Spieler: Siege, Niederlagen, aktuelle Serie (+ Siege / - Niederlagen), beste Siegesserie
-- optional nur Spiele im Zeitraum [from, to) (Saison)
function DR.Ranking(from, to)
    local stats = {}
    local function s(name)
        local key = mainOf(name)
        stats[key] = stats[key] or { name = key, w = 0, l = 0, streak = 0, best = 0 }
        return stats[key]
    end
    for _, d in ipairs(sortedDuels()) do
        local ts = d.ts or d.u or 0
        if not from or (ts >= from and ts < to) then
        local w, l = s(d.winner), s(d.loser)
        addChar(w, d.winner, true) addChar(l, d.loser, false)
        w.w = w.w + 1
        w.streak = w.streak >= 0 and w.streak + 1 or 1
        w.best = math.max(w.best, w.streak)
        l.l = l.l + 1
        l.streak = l.streak <= 0 and l.streak - 1 or -1
        end
    end
    local out = {}
    for _, v in pairs(stats) do out[#out + 1] = v end
    table.sort(out, function(a, b)
        if a.w ~= b.w then return a.w > b.w end
        if a.l ~= b.l then return a.l < b.l end
        return a.name < b.name
    end)
    return out
end

-- Elo-Rangliste: alle bisherigen Spiele in zeitlicher Reihenfolge, jeder startet mit 1000.
-- Erwartung E = 1 / (1 + 10^((Gegner - ich) / 400)), Aenderung = K * (Ergebnis - E), K = 32
-- (Sieg gegen Staerkere bringt mehr, Niederlage gegen Schwaechere kostet mehr)
DR.ELO_START, DR.ELO_K = 1000, 32
function DR.Elo()
    local st = {}
    local function s(name)
        local key = mainOf(name)
        st[key] = st[key] or { name = key, elo = DR.ELO_START, w = 0, l = 0, streak = 0, best = 0, peak = DR.ELO_START, last = 0 }
        return st[key]
    end
    for _, d in ipairs(sortedDuels()) do
        if d.winner and d.loser then
            local w, l = s(d.winner), s(d.loser)
            addChar(w, d.winner, true) addChar(l, d.loser, false)
            local ew =1 / (1 + 10 ^ ((l.elo - w.elo) / 400))
            local delta = math.floor(DR.ELO_K * (1 - ew) + 0.5)
            if delta < 1 then delta = 1 end
            w.elo, l.elo = w.elo + delta, l.elo - delta
            w.last, l.last = delta, -delta
            w.w, l.l = w.w + 1, l.l + 1
            w.streak = w.streak >= 0 and w.streak + 1 or 1
            l.streak = l.streak <= 0 and l.streak - 1 or -1
            w.best = math.max(w.best, w.streak)
            w.peak = math.max(w.peak, w.elo)
        end
    end
    local out = {}
    for _, v in pairs(st) do out[#out + 1] = v end
    table.sort(out, function(a, b) if a.elo ~= b.elo then return a.elo > b.elo end return a.name < b.name end)
    return out
end

-- eigene Bilanz gegen jeden Gegner
function DR.Rivals()
    local me = mainOf(ns.me())
    local by = {}
    for _, d in ipairs(sortedDuels()) do
        local w, l = mainOf(d.winner), mainOf(d.loser)
        local opp, won
        if w == me then opp, won = l, true elseif l == me then opp, won = w, false end
        if opp then
            local r = by[opp] or { name = opp, w = 0, l = 0, last = 0 }
            if won then r.w = r.w + 1 else r.l = r.l + 1 end
            r.last = math.max(r.last, d.ts or d.u or 0)
            by[opp] = r
        end
    end
    local out = {}
    for _, r in pairs(by) do out[#out + 1] = r end
    table.sort(out, function(a, b) if a.w + a.l ~= b.w + b.l then return a.w + a.l > b.w + b.l end return a.last > b.last end)
    return out
end

------------------------------------------------------------------------
-- Demo (nur lokal)
------------------------------------------------------------------------
local DEMO = {
    -- Sieger, Verlierer, Start, Einsatz, Wuerfe, vor Stunden
    { "Zul'mira", "Grukthar", 100, "10g", 7, 5 }, { "Zul'mira", "Mokrash", 100, "", 5, 8 }, { "Tavira", "Zul'mira", 1000, "1g", 9, 12 },
    { "Grukthar", "Hoknar", 100, "", 6, 20 }, { "Vex'ra", "Tavira", 10000, "50g", 13, 26 }, { "Vex'ra", "Grukthar", 1000, "", 8, 30 },
    { "Hoknar", "Nakira", 100, "Bier", 4, 33 }, { "Vex'ra", "Drogbar", 100, "", 6, 40 }, { "Nakira", "Mokrash", 1000, "", 10, 47 },
    { "Tavira", "Yenzi", 100, "2g", 5, 52 }, { "Grukthar", "Tavira", 100, "", 7, 60 }, { "Vex'ra", "Zul'mira", 100, "5g", 6, 71 },
    { "ME", "Grukthar", 100, "", 6, 3 }, { "Tavira", "ME", 1000, "1g", 11, 28 }, { "ME", "Hoknar", 100, "", 5, 44 },
}
function DR.SeedDemo()
    local now = ns.now()
    for i, x in ipairs(DEMO) do
        local w = x[1] == "ME" and ns.me() or ns.fullName(x[1])
        local l = x[2] == "ME" and ns.me() or ns.fullName(x[2])
        Store.merge("duels", { id = "demo-dr-" .. i, demo = true, u = now - x[6] * 3600, by = w,
            winner = w, loser = l, start = x[3], stake = x[4], rolls = x[5], ts = now - x[6] * 3600 })
    end
    DR.queue[ns.fullName("Tavira")] = { name = ns.fullName("Tavira"), start = 100, stake = "5g", t = now - 95, race = 5, sex = 1, demo = true }
    DR.queue[ns.fullName("Grukthar")] = { name = ns.fullName("Grukthar"), start = 1000, stake = "", t = now - 40, race = 2, sex = 0, demo = true }
    ns.RefreshPage("deathroll")
end

------------------------------------------------------------------------
-- Seite (Neuaufbau 05.10.): ein Spiel im Spiel
--  oben   Arena-Banner: deine Werte + grosser Knopf (Spielen / Suche laeuft / Zurueck ins Spiel)
--  Leiste Startwert + Einsatz - gilt fuer alles (Spielen, Fordern, Ueben)
--  links  "Will spielen" (Warteliste) und "Online - jetzt fordern" (Gilde, ein Klick)
--  rechts Rangliste / Deine Gegner / Verlauf
------------------------------------------------------------------------
local startVal, rightView, lastFilter = 100, "rank", "all"
local seasonView = "month"   -- Rangliste: "month" (Saison) oder "all" (gesamt)

local function panel(parent, title, color)
    local f = K.Panel(parent, C.panel)
    f.head = K.GameHead(f, title, color or C.red)
    f.head:SetPoint("TOPLEFT", 12, -12)
    f.head:SetWidth(220)
    return f
end

local function fmtNum(n)
    n = tonumber(n) or 0
    local s = tostring(n):reverse():gsub("(%d%d%d)", "%1."):reverse()
    return (s:gsub("^%.", ""))
end

local function streakText(n)
    if n >= 2 then return "|cff66db9e" .. (L["%d Siege in Folge"]):format(n) .. "|r" end
    if n <= -2 then return "|cffe06060" .. (L["%d Niederlagen in Folge"]):format(-n) .. "|r" end
    return ""
end

-- gewaehlter Kaempfer eines anderen (aus seinem Oasis-Profil), nil = unbekannt
function DR.FighterOf(name)
    if not name then return nil end
    if ns.isMe(name) then return DR.MyFighter() end
    local pr = ns.db.members and ns.db.members[name]
    if not pr and ns.Radar and ns.Radar.AliasOf then local a = ns.Radar.AliasOf(name) pr = a and ns.db.members[a] end
    local k = pr and pr.drf
    if type(k) == "string" and FBY[k] then return k end
end
local function curStart(p) return tonumber(p.start:GetText()) or startVal end
local function curStake(p) return (p.stake:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "") end
local function challenge(p, who)
    who = (who or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if who == "" then who = ns.safe(ns.UnitName("target")) or "" end
    if who == "" then ns.print(L["Wen moechtest du herausfordern? Namen eingeben oder jemanden anvisieren."]) return end
    local full = ns.fullName(who)
    local has = ns.Radar and ns.Radar.HasAddon and (ns.Radar.HasAddon(full) or ns.Radar.HasAddon(who))
    -- Oasis-Kontakt in meiner Gruppe: Spiel ueber den Gruppenkanal moeglich (sonst normales /roll-Duell)
    if not has and ns.Contacts and ns.Contacts.Get(full) and ns.Comm.ViaGroup and ns.Comm.ViaGroup(full) then has = true end
    DR.Challenge(who, curStart(p), curStake(p), not has)
end
-- Zustand einer Gegnerkarte: "pending" (meine offene Anfrage an ihn), "playing" (Spiel gegen ihn),
-- "locked" (ich spiele/frage gerade jemand anderen an), nil = frei. 2. Rueckgabe: aktueller Gegner
function DR.CardMode(name)
    local g = DR.game
    if not g or g.bot and g.state ~= "live" then return nil end
    local opp = other(g, ns.me())
    local mine = sameName(opp, name)
    if g.state == "invite_out" then return mine and "pending" or "locked", opp end
    if g.state == "live" or g.state == "invite_in" then return mine and "playing" or "locked", opp end
    return nil, opp
end
-- Klick auf eine Gegnerkarte: fordern / beitreten; waehrend eigener Anfrage an ihn = zurueckziehen
function DR.CardClick(it, p)
    local mode = DR.CardMode(it.name)
    if mode == "pending" then DR.Decline() ns.RefreshPage("deathroll") return end
    if mode == "playing" then DR.Show() return end
    if mode == "locked" then return end   -- nur ein Spiel/eine Anfrage gleichzeitig
    if DR.game then DR.Decline() end      -- beendetes Spiel aufraeumen
    if it.q then DR.JoinGame(it.q.name) else challenge(p, ns.short(it.name)) end
end

-- kleine Kennzahl im Banner
local function stat(parent, label)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(84, 54)
    f.v = K.Title(f, 20, C.text, "CENTER")
    f.l = K.Text(f, 10, C.dim, "CENTER")
    f.l:SetText(K.Upper(label))
    return f
end
-- Kennzahl-Pillen + Startwert/Einsatz an die Breite anpassen: Zahl oben, Beschriftung darunter,
-- Reihe endet mit >= 16 px Abstand vor der rechten Spalte (Kampf!/Ueben/Hinweis). Wenig Platz:
-- kleinere Schrift, sehr wenig Platz: nur 3 Pillen (Platz entfaellt).
local STAT_L, STAT_R = 232, 216 + 16   -- links Kaempfer-Karte, rechts Aktionsspalte (200 + 16 Rand) + Abstand
-- Anzahl, Breite, Abstand, Schriftgroesse der Pillen fuer eine Bannerbreite W
function DR.StatGeometry(W)
    local avail = W - STAT_L - STAT_R
    local gap = 8
    local n = 4
    if (avail - 3 * gap) / 4 < 58 then n = 3 end
    local w = math.floor(math.min(96, math.max(1, (avail - (n - 1) * gap) / n)))
    local size = w >= 70 and 20 or (w >= 58 and 17 or 15)
    return n, w, gap, size
end
function DR.LayoutStats(p)
    local hero = p and p.hero
    if not hero or not p.stBal then return end
    local W = hero:GetWidth() or 0
    if W < 300 then W = 760 end
    local list = { p.stBal, p.stQuote, p.stStreak, p.stRank }
    local n, w, gap, size = DR.StatGeometry(W)
    local prev
    for i, st in ipairs(list) do
        if i > n then st:Hide() else
            st:Show()
            st:SetSize(w, 54)
            st:ClearAllPoints()
            if prev then st:SetPoint("LEFT", prev, "RIGHT", gap, 0) else st:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", STAT_L, 58) end
            if K.SetFontSafe then K.SetFontSafe(st.v, K.FONT_HEAD or K.FONT, size, "", K.FONT) end
            st.v:ClearAllPoints() st.v:SetPoint("TOP", 0, -8) st.v:SetWidth(w - 10)
            st.v:SetJustifyH("CENTER") st.v:SetWordWrap(false)
            st.l:ClearAllPoints() st.l:SetPoint("BOTTOM", 0, 8) st.l:SetWidth(w - 8)
            st.l:SetJustifyH("CENTER") st.l:SetWordWrap(false)
            prev = st
        end
    end
    -- Startwert/Einsatz: Einsatzfeld nimmt den Rest, nichts ragt in die rechte Spalte
    if p.stake and p.start and p.stakeLbl and p.startLbl then
        local bw = W - 224 - 230
        local used = 8 + (p.startLbl:GetStringWidth() or 60) + 12 + 64 + 16 + (p.stakeLbl:GetStringWidth() or 50) + 12
        p.stake:SetWidth(math.floor(math.max(60, math.min(130, bw - used - 8))))
    end
end

ns.RegisterPage({
    key = "deathroll", title = "Todeswuerfeln", order = 7.5,
    sub = "Abwechselnd wuerfeln, das Ergebnis ist das neue Maximum - wer die 1 wuerfelt, verliert",
    build = function(p)
        p:HookScript("OnShow", function(self) self.fresh = true C_Timer.After(0, DR.MusicUpdate) end)
        p:HookScript("OnHide", function() C_Timer.After(0, DR.MusicUpdate) end)
        musicPage = p
        p.fresh = true
        ----------------------------------------------------------------
        -- ARENA-LOBBY: links grosser Kaempfer auf Plattform, Mitte Titel/Werte, rechts KAMPF!-Knopf
        ----------------------------------------------------------------
        local hero = K.Panel(p, { 0.05, 0.025, 0.025, 1 })
        hero:SetPoint("TOPLEFT", 0, 0)
        hero:SetPoint("TOPRIGHT", 0, 0)
        hero:SetHeight(210)
        hero:SetClipsChildren(true)
        p.hero = hero
        hero.arena = hero:CreateTexture(nil, "BACKGROUND", nil, 1)
        if K.BgImg then K.BgImg(hero.arena) end   -- 0.6.227: Helligkeit einstellbar
        hero.arena:SetPoint("TOPLEFT", 1, -1) hero.arena:SetPoint("BOTTOMRIGHT", -1, 1)
        hero.arena:SetTexture(ns.MEDIA .. "dr\\arena")
        hero.arena:SetTexCoord(0, 1, 0.18, 0.72)
        hero.arena:SetAlpha(0.55)
        hero.glow = hero:CreateTexture(nil, "BACKGROUND", nil, 2)
        hero.glow:SetPoint("TOPLEFT", 1, -1) hero.glow:SetPoint("BOTTOMRIGHT", -1, 1)
        if not K.Gradient(hero.glow, "HORIZONTAL", { 0.02, 0.01, 0.01, 0.15 }, { 0.02, 0.01, 0.01, 0.92 }) then hero.glow:SetColorTexture(0, 0, 0, 0.5) end
        hero.top = hero:CreateTexture(nil, "ARTWORK")
        hero.top:SetPoint("TOPLEFT", 1, -1) hero.top:SetPoint("TOPRIGHT", -1, -1) hero.top:SetHeight(2)
        hero.top:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.9)
        -- 0.6.194: mit Gildenmodul Hintergrund "Gothische Festung ueber Lavakluft" mit eigenem Rahmen - Arena-Bild,
        -- rote Oberkante und Panel-Kante dann aus; rechts leicht abgedunkelt fuer die Knoepfe
        if ns.GuildPack then
            hero.arena:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\deathroll_bg")
            hero.arena:SetTexCoord(0, 1, 0, 1)   -- 0.6.196: Bildrahmen bleibt sichtbar (0.6.195 hatte ihn abgeschnitten)
            hero.arena:ClearAllPoints() hero.arena:SetAllPoints()
            hero.arena:SetAlpha(1)
            if not K.Gradient(hero.glow, "HORIZONTAL", { 0, 0, 0, 0 }, { 0, 0, 0, 0.35 }) then hero.glow:SetColorTexture(0, 0, 0, 0.2) end
            hero.top:Hide()
            if hero.bg then hero.bg:SetAlpha(0) end
            if hero.borders then for _, b in ipairs(hero.borders) do b:SetAlpha(0) end end
            if hero.skinLine then for _, b in ipairs(hero.skinLine) do b:SetAlpha(0) end end
        end
        -- Kaempfer auf leuchtender Plattform (Klick: Auswahl)
        local fc = CreateFrame("Button", nil, hero)
        fc:SetSize(210, 206)
        fc:SetPoint("BOTTOMLEFT", 6, 2)
        fc.plat = fc:CreateTexture(nil, "BACKGROUND", nil, 3)
        fc.plat:SetTexture(ns.MEDIA .. "dr\\platform")
        fc.plat:SetSize(230, 96)
        fc.plat:SetPoint("BOTTOM", 0, -6)
        fc.plat:SetBlendMode("ADD")
        fc.plat:SetVertexColor(1, 0.35, 0.25, 0.9)
        fc.light = fc:CreateTexture(nil, "BACKGROUND", nil, 2)
        fc.light:SetTexture(ns.MEDIA .. "shine")
        fc.light:SetPoint("CENTER", 0, 10) fc.light:SetSize(260, 260)
        fc.light:SetVertexColor(C.red[1], C.red[2], C.red[3])
        fc.light:SetAlpha(0.3)
        fc.light:SetBlendMode("ADD")
        fc.m = CreateFrame("PlayerModel", nil, fc)
        fc.m:SetPoint("TOPLEFT", 10, -4) fc.m:SetPoint("BOTTOMRIGHT", -10, 22)
        fc.n = K.Title(fc, 13, C.text, "CENTER")
        fc.n:SetPoint("BOTTOM", 0, 6)
        fc.n:SetWidth(200)
        if ns.GuildPack then   -- 0.6.198: Namensschild schwebt ueber dem Kopf (sanftes Auf und Ab)
            fc.tag = CreateFrame("Frame", nil, fc)
            fc.tag:SetAllPoints()
            fc.tag:SetFrameLevel(fc.m:GetFrameLevel() + 3)   -- ueber dem 3D-Modell
            fc.n:SetParent(fc.tag)
            fc.m:ClearAllPoints()   -- Modell etwas tiefer: Platz fuer das Schild ueber dem Kopf
            fc.m:SetPoint("TOPLEFT", 10, -46) fc.m:SetPoint("BOTTOMRIGHT", -10, 0)
            -- 0.6.206: Kamera etwas weiter weg, damit die ganze Figur hineinpasst (Schulter/Beine wurden abgeschnitten)
            local function zoomOut(m)
                if m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, 0) end
                if m.SetCamDistanceScale then pcall(m.SetCamDistanceScale, m, 1.45) end
            end
            zoomOut(fc.m)
            -- 0.6.207: leuchtende Plattform-Ellipse unter der Figur aus (passt nicht aufs Lava-Bild)
            fc.plat:SetAlpha(0) fc.plat.SetAlpha = function() end fc.plat:Hide() fc.plat.Show = function() end
            fc.m:HookScript("OnModelLoaded", function(self) zoomOut(self) end)
            fc.m:HookScript("OnShow", function(self) zoomOut(self) end)
            fc.n:ClearAllPoints()
            fc.n:SetPoint("TOP", fc, "TOP", 0, -26)
            fc.bob = 0
            fc:HookScript("OnUpdate", function(self, el)
                if ns.db and ns.db.settings.noAnim then return end
                self.bob = (self.bob + (el or 0)) % 3
                self.n:SetPoint("TOP", self, "TOP", 0, -26 + 3 * math.sin(self.bob / 3 * math.pi * 2))
            end)
        end
        if ns.GuildPack then   -- 0.6.197: dunkle Platte hinter dem Namen
            fc.nBg = (fc.tag or fc):CreateTexture(nil, "OVERLAY", nil, -1)
            fc.nBg:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\" .. "dr_plate")
            fc.nBg:SetSize(176, 32)
            fc.nBg:SetPoint("CENTER", fc.n, "CENTER", 0, 0)
        end
        fc.cap = K.Text(fc, 9, C.amber, "CENTER")
        fc.cap:SetPoint("TOP", 0, -6)
        fc.cap:SetText(K.Upper(L["Klick: Kaempfer waehlen"]))
        fc.cap:SetAlpha(0)
        fc:SetScript("OnClick", function() DR.ShowPicker() end)
        fc:SetScript("OnEnter", function(self) self.cap:SetAlpha(1) self.light:SetAlpha(0.55) end)
        fc:SetScript("OnLeave", function(self) self.cap:SetAlpha(0) self.light:SetAlpha(0.3) end)
        fc:SetScript("OnUpdate", function(self, el)
            self.t = (self.t or 0) + el
            self.plat:SetAlpha(0.65 + 0.25 * math.sin(self.t * 2.2))
            -- Figur dreht sich langsam hin und her
            if self.m.fi then pcall(self.m.SetFacing, self.m, 0.35 + 0.35 * math.sin(self.t * 0.6)) end
        end)
        p.fcard = fc
        -- Mitte: Name, Titel, Serie, Werte
        -- Klassenbadge vor dem Namen
        -- 0.6.199: groesser, mit Ornament-Ring in Klassenfarbe (Gildenmodul); eigener Rueckfall, falls der Helfer fehlt
        hero.cls = hero:CreateTexture(nil, "OVERLAY", nil, 1)
        hero.cls:SetSize(26, 26)
        hero.cls:SetPoint("TOPLEFT", 236, -18)
        local _, myClass = UnitClass("player")
        local GI = ns.GuildInfo
        local hasCls = GI and GI.SetClassIcon and GI.SetClassIcon(hero.cls, myClass) or false
        if not hasCls and myClass then
            if hero.cls.SetAtlas and pcall(hero.cls.SetAtlas, hero.cls, "classicon-" .. myClass:lower()) and hero.cls:GetAtlas() then
                hasCls = true
            else
                local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[myClass]
                if tc then
                    hero.cls:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
                    hero.cls:SetTexCoord(tc[1] + 0.015, tc[2] - 0.015, tc[3] + 0.015, tc[4] - 0.015)
                    hasCls = true
                end
            end
        end
        hero.cls:SetShown(hasCls)
        if hasCls and ns.GuildPack then
            hero.clsRing = hero:CreateTexture(nil, "OVERLAY", nil, 2)
            hero.clsRing:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\online_ring")
            hero.clsRing:SetSize(40, 40)
            hero.clsRing:SetPoint("CENTER", hero.cls)
            local cr, cg, cb = ns.classColor(myClass)
            hero.clsRing:SetVertexColor(cr or 0.8, cg or 0.8, cb or 0.8)
        end
        hero.title = K.Title(hero, 26, C.text)
        if hasCls then
            hero.title:SetPoint("LEFT", hero.cls, "RIGHT", 14, 0)
        else
            hero.title:SetPoint("TOPLEFT", 232, -22)
        end
        hero.title:SetText(K.Upper(ns.short(ns.me())))
        hero.rankT = K.Title(hero, 13, C.amber)
        hero.rankT:SetPoint("TOPLEFT", hero.title, "BOTTOMLEFT", 0, -4)   -- 0.6.199: unter dem Namen (nicht unter der Badge)
        -- Flammen bei Siegesserie
        hero.flames = {}
        for i = 1, 3 do
            local f = hero:CreateTexture(nil, "ARTWORK")
            f:SetTexture(ns.MEDIA .. "ember")
            f:SetSize(28, 28)
            f:SetBlendMode("ADD")
            f:SetVertexColor(1, 0.5 + i * 0.1, 0.15)
            f:Hide()
            hero.flames[i] = f
        end
        p.stBal = stat(hero, L["Bilanz"])
        p.stQuote = stat(hero, L["Quote"])
        p.stStreak = stat(hero, L["Serie"])
        p.stRank = stat(hero, L["Platz"])
        hero:HookScript("OnSizeChanged", function() DR.LayoutStats(p) end)
        -- Startwert + Einsatz (unten in der Mitte)
        local bar = CreateFrame("Frame", nil, hero)
        bar:SetPoint("BOTTOMLEFT", 224, 10)
        bar:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", -230, 10)
        bar:SetHeight(34)
        bar.line = bar:CreateTexture(nil, "ARTWORK")
        bar.line:SetPoint("TOPLEFT", 8, 0) bar.line:SetPoint("TOPRIGHT", 0, 0) bar.line:SetHeight(1)
        bar.line:SetColorTexture(1, 1, 1, 0.07)
        local c1 = K.Text(bar, 10, C.dim)
        c1:SetPoint("LEFT", 8, 0)
        c1:SetText(K.Upper(L["Startwert"]))
        p.start = K.Input(bar, 64, "100")
        p.start:SetPoint("LEFT", c1, "RIGHT", 12, 0)
        p.start:SetNumeric(true)
        p.start:SetText(startVal)
        local c2 = K.Text(bar, 10, C.dim)
        c2:SetPoint("LEFT", p.start, "RIGHT", 16, 0)
        c2:SetText(K.Upper(L["Einsatz"]))
        p.stake = K.Input(bar, 96, L["z.B. 10g"])
        p.stake:SetPoint("LEFT", c2, "RIGHT", 12, 0)
        p.startLbl, p.stakeLbl = c1, c2
        if ns.GuildPack then   -- 0.6.200: auf dem Lava-Bild heller + Schatten
            for _, fs in ipairs({ c1, c2 }) do
                fs:SetTextColor(0.8, 0.76, 0.72)
                if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) fs:SetShadowOffset(1, -1) end
            end
        end
        DR.LayoutStats(p)
        -- rechts: KAMPF! (pulsiert), Radar beim Suchen, Ueben
        local right = CreateFrame("Frame", nil, hero)
        right:SetPoint("TOPRIGHT", -16, -16)
        right:SetPoint("BOTTOMRIGHT", -16, 12)
        right:SetWidth(200)
        right.radar = right:CreateTexture(nil, "BACKGROUND", nil, 4)
        right.radar:SetTexture(ns.MEDIA .. "sweep")
        right.radar:SetSize(250, 250)
        right.radar:SetPoint("CENTER", 0, 26)
        right.radar:SetBlendMode("ADD")
        right.radar:SetVertexColor(C.red[1], C.red[2], C.red[3], 0.55)
        right.radar:Hide()
        right.ring = right:CreateTexture(nil, "BACKGROUND", nil, 3)
        right.ring:SetTexture(ns.MEDIA .. "radar")
        right.ring:SetSize(250, 250)
        right.ring:SetPoint("CENTER", 0, 26)
        right.ring:SetVertexColor(C.red[1], C.red[2], C.red[3], 0.35)
        right.ring:Hide()
        p.play = K.Button(right, "", 200, 58, "primary", function()
            if DR.Running() then DR.Show() return end
            if DR.game then DR.Decline() end   -- beendetes Spiel/offene Anfrage sauber aufraeumen
            if DR.inQueue then DR.LeaveQueue() else DR.JoinQueue(curStart(p), curStake(p)) end
            pcall(PlaySound, (SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) or 856, "SFX")
            ns.RefreshPage("deathroll")
        end)
        p.play:SetPoint("TOP", 0, -8)
        p.play.label:SetFont(K.FONT_HEAD or K.FONT, 22, "")
        p.play.halo = p.play:CreateTexture(nil, "BACKGROUND")
        p.play.halo:SetTexture(ns.MEDIA .. "shine")
        p.play.halo:SetPoint("CENTER") p.play.halo:SetSize(330, 140)
        p.play.halo:SetBlendMode("ADD")
        p.play.halo:SetVertexColor(C.red[1], C.red[2], C.red[3])
        p.practice = K.Button(right, L["Ueben gegen die Puppe"], 200, 26, "ghost", function()
            if DR.Running() then ns.print(L["Es laeuft schon ein Spiel."]) DR.Show() return end
            if DR.game then DR.Decline() end
            DR.StartBot("Uebungspuppe", curStart(p), "", 2, 0)
        end)
        p.practice:SetPoint("TOP", p.play, "BOTTOM", 0, -10)
        -- 0.6.197: Bild-Knoepfe (Gildenmodul): Kampf = rote Lavaplatte, Ueben = dunkle Platte. Eigene Flaechen/Kanten des
        -- Knopfs unsichtbar, Hover hellt das Bild auf; calm()/Glas laesst sie in Ruhe (imgSkin)
        local function imgBtn(b, file, w, h)
            if not (ns.GuildPack and b) then return end
            b.imgSkin = true
            if b.sheen then b.sheen:Hide() end
            b.img = b:CreateTexture(nil, "BACKGROUND", nil, -8)
            b.img:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\" .. file)
            b.img:SetSize(w, h)
            b.img:SetPoint("CENTER")
            -- 0.6.198: Leuchten beim Hovern = dasselbe Bild additiv darueber (statt Umfaerben der Knopfflaeche)
            b.imgGlow = b:CreateTexture(nil, "BACKGROUND", nil, -7)
            b.imgGlow:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\" .. file)
            b.imgGlow:SetAllPoints(b.img)
            b.imgGlow:SetBlendMode("ADD")
            b.imgGlow:SetAlpha(0)
            local keep = { [b.img] = true, [b.imgGlow] = true }
            -- eigene Flaechen/Kanten des Knopfs dauerhaft unsichtbar (auch spaeter angelegte, z. B. vom Design)
            local function hideOwn()
                for _, r in ipairs({ b:GetRegions() }) do
                    if not keep[r] and r ~= b.label and r.GetObjectType and r:GetObjectType() == "Texture" and not r.oasisLocked then
                        r:SetAlpha(0)
                        r.SetAlpha = function() end
                        r.oasisLocked = true
                    end
                end
            end
            hideOwn()
            b.hideOwn = hideOwn
            b:HookScript("OnShow", hideOwn)
            local target, cur = 0, 0
            b:SetScript("OnEnter", function(self) hideOwn() target = 0.45 end)
            b:SetScript("OnLeave", function(self) target = 0 end)
            b:HookScript("OnUpdate", function(self, el)
                if cur ~= target then
                    local step = (el or 0) * 3
                    cur = (cur < target) and math.min(target, cur + step) or math.max(target, cur - step)
                    self.imgGlow:SetAlpha(cur)
                end
            end)
        end
        imgBtn(p.play, "dr_fight_btn", 226, 66)
        if p.play.halo and ns.GuildPack then p.play.halo:SetAlpha(0.35) end
        p.practice:SetHeight(30)
        imgBtn(p.practice, "dr_plate", 214, 40)
        p.playHint = K.Text(right, 10, C.muted, "CENTER")
        p.playHint:SetPoint("TOP", p.practice, "BOTTOM", 0, -8)
        p.playHint:SetWidth(200)
        p.playHint:SetWordWrap(false)
        right:SetScript("OnUpdate", function(self, el)
            self.t = (self.t or 0) + el
            local searching = DR.inQueue ~= nil
            p.play.halo:SetAlpha((searching and 0.55 or 0.3) + 0.2 * math.sin(self.t * (searching and 6 or 2.5)))
            if searching then pcall(self.radar.SetRotation, self.radar, -self.t * 2.4) end
            -- Flammen tanzen
            for i, f in ipairs(hero.flames) do
                if f:IsShown() then
                    local k = 1 + 0.18 * math.sin(self.t * (7 + i) + i)
                    f:SetSize(28 * k, 30 * k)
                    f:SetAlpha(0.7 + 0.3 * math.sin(self.t * (9 + i * 2)))
                end
            end
        end)
        p.right = right
        -- Konfetti (Aufstieg in der Rangliste)
        function p:Confetti()
            if ns.db and ns.db.settings.noAnim then return end
            self.conf = self.conf or {}
            local W = hero:GetWidth() or 900
            for i = 1, 40 do
                local c = self.conf[i]
                if not c then c = hero:CreateTexture(nil, "OVERLAY") c:SetTexture(ns.MEDIA .. "diamond") self.conf[i] = c end
                local col = ({ C.red, C.amber, C.mint, { 0.4, 0.6, 1 }, { 1, 1, 1 } })[math.random(5)]
                c:SetVertexColor(col[1], col[2], col[3], 1)
                local sz = math.random(5, 10)
                c:SetSize(sz, sz)
                local x0, drift, delay = math.random(20, math.floor(W) - 20), math.random(-40, 40), math.random() * 0.6
                c:ClearAllPoints()
                c:SetPoint("TOPLEFT", x0, 10)
                c:Show()
                K.Tween(c, 1.6 + math.random() * 0.8, function(q)
                    c:ClearAllPoints()
                    c:SetPoint("TOPLEFT", x0 + drift * q, 10 - q * 230)
                    c:SetAlpha(1 - q * q)
                    if c.SetRotation then pcall(c.SetRotation, c, q * 9) end
                end, function() c:Hide() end, delay)
            end
        end

        local LW = 290   -- 0.5.611: Gegner schmal + untereinander, Rangliste rechts breiter
        local TOP = -220
        ----------------------------------------------------------------
        -- links: GEGNER als Kaempferkarten (wer wartet, steht oben und leuchtet)
        ----------------------------------------------------------------
        local ch = panel(p, L["Gegner"], C.red)
        ch:SetPoint("TOPLEFT", 0, TOP)
        ch:SetPoint("BOTTOMLEFT")
        ch:SetWidth(LW)
        p.lobCount = K.Text(ch, 11, C.dim, "RIGHT")
        p.lobCount:SetPoint("TOPRIGHT", -12, -16)
        -- 0.6.218: Status des Todeswuerfel-Netzes neben der Online-Zahl; nicht verbunden -> Klick verbindet
        local nb = CreateFrame("Button", nil, ch)
        nb:SetSize(110, 16)
        nb:SetPoint("RIGHT", p.lobCount, "LEFT", -22, 0)
        nb.t = K.Text(nb, 10, C.dim, "RIGHT")
        nb.t:SetPoint("RIGHT", 0, 0)
        nb.t:SetWordWrap(false)
        if nb.t.SetShadowColor then nb.t:SetShadowColor(0, 0, 0, 1) nb.t:SetShadowOffset(1, -1) end
        nb.dot = nb:CreateTexture(nil, "OVERLAY")
        nb.dot:SetSize(12, 12)
        nb.dot:SetPoint("RIGHT", nb.t, "LEFT", -1, 0)
        function nb:Update()
            local on = ns.db and ns.db.settings.drNet ~= false
            self:SetShown(on)
            if not on then return end
            local ok = DR.net and DR.net.chan and DR.NetChanId and DR.NetChanId(DR.net.chan)
            self.ok = ok and true or false
            self.t:SetText(ok and ("|cffc8c8cc" .. L["Netz"] .. "|r") or ("|cffe8b44a" .. L["Netz verbinden"] .. "|r"))
            self.dot:SetTexture("Interface\\COMMON\\Indicator-" .. (ok and "Green" or "Red"))
        end
        nb:SetScript("OnClick", function(self)
            if not self.ok then
                if DR.net then DR.net.joinTry = nil end
                DR.NetJoin(curStart(p))
                self.t:SetText("|cffe8b44a" .. L["verbinde ..."] .. "|r")
                C_Timer.After(3.5, function() self:Update() end)
            end
        end)
        nb:SetScript("OnEnter", function(self)
            local lines = { L["Todeswuerfel-Netz"] }
            if self.ok then
                local n = 0
                for _, q in pairs(DR.queue) do if q.net then n = n + 1 end end
                lines[#lines + 1] = "|cff66db9e" .. L["verbunden"] .. "|r  " .. tostring(DR.net.chan)
                lines[#lines + 1] = (L["%d Suchende aus anderen Gilden"]):format(n)
                lines[#lines + 1] = "|cff888888" .. L["Stufe richtet sich nach deinem Startwert (bis 1.000 / 10.000 / darueber)."] .. "|r"
            else
                lines[#lines + 1] = "|cffe06060" .. L["nicht verbunden"] .. "|r"
                lines[#lines + 1] = "|cff888888" .. L["Klick: verbinden - dann siehst du Gegner auch ausserhalb der Gilde."] .. "|r"
            end
            K.ShowTip(self, lines)
        end)
        nb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        nb.acc = 0
        nb:SetScript("OnUpdate", function(self, el) self.acc = self.acc + el if self.acc > 1 then self.acc = 0 self:Update() end end)
        nb:Update()
        p.netBtn = nb
        p.name = K.Input(ch, LW - 24 - 78, L["Name oder Ziel"])
        p.name:SetPoint("TOPLEFT", 12, -40)
        if K.AttachNameSuggest then K.AttachNameSuggest(p.name) end
        p.name.onEnter = function(t) challenge(p, t) end
        p.go = K.Button(ch, L["Fordern"], 70, 24, "primary", function() challenge(p, p.name:GetText()) end)
        p.go:SetPoint("LEFT", p.name, "RIGHT", 8, 0)
        imgBtn(p.go, "dr_fight_btn", 80, 30)   -- 0.6.201
        -- 0.6.212: Bild ragt seitlich ueber den Knopf -> Eingabefeld etwas schmaler, damit nichts rechts ueberlaeuft
        if p.go.img then p.name:SetWidth(math.max(60, (p.name:GetWidth() or (LW - 102)) - 14)) end
        local CW = LW - 16
        local function oppCard(row)
            local c = CreateFrame("Button", nil, row)
            c:SetSize(CW, 48)
            c:SetClipsChildren(true)
            c.bg = K.Fill(c, { 0.07, 0.05, 0.05, 1 })
            c.border = K.Border(c, C.line)
            c.stripe = c:CreateTexture(nil, "ARTWORK")
            c.stripe:SetPoint("TOPLEFT", 1, -1) c.stripe:SetPoint("BOTTOMLEFT", 1, 1) c.stripe:SetWidth(3)
            c.wait = c:CreateTexture(nil, "BORDER")
            c.wait:SetAllPoints()
            c.shine = c:CreateTexture(nil, "BORDER", nil, 1)
            c.shine:SetTexture(ns.MEDIA .. "shine")
            c.shine:SetPoint("CENTER", c, "LEFT", 40, 0) c.shine:SetSize(140, 140)
            c.shine:SetBlendMode("ADD")
            c.shine:SetAlpha(0.25)
            -- Avatar: Klassenring (Klassenfarbe) + Klassensymbol bzw. gewaehlter Kaempfer
            c.ring = c:CreateTexture(nil, "ARTWORK", nil, 1)
            -- Raster in EINER Zeile, alles vertikal zentriert:
            -- [12 | Avatar 40 | 10 | Name / Info-Zeile | 10 | Fordern 84x24 | 10]
            c.ring:SetSize(32, 32)
            c.ring:SetPoint("LEFT", 10, 0)
            c.ring:SetColorTexture(1, 1, 1, 1)
            if K.RoundMask then K.RoundMask(c.ring, c.ring, 16) end
            c.m = CreateFrame("PlayerModel", nil, c)
            c.m:SetPoint("CENTER", c.ring, "CENTER") c.m:SetSize(30, 30)
            c.cls = c:CreateTexture(nil, "ARTWORK", nil, 2)
            c.cls:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            c.cls:SetSize(27, 27)
            c.cls:SetPoint("CENTER", c.ring, "CENTER")
            -- Status-Punkt am Avatar (hat Oasis / nur /roll / wartet), Erklaerung im Tooltip
            c.dot = c:CreateTexture(nil, "OVERLAY", nil, 3)
            c.dot:SetSize(10, 10)
            c.dot:SetPoint("BOTTOMRIGHT", c.ring, "BOTTOMRIGHT", 1, -1)
            c.dot:SetColorTexture(1, 1, 1, 1)
            if K.RoundMask then K.RoundMask(c.dot, c.dot, 5) end
            -- kein Knopf: Klick auf die Karte fordert heraus. Rechts: Lade-Zustand waehrend der eigenen Anfrage
            c.side = CreateFrame("Frame", nil, c)
            c.side:SetSize(18, 18)
            c.side:SetPoint("RIGHT", -12, 0)
            c.spin = c.side:CreateTexture(nil, "OVERLAY")
            c.spin:SetAllPoints()
            c.spin:SetTexture(ns.MEDIA .. "arc")
            c.spin:SetVertexColor(C.accent[1], C.accent[2], C.accent[3], 1)
            c.side:Hide()
            c.state = K.Text(c, 11, C.accent, "RIGHT")
            c.state:SetPoint("RIGHT", c.side, "LEFT", -6, 0)
            c.state:SetWordWrap(false)
            c.n = K.Text(c, 13, C.text)
            c.n:SetPoint("BOTTOMLEFT", c.ring, "RIGHT", 10, 1)
            c.n:SetPoint("RIGHT", -12, 0)
            c.n:SetWordWrap(false)
            c.f = K.Text(c, 11, C.muted)
            c.f:SetPoint("TOPLEFT", c.ring, "RIGHT", 10, -3)
            c.f:SetPoint("RIGHT", -12, 0)
            c.f:SetWordWrap(false)
            c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            c:SetScript("OnEnter", function(self)
                local it = self.item
                if not it then return end
                local mode, opp = DR.CardMode(it.name)
                if mode ~= "locked" then
                    K.SetBorderColor(self, C.accent)
                    self.shine:SetAlpha(0.5)
                end
                local stt = it.q and ("|cffe8b44a" .. L["wartet"] .. "  " .. L["ab "] .. fmtNum(it.q.start) .. "|r")
                    or (it.oasis and ("|cff66db9e" .. L["hat Oasis"] .. "|r") or ("|cff888888" .. L["nur /roll"] .. "|r"))
                local hint
                if mode == "pending" then hint = L["Klick: Anfrage zurueckziehen"]
                elseif mode == "locked" then
                    local g = DR.game
                    if g and g.state == "invite_out" then
                        hint = (L["Warte auf Antwort von %s - Klick auf %s zieht zurueck"]):format(ns.displayName(opp), ns.displayName(opp))
                    else hint = (L["Du spielst gerade gegen %s"]):format(ns.displayName(opp or "?")) end
                elseif mode == "playing" then hint = L["Klick: zum Kampf"]
                else hint = it.q and L["Wartet auf einen Gegner - Klick: annehmen"] or L["Klick: herausfordern"] end
                K.ShowTip(self, { ns.Radar.Colored(it.name), stt, hint, "|cff888888" .. L["Rechtsklick: Menue"] .. "|r" })
            end)
            c:SetScript("OnLeave", function(self) K.SetBorderColor(self, self.item and self.item.q and C.amber or C.line) self.shine:SetAlpha(0.25) GameTooltip:Hide() end)
            c:SetScript("OnClick", function(self, btn)
                local it = self.item
                if not it then return end
                if btn == "RightButton" then
                    local who = it.name
                    K.ShowMenu(self, {
                        { text = L["Herausfordern"], disabled = DR.CardMode(who) == "locked", fn = function() DR.CardClick(it, p) end },
                        { text = L["Fluestern"], fn = function() if ChatFrame_SendTell then ChatFrame_SendTell(Comm.WhisperName(who)) end end },
                        { text = L["Profil ansehen"], disabled = not (ns.Profile and ns.Profile.Show), fn = function() ns.Profile.Show(who) end },
                    }, ns.displayName(who))
                    return
                end
                DR.CardClick(it, p)
            end)
            c:SetScript("OnUpdate", function(self, el)
                local it = self.item
                if not it then return end
                self.t = (self.t or 0) + el
                if it.q then self.wait:SetColorTexture(C.amber[1], C.amber[2], C.amber[3], 0.06 + 0.05 * math.sin(self.t * 4)) end
                -- Sperre/Lade-Zustand laufend nachfuehren (ohne Seiten-Neuaufbau)
                local mode = DR.CardMode(it.name)
                self:SetAlpha(mode == "locked" and 0.4 or 1)
                local pend = mode == "pending"
                self.side:SetShown(pend)
                if pend then
                    self.state:SetText(L["Anfrage gesendet ..."])
                    if not (ns.db and ns.db.settings.noAnim) then pcall(self.spin.SetRotation, self.spin, -self.t * 4) end
                elseif mode == "playing" then self.state:SetText(L["im Kampf"])
                else self.state:SetText("") end
            end)
            return c
        end
        local function fillCard(c, it)
            c.item = it
            if not it then c:Hide() return end
            c:Show()
            local cr, cg, cb = ns.classColor(it.class)
            c.stripe:SetColorTexture(cr or 0.5, cg or 0.5, cb or 0.5, 1)
            c.shine:SetVertexColor(cr or 0.6, cg or 0.6, cb or 0.6)
            local fk = it.fk
            local fi = fk and fk ~= "me" and DR.Fighter(fk)
            if fi and fi.key ~= "me" then
                c.cls:Hide()
                c.m:Show()
                if c.m.key ~= fi.key then
                    c.m.key = fi.key
                    DR.LoadFighter(c.m, fi)
                    DR.ApplyCam(c.m, fi, 0.5)
                    c.m.fi = fi
                    if not c.m.hooked then
                        c.m.hooked = true
                        c.m:SetScript("OnModelLoaded", function(self) DR.ApplyCam(self, self.fi, 0.5) end)
                    end
                end
            else
                c.m:Hide()
                c.m.key = nil
                local tc = it.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[it.class]
                if tc then c.cls:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) c.cls:Show() else c.cls:Hide() end
            end
            c.ring:SetVertexColor(cr or 0.5, cg or 0.5, cb or 0.5, c.m:IsShown() and 0.35 or 0.9)
            -- Info-Zeile: "Lvl 30 · Krieger · Bilanz 4:6" bzw. "... · neu" (wartend: "ab 100")
            local m = ns.Radar.byName and ns.Radar.byName[it.name]
            local sub = {}
            local lvl = m and tonumber(m.level)
            if lvl and lvl > 0 then sub[#sub + 1] = (L["Lvl %d"]):format(lvl) end
            local cn = it.class and ((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[it.class]) or (m and m.classLoc))
            if cn then sub[#sub + 1] = cn end
            if it.q then sub[#sub + 1] = "|cffe8b44a" .. L["ab "] .. fmtNum(it.q.start) .. "|r" end
            sub[#sub + 1] = it.rec ~= "" and it.rec or L["neu"]
            c.f:SetText(table.concat(sub, " · "))
            c.n:SetText(ns.Radar.Colored(it.name))
            -- Status-Punkt am Avatar
            local pc = it.q and C.amber or (it.oasis and C.mint or C.dim)
            c.dot:SetVertexColor(pc[1], pc[2], pc[3], 1)
            if it.q then
                K.SetBorderColor(c, C.amber)
                c.wait:Show()
            else
                K.SetBorderColor(c, C.line)
                c.wait:Hide()
            end
        end
        p.onList = K.List(ch, 52, function(l)
            local r = K.Row(l)
            r.a = oppCard(r) r.a:SetPoint("TOPLEFT", 0, -2)
            if r.hl then r.hl:Hide() end
            return r
        end, function(r, it)
            fillCard(r.a, it)
            r.sel:Hide()
        end)
        p.onList:SetPoint("TOPLEFT", 8, -74)
        p.onList:SetPoint("BOTTOMRIGHT", -8, 6)
        p.onList.empty:SetText(L["Gerade ist sonst niemand online."])

        ----------------------------------------------------------------
        -- rechts: Rangliste (Podest) / Deine Gegner / Verlauf (Kampf-Feed)
        ----------------------------------------------------------------
        local rp = K.Panel(p, C.panel)
        rp:SetPoint("TOPLEFT", LW + 10, TOP)
        rp:SetPoint("BOTTOMRIGHT")
        p.rightSeg = K.Segments(rp, { { key = "rank", text = L["Rangliste"] }, { key = "rivals", text = L["Deine Gegner"] },
            { key = "last", text = L["Verlauf"] } }, function(k)
            rightView = k
            ns.RefreshPage("deathroll")
        end)
        p.rightSeg:SetPoint("TOPLEFT", 6, -6)
        p.lastSeg = K.Segments(rp, { { key = "all", text = L["Alle"] }, { key = "mine", text = L["Meine"] } }, function(k)
            lastFilter = k
            ns.RefreshPage("deathroll")
        end)
        p.lastSeg:SetPoint("TOPRIGHT", -6, -6)
        -- 0.5.622: Elo steht als Spalte, eigener Reiter entfaellt
        p.seasonSeg = K.Segments(rp, { { key = "month", text = L["Monat"] }, { key = "all", text = L["Gesamt"] } }, function(k)
            seasonView = k
            ns.RefreshPage("deathroll")
        end)
        p.seasonSeg:SetPoint("TOPRIGHT", -6, -6)   -- 0.5.799: neben den Reitern statt in eigener Zeile (mehr Platz fuer die Liste)
        -- Reiter immer ueber Podest/Modellen
        for _, sg in ipairs({ p.rightSeg, p.lastSeg, p.seasonSeg }) do if sg.SetFrameLevel then sg:SetFrameLevel(rp:GetFrameLevel() + 30) end end
        p.resetBtn = K.Button(rp, L["Zuruecksetzen"], 96, 20, "ghost", function(self)
            if not self.armed then
                self.armed = true
                self.label:SetText(L["Wirklich?"])
                ns.After(3, function() self.armed = nil self.label:SetText(L["Zuruecksetzen"]) end)
                return
            end
            self.armed = nil
            self.label:SetText(L["Zuruecksetzen"])
            DR.ResetRanking()
        end)
        p.resetBtn:SetPoint("BOTTOMRIGHT", -8, 5)
        p.seasonInfo = K.Text(rp, 10, C.muted)
        p.seasonInfo:SetPoint("BOTTOMLEFT", 10, 9)
        p.seasonInfo:SetPoint("RIGHT", -112, 0)
        p.seasonInfo:SetWordWrap(false)
        -- Podest: Plaetze 1-3 mit Kaempfer, Krone auf Platz 1
        local pod = CreateFrame("Frame", nil, rp)
        -- Podest beginnt direkt unter den Reitern; Modelle bleiben im (beschnittenen) Rahmen
        -- 0.5.799: flacher (128 statt 168), damit darunter deutlich mehr Plaetze sichtbar sind
        pod:SetPoint("TOPLEFT", 8, -38)
        pod:SetPoint("TOPRIGHT", -8, -38)
        pod:SetHeight(128)
        p.podium = pod
        pod.cols = {}
        local ORDER = { 2, 1, 3 }
        local HEIGHT = { 48, 38, 30 }
        local PCOL = { { 1, 0.80, 0.25 }, { 0.80, 0.83, 0.90 }, { 0.85, 0.55, 0.32 } }
        for slot, place in ipairs(ORDER) do
            local col = CreateFrame("Button", nil, pod)
            if col.SetClipsChildren then col:SetClipsChildren(true) end
            col.place = place
            col.block = col:CreateTexture(nil, "ARTWORK")
            col.block:SetPoint("BOTTOMLEFT") col.block:SetPoint("BOTTOMRIGHT")
            col.block:SetHeight(HEIGHT[place])
            local pc = PCOL[place]
            if not K.Gradient(col.block, "VERTICAL", { pc[1] * 0.25, pc[2] * 0.25, pc[3] * 0.25, 0.9 }, { pc[1] * 0.55, pc[2] * 0.55, pc[3] * 0.55, 0.9 }) then col.block:SetColorTexture(pc[1] * 0.4, pc[2] * 0.4, pc[3] * 0.4, 0.9) end
            col.edge = col:CreateTexture(nil, "OVERLAY")
            col.edge:SetPoint("BOTTOMLEFT", col.block, "TOPLEFT") col.edge:SetPoint("BOTTOMRIGHT", col.block, "TOPRIGHT") col.edge:SetHeight(2)
            col.edge:SetColorTexture(pc[1], pc[2], pc[3], 1)
            col.num = K.Title(col, 16, pc, "CENTER")
            col.num:SetPoint("CENTER", col.block, "CENTER", 0, 6)
            col.num:SetText(place)
            col.m = CreateFrame("PlayerModel", nil, col)
            col.m:SetPoint("BOTTOMLEFT", col.block, "TOPLEFT", 8, 14)
            col.m:SetPoint("BOTTOMRIGHT", col.block, "TOPRIGHT", -8, 14)
            col.m:SetHeight(place == 1 and 46 or 42)
            col.cls = col:CreateTexture(nil, "ARTWORK")
            col.cls:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            col.cls:SetSize(32, 32)
            col.cls:SetPoint("BOTTOM", col.block, "TOP", 0, 22)
            col.n = K.Text(col, 11, C.text, "CENTER")
            col.n:SetPoint("BOTTOMLEFT", col.block, "TOPLEFT", 0, 3)
            col.n:SetPoint("BOTTOMRIGHT", col.block, "TOPRIGHT", 0, 3)
            col.n:SetWordWrap(false)
            col.wl = K.Text(col, 10, C.text, "CENTER")
            col.wl:SetPoint("BOTTOM", 0, 3)
            if place == 1 then
                col.crown = col:CreateTexture(nil, "OVERLAY")
                col.crown:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
                col.crown:SetSize(18, 18)
                col.crown:SetPoint("BOTTOM", col.m, "TOP", 0, 0)   -- passt noch in die Saeule (48 + 14 + 46 + 18 < 128)
                col.crown:SetVertexColor(1, 0.8, 0.25)
            end
            col:SetScript("OnClick", function(self) if self.who and not ns.isMe(self.who) then p.name:SetText(ns.displayName(self.who)) end end)
            pod.cols[place] = col
            col.slot = slot
        end
        function pod:Layout()
            local W = self:GetWidth() or 400
            local cw = math.floor((W - 16) / 3)
            for place, col in pairs(self.cols) do
                col:ClearAllPoints()
                col:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", (col.slot - 1) * (cw + 8), 0)
                col:SetSize(cw, 128)
            end
        end
        pod:SetScript("OnSizeChanged", function(self) self:Layout() end)
        -- kompakt: eine Zeile je Spieler (Platz | Klassensymbol | Name | Bilanz | Quote), Zusaetze im Tooltip
        p.rank = K.List(rp, 30, function(l)
            local r = K.Row(l)
            r:Col("pos", 6, 26, 16, C.accent)
            r.cols.pos:SetFont(K.FONT_HEAD, 14, "")
            r.dice = r:CreateTexture(nil, "ARTWORK")
            r.dice:SetSize(18, 18)
            r.dice:SetPoint("LEFT", 10, 0)
            r.dice:SetTexture(ns.MEDIA .. "icons\\deathroll")
            r.cls = r:CreateTexture(nil, "ARTWORK")
            r.cls:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            r.cls:SetSize(18, 18)
            r.cls:SetPoint("LEFT", 34, 0)
            r.cols.name = K.Text(r, 12, C.text)
            r.cols.name:SetPoint("TOPLEFT", 40, -3)
            r.cols.name:SetPoint("RIGHT", r, "RIGHT", -112, 0)
            r.cols.name:SetWordWrap(false)
            r.cols.sub = K.Text(r, 10, C.dim)
            r.cols.sub:SetPoint("BOTTOMLEFT", 40, 3)
            r.cols.sub:SetPoint("RIGHT", r, "RIGHT", -112, 0)
            r.cols.sub:SetWordWrap(false)
            r.cols.wl = K.Text(r, 12, C.text, "RIGHT")
            r.cols.wl:SetPoint("RIGHT", -10, 0)
            -- 0.5.611: Elo als eigene Spalte (in jeder Rangliste)
            r.cols.elo = K.Text(r, 13, { 0.91, 0.71, 0.29 }, "RIGHT")
            r.cols.elo:SetPoint("RIGHT", -120, 0)
            r.cols.elo:SetWidth(54)
            r.cols.eloD = K.Text(r, 9, C.dim, "LEFT")
            r.cols.eloD:SetPoint("LEFT", r.cols.elo, "RIGHT", 3, -1)
            r.bar = K.Bar(r, 100, 2)
            r.bar:SetPoint("BOTTOMRIGHT", -10, 3)
            r:HookScript("OnEnter", function(self)
                local s = self.item
                if not s or rightView ~= "rank" or not s.name then return end
                local lines = { ns.Radar.Colored(s.name) }
                if s.elo then lines[#lines + 1] = (L["Elo %d (Bestwert %d)"]):format(s.elo, s.peak or s.elo) end
                local stt = streakText(s.streak or 0)
                if stt ~= "" then lines[#lines + 1] = stt end
                if s.chars and #s.chars > 1 then
                    lines[#lines + 1] = "|cff888888" .. L["Charaktere:"] .. "|r"
                    for _, x in ipairs(s.chars) do
                        lines[#lines + 1] = ns.Radar.Colored(x.name) .. "  |cff66db9e" .. x.w .. "|r|cff666666 : |r|cffe06060" .. x.l .. "|r"
                    end
                end
                K.ShowTip(self, lines)
            end)
            r:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            r:SetScript("OnClick", function(self)
                local s = self.item
                if not s then return end
                local who = s.name or (ns.isMe(s.winner or "") and s.loser or s.winner)
                if who and not ns.isMe(who) then p.name:SetText(ns.displayName(who)) end
            end)
            return r
        end, function(r, s, i)
            if rightView == "last" then
                local d = s
                r.cols.pos:SetText("")
                r.dice:Show()
                local c = ns.isMe(d.winner) and C.mint or (ns.isMe(d.loser) and C.red or C.dim)
                r.dice:SetVertexColor(c[1], c[2], c[3])
                -- Kampf-Feed: "X besiegt Y in 7 Wuerfen"
                local big = (d.start or 0) >= 1000 and ("  |cffe8b44a" .. L["Hochrisiko!"] .. "|r") or ""
                r.cols.name:SetText(ns.Radar.Colored(d.winner) .. " |cff888888" .. L["besiegt"] .. "|r " .. ns.Radar.Colored(d.loser)
                    .. " |cff888888" .. (L["in %d Wuerfen"]):format(d.rolls or 0) .. "|r" .. big)
                local sub = { L["ab "] .. fmtNum(d.start or 0) }
                if (d.stake or "") ~= "" then sub[#sub + 1] = "|cffe8b44a" .. L["um"] .. " " .. d.stake .. "|r" end
                r.cols.sub:SetText(table.concat(sub, "  ·  "))
                r.cols.wl:SetText("|cff777777" .. ns.ago(d.ts or d.u) .. "|r")
                r.cols.elo:Hide() r.cols.eloD:Hide()
                r.bar:Hide()
                r.cls:Hide()
                r.cols.name:ClearAllPoints() r.cols.name:SetPoint("TOPLEFT", 40, -3) r.cols.name:SetPoint("RIGHT", r, "RIGHT", -112, 0)
                r.cols.sub:Show()
                r.sel:Hide()
                return
            end
            r.dice:Hide()
            local tot = s.w + s.l
            if rightView == "rank" then
                local pos = s.pos or i
                r.cols.pos:SetText(pos)
                r.cols.pos:SetTextColor(unpack(C.dim))
                -- eine Zeile: Platz | Klassensymbol | Name (Main) | Bilanz + Quote; Serie/Elo-Details/Twinks im Tooltip
                local m = ns.Radar.byName and ns.Radar.byName[s.name]
                local tc = m and m.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class]
                if tc then r.cls:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) r.cls:Show() else r.cls:Hide() end
                r.cols.name:ClearAllPoints()
                r.cols.name:SetPoint("LEFT", 58, 0)
                r.cols.name:SetPoint("RIGHT", r, "RIGHT", -182, 0)
                local mark = ""
                if (s.streak or 0) >= 3 then mark = "  |cffff8a2a" .. L["heiss"] .. "|r" end
                if s.chars and #s.chars > 1 then mark = mark .. "  |cff777777+" .. (#s.chars - 1) .. "|r" end
                r.cols.name:SetText(ns.Radar.Colored(s.name) .. (ns.isMe(s.name) and (" |cff888888(" .. L["du"] .. ")|r") or "") .. mark)
                r.cols.sub:SetText("")
                r.cols.sub:Hide()
                r.bar:Hide()
                -- Elo immer zeigen (auch in Monat/Gesamt), Trend zum Bestwert klein daneben
                local e = s.elo and s or (p.eloMap and p.eloMap[s.name])
                r.cols.elo:Show() r.cols.eloD:Show()
                if e and e.elo then
                    r.cols.elo:SetText(e.elo)
                    r.cols.eloD:SetText("")
                else
                    r.cols.elo:SetText("|cff555555-|r")
                    r.cols.eloD:SetText("")
                end
            else
                r.cols.elo:Hide() r.cols.eloD:Hide()
                r.cls:Hide()
                r.bar:Show()
                r.cols.sub:Show()
                r.cols.name:ClearAllPoints() r.cols.name:SetPoint("TOPLEFT", 40, -3) r.cols.name:SetPoint("RIGHT", r, "RIGHT", -112, 0)
                r.cols.pos:SetText("")
                r.cols.name:SetText(ns.Radar.Colored(s.name))
                local lead = s.w > s.l and ("|cff66db9e" .. L["du fuehrst"] .. "|r") or (s.w < s.l and ("|cffe06060" .. L["du liegst hinten"] .. "|r") or L["ausgeglichen"])
                r.cols.sub:SetText(lead .. "  ·  " .. L["zuletzt "] .. ns.ago(s.last))
            end
            r.cols.wl:ClearAllPoints()
            r.cols.wl:SetPoint("RIGHT", -10, rightView == "rank" and 0 or 3)
            r.cols.wl:SetText("|cff66db9e" .. s.w .. "|r |cff666666:|r |cffe06060" .. s.l .. "|r" ..
                (tot > 0 and ("  |cff888888" .. math.floor(s.w / tot * 100 + 0.5) .. " %|r") or ""))
            r.bar:Set(tot > 0 and s.w / tot or 0)
            r.sel:SetShown(rightView == "rank" and ns.isMe(s.name))
        end)
        p.rank:SetPoint("BOTTOMRIGHT", -4, 26)
        -- Spaltenkoepfe der Rangliste
        p.rankHead = CreateFrame("Frame", nil, rp)
        p.rankHead:SetHeight(14)
        p.rankHead:SetPoint("BOTTOMLEFT", p.rank, "TOPLEFT", 0, 2)
        p.rankHead:SetPoint("BOTTOMRIGHT", p.rank, "TOPRIGHT", 0, 2)
        local function hd(txt, pt, x, j)
            local t = K.Text(p.rankHead, 9, C.dim, j)
            t:SetPoint(pt, x, 0)
            t:SetText(txt)
            return t
        end
        hd(L["Spieler"], "LEFT", 58, "LEFT")
        local he = hd(L["Elo"], "RIGHT", -120, "RIGHT") he:SetWidth(54)
        hd(L["Bilanz"], "RIGHT", -10, "RIGHT")
    end,

    refresh = function(p)
        -- Musik auch beim ersten Oeffnen (der OnShow-Haken wird erst beim Aufbau gesetzt)
        C_Timer.After(0, DR.MusicUpdate)
        p.rightSeg:Select(rightView)
        p.lastSeg:Select(lastFilter)
        p.lastSeg:SetShown(rightView == "last")
        p.seasonSeg:SetShown(rightView == "rank")
        p.resetBtn:SetShown(rightView == "rank" and ns.Admin and ns.Admin.CanManage and ns.Admin.CanManage() or false)
        if seasonView == "elo" then seasonView = "month" end
        p.seasonSeg:Select(seasonView)
        local champ, cw = DR.MonthChampion(-1)
        p.seasonInfo:SetText(champ and ((L["Wuerfelkoenig im %s: %s (%d Siege)"]):format(DR.MonthName(-1), ns.Radar.Colored(champ), cw))
            or ((L["Saison %s - wer am Monatsende vorne liegt, wird Wuerfelkoenig des Monats."]):format(DR.MonthName(0))))
        -- Banner-Werte
        local ranking = DR.Ranking()
        local me = mainOf(ns.me())
        local mine
        for _, s in ipairs(ranking) do if s.name == me then mine = s end end
        local w, l = mine and mine.w or 0, mine and mine.l or 0
        p.stBal.v:SetText("|cff66db9e" .. w .. "|r|cff666666 : |r|cffe06060" .. l .. "|r")
        p.stQuote.v:SetText(w + l > 0 and (math.floor(w / (w + l) * 100 + 0.5) .. "%") or "–")
        local st = mine and mine.streak or 0
        p.stStreak.v:SetText(st > 0 and ("|cff66db9e+" .. st .. "|r") or (st < 0 and ("|cffe06060" .. st .. "|r") or "–"))
        local month = DR.Ranking(DR.MonthRange(0))
        local pos
        for i, s in ipairs(month) do if s.name == me then pos = i end end
        p.stRank.v:SetText(pos and ("#" .. pos) or "–")
        local MEDAL = { { 1, 0.82, 0.3 }, { 0.78, 0.8, 0.86 }, { 0.85, 0.55, 0.3 } }
        p.rankMedal = pos and MEDAL[pos] or nil
        local rc = p.rankMedal or C.text
        p.stRank.v:SetTextColor(rc[1], rc[2], rc[3])
        DR.LayoutStats(p)
        -- Titel nach Serie/Platz
        local title
        if pos == 1 and #month > 1 then title = L["Wuerfelkoenig"] .. " · " .. DR.MonthName(0)
        elseif st >= 5 then title = L["Unbesiegbar"]
        elseif st >= 3 then title = L["Heiss gelaufen"]
        elseif st <= -3 then title = L["Pechvogel"]
        elseif w + l == 0 then title = L["Neu in der Arena"]
        else title = (L["Platz %d im %s"]):format(pos or (#month + 1), DR.MonthName(0)) end
        p.hero.rankT:SetText(title)
        -- Flammen ab 3 Siegen in Folge
        local nFl = st >= 7 and 3 or (st >= 5 and 2 or (st >= 3 and 1 or 0))
        for i, f in ipairs(p.hero.flames) do
            f:ClearAllPoints()
            f:SetPoint("LEFT", p.hero.title, "RIGHT", 6 + (i - 1) * 20, 2)
            f:SetShown(i <= nFl)
        end
        -- Konfetti, wenn ich in der Monatsrangliste aufgestiegen bin
        ns.db.drLastPos = ns.db.drLastPos or {}
        local key = DR.MonthName(0)
        local before = ns.db.drLastPos[key]
        if pos and before and pos < before then p:Confetti() pcall(PlaySound, (SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST) or 31578, "SFX") end
        if pos then ns.db.drLastPos[key] = pos end
        if p.fresh then K.FadeIn(p.hero, 0) p.fresh = false end
        -- Kaempfer
        local fi = DR.Fighter(DR.MyFighter())
        p.fcard.n:SetText(L[fi.name])
        if p.fcard.key ~= fi.key then
            p.fcard.key = fi.key
            DR.LoadFighter(p.fcard.m, fi)
            DR.ApplyCam(p.fcard.m, fi, 0.4)
            p.fcard.m.fi, p.fcard.m.facing = fi, 0.4
            if not p.fcard.m.hooked then
                p.fcard.m.hooked = true
                p.fcard.m:SetScript("OnModelLoaded", function(self) DR.ApplyCam(self, self.fi, self.facing) end)
            end
        end
        -- KAMPF!-Knopf
        local searching = DR.inQueue ~= nil
        p.right.radar:SetShown(searching)
        p.right.ring:SetShown(searching)
        if DR.Running() then
            p.play:SetLabel(L["ZUM KAMPF"])
            p.playHint:SetText("|cffff7838" .. L["Ein Spiel laeuft gerade."] .. "|r")
        elseif searching then
            p.play:SetLabel(L["SUCHE ..."])
            p.playHint:SetText("|cffff7838" .. (L["Suche Gegner ab %s ... (Klick: abbrechen)"]):format(fmtNum(DR.inQueue.start)) .. "|r")
        else
            p.play:SetLabel(L["KAMPF!"])
            p.playHint:SetText("")   -- 0.6.205: Ruhetext "Die Gilde bekommt Bescheid" entfernt
        end
        p.practice:SetShown(not DR.Running())
        -- Gegner: Wartende zuerst, dann Online (mit Oasis vor ohne)
        local rivals = {}
        for _, r in ipairs(DR.Rivals()) do rivals[r.name] = r end
        local items, seen = {}, {}
        local function recOf(name)
            local rv = rivals[mainOf(name)]
            return rv and (L["Bilanz"] .. " |cff66db9e" .. rv.w .. "|r|cff666666:|r|cffe06060" .. rv.l .. "|r") or ""
        end
        local waiting = 0
        for _, q in ipairs(DR.Waiting()) do
            if not ns.isMe(q.name) then
                waiting = waiting + 1
                local m = ns.Radar.byName and ns.Radar.byName[q.name]
                items[#items + 1] = { name = q.name, class = m and m.class, oasis = true, q = q, fk = DR.FighterOf(q.name), rec = recOf(q.name) }
                seen[q.name] = true
            end
        end
        local on = {}
        for _, m in ipairs((ns.Radar and ns.Radar.roster) or {}) do
            if m.online and not ns.isMe(m.name) and not seen[m.name] then
                local has = ns.Radar.HasAddon and ns.Radar.HasAddon(m.name)
                on[#on + 1] = { name = m.name, class = m.class, oasis = has, fk = DR.FighterOf(m.name), rec = recOf(m.name) }
            end
        end
        if ns.Contacts and ns.Contacts.Candidates then
            local inOn = {}
            for _, x in ipairs(on) do inOn[x.name] = true end
            for _, c in ipairs(ns.Contacts.Candidates()) do
                if not seen[c.name] and not inOn[c.name] and not ns.isMe(c.name) then
                    on[#on + 1] = { name = c.name, class = c.class, oasis = c.oasis, fk = DR.FighterOf(c.name), rec = recOf(c.name) }
                end
            end
        end
        p.lobbyNames = {}
        for _, x in ipairs(on) do p.lobbyNames[#p.lobbyNames + 1] = x.name end
        table.sort(on, function(a, b)
            if (a.oasis and 1 or 0) ~= (b.oasis and 1 or 0) then return a.oasis end
            return a.name < b.name
        end)
        for _, x in ipairs(on) do items[#items + 1] = x end
        p.onList:SetData(items)
        p.lobCount:SetText(waiting > 0 and ("|cffe8b44a" .. (L["%d warten"]):format(waiting) .. "|r") or ("|cff888888" .. (L["%d online"]):format(#items) .. "|r"))
        -- rechts
        local all = DR.Duels()
        local showPod = rightView == "rank"
        p.podium:SetShown(showPod)
        p.rank:ClearAllPoints()
        p.rank:SetPoint("TOPLEFT", 4, showPod and -188 or -38)
        -- Rangliste einzeilig -> niedrigere Zeilen; Verlauf/Gegner brauchen zwei Zeilen Text
        local rh = showPod and 24 or 30
        if p.rank.rowH ~= rh then
            p.rank.rowH = rh
            for _, row in ipairs(p.rank.rows) do row:SetHeight(rh - 1) end
        end
        p.rankHead:SetShown(showPod)
        p.eloMap = {}
        for _, e in ipairs(DR.Elo() or {}) do p.eloMap[e.name] = e end
        p.rank:SetPoint("BOTTOMRIGHT", -4, 26)
        if rightView == "last" then
            local d = {}
            for _, x2 in ipairs(all) do
                if lastFilter == "all" or ns.isMe(x2.winner) or ns.isMe(x2.loser) then d[#d + 1] = x2 end
            end
            table.sort(d, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
            p.rank:SetData(d)
            p.rank.empty:SetText(L["Noch keine Spiele."])
        elseif showPod then
            local list = seasonView == "month" and month or (seasonView == "elo" and DR.Elo() or ranking)
            p.podium:Layout()
            for place, col in pairs(p.podium.cols) do
                local s = list[place]
                col.who = s and s.name
                if s then
                    col.n:SetText(ns.Radar.Colored(s.name))
                    local pe = s.elo or (p.eloMap[s.name] and p.eloMap[s.name].elo)
                    col.wl:SetText(pe and ("|cffe8b44a" .. pe .. "|r  |cff66db9e" .. s.w .. "|r|cff666666:|r|cffe06060" .. s.l .. "|r")
                        or ("|cff66db9e" .. s.w .. "|r|cff666666:|r|cffe06060" .. s.l .. "|r"))
                    local m = ns.Radar.byName and ns.Radar.byName[s.name]
                    local fk = DR.FighterOf(s.name)
                    local f2 = fk and fk ~= "me" and DR.Fighter(fk)
                    if f2 then
                        col.cls:Hide()
                        col.m:Show()
                        if col.m.key ~= f2.key then
                            col.m.key = f2.key
                            DR.LoadFighter(col.m, f2)
                            DR.ApplyCam(col.m, f2, 0.3)
                            col.m.fi = f2
                            if not col.m.hooked then col.m.hooked = true col.m:SetScript("OnModelLoaded", function(self) DR.ApplyCam(self, self.fi, 0.3) end) end
                        end
                    elseif ns.isMe(s.name) then
                        col.cls:Hide()
                        col.m:Show()
                        if col.m.key ~= "me" then col.m.key = "me" DR.LoadFighter(col.m, DR.Fighter("me")) DR.ApplyCam(col.m, DR.Fighter("me"), 0.3) end
                    else
                        col.m:Hide()
                        col.m.key = nil
                        local tc = m and m.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[m.class]
                        if tc then col.cls:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) col.cls:Show() else col.cls:Hide() end
                    end
                    if col.crown then col.crown:Show() end
                    col:SetAlpha(1)
                else
                    col.n:SetText("|cff555555" .. L["frei"] .. "|r")
                    col.wl:SetText("")
                    col.m:Hide() col.m.key = nil
                    col.cls:Hide()
                    if col.crown then col.crown:Hide() end
                    col:SetAlpha(0.5)
                end
            end
            local rest = {}
            for i = 4, #list do local s = list[i] s.pos = i rest[#rest + 1] = s end
            p.rank:SetData(rest)
            p.rank.empty:SetText(#list == 0 and (seasonView == "month" and L["Diesen Monat noch keine Spiele."] or L["Noch keine Spiele."]) or "")
        else
            p.rank:SetData(DR.Rivals())
            p.rank.empty:SetText(L["Du hast noch nicht gewuerfelt. Fordere jemanden heraus!"])
        end
    end,
})

ns.Listen("LOGIN", function()
    local D = ns.Demo
    if D and not D.drHooked then
        D.drHooked = true
        local load, remove = D.Load, D.Remove
        D.Load = function(...) load(...) DR.SeedDemo() end
        D.Remove = function(...)
            remove(...)
            for n, q in pairs(DR.queue) do if q.demo then DR.queue[n] = nil end end
            ns.RefreshPage("deathroll")
        end
        if D.IsActive() then ns.After(3, DR.SeedDemo) end
    end
end)

ns.Listen("STORE", function(coll) if coll == "duels" then ns.RefreshPage("deathroll") end end)
ns.Listen("LOGIN", function()
    ns.Every(60, function() if DR.inQueue then sendQueue() end end)
    ns.Every(15, function() ns.RefreshPage("deathroll") end)
end)
ns.slash.wuerfeln = function(rest)
    if (rest or ""):lower():match("^%s*reset%s*$") then DR.ResetRanking() return end
    local text = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local name, start = text:match("^(.-)%s+(%d+)$")
    if not name then name = text end
    DR.Challenge(name, tonumber(start) or 100, "", false)
end
ns.slash.deathroll = ns.slash.wuerfeln

Comm.On("DRLOOK", function(sender, _, id, race, sex, gear)
    local g = DR.game
    if not g or g.id ~= id or not fromOpp(g, sender) then return end
    local opp = ns.isMe(g.a) and g.b or g.a
    local items = {}
    for n in tostring(gear or ""):sub(1, 400):gmatch("%d+") do
        if #items >= 19 then break end
        local v = SEC.Num(n, 1, 9999999, true)
        if v then items[#items + 1] = v end
    end
    g.look = g.look or {}
    g.look[opp] = { race = SEC.Num(race, 0, 200, true), sex = SEC.Num(sex, 0, 3, true), gear = items }
    -- nur ein OFFENES Kampffenster auffrischen; bei einer Einladung (Popup offen) kein zweites Fenster aufmachen
    if DR.frame and DR.frame:IsShown() then DR.frame.gameId = nil DR.Show() end
end)

------------------------------------------------------------------------
-- 2026: Glas-Design fuer Deathroll (Seite, Arena, Kaempferwahl, Einladung)
-- Wird ueber die fertigen Frames gelegt; Spiel-Logik (Commit-Reveal, /roll, Einsatz, Elo, Gruppenkanal) bleibt unberuehrt.
-- Bewegung: Nebel (Media\fx\mist256) + aufsteigende Lichtteilchen (spark32), ADD gedaempft, ~30 fps, nur sichtbar, noAnim = still.
------------------------------------------------------------------------
do
    local FX = ns.MEDIA .. "fx\\"
    local function hasGlass() return ns.Insta and ns.Insta.Glass and true or false end
    local function glass(f, fill, line, r) if hasGlass() and f then ns.Insta.Glass(f, fill, line, r) end end
    local function round(t, box, r) if K.RoundMask and t then K.RoundMask(t, box or t, r) end end
    local function animOK() return not (ns.db and ns.db.settings and ns.db.settings.noAnim) end
    local function calm(b, primary, r)
        if not (b and hasGlass()) or b.imgSkin then return b end   -- 0.6.197: Bild-Knoepfe nicht ueberglasen
        local ac = C.accent
        local fill = primary and { ac[1], ac[2], ac[3], 0.20 } or { 1, 1, 1, 0.05 }
        local line = primary and { ac[1], ac[2], ac[3], 0.60 } or { 1, 1, 1, 0.10 }
        if b.sheen then b.sheen:Hide() end
        glass(b, fill, line, r or 9)
        b:SetScript("OnEnter", function(self) glass(self, { fill[1], fill[2], fill[3], fill[4] + 0.06 }, { line[1], line[2], line[3], math.min(1, line[4] + 0.15) }) end)
        b:SetScript("OnLeave", function(self) glass(self, fill, line) end)
        return b
    end
    local function pills(seg)
        if not (seg and seg.buttons and hasGlass()) then return end
        local x = 0
        for _, b in ipairs(seg.buttons) do
            if b.under then b.under:Hide() end
            b:SetHeight(24)
            b:ClearAllPoints()
            b:SetPoint("LEFT", seg, "LEFT", x, 0)
            x = x + (b:GetWidth() or 48) + 4
        end
        seg:SetWidth(math.max(10, x - 4))
        local orig = seg.Select
        function seg:Select(key, user)
            orig(self, key, user)
            local ac = C.accent
            for _, b in ipairs(self.buttons) do
                if b.under then b.under:Hide() end
                local on = b.key == key
                if ns.GuildPack then
                    -- 0.6.203: statt Bild-Platten (passten klein nicht) ruhige Flaechen: aktiv dunkelrot mit Akzentkante,
                    -- sonst fast schwarz mit feiner Bronzekante
                    if on then glass(b, { ac[1] * 0.45, ac[2] * 0.45, ac[3] * 0.45, 0.85 }, { ac[1], ac[2], ac[3], 0.75 }, 6)
                    else glass(b, { 0.03, 0.025, 0.025, 0.85 }, { 0.85, 0.55, 0.25, 0.28 }, 6) end
                    if b.label then b.label:SetTextColor(on and 1 or 0.72, on and 0.94 or 0.68, on and 0.9 or 0.64) end
                else
                    glass(b, on and { ac[1], ac[2], ac[3], 0.15 } or { 1, 1, 1, 0.03 }, on and { ac[1], ac[2], ac[3], 0.45 } or { 1, 1, 1, 0.07 }, 8)
                end
            end
        end
        seg:Select(seg.value)
    end
    -- Gross-Schrift-Beschriftungen in normale Schreibweise zurueckholen
    local UPPER = { "Startwert", "Einsatz", "Klick: Kaempfer waehlen", "Musik", "Sound", "Fordern", "Waehle deinen Kaempfer", "Bilanz", "Quote", "Serie", "Platz" }
    local function deupper(frame)
        if not frame then return end
        local map = {}
        for _, k in ipairs(UPPER) do map[K.Upper(L[k])] = L[k] end
        local function walk(f)
            for _, r in ipairs({ f:GetRegions() }) do
                if r.GetText and r.SetText then
                    local t = r:GetText()
                    if t and map[t] then r:SetText(map[t]) end
                end
            end
            for _, c in ipairs({ f:GetChildren() }) do walk(c) end
        end
        walk(frame)
    end

    -- lebendiger Hintergrund: Nebel driftet, Lichtteilchen steigen auf (gedaempft, nur sichtbar)
    local function addFx(host, col, motes, level)
        local fx = CreateFrame("Frame", nil, host)
        fx:SetAllPoints(host)
        fx:SetFrameLevel(level or host:GetFrameLevel())
        fx:EnableMouse(false)
        if fx.SetClipsChildren then fx:SetClipsChildren(true) end
        fx.mist = {}
        for i = 1, 2 do
            local t = fx:CreateTexture(nil, "BACKGROUND", nil, 5)
            t:SetTexture(FX .. "mist256")
            t:SetBlendMode("ADD")
            t:SetSize(520, 200)
            local k = i == 1 and 0.16 or 0.10
            t:SetVertexColor(col[1] * k, col[2] * k, col[3] * k)
            round(t, host, 12)
            fx.mist[i] = t
        end
        fx.motes = {}
        for i = 1, (motes or 10) do
            local t = fx:CreateTexture(nil, "ARTWORK", nil, 1)
            t:SetTexture(FX .. "spark32")
            t:SetBlendMode("ADD")
            t:SetSize(5, 5)
            t:SetAlpha(0)
            fx.motes[i] = { t = t, life = 0 }
        end
        local function place(tm)
            local W, H = host:GetWidth() or 600, host:GetHeight() or 200
            if W < 50 then W, H = 600, 200 end
            fx.mist[1]:ClearAllPoints()
            fx.mist[1]:SetPoint("CENTER", host, "TOPLEFT", W * (0.3 + 0.12 * math.sin(tm * 0.05)), -H * (0.6 + 0.1 * math.cos(tm * 0.04)))
            fx.mist[2]:ClearAllPoints()
            fx.mist[2]:SetPoint("CENTER", host, "TOPLEFT", W * (0.72 + 0.1 * math.cos(tm * 0.06)), -H * (0.45 + 0.12 * math.sin(tm * 0.05)))
        end
        place(0)
        fx.acc = 0
        fx:SetScript("OnUpdate", function(self, el)
            self.acc = self.acc + (el or 0)
            if self.acc < 0.033 then return end
            local dt = self.acc
            self.acc = 0
            if not animOK() then
                for _, m in ipairs(self.motes) do m.t:SetAlpha(0) m.life = 0 end
                return
            end
            local tm = GetTime()
            place(tm)
            local W, H = host:GetWidth() or 600, host:GetHeight() or 200
            for _, m in ipairs(self.motes) do
                if m.life <= 0 then
                    m.t:SetAlpha(0)
                    if math.random() < 0.03 then
                        m.life, m.max = 1, 3 + math.random() * 3
                        m.x, m.y = math.random() * W, -H + 6
                        m.vx, m.vy = (math.random() - 0.5) * 6, 12 + math.random() * 10
                    end
                else
                    m.life = m.life - dt / m.max
                    m.x, m.y = m.x + m.vx * dt, m.y + m.vy * dt
                    m.t:ClearAllPoints()
                    m.t:SetPoint("CENTER", host, "TOPLEFT", m.x, m.y)
                    local k = math.sin(math.max(0, m.life) * math.pi) * 0.45
                    m.t:SetVertexColor(col[1] * k + 0.08 * k, col[2] * k + 0.08 * k, col[3] * k + 0.08 * k)
                    m.t:SetAlpha(1)
                end
            end
        end)
        return fx
    end
    DR.AddFx = addFx

    ----------------------------------------------------------------
    -- Seite
    ----------------------------------------------------------------
    local def = ns.PageDef and ns.PageDef("deathroll")
    if def then
        local build0, refresh0 = def.build, def.refresh
        def.build = function(p)
            build0(p)
            if not hasGlass() then return end
            local ac = C.accent
            local hero = p.hero
            -- Buehne: dunkles Glas, Arena nur noch als Ahnung, Nebel + Teilchen
            -- 0.6.195: mit Gildenmodul-Bild kein Glas darueber (machte das Bild fast unsichtbar und zog eine Kante)
            if not ns.GuildPack then glass(hero, { 0.03, 0.03, 0.04, 0.92 }, { 1, 1, 1, 0.10 }, 14) end
            if hero.arena then hero.arena:SetAlpha(ns.GuildPack and 1 or 0.22) round(hero.arena, hero, 14) end
            if hero.glow then round(hero.glow, hero, 14) end
            if hero.top then hero.top:Hide() end
            hero.fx = addFx(hero, ac, 12)
            local fc = p.fcard
            fc.plat:SetVertexColor(ac[1] * 0.6, ac[2] * 0.6, ac[3] * 0.6, 0.8)
            fc.light:SetTexture(FX .. "glow128")
            fc.light:SetVertexColor(ac[1] * 0.5, ac[2] * 0.5, ac[3] * 0.5)
            fc.cap:SetTextColor(C.text[1], C.text[2], C.text[3])
            hero.title:SetText(ns.short(ns.me()))
            -- Kennzahlen als Glas-Pillen
            local stats = { { p.stBal, "Bilanz" }, { p.stQuote, "Quote" }, { p.stStreak, "Serie" }, { p.stRank, "Platz" } }
            -- 0.6.200: auf dem Lava-Bild dunkle, fast deckende Kacheln mit Bronzekante (Glas war kaum lesbar)
            local onArt = ns.GuildPack and true or false
            local BRONZE = { 0.85, 0.55, 0.25, 0.6 }
            for i, s in ipairs(stats) do
                local st = s[1]
                if onArt then glass(st, { 0.035, 0.02, 0.02, 0.86 }, BRONZE, 10)
                else glass(st, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.12 }, 10) end
                st.l:SetText(L[s[2]])
                K.SetFontSafe(st.l, K.FONT, 10, "", K.FONT)
                if onArt then
                    st.l:SetTextColor(0.78, 0.74, 0.7)
                    for _, fs in ipairs({ st.v, st.l }) do if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) fs:SetShadowOffset(1, -1) end end
                end
            end
            if onArt then
                -- weiche dunkle Flaeche hinter Name und Werten, laeuft zu den Seiten aus
                local function shade(a1, a2)
                    local t = hero:CreateTexture(nil, "BACKGROUND", nil, 3)
                    if not K.Gradient(t, "HORIZONTAL", { 0, 0, 0, a1 }, { 0, 0, 0, a2 }) then t:SetColorTexture(0, 0, 0, (a1 + a2) / 2) end
                    return t
                end
                hero.midL = shade(0, 0.62)
                hero.midL:SetPoint("TOPLEFT", 190, 0) hero.midL:SetPoint("BOTTOMLEFT", 190, 0) hero.midL:SetWidth(60)
                hero.midC = hero:CreateTexture(nil, "BACKGROUND", nil, 3)
                hero.midC:SetColorTexture(0, 0, 0, 0.62)
                hero.midC:SetPoint("TOPLEFT", hero.midL, "TOPRIGHT") hero.midC:SetPoint("BOTTOMLEFT", hero.midL, "BOTTOMRIGHT")
                hero.midC:SetPoint("RIGHT", hero, "RIGHT", -290, 0)
                hero.midR = shade(0.62, 0)
                hero.midR:SetPoint("TOPLEFT", hero.midC, "TOPRIGHT") hero.midR:SetPoint("BOTTOMLEFT", hero.midC, "BOTTOMRIGHT") hero.midR:SetWidth(60)
                for _, fs in ipairs({ hero.title, hero.rankT }) do if fs and fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) fs:SetShadowOffset(1, -1) end end
            end
            -- Groesse/Lage aus der verfuegbaren Breite (Zahl oben, Beschriftung darunter, Abstand zur rechten Spalte)
            DR.LayoutStats(p)
            -- Kampf! als edler Akzent-Knopf mit sanftem Puls
            calm(p.play, true, 14)
            p.play.halo:SetTexture(FX .. "glow128")
            p.play.halo:SetVertexColor(ac[1] * 0.45, ac[2] * 0.45, ac[3] * 0.45)
            p.play.halo:SetSize(300, 120)
            p.right.radar:SetVertexColor(ac[1], ac[2], ac[3], 0.35)
            p.right.ring:SetVertexColor(ac[1], ac[2], ac[3], 0.22)
            for i, fl in ipairs(hero.flames or {}) do fl:SetTexture(FX .. "glow128") fl:SetVertexColor(1 * 0.6, (0.5 + i * 0.1) * 0.6, 0.1) end
            calm(p.practice) calm(p.go) calm(p.resetBtn)
            for _, e in ipairs({ p.start, p.stake, p.name }) do
                if ns.GuildPack then glass(e, { 0.035, 0.02, 0.02, 0.86 }, { 0.85, 0.55, 0.25, 0.45 }, 8)   -- 0.6.200
                else glass(e, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.12 }, 8) end
            end
            -- Gegner + Rangliste als Glasflaechen, Koepfe normal geschrieben
            local ch = p.onList:GetParent()
            glass(ch, nil, nil, 12)
            if ch.head then ch.head.text:SetText(L["Gegner"]) end
            -- 0.6.201: Gegner-Box mit Tavernen-Bild (eigener Rahmen), Kopf in Gold, Online-Zahl mit gruenem Punkt,
            -- leer: DEATHROLL-Emblem ueber dem Hinweis
            if ns.GuildPack and not ch.art then
                glass(ch, { 0, 0, 0, 0 }, { 0, 0, 0, 0 }, 12)
                ch.art = ch:CreateTexture(nil, "BACKGROUND", nil, 4)
                if K.BgImg then K.BgImg(ch.art) end   -- 0.6.227: Helligkeit einstellbar
                ch.art:SetAllPoints()
                ch.art:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\" .. "dr_opp_bg")
                -- 0.6.203: ganz zeigen (Bildrahmen nicht abschneiden), stark abgedunkelt = dezent
                ch.art:SetTexCoord(0, 1, 0, 1)
                ch.art:SetVertexColor(0.38, 0.36, 0.35)
                -- 0.6.204: Innenabstand zum Bildrahmen
                local PAD = 16
                if ch.head then ch.head:ClearAllPoints() ch.head:SetPoint("TOPLEFT", PAD + 4, -PAD) end
                p.lobCount:ClearAllPoints() p.lobCount:SetPoint("TOPRIGHT", -PAD - 4, -PAD - 4)
                -- 0.6.216: erst den Knopf loesen (hing am Suchfeld), sonst Anker-Kreis -> Fehler beim Aufbau
                p.go:ClearAllPoints() p.go:SetPoint("TOPRIGHT", ch, "TOPRIGHT", -PAD - 4, -PAD - 32)
                p.name:ClearAllPoints() p.name:SetPoint("TOPLEFT", PAD, -PAD - 32)
                p.name:SetPoint("RIGHT", p.go, "LEFT", -8, 0)
                p.onList:ClearAllPoints()
                p.onList:SetPoint("TOPLEFT", PAD, -PAD - 70)
                p.onList:SetPoint("BOTTOMRIGHT", -PAD, PAD)
                ch.topShade = ch:CreateTexture(nil, "BACKGROUND", nil, 5)
                ch.topShade:SetPoint("TOPLEFT", 6, -6) ch.topShade:SetPoint("TOPRIGHT", -6, -6) ch.topShade:SetHeight(110)
                if not K.Gradient(ch.topShade, "VERTICAL", { 0, 0, 0, 0 }, { 0, 0, 0, 0.75 }) then ch.topShade:SetColorTexture(0, 0, 0, 0.4) end
                if ch.head then
                    if ch.head.mark then ch.head.mark:Hide() end
                    ch.head.text:SetTextColor(1, 0.82, 0.45)
                    K.SetFontSafe(ch.head.text, K.FONT_HEAD or K.FONT, 15, "", K.FONT)
                    if ch.head.text.SetShadowColor then ch.head.text:SetShadowColor(0, 0, 0, 1) ch.head.text:SetShadowOffset(1, -1) end
                    ch.head.text:ClearAllPoints() ch.head.text:SetPoint("LEFT", ch.head, "LEFT", 22, 0)
                    ch.headIco = ch:CreateTexture(nil, "OVERLAY")
                    ch.headIco:SetTexture("Interface\\Icons\\Ability_DualWield")
                    ch.headIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    ch.headIco:SetSize(16, 16)
                    ch.headIco:SetPoint("RIGHT", ch.head.text, "LEFT", -6, 0)
                end
                p.lobCount:SetTextColor(0.8, 0.8, 0.82)
                ch.dot = ch:CreateTexture(nil, "OVERLAY")
                ch.dot:SetTexture("Interface\\COMMON\\Indicator-Green")
                ch.dot:SetSize(12, 12)
                ch.dot:SetPoint("RIGHT", p.lobCount, "LEFT", -2, 0)
                ch.emb = ch:CreateTexture(nil, "ARTWORK")
                ch.emb:SetTexture("Interface\\AddOns\\Oasis_Guild\\Media\\" .. "dr_emblem")
                ch.emb:SetBlendMode("ADD")
                ch.emb:SetSize(120, 120)
                ch.emb:SetPoint("BOTTOM", p.onList.empty, "TOP", 0, 4)
                ch.emb:Hide()
                local e = p.onList.empty
                if e.SetShadowColor then e:SetShadowColor(0, 0, 0, 1) e:SetShadowOffset(1, -1) end
                e:SetTextColor(0.9, 0.86, 0.8)
                -- 0.6.217: Emblem aus (lag hinter dem Suchfeld)
            end
            local rp = p.rank:GetParent()
            glass(rp, nil, nil, 12)
            pills(p.rightSeg) pills(p.lastSeg) pills(p.seasonSeg)
            -- Podest: ruhige Glas-Bloecke in Medaillenfarbe
            local PCOL = { { 1, 0.80, 0.25 }, { 0.80, 0.83, 0.90 }, { 0.85, 0.55, 0.32 } }
            p.podium.cardStyle = ns.GuildPack and true or false
            for place, col in pairs(p.podium.cols) do
                local pc = PCOL[place]
                col.block:SetColorTexture(pc[1] * 0.35, pc[2] * 0.35, pc[3] * 0.35, 0.55)
                round(col.block, col.block, 8)
                col.edge:SetAlpha(0)
                col.cls:SetDrawLayer("ARTWORK", 2)
                if p.podium.cardStyle then
                    -- 0.6.201: jede Stufe als Karte in Medaillenfarbe (Verlauf, Rahmen, Lichtkante oben),
                    -- Klassensymbol + Krone oben, Name, grosse Platzzahl, Elo/Bilanz unten; kein 3D-Modell
                    col.block:ClearAllPoints() col.block:SetAllPoints(col)
                    if not K.Gradient(col.block, "VERTICAL", { pc[1] * 0.06, pc[2] * 0.06, pc[3] * 0.06, 0.92 }, { pc[1] * 0.34, pc[2] * 0.34, pc[3] * 0.34, 0.92 }) then col.block:SetColorTexture(pc[1] * 0.2, pc[2] * 0.2, pc[3] * 0.2, 0.92) end
                    if not col.cardBorder then K.Border(col, { pc[1], pc[2], pc[3], 0.7 }) col.cardBorder = true end
                    col.edge:ClearAllPoints() col.edge:SetPoint("TOPLEFT", 1, -1) col.edge:SetPoint("TOPRIGHT", -1, -1) col.edge:SetHeight(2)
                    col.edge:SetAlpha(1)
                    col.m:Hide() col.m.Show = function() end
                    col.cls:ClearAllPoints() col.cls:SetPoint("TOP", 0, -24) col.cls:SetSize(30, 30)
                    if col.crown then col.crown:ClearAllPoints() col.crown:SetPoint("BOTTOM", col.cls, "TOP", 0, -2) col.crown:SetSize(20, 20) end
                    col.n:ClearAllPoints() col.n:SetPoint("TOP", col.cls, "BOTTOM", 0, -4) col.n:SetPoint("LEFT", col, "LEFT", 4, 0) col.n:SetPoint("RIGHT", col, "RIGHT", -4, 0)
                    col.num:ClearAllPoints() col.num:SetPoint("TOP", col.n, "BOTTOM", 0, -2)
                    K.SetFontSafe(col.num, K.FONT_HEAD or K.FONT, 24, "", K.FONT)
                    col.wl:ClearAllPoints() col.wl:SetPoint("BOTTOM", 0, 8)
                    for _, fs in ipairs({ col.n, col.num, col.wl }) do if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) fs:SetShadowOffset(1, -1) end end
                end
            end
            deupper(p)
        end
        def.refresh = function(p)
            refresh0(p)
            if not hasGlass() then return end
            -- Platz-Pille: Gold/Silber/Bronze dezent getoent, ab Platz 4 neutral
            local mc = p.rankMedal
            if mc then glass(p.stRank, { mc[1], mc[2], mc[3], 0.10 }, { mc[1], mc[2], mc[3], 0.45 }, 10)
            else glass(p.stRank, { 1, 1, 1, 0.05 }, { 1, 1, 1, 0.12 }, 10) end
            -- Gegnerkarten (entstehen in der Liste): Glas, Klassenring, ruhiger Fordern-Text, Wartende in Bernstein
            for _, r in pairs(p.onList.rows or {}) do
                for _, c in ipairs({ r.a, r.b }) do
                    if c and not c.glassDone then
                        c.glassDone = true
                        if c.bg then c.bg:Hide() end
                        glass(c, { 1, 1, 1, 0.035 }, { 1, 1, 1, 0.09 }, 12)
                        c.stripe:SetAlpha(0)
                        c.shine:SetTexture(FX .. "glow128")
                        c.wait:SetAlpha(0)
                        c:HookScript("OnEnter", function(self) glass(self, { 1, 1, 1, 0.06 }, { C.accent[1], C.accent[2], C.accent[3], 0.5 }) end)
                        c:HookScript("OnLeave", function(self)
                            local q = self.item and self.item.q
                            glass(self, { 1, 1, 1, 0.035 }, q and { C.amber[1], C.amber[2], C.amber[3], 0.5 } or { 1, 1, 1, 0.09 })
                        end)
                    end
                    if c and c.item then
                        local cr, cg, cb = ns.classColor(c.item.class)
                        c.shine:SetVertexColor((cr or 0.6) * 0.35, (cg or 0.6) * 0.35, (cb or 0.6) * 0.35)
                        local q = c.item.q
                        glass(c, { 1, 1, 1, 0.035 }, q and { C.amber[1], C.amber[2], C.amber[3], 0.5 } or { 1, 1, 1, 0.09 })
                    end
                end
            end
            for _, r in pairs(p.rank.rows or {}) do
                if r.bar and not r.barRound then r.barRound = true round(r.bar.fill, r.bar, 2) end
            end
        end
    end

    ----------------------------------------------------------------
    -- Arena
    ----------------------------------------------------------------
    local arenaDone = false
    local function skinArena(f)
        if arenaDone or not f or not hasGlass() then return end
        arenaDone = true
        local ac = C.accent
        glass(f, { 0.02, 0.02, 0.025, 0.97 }, { 1, 1, 1, 0.12 }, 16)
        f.arena:SetAlpha(0.55)
        round(f.arena, f, 16)
        f.stageLight:SetTexture(FX .. "glow128")
        f.stageLight:SetVertexColor(ac[1] * 0.25, ac[2] * 0.25, ac[3] * 0.25)
        f.stageLight:SetAlpha(1)
        f.stageLight:SetBlendMode("ADD")
        f.fx = addFx(f, ac, 14, f:GetFrameLevel() + 1)
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetText and r:GetText() == L["DEATHROLL"] then r:SetText(L["Todeswuerfeln"]) end
        end
        for _, s in ipairs({ f.A, f.B }) do
            -- HP-Leiste rund (Glas), Fuellungen gerundet
            for _, r in ipairs({ s.bar:GetRegions() }) do
                if r ~= s.lag and r ~= s.fill and r.GetObjectType and r:GetObjectType() == "Texture" then r:Hide() end
            end
            glass(s.bar, { 0, 0, 0, 0.45 }, { 1, 1, 1, 0.14 }, 9)
            round(s.fill, s.bar, 9)
            round(s.lag, s.bar, 9)
            s.glow:SetTexture(FX .. "glow128")
            -- "Am Zug" als kleine Akzent-Pille
            s.turnPill = CreateFrame("Frame", nil, s.top)
            s.turnPill:SetHeight(18)
            s.turnPill:SetPoint("CENTER", s.turn, "CENTER", 0, 0)
            s.turnPill:SetFrameLevel(s.top:GetFrameLevel())
            glass(s.turnPill, { ac[1], ac[2], ac[3], 0.25 }, { ac[1], ac[2], ac[3], 0.7 }, 9)
            s.turnPill:Hide()
            s.turn:SetTextColor(C.text[1], C.text[2], C.text[3])
            if DR.ArtSide then DR.ArtSide(f, s) end
        end
        calm(f.b1, true, 12)
        calm(f.b2) calm(f.pick)
        if f.mLbl then f.mLbl:SetText(L["Musik"]) f.sLbl:SetText(L["Sound"]) end
        f.vs.bg:SetColorTexture(0, 0, 0, 0.6)
        f.vs.word:SetTextColor(ac[1], ac[2], ac[3])
        -- Ergebnis-Rueckblick: Glasflaeche hinter dem Wurfverlauf
        f.histBg = CreateFrame("Frame", nil, f.front)
        f.histBg:SetPoint("BOTTOMLEFT", f.hist, "BOTTOMLEFT", -10, -4)
        f.histBg:SetPoint("TOPRIGHT", f.hist, "TOPRIGHT", 10, 4)
        f.histBg:SetFrameLevel(f.front:GetFrameLevel() - 1)
        glass(f.histBg, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.08 }, 8)
        -- Zahl beim Landen: kurzer weicher Schein (gedaempft)
        f.numGlow = f.center:CreateTexture(nil, "ARTWORK")
        f.numGlow:SetTexture(FX .. "glow128")
        f.numGlow:SetBlendMode("ADD")
        f.numGlow:SetSize(180, 180)
        f.numGlow:SetPoint("CENTER", f.numF, "CENTER", 0, 0)
        f.numGlow:SetAlpha(0)
        f:HookScript("OnUpdate", function(self, el)
            local a = DR.anim
            if a and a.landed and animOK() then
                local k = math.max(0, 1 - ((a.t or 0) - 0.85) / 0.6)
                local c = (a.to or 2) <= 1 and C.red or ac
                self.numGlow:SetVertexColor(c[1] * 0.4 * k, c[2] * 0.4 * k, c[3] * 0.4 * k)
                self.numGlow:SetAlpha(1)
            else
                self.numGlow:SetAlpha(0)
            end
        end)
    end
    local show0 = DR.Show
    function DR.Show(...)
        local r = show0(...)
        skinArena(DR.frame)
        local f, g = DR.frame, DR.game
        if f and g and hasGlass() and f.vs:IsShown() then
            f.vs.a:SetText(ns.displayName(g.a))
            f.vs.b:SetText(ns.displayName(g.b))
        end
        return r
    end
    local update0 = DR.Update
    function DR.Update(...)
        local r = update0(...)
        local f = DR.frame
        if f and f.A and f.A.turnPill then
            for _, s in ipairs({ f.A, f.B }) do
                local t = s.turn:GetText() or ""
                s.turnPill:SetShown(t ~= "")
                if t ~= "" then s.turnPill:SetWidth((s.turn:GetStringWidth() or 40) + 18) end
            end
        end
        return r
    end

    ----------------------------------------------------------------
    -- Kaempferwahl
    ----------------------------------------------------------------
    local pick0 = DR.ShowPicker
    function DR.ShowPicker(...)
        local r = pick0(...)
        local f = _G.OasisFighterSelect
        if f and not f.glassDone and hasGlass() then
            f.glassDone = true
            local ac = C.accent
            glass(f, { 0.02, 0.02, 0.025, 0.97 }, { 1, 1, 1, 0.12 }, 16)
            for _, rg in ipairs({ f:GetRegions() }) do
                if rg.GetObjectType and rg:GetObjectType() == "Texture" and rg:GetHeight() and rg:GetHeight() <= 3 then rg:Hide() end
            end
            f.title:SetText(L["Waehle deinen Kaempfer"])
            f.fx = addFx(f, ac, 10)
            calm(f.ok, true, 12)
            for _, t in ipairs(f.tiles) do
                glass(t, { 1, 1, 1, 0.04 }, { 1, 1, 1, 0.10 }, 10)
                t.glow:SetTexture(FX .. "glow128")
                t.glow:SetVertexColor(ac[1] * 0.5, ac[2] * 0.5, ac[3] * 0.5)
                round(t.nameBg, t, 10)
            end
            local preview0, mark0 = f.Preview, f.Mark
            function f:Preview(fi)
                preview0(self, fi)
                self.bigName:SetText(L[fi.name])
            end
            function f:Mark()
                mark0(self)
                local cur = DR.MyFighter()
                for _, t in ipairs(self.tiles) do
                    local on = t.fi.key == cur
                    glass(t, on and { ac[1], ac[2], ac[3], 0.14 } or { 1, 1, 1, 0.04 }, on and { ac[1], ac[2], ac[3], 0.7 } or { 1, 1, 1, 0.10 })
                end
            end
            for _, t in ipairs(f.tiles) do
                t:HookScript("OnEnter", function(self) glass(self, nil, { ac[1], ac[2], ac[3], 0.5 }) end)
            end
            f:Preview(DR.Fighter(DR.MyFighter()))
            f:Mark()
        end
        return r
    end

    ----------------------------------------------------------------
    -- Einladung: Glas-Popup mit Countdown-Ring um das Wuerfel-Symbol
    ----------------------------------------------------------------
    local inv0 = DR.InvitePopup
    function DR.InvitePopup(...)
        local r = inv0(...)
        local f = _G.OasisDRInvite
        if f and not f.glassDone and hasGlass() then
            f.glassDone = true
            local ac = C.accent
            glass(f, { 0.03, 0.03, 0.035, 0.97 }, { ac[1], ac[2], ac[3], 0.45 }, 14)
            f.top:Hide() f.glow:Hide()
            f.timer:Hide()
            calm(f.yes, true, 10) calm(f.no)
            f.dots = {}
            local N, R = 36, 25
            for i = 1, N do
                local d = f:CreateTexture(nil, "OVERLAY")
                d:SetTexture(ns.MEDIA .. "dot")
                d:SetSize(3, 3)
                local a = math.pi / 2 - (i - 1) / N * math.pi * 2
                d:SetPoint("CENTER", f.icon, "CENTER", math.cos(a) * R, math.sin(a) * R)
                f.dots[i] = d
            end
            f:HookScript("OnUpdate", function(self)
                local k = math.floor(math.max(0, (self.left or 0) / 60) * #self.dots + 0.5)
                for i, d in ipairs(self.dots) do
                    if i <= k then d:SetVertexColor(ac[1], ac[2], ac[3], 0.95) else d:SetVertexColor(1, 1, 1, 0.08) end
                end
            end)
        end
        return r
    end
end

-- Modell im Kaempfer-Vorschaufenster ausprobieren: /oa drmodel 620 | /oa drmodel d4527 | /oa drmodel World\\...\\x.m2
ns.slash.drmodel = function(a)
    a = (a or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if a == "" then ns.print("/oa drmodel <NPC-ID> | d<Display-ID> | <Modellpfad>") return end
    local fi = { key = "test", name = "Test", sub = a, zoom = 0, dist = 1, y = 0 }
    if a:match("^%d+$") then fi.npc = tonumber(a)
    elseif a:match("^d%d+$") then fi.disp = tonumber(a:sub(2))
    else fi.model = { a } end
    local f = picker or buildPicker()
    f:Show()
    f:Preview(fi)
    C_Timer.After(0.6, function()
        local ok, id = pcall(f.big.GetModelFileID, f.big)
        ns.print("drmodel " .. a .. " -> Modell-Datei " .. tostring(ok and id or "?"))
    end)
end
end)

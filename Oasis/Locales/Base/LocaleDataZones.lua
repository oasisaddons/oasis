-- Oasis - Gebietsnamen der Dungeon-Datenbank (englisch -> deutscher Client)
local ADDON, ns = ...
local DE = ns.LOCALE_DE

local Z = {
    ["Tirisfal Glades"] = "Tirisfal",
    ["The Barrens"] = "Brachland",
    ["Blackrock Mountain"] = "Der Schwarzfels",
    ["Eastern Plaguelands"] = "Östliche Pestländer",
    ["Western Plaguelands"] = "Westliche Pestländer",
    ["Ashenvale"] = "Eschental",
    ["Wetlands"] = "Sumpfland",
    ["Un'Goro Crater"] = "Krater von Un'Goro",
    ["Swamp of Sorrows"] = "Sümpfe des Elends",
    ["Stranglethorn Vale"] = "Schlingendorntal",
    ["Stormwind City"] = "Sturmwind",
    ["Silverpine Forest"] = "Silberwald",
    ["Dustwallow Marsh"] = "Düstermarschen",
    ["Duskwood"] = "Dämmerwald",
    ["Badlands"] = "Ödland",
    ["Alterac Mountains"] = "Alteracgebirge",
    ["Thousand Needles"] = "Tausend Nadeln",
}
for k, v in pairs(Z) do DE[k] = v end

-- Chronik-Seite
local DE2 = {
    ["Amnennar der Kaeltebringer"] = "Amnennar der Kältebringer",
    ["Hochinquisitor Weisstraene"] = "Hochinquisitor Weißsträhne",
    ["Haeuptling Ukorz Sandskalp"] = "Häuptling Ukorz Sandskalp",
    ["Klick: nur Eintraege dieser Person"] = "Klick: nur Einträge dieser Person",
    ["%d Eintraege"] = "%d Einträge",
}
for k, v in pairs(DE2) do DE[k] = v end
local EN = ns.LOCALE_EN
local EN2 = {
    ["Heute"] = "Today", ["Gestern"] = "Yesterday",
    ["Sonntag"] = "Sunday", ["Montag"] = "Monday", ["Dienstag"] = "Tuesday", ["Mittwoch"] = "Wednesday",
    ["Donnerstag"] = "Thursday", ["Freitag"] = "Friday", ["Samstag"] = "Saturday",
    ["hat Level %d bis %d erreicht"] = "reached level %d to %d",
    ["Dabei: "] = "Present: ", ["Klick: nur Eintraege dieser Person"] = "Click: only this person's entries",
    ["%d Eintraege"] = "%d entries", ["mit "] = "with ", ["nur "] = "only ",
    ["Diese Woche"] = "This week", ["Am aktivsten (7 Tage)"] = "Most active (7 days)", ["Diese Woche noch ruhig."] = "Quiet week so far.",
    ["Level-Meilensteine"] = "Level milestones", ["Epische Beute"] = "Epic loot", ["Bosse besiegt"] = "Bosses defeated",
    ["Legacy-Challenges"] = "Legacy challenges", ["Neue Mitglieder"] = "New members",
    ["Amnennar der Kaeltebringer"] = "Amnennar the Coldbringer", ["Hochinquisitor Weisstraene"] = "High Inquisitor Whitemane",
    ["Haeuptling Ukorz Sandskalp"] = "Chief Ukorz Sandscalp",
}
for k, v in pairs(EN2) do if not EN[k] then EN[k] = v end end

-- Karte-Seite
local DE3 = {
    ["In deiner Naehe (500 m)"] = "In deiner Nähe (500 m)",
    ["Weltkarte oeffnen"] = "Weltkarte öffnen",
    ["Klick: Weltkarte  ·  Rechtsklick: Ziel, Fluestern, Einladen"] = "Klick: Weltkarte  ·  Rechtsklick: Ziel, Flüstern, Einladen",
    ["Gerade teilt niemand seine Position.\nWer Oasis hat und 'Meine Position teilen' anlaesst, erscheint hier."] = "Gerade teilt niemand seine Position.\nWer Oasis hat und „Meine Position teilen“ anlässt, erscheint hier.",
    ["Wo ist die Gilde? Wer ist in deiner Naehe - mit Entfernung, Richtung und Punkten auf Welt- und Minimap"] = "Wo ist die Gilde? Wer ist in deiner Nähe – mit Entfernung, Richtung und Punkten auf Welt- und Minimap",
    ["Anfluestern"] = "Anflüstern",
}
for k, v in pairs(DE3) do DE[k] = v end
local EN3 = {
    ["Auf der Weltkarte zeigen"] = "Show on world map", ["Als Ziel setzen (Pfeil auf der Minimap)"] = "Set as target (minimap arrow)",
    ["In Gruppe einladen"] = "Invite to group", ["Teilen ihre Position"] = "Sharing position", ["In deinem Gebiet"] = "In your zone",
    ["In deiner Naehe (500 m)"] = "Near you (500 m)", ["Name oder Gebiet suchen ..."] = "Search name or zone ...",
    ["Entfernung: "] = "Distance: ", ["Klick: Weltkarte  ·  Rechtsklick: Ziel, Fluestern, Einladen"] = "Click: world map  ·  Right-click: target, whisper, invite",
    ["dein Gebiet"] = "your zone", ["Gebiete"] = "Zones", ["Noch keine Positionen."] = "No positions yet.",
    ["Nur Gilde mit Oasis, nie in Instanzen"] = "Guild with Oasis only, never in instances",
    ["Gerade teilt niemand seine Position.\nWer Oasis hat und 'Meine Position teilen' anlaesst, erscheint hier."] = "Nobody is sharing their position.\nAnyone with Oasis and 'Share my position' on shows up here.",
    ["Wo ist die Gilde? Wer ist in deiner Naehe - mit Entfernung, Richtung und Punkten auf Welt- und Minimap"] = "Where is the guild? Who is near you – with distance, direction and dots on world map and minimap",
}
for k, v in pairs(EN3) do if not EN[k] then EN[k] = v end end

-- Deathroll-Seite
local DE4 = {
    ["schlaegt"] = "schlägt", ["%d Wuerfe"] = "%d Würfe", ["Wuerfelkoenig"] = "Würfelkönig", ["du fuehrst"] = "du führst",
    ["Laufendes Spiel oeffnen"] = "Laufendes Spiel öffnen",
    ["Du hast noch nicht gewuerfelt. Fordere jemanden heraus!"] = "Du hast noch nicht gewürfelt. Fordere jemanden heraus!",
}
for k, v in pairs(DE4) do DE[k] = v end
local EN4 = {
    ["Deine Bilanz"] = "Your record", ["Siegquote"] = "Win rate", ["Deine Serie"] = "Your streak", ["Spiele in der Gilde"] = "Games in the guild",
    ["Online:"] = "Online:", ["Startwert"] = "Start value", ["Meine"] = "Mine", ["schlaegt"] = "beats", ["ab "] = "from ",
    ["%d Wuerfe"] = "%d rolls", ["Rangliste der Gilde"] = "Guild ranking", ["Deine Gegner"] = "Your opponents",
    ["%d Siege, %d Niederlagen"] = "%d wins, %d losses", ["Siegquote %d %%"] = "Win rate %d %%", ["Beste Serie: %d Siege"] = "Best streak: %d wins",
    ["Klick: als Gegner eintragen"] = "Click: set as opponent", ["Wuerfelkoenig"] = "Dice king", ["du"] = "you",
    ["du fuehrst"] = "you lead", ["du liegst hinten"] = "you trail", ["ausgeglichen"] = "even", ["zuletzt "] = "last ",
    ["%d Siege in Folge"] = "%d wins in a row", ["%d Niederlagen in Folge"] = "%d losses in a row",
    ["Sieg"] = "win", ["Siege"] = "wins", ["Niederlage"] = "loss", ["Niederl."] = "losses", ["%d heute"] = "%d today",
    ["Du hast noch nicht gewuerfelt. Fordere jemanden heraus!"] = "You haven't rolled yet. Challenge someone!",
}
for k, v in pairs(EN4) do if not EN[k] then EN[k] = v end end

-- Deathroll: Lobby + Arena
local DE5 = {
    ["Uebung"] = "Übung", ["Uebungsspiel"] = "Übungsspiel", ["(Uebungsspiel)"] = "(Übungsspiel)", ["Uebungspuppe"] = "Übungspuppe",
    ["WUERFELN"] = "WÜRFELN", ["WUERFELN  1-%d"] = "WÜRFELN  1–%d", ["wuerfeln von 1 bis %d"] = "würfeln von 1 bis %d",
    ["Gerade wartet niemand.\nKlick 'Ich will spielen' - die Gilde bekommt Bescheid."] = "Gerade wartet niemand.\nKlick „Ich will spielen“ – die Gilde bekommt Bescheid.",
    ["Startwert und Einsatz kommen aus 'Direkt herausfordern' unten."] = "Startwert und Einsatz kommen aus „Direkt herausfordern“ unten.",
    ["ab %s - klick zum Mitspielen"] = "ab %s – klick zum Mitspielen",
}
for k, v in pairs(DE5) do DE[k] = v end
local EN5 = {
    ["Uebung"] = "Practice", ["Uebungsspiel"] = "Practice game", ["(Uebungsspiel)"] = "(practice game)", ["Uebungspuppe"] = "Training Dummy",
    ["WUERFELN"] = "ROLL", ["WUERFELN  1-%d"] = "ROLL  1–%d", ["wuerfeln von 1 bis %d"] = "roll from 1 to %d",
    ["Du wartest auf einen Gegner"] = "Waiting for an opponent",
    ["Die Gilde sieht deine Einladung. Sobald jemand mitspielt, geht es los."] = "The guild sees your invite. As soon as someone joins, the game starts.",
    [" will Deathroll spielen"] = " wants to play Deathroll", ["ab %s - klick zum Mitspielen"] = "from %s – click to join",
    ["Die Einladung ist nicht mehr da."] = "That invite is gone.", ["Anfrage gesendet"] = "Request sent", ["Warte auf %s ..."] = "Waiting for %s ...",
    [" spielt schon"] = " is already playing", ["Jemand anderes war schneller."] = "Someone else was faster.",
    ["DEATHROLL"] = "DEATHROLL", ["AM ZUG"] = "YOUR MOVE", ["SIEG!"] = "VICTORY!", ["NIEDERLAGE"] = "DEFEAT",
    ["Gegner ist dran ..."] = "Opponent's turn ...", ["Mitspielen"] = "Join", ["Ich will spielen"] = "I want to play",
    ["Gerade wartet niemand.\nKlick 'Ich will spielen' - die Gilde bekommt Bescheid."] = "Nobody is waiting.\nClick 'I want to play' – the guild gets notified.",
    ["Direkt herausfordern"] = "Challenge directly", ["Einsatz, z.B. 10g"] = "Stake, e.g. 10g", ["Rangliste"] = "Ranking",
    ["Suche abbrechen"] = "Stop searching", ["Du wartest auf einen Gegner (ab %s) ..."] = "Waiting for an opponent (from %s) ...",
    ["Startwert und Einsatz kommen aus 'Direkt herausfordern' unten."] = "Start value and stake come from 'Challenge directly' below.",
    ["wartet gerade"] = "just joined", ["wartet seit %d Min"] = "waiting %d min",
    ["Ohne Addon: "] = "Without addon: ", [" muss /roll "] = " has to type /roll ", [" tippen."] = ".",
}
for k, v in pairs(EN5) do EN[k] = v end

local DE6 = {
    ["Deathroll laeuft weiter"] = "Deathroll läuft weiter",
    ["Nur ausgeblendet - klick hier, um zurueckzukehren. Aufgeben geht nur ueber 'Aufgeben'."] = "Nur ausgeblendet – klick hier, um zurückzukehren. Aufgeben geht nur über „Aufgeben“.",
    ["Ausblenden - das Spiel laeuft weiter"] = "Ausblenden – das Spiel läuft weiter",
}
for k, v in pairs(DE6) do DE[k] = v end
EN["Deathroll laeuft weiter"] = "Deathroll continues"
EN["Nur ausgeblendet - klick hier, um zurueckzukehren. Aufgeben geht nur ueber 'Aufgeben'."] = "Only hidden – click here to return. You only lose by clicking 'Give up'."
EN["Ausblenden - das Spiel laeuft weiter"] = "Hide – the game continues"

-- Chronik-Seite (Neugestaltung: Zeitleiste, Kacheln, Highlight, Aktionen)
local DE7 = {
    ["Klick auf Name: Profil  ·  Rechtsklick: Aktionen"] = "Klick auf Name: Profil  ·  Rechtsklick: Aktionen",
    ["Noch kein Highlight - die Woche ist jung."] = "Noch kein Highlight – die Woche ist jung.",
    ["Nichts gefunden - andere Filter probieren?"] = "Nichts gefunden – andere Filter probieren?",
    ["Stark gemacht, %s - GZ zu %s!"] = "Stark gemacht, %s – GZ zu %s!",
}
for k, v in pairs(DE7) do DE[k] = v end
local EN7 = {
    ["+%d heute"] = "+%d today", ["... und %d weitere"] = "... and %d more", ["Eintrag kopieren"] = "Copy entry",
    ["Erstkill"] = "First kill", ["GZ %s!"] = "Grats %s!", ["GZ zu %s, %s!"] = "Grats on %s, %s!",
    ["GZ zu Level %d, %s!"] = "Grats on level %d, %s!", ["GZ zu Level 60, %s! Willkommen im Endgame!"] = "Grats on level 60, %s! Welcome to the endgame!",
    ["GZ zum neuen Abzeichen, %s!"] = "Grats on the new badge, %s!", ["GZ zur Legacy-Challenge, %s!"] = "Grats on the Legacy challenge, %s!",
    ["Stark gemacht, %s - GZ zu %s!"] = "Well done, %s – grats on %s!", ["Willkommen in der Gilde, %s!"] = "Welcome to the guild, %s!",
    ["Gegenstand im Chat verlinken"] = "Link item in chat", ["Gratulieren"] = "Congratulate", ["Gratulieren im Gildenchat ..."] = "Congratulate in guild chat ...",
    ["Text fuer den Gildenchat:"] = "Text for guild chat:", ["Highlight der Woche"] = "Highlight of the week",
    ["Klick auf Name: Profil  ·  Rechtsklick: Aktionen"] = "Click name: profile  ·  Right-click: actions",
    ["Klick: Filter aufheben"] = "Click: clear filter", ["Klick: Personenfilter aufheben"] = "Click: clear person filter",
    ["Klick: Profil ansehen"] = "Click: view profile", ["Klick: nur diese Art zeigen"] = "Click: show only this kind",
    ["Level 60"] = "Level 60", ["Nichts gefunden - andere Filter probieren?"] = "Nothing found – try other filters?",
    ["Noch kein Highlight - die Woche ist jung."] = "No highlight yet – the week is young.",
    ["Nur Eintraege dieser Person"] = "Only this person's entries", ["Nur meine"] = "Only mine",
    ["Personenfilter aufheben"] = "Clear person filter", ["letzte 7 Tage"] = "last 7 days",
    ["hat %d Abzeichen erhalten"] = "earned %d badges", ["hat %d Beutestuecke erbeutet"] = "looted %d items",
    ["und Gruppe besiegen %d Bosse"] = "and group defeat %d bosses", ["hat %d Wuerfelspiele gespielt"] = "played %d dice games",
    ["%d Gilden-News"] = "%d guild news", ["hat %d Legacy-Challenges geschafft"] = "completed %d Legacy challenges",
}
for k, v in pairs(EN7) do if not EN[k] then EN[k] = v end end

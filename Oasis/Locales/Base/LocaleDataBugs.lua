-- Oasis - Texte: Fehlerberichte + Bug melden
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["Links einen Bericht waehlen."] = "Links einen Bericht wählen.",
    ["Reihenfolge zuruecksetzen"] = "Reihenfolge zurücksetzen",
    ["Koennen"] = "Können",
    ["Beim Oeffnen des Auktionshauses startet Midas den Scan im Hintergrund (hoechstens alle 15 Minuten, Server-Sperre)."] = "Beim Öffnen des Auktionshauses startet Midas den Scan im Hintergrund (höchstens alle 15 Minuten, Server-Sperre).",
}
for k, v in pairs(DEFIX) do DE[k] = v end

local ENC = {
    ["Bug melden"] = "Report a bug",
    ["Was ist passiert? Je genauer, desto schneller ist es behoben. Die Meldung geht an den Entwickler von Oasis."] = "What happened? The more precise, the faster it gets fixed. Your report goes to the Oasis developer.",
    ["Fehler"] = "Bug", ["Idee"] = "Idea", ["Sonstiges"] = "Other",
    ["Zum Beispiel: Auf der Seite Gruppen bleibt die Liste leer, wenn ..."] = "For example: on the Groups page the list stays empty when ...",
    ["Fehler automatisch teilen"] = "Share errors automatically",
    ["Lua-Fehler aus Oasis gehen mit Version und Spielsprache an den Entwickler - keine Chatnachrichten, keine Daten anderer Addons."] = "Lua errors from Oasis go to the developer with version and game language - no chat messages, no data from other addons.",
    ["Senden"] = "Send", ["Abbrechen"] = "Cancel",
    ["Danke!"] = "Thank you!",
    ["Deine Meldung ist unterwegs zum Entwickler."] = "Your report is on its way to the developer.",
    ["Klick: Meldung schreiben"] = "Click: write a report",
    ["Rechtsklick: eingegangene Fehlerberichte"] = "Right-click: incoming bug reports",
    ["Etwas funktioniert nicht oder du hast eine Idee? Hier schreiben - es geht direkt an den Entwickler."] = "Something broken or got an idea? Write it here - it goes straight to the developer.",
    ["Neue Bug-Meldung"] = "New bug report",
    ["Fehlerberichte"] = "Bug reports",
    ["Lua-Fehler und Meldungen aus der Gilde"] = "Lua errors and reports from the guild",
    ["Offen"] = "Open", ["Meldungen"] = "Reports", ["Lua-Fehler"] = "Lua errors", ["Erledigt"] = "Done", ["Wieder offen"] = "Reopen",
    ["Selbst melden"] = "Report myself",
    ["Keine Fehlerberichte - alles ruhig."] = "No bug reports - all quiet.",
    ["Kopieren"] = "Copy", ["Anfluestern"] = "Whisper",
    ["Text ist markiert - Strg+C zum Kopieren."] = "Text is selected - press Ctrl+C to copy.",
    ["Links einen Bericht waehlen."] = "Pick a report on the left.",
    ["zuletzt"] = "last", ["Seite"] = "Page",
    -- Mitglieder-Tooltip
    -- Markt
    ["Midas scannt automatisch"] = "Midas scans automatically", ["Beim Oeffnen des Auktionshauses startet Midas den Scan im Hintergrund (hoechstens alle 15 Minuten, Server-Sperre)."] = "When you open the auction house, Midas starts its scan in the background (at most every 15 minutes, server limit).",
    -- Held/Pechvogel
    ["Pechvogel der Woche"] = "Unlucky one of the week", ["1 Tod"] = "1 death", ["%d Tode"] = "%d deaths", ["meist durch %s"] = "mostly by %s", ["Die meisten Tode der letzten 7 Tage"] = "Most deaths in the last 7 days",
    -- Dashboard
    ["Nachricht der Gildenleitung"] = "Message from the guild leaders", ["Gildennachricht bearbeiten"] = "Edit guild message",
    ["Nachricht"] = "Message", ["Klick: Gildenchat"] = "Click: guild chat", ["Entwickler"] = "Developer",
    -- Profil
    ["Werte"] = "Stats", ["Tagebuch"] = "Diary",
    ["Erfolge"] = "Achievements", ["Koennen"] = "Skills", ["Dein Charakter: Reise, Erfolge, Abenteuer und Ziele"] = "Your character: journey, achievements, adventures and goals",
    -- Navigation
    ["Favoriten stehen ganz oben in der Navigation"] = "Favourites appear at the top of the navigation",
    ["Unter Entdecken jederzeit wieder einschalten"] = "Turn it back on any time under Discover",
    ["Zu Favoriten"] = "Add to favourites", ["Aus Favoriten entfernen"] = "Remove from favourites", ["Reihenfolge zuruecksetzen"] = "Reset order",
    -- Entdecken
    ["Klick: ausblenden"] = "Click: hide", ["%d von %d an"] = "%d of %d on",
    ["Spielzeit"] = "Playtime", ["Woche"] = "week", ["bei dir"] = "near you", ["Gemeinsame Quests"] = "Shared quests",
}
for k, v in pairs(ENC) do if EN[k] == nil then EN[k] = v end end

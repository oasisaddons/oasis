-- Oasis - Texte fuer Uebersicht (Dashboard), Oasis-Leiste und Demo-Daten
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

DE["%d Handwerks-Auftraege warten auf dich"] = "%d Handwerks-Aufträge warten auf dich"
DE["Fuer dich"] = "Für dich"
DE["Was in der Oasis gerade los ist - und was als Naechstes ansteht"] = "Was in der Oasis gerade los ist – und was als Nächstes ansteht"
DE["Alles erledigt - schau in die Chronik"] = "Alles erledigt – schau in die Chronik"
DE["Welcher Abend fuer den naechsten Gildenrun?"] = "Welcher Abend für den nächsten Gildenrun?"
DE["Demo-Daten entfernt (%d Eintraege)."] = "Demo-Daten entfernt (%d Einträge)."

local EN6 = {
    ["%d Handwerks-Auftraege warten auf dich"] = "%d crafting orders are waiting for you",
    ["%d Umfragen warten auf deine Stimme"] = "%d polls are waiting for your vote",
    ["%d deiner Quests hat gerade auch jemand aus der Gilde"] = "%d of your quests are shared by a guildmate right now",
    ["%d neu"] = "%d new",
    ["%d online"] = "%d online",
    ["Alles erledigt - schau in die Chronik"] = "All caught up – check the chronicle",
    ["Demo-Daten entfernt (%d Eintraege)."] = "Demo data removed (%d entries).",
    ["Demo-Daten geladen (nur bei dir, wird nicht an die Gilde gesendet). Entfernen: /oa demo aus"] = "Demo data loaded (only on your client, never sent to the guild). Remove: /oa demo off",
    ["Du hast %d Items, die jemand sucht"] = "You have %d items someone is looking for",
    ["Einklappen (Oasis-Leiste)"] = "Collapse (Oasis bar)",
    ["Fast geschafft: %s (%d/%d)"] = "Almost there: %s (%d/%d)",
    ["Fuer dich"] = "For you",
    ["Gerade niemand online."] = "Nobody online right now.",
    ["Klick: aufklappen"] = "Click: expand",
    ["Mitglied"] = "Member",
    ["Offizier"] = "Officer",
    ["Passender Dungeon: %s (%s)"] = "Dungeon for you: %s (%s)",
    ["Umfrage:"] = "Poll:",
    ["Was in der Oasis gerade los ist - und was als Naechstes ansteht"] = "What's happening in Oasis – and what's coming up",
    ["Was ist los"] = "What's happening",
    ["Welcher Abend fuer den naechsten Gildenrun?"] = "Which evening for the next guild run?",
    ["Ziehen: verschieben (oben am Rand rastet sie ein)"] = "Drag: move (snaps to the top edge)",
    ["sucht:"] = "looking for:",
    ["Dungeon"] = "Dungeon",
}
for k, v in pairs(EN6) do EN[k] = v end

DE["Fuellt Oasis mit Beispiel-Mitgliedern, Terminen, Chronik, Umfragen usw. Bleibt nur bei dir und wird nie an die Gilde gesendet."] = "Füllt Oasis mit Beispiel-Mitgliedern, Terminen, Chronik, Umfragen usw. Bleibt nur bei dir und wird nie an die Gilde gesendet."
EN["Demo-Daten"] = "Demo data"
EN["Demo-Daten entfernen"] = "Remove demo data"
EN["Demo-Daten laden (zum Testen)"] = "Load demo data (for testing)"
EN["Fuellt Oasis mit Beispiel-Mitgliedern, Terminen, Chronik, Umfragen usw. Bleibt nur bei dir und wird nie an die Gilde gesendet."] = "Fills Oasis with sample members, events, chronicle, polls etc. Stays on your client only and is never sent to the guild."
EN["Veteran"] = "Veteran"
EN["%s ist jetzt online."] = "%s is now online."
EN["%s ist jetzt offline."] = "%s is now offline."
DE["um mein Level (+-5)"] = "um mein Level (±5)"
EN["um mein Level (+-5)"] = "around my level (±5)"
EN["Klasse"] = "Class"
EN["Rolle"] = "Role"
EN["Beruf"] = "Profession"
EN["Filter aus"] = "Clear filters"
EN["%d Treffer"] = "%d matches"
EN["NEU"] = "NEW"

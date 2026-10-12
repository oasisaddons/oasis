-- Oasis - Texte: Chat (Privat-Reiter: Kontextmenues, Suche, Filter, Merkliste, Einstellungen)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN
local T = {
    ["%A, %d.%m.%Y %H:%M:%S"] = { "%A, %d.%m.%Y %H:%M:%S", "%A, %m/%d/%Y %H:%M:%S" },
    ["%d.%m.%Y %H:%M"] = { "%d.%m.%Y %H:%M", "%m/%d/%Y %H:%M" },
    ["%d.%m.%Y"] = { "%d.%m.%Y", "%m/%d/%Y" },
    ["Alle Privatgespraeche durchsuchen ..."] = { "Alle Privatgespräche durchsuchen ...", "Search all private chats ..." },
    ["Alles gelesen."] = { "Alles gelesen.", "All read." },
    ["Als ungelesen markieren"] = { "Als ungelesen markieren", "Mark as unread" },
    ["Angeheftet"] = { "Angeheftet", "Pinned" },
    ["Anheften"] = { "Anheften", "Pin" },
    ["Losloesen"] = { "Loslösen", "Unpin" },
    ["Antwort auf"] = { "Antwort auf", "Reply to" },
    ["Antworten / Zitieren"] = { "Antworten / Zitieren", "Reply / quote" },
    ["Battle.net"] = { "Battle.net", "Battle.net" },
    ["Den ganzen Verlauf mit %s loeschen? Gemerkte Nachrichten gehen mit."] = { "Den ganzen Verlauf mit %s löschen? Gemerkte Nachrichten gehen mit.", "Delete the whole history with %s? Saved messages are deleted too." },
    ["Entwurf"] = { "Entwurf", "Draft" },
    ["Freund hinzufuegen"] = { "Freund hinzufügen", "Add friend" },
    ["Freund"] = { "Freund", "Friend" },
    ["Freundesliste ist hier nicht verfuegbar."] = { "Freundesliste ist hier nicht verfügbar.", "Friends list is not available here." },
    ["Gemerkt"] = { "Gemerkt", "Saved" },
    ["Gespeicherte Fluesternachrichten"] = { "Gespeicherte Flüsternachrichten", "Stored whispers" },
    ["Gespraech loeschen"] = { "Gespräch löschen", "Delete conversation" },
    ["Keine Treffer."] = { "Keine Treffer.", "No matches." },
    ["Klick: zum Gildenchat"] = { "Klick: zum Gildenchat", "Click: go to guild chat" },
    ["Klick: zur Nachricht springen"] = { "Klick: zur Nachricht springen", "Click: jump to message" },
    ["Kopieren"] = { "Kopieren", "Copy" },
    ["Loeschen (nur bei dir)"] = { "Löschen (nur bei dir)", "Delete (only for you)" },
    ["Nachricht kopieren"] = { "Nachricht kopieren", "Copy message" },
    ["Nachricht merken"] = { "Nachricht merken", "Save message" },
    ["Nicht mehr merken"] = { "Nicht mehr merken", "Unsave" },
    ["Name eingeben - Gildenmitglieder werden vorgeschlagen."] = { "Name eingeben - Gildenmitglieder werden vorgeschlagen.", "Enter a name - guild members are suggested." },
    ["Neue Nachrichten"] = { "Neue Nachrichten", "New messages" },
    ["Neues Gespraech"] = { "Neues Gespräch", "New chat" },
    ["Nichts angeheftet - Rechtsklick auf ein Gespraech: Anheften."] = { "Nichts angeheftet - Rechtsklick auf ein Gespräch: Anheften.", "Nothing pinned - right-click a conversation: Pin." },
    ["Noch keine Fluesternachrichten. Schreib jemandem aus der Gilde!"] = { "Noch keine Flüsternachrichten. Schreib jemandem aus der Gilde!", "No whispers yet. Write to someone from the guild!" },
    ["Noch nichts gemerkt - Rechtsklick auf eine Nachricht: Nachricht merken."] = { "Noch nichts gemerkt - Rechtsklick auf eine Nachricht: Nachricht merken.", "Nothing saved yet - right-click a message: Save message." },
    ["Notiz zur Person"] = { "Notiz zur Person", "Note about this person" },
    ["Nur diese Person hoert ihn (wenn sie Oasis hat)."] = { "Nur diese Person hört ihn (wenn sie Oasis hat).", "Only this person hears it (if they have Oasis)." },
    ["Nur fuer dich sichtbar - steht im Kopf des Gespraechs mit %s."] = { "Nur für dich sichtbar - steht im Kopf des Gesprächs mit %s.", "Only visible to you - shown in the header of the chat with %s." },
    ["OK"] = { "OK", "OK" },
    ["Position unbekannt."] = { "Position unbekannt.", "Position unknown." },
    ["Privatnachrichten"] = { "Privatnachrichten", "Private messages" },
    ["Rechtsklick: Kopieren, Zitieren, Reagieren, Merken"] = { "Rechtsklick: Kopieren, Zitieren, Reagieren, Merken", "Right-click: copy, quote, react, save" },
    ["Rechtsklick: mehr"] = { "Rechtsklick: mehr", "Right-click: more" },
    ["Senden fehlgeschlagen."] = { "Senden fehlgeschlagen.", "Sending failed." },
    ["Ungelesen"] = { "Ungelesen", "Unread" },
    ["Verlauf exportieren"] = { "Verlauf exportieren", "Export history" },
    ["Verlauf mit %s"] = { "Verlauf mit %s", "History with %s" },
    ["Zitat entfernen"] = { "Zitat entfernen", "Remove quote" },
    ["stumm"] = { "stumm", "muted" },
    ["Entwuerfe je Gespraech merken"] = { "Entwürfe je Gespräch merken", "Remember drafts per conversation" },
    ["Angefangener Text bleibt beim Wechsel des Gespraechs stehen"] = { "Angefangener Text bleibt beim Wechsel des Gesprächs stehen", "Unsent text stays when you switch conversations" },
    ["Reaktionen an den Gespraechspartner schicken"] = { "Reaktionen an den Gesprächspartner schicken", "Send reactions to your chat partner" },
    ["Nur wenn er Oasis hat - sonst bleibt die Reaktion bei dir"] = { "Nur wenn er Oasis hat - sonst bleibt die Reaktion bei dir", "Only if they have Oasis - otherwise the reaction stays with you" },
}
for k, v in pairs(T) do
    if DE and DE[k] == nil then DE[k] = v[1] end
    if EN and EN[k] == nil then EN[k] = v[2] end
end
if EN and EN["Vorschau:"] == nil then EN["Vorschau:"] = "Preview:" end
for k, v in pairs({
    ["Zuordnen zu ..."] = "Assign to ...", ["Zugeordnet"] = "Assigned", ["Name eingeben ..."] = "Enter name ...",
    ["Verlauf von %s steht jetzt bei %s."] = "History of %s is now with %s.",
    ["Charaktername der Person (z.B. Anna Berg)"] = "Character name of the person (e.g. Anna Berg)",
}) do if EN and EN[k] == nil then EN[k] = v end end
-- Privat-Ansicht (neues Design): Kopf-Knoepfe, Status-Pille, Senden-Tooltip
for k, v in pairs({
    ["Mehr"] = "More", ["AFK"] = "AFK", ["Enter"] = "Enter", ["nicht in der Gilde"] = "not in the guild",
}) do if EN and EN[k] == nil then EN[k] = v end end
if DE then
    DE["Mehr"] = DE["Mehr"] or "Mehr"
    DE["AFK"] = DE["AFK"] or "AFK"
    DE["Enter"] = DE["Enter"] or "Enter"
    DE["nicht in der Gilde"] = DE["nicht in der Gilde"] or "nicht in der Gilde"
end
if DE then
    DE["Verlauf von %s steht jetzt bei %s."] = DE["Verlauf von %s steht jetzt bei %s."] or "Verlauf von %s steht jetzt bei %s."
end

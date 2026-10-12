-- Oasis - Texte: Chat-Darstellung (Schrift, Farben, Abstaende, Zahnrad im Chat)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["Schrift, Farben und Abstaende - nur fuer dich"] = "Schrift, Farben und Abstände - nur für dich",
    ["Schriftgroesse"] = "Schriftgröße",
    ["Farbe waehlen"] = "Farbe wählen",
    ["Zuruecksetzen"] = "Zurücksetzen",
    ["Emoji-Groesse im Chat"] = "Emoji-Größe im Chat",
}
for k, v in pairs(DEFIX) do DE[k] = v end

local ENC = {
    ["Chat-Darstellung"] = "Chat appearance",
    ["Schrift, Farben und Abstaende - nur fuer dich"] = "Font, colors and spacing - just for you",
    ["Darstellung"] = "Appearance",
    ["Schriftart"] = "Font",
    ["Oasis-Schrift"] = "Oasis font",
    ["Schriftgroesse"] = "Font size",
    ["Zeilenabstand"] = "Line spacing",
    ["Emoji-Groesse im Chat"] = "Emoji size in chat",
    ["Farbe waehlen"] = "Pick color",
    ["Schriftfarbe"] = "Text color",
    ["Zeitstempel"] = "Timestamp",
    ["Hintergrund"] = "Background",
    ["Deckkraft Hintergrund"] = "Background opacity",
    ["Blase eigene (Privat)"] = "Own bubble (private)",
    ["Blase fremde (Privat)"] = "Other bubble (private)",
    ["Zeitstempel anzeigen"] = "Show timestamps",
    ["Nachrichten gruppieren"] = "Group messages",
    ["Mehrere Nachrichten derselben Person kurz hintereinander stehen unter einem Namen"] = "Several messages from the same person in quick succession appear under one name",
    ["Zuruecksetzen"] = "Reset",
    ["Neue Nachrichten"] = "New messages",
    ["Neu seit deinem letzten Besuch"] = "New since your last visit",
    ["Rechtsklick: Reagieren, Antworten, Zitieren, Anpinnen ..."] = "Right-click: react, reply, quote, pin ...",
    ["schreiben"] = "writing",
    ["Nachrichten"] = "Messages",
}
for k, v in pairs(ENC) do EN[k] = v end

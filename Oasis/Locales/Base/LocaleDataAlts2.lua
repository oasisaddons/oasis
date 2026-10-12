-- Oasis - Texte: Main/Twink-Abfrage, Reiter "Charaktere", "Twink von" in der Mitgliederliste
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["Oasis fasst deine Charaktere in der Gilde zu einem Spieler zusammen. Spaeter aenderbar unter Einstellungen > Profil & Sichern."] = "Oasis fasst deine Charaktere in der Gilde zu einem Spieler zusammen. Später änderbar unter Einstellungen > Profil & Sichern.",
    ["Spaeter"] = "Später",
    ["Zurueck"] = "Zurück",
    ["Klick: Profilkarte oeffnen"] = "Klick: Profilkarte öffnen",
}
for k, v in pairs(DEFIX) do DE[k] = v end

local ENC = {
    ["Ist %s dein Main oder ein Twink?"] = "Is %s your main or an alt?",
    ["Oasis fasst deine Charaktere in der Gilde zu einem Spieler zusammen. Spaeter aenderbar unter Einstellungen > Profil & Sichern."] = "Oasis groups your characters in the guild into one player. You can change this later under Settings > Profile & Backup.",
    ["Main"] = "Main", ["Twink"] = "Alt", ["Spaeter"] = "Later", ["Zurueck"] = "Back", ["Speichern"] = "Save",
    ["Twink von"] = "Alt of", ["Twink von %s"] = "Alt of %s",
    ["%s ist jetzt dein Main."] = "%s is now your main.",
    ["%s ist jetzt Twink von %s."] = "%s is now an alt of %s.",
    ["Gespeichert"] = "Saved",
    ["Charaktere"] = "Characters", ["Lvl %s %s"] = "Lvl %s %s", ["diese Karte"] = "this card",
    ["Klick: Profilkarte oeffnen"] = "Click: open profile card",
    ["Keine Berufe bekannt."] = "No professions known.",
    ["Rolle"] = "Role",
}
for k, v in pairs(ENC) do if EN[k] == nil then EN[k] = v end end

-- Oasis - Texte: Profil (Chronik-Kacheln)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN
local T = {
    ["Aktive Tage"] = { "Aktive Tage", "Active days" },
    ["Level-Ups diese Woche"] = { "Level-Ups diese Woche", "Level-ups this week" },
    ["Schritte heute"] = { "Schritte heute", "Steps today" },
    ["Schritte Woche"] = { "Schritte diese Woche", "Steps this week" },
    ["Klick: Waffenmeister auf der Karte zeigen"] = { "Klick: Waffenmeister auf der Karte zeigen", "Click: show weapon master on the map" },
    ["Umfragen koennen nur Offiziere und die Gildenleitung starten."] = { "Umfragen können nur Offiziere und die Gildenleitung starten.", "Only officers and the guild leadership can start polls." },
    ["Das ist eine Demo-Quest - sie steht nicht in deinem Questlog."] = { "Das ist eine Demo-Quest – sie steht nicht in deinem Questlog.", "This is a demo quest - it is not in your quest log." },
    ["Diese Quest hat %s, nicht du."] = { "Diese Quest hat %s, nicht du.", "%s has this quest, not you." },
    ["Nur fuer den Schlachtzugsleiter"] = { "Nur für den Schlachtzugsleiter", "Raid leader only" },
    ["Schlachtzugsleiter und Raid-Assistenten benennt die Gildenleitung (Krone > Module > Raids & Beute). Im laufenden Raid zaehlen auch Raidleiter und Assistenten."] = { "Schlachtzugsleiter und Raid-Assistenten benennt die Gildenleitung (Krone > Module > Raids & Beute). Im laufenden Raid zählen auch Raidleiter und Assistenten.", "Raid leaders and assistants are set by the guild leadership (crown > modules > Raids & Loot). In a running raid the raid leader and assistants count too." },
    ["Du hast diese Rechte."] = { "Du hast diese Rechte.", "You have these rights." },
    ["Du hast diese Rechte nicht - du siehst nur."] = { "Du hast diese Rechte nicht – du siehst nur.", "You don't have these rights - view only." },
}
for k, v in pairs(T) do
    if DE and DE[k] == nil then DE[k] = v[1] end
    if EN and EN[k] == nil then EN[k] = v[2] end
end

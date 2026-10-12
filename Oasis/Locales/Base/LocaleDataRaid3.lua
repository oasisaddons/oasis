-- Oasis - Texte: Neugestaltung Raid-Zeit (Modules\RaidTime.lua), Raid-IDs (Modules\Lockouts.lua), Kampfberichte (Modules\WipeReport.lua)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

-- Deutsch: nur, wo die automatische Umlaut-Ableitung nicht reicht (ß, Gedankenstrich)
local DEFIX = {
    ["Raidgroesse"] = "Raidgröße",
    ["Abends ist noch kein Fenster mit genug Leuten. Probier eine kleinere Raidgroesse - oder lass auch Zeiten tagsueber zu."] = "Abends ist noch kein Fenster mit genug Leuten. Probier eine kleinere Raidgröße – oder lass auch Zeiten tagsüber zu.",
    ["Kein Zeitfenster mit genug Leuten. Probier eine kleinere Raidgroesse oder einen kuerzeren Raidabend (Zahnrad)."] = "Kein Zeitfenster mit genug Leuten. Probier eine kleinere Raidgröße oder einen kürzeren Raidabend (Zahnrad).",
    ["Niemand gestorben - sauber gespielt."] = "Niemand gestorben – sauber gespielt.",
    ["Noch keine Kampfberichte. Nach dem ersten Bosskampf steht hier jeder Versuch - mit Zeitstrahl der Tode und wiederkehrenden Mustern."] = "Noch keine Kampfberichte. Nach dem ersten Bosskampf steht hier jeder Versuch – mit Zeitstrahl der Tode und wiederkehrenden Mustern.",
    ["Raid-Check-Modul fehlt - diese Ansicht braucht seine Bausteine."] = "Raid-Check-Modul fehlt – diese Ansicht braucht seine Bausteine.",
    ["Hoehe = geschafftes Boss-Leben, Klick waehlt den Versuch"] = "Höhe = geschafftes Boss-Leben, Klick wählt den Versuch",
}
for k, v in pairs(DEFIX) do if DE[k] == nil then DE[k] = v end end

local ENC = {
    ["%d geteilt"] = "%d shared",
    ["%d%% Quote"] = "%d%% rate",
    ["Abends ist noch kein Fenster mit genug Leuten. Probier eine kleinere Raidgroesse - oder lass auch Zeiten tagsueber zu."] = "No evening window with enough people yet. Try a smaller raid size – or allow daytime slots too.",
    ["Auch tagsueber"] = "Include daytime",
    ["Besetzung"] = "Turnout",
    ["Bestes Ergebnis"] = "Best result",
    ["Boss waehlen"] = "Choose boss",
    ["Boss-Leben"] = "Boss health",
    ["Der Mitschnitt der Spielzeiten ist aus. Schalte ihn ein, dann lernt Oasis mit jedem Abend dazu."] = "Play-time tracking is off. Turn it on and Oasis learns a little more every evening.",
    ["Erster Tod"] = "First death",
    ["Freischaltung"] = "Attunement",
    ["Hoehe = geschafftes Boss-Leben, Klick waehlt den Versuch"] = "Height = boss health taken down, click selects the attempt",
    ["Je Spieler ein Charakter (online, Main und hoehere Stufe zuerst). Rollen aus den Profilen."] = "One character per player (online, main and higher level first). Roles from the profiles.",
    ["Kein Zeitfenster mit genug Leuten. Probier eine kleinere Raidgroesse oder einen kuerzeren Raidabend (Zahnrad)."] = "No time window with enough people. Try a smaller raid size or a shorter raid night (gear icon).",
    ["Mitschnitt einschalten"] = "Turn on tracking",
    ["Niemand gestorben - sauber gespielt."] = "Nobody died – clean run.",
    ["Noch keine Kampfberichte. Nach dem ersten Bosskampf steht hier jeder Versuch - mit Zeitstrahl der Tode und wiederkehrenden Mustern."] = "No combat reports yet. After the first boss fight every attempt shows up here – with a death timeline and recurring patterns.",
    ["Quellen: %d geteilt, %d eigene Beobachtung, %d grob aus Spielzeit. Ueberfahren zeigt, wer da ist."] = "Sources: %d shared, %d own observation, %d rough from play time. Hover to see who is there.",
    ["Raid-Check-Modul fehlt - diese Ansicht braucht seine Bausteine."] = "Raid check module missing – this view needs its building blocks.",
    ["Raidgroesse"] = "Raid size",
    ["Schaden & Heilung"] = "Damage & healing",
    ["Tode je Versuch"] = "Deaths per attempt",
    ["Tote"] = "Deaths",
    ["Twinks erscheinen mit dem Stand ihres letzten Logins."] = "Alts show the state of their last login.",
    ["Verlauf aller Versuche"] = "All attempts",
    ["Wahrscheinlich dabei"] = "Likely to join",
    ["die letzten %d"] = "last %d",
    ["erster Tod"] = "first death",
    ["geb."] = "saved",
    ["im Schnitt"] = "on average",
    ["max. %d gleichzeitig"] = "max. %d at once",
    ["naechster Termin: %s"] = "next date: %s",
    ["viele"] = "many",
    ["vorgeschlagenes Fenster"] = "suggested window",
    ["wenig"] = "few",
}
-- vorhandene Uebersetzungen anderer Dateien nicht ueberschreiben
for k, v in pairs(ENC) do if EN[k] == nil then EN[k] = v end end

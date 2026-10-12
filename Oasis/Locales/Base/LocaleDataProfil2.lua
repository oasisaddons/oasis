-- Oasis - Texte: Profilseite 2026 (Glas-Kopfzeile, schlanke Reiter, Jahrbuch)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["Gruen = Hoechststufe erreicht  ·  Gold = noch steigerbar (Waffe benutzen bzw. Treffer einstecken)"] = "Grün = Höchststufe erreicht  ·  Gold = noch steigerbar (Waffe benutzen bzw. Treffer einstecken)",
    ["Rot = noch nicht gelernt  ·  Gruen = schon gelernt  ·  Stand Classic, WoW Forever kann abweichen. Kosten: 10 Silber je Waffe."] = "Rot = noch nicht gelernt  ·  Grün = schon gelernt  ·  Stand Classic, WoW Forever kann abweichen. Kosten: 10 Silber je Waffe.",
    ["Klick: Visitenkarte bearbeiten"] = "Klick: Visitenkarte bearbeiten",
    ["Persoenliche Rekorde"] = "Persönliche Rekorde",
    ["%d Laeufe"] = "%d Läufe",
    ["Dungeon-Laeufe"] = "Dungeon-Läufe",
    ["in diesem Client nicht verfuegbar"] = "in diesem Client nicht verfügbar",
    -- Item-Vergleich
    ["Ruestung"] = "Rüstung", ["Staerke"] = "Stärke", ["Seitwaerts"] = "Seitwärts",
    ["Bewertet fuer %s"] = "Bewertet für %s", ["Unpassend fuer %s"] = "Unpassend für %s",
    ["Zauberkrit-Wertung"] = "Zauberkrit-Wertung",
    ["Weitere Plaetze erscheinen, sobald mehr Gildenmitglieder mit Oasis ihre Sammlung teilen."] = "Weitere Plätze erscheinen, sobald mehr Gildenmitglieder mit Oasis ihre Sammlung teilen.",
    ["Noch keine Daten - oeffne einmal das Sammlungsfenster oder trage Reittiere und Haustiere in der Tasche. Sobald Gildenmitglieder mit Oasis online sind, erscheinen sie hier."] = "Noch keine Daten – öffne einmal das Sammlungsfenster oder trage Reittiere und Haustiere in der Tasche. Sobald Gildenmitglieder mit Oasis online sind, erscheinen sie hier.",
}
for k, v in pairs(DEFIX) do DE[k] = v end

local ENC = {
    ["Reittiere und Haustiere der Gilde: Rangliste, wer hat was, Seltenes"] = "Guild mounts and pets: ranking, who has what, rare ones",
    ["Du"] = "You", ["Setzt sich zusammen aus"] = "Made up of",
    ["Aufgaben"] = "Tasks",
    ["Fertigkeiten"] = "Skills", ["Der Client liefert gerade keine Fertigkeiten - nach dem Einloggen kurz warten."] = "The client delivers no skills right now - wait a moment after logging in.", ["Stufen der Waffenfertigkeiten liefert WoW Forever nicht - angezeigt wird, was du gelernt hast."] = "WoW Forever does not provide weapon skill levels - showing what you have learned.", ["Gruen = Hoechststufe erreicht  ·  Gold = noch steigerbar (Waffe benutzen bzw. Treffer einstecken)"] = "Green = maxed  ·  gold = can still improve (use the weapon or take hits)",
    ["gelernt"] = "learned",
    ["Rot = noch nicht gelernt  ·  Gruen = schon gelernt  ·  Stand Classic, WoW Forever kann abweichen. Kosten: 10 Silber je Waffe."] = "Red = not learned yet  ·  green = already learned  ·  Classic data, WoW Forever may differ. Cost: 10 silver per weapon.",
    ["Klick: Visitenkarte bearbeiten"] = "Click: edit your card",
    -- Jahrbuch
    ["Jahrbuch %s"] = "Yearbook %s",
    ["Kampf"] = "Combat", ["Abenteuer"] = "Adventure", ["Gold"] = "Gold", ["Meilensteine"] = "Milestones",
    ["Persoenliche Rekorde"] = "Personal records", ["Ziele erreicht"] = "Goals reached",
    ["Bester Mitspieler"] = "Best companion", ["noch keiner"] = "none yet",
    ["%d Laeufe"] = "%d runs", ["%d Tode"] = "%d deaths", ["%d Tage"] = "%d days",
    -- Item-Vergleich
    ["Besser"] = "Better", ["Schlechter"] = "Worse", ["Seitwaerts"] = "Sidegrade", ["Gleichwertig"] = "Equal",
    ["Nicht tragbar"] = "Can't equip", ["Unpassend"] = "Not for you", ["Vor- und Nachteile"] = "Pros and cons",
    ["Auswirkung"] = "Effect", ["Werte"] = "Stats", ["Jetzt"] = "Now", ["Neu"] = "New",
    ["Bewertet fuer %s"] = "Rated for %s", ["Unpassend fuer %s"] = "Not useful for %s",
    ["Kritischer Trefferwert"] = "Critical strike rating", ["Kritische Trefferchance"] = "Critical strike chance",
    ["Trefferwertung"] = "Hit rating", ["Zauberkrit-Wertung"] = "Spell crit rating", ["Zaubertreffer-Wertung"] = "Spell hit rating",
    ["Ausweichwertung"] = "Dodge rating", ["Parierwertung"] = "Parry rating", ["Blockwertung"] = "Block rating", ["Verteidigungswertung"] = "Defense rating",
    ["Zeigt Besser / Schlechter / Nicht tragbar mit Auswirkung (DPS, Leben, Ruestung) und Werte-Tabelle. Blizzards Vergleich erscheint dann nur mit Shift. Ist nesUI mit eigenem Vergleich geladen, zeigt Oasis nichts (sonst doppelt) - dort mit /nes vergleich abschalten."] = "Shows better / worse / can't equip with effect (DPS, health, armor) and a stats table. Blizzard's comparison then only appears with Shift. If nesUI with its own comparison is loaded, Oasis shows nothing (otherwise doubled) - turn it off there with /nes vergleich.",
    -- Sammlungen
    ["1. Platz"] = "1st place", ["2. Platz"] = "2nd place", ["3. Platz"] = "3rd place",
    ["in diesem Client nicht verfuegbar"] = "not available in this client", ["noch keine Daten"] = "no data yet",
    ["von %d (Gildenbestwert)"] = "of %d (guild best)", ["von %d"] = "of %d", ["noch nicht in der Rangliste"] = "not ranked yet",
    ["Weitere Plaetze erscheinen, sobald mehr Gildenmitglieder mit Oasis ihre Sammlung teilen."] = "More places appear as more guild members share their collection with Oasis.",
    ["Noch keine Daten - oeffne einmal das Sammlungsfenster oder trage Reittiere und Haustiere in der Tasche. Sobald Gildenmitglieder mit Oasis online sind, erscheinen sie hier."] = "No data yet - open the collections window once or carry mounts and pets in your bags. Guild members with Oasis appear here once they are online.",
}
for k, v in pairs(ENC) do if EN[k] == nil or k == "Klick: Visitenkarte bearbeiten" then EN[k] = v end end

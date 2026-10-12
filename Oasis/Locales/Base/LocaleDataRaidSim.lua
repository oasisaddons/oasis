-- Oasis - Texte: Raid-Simulator (Modules\RaidSim.lua) und Sim-Anbindung der Raid-Module, neue Demo-Inhalte
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["Den Raid-Simulator gibt es nur in der Entwicklerversion."] = "Den Raid-Simulator gibt es nur in der Entwicklerversion.",
    ["Raid-Simulator: %d Spieler in %s (nur bei dir, nichts geht an die Gilde). Beenden: /oa raidsim aus"] = "Raid-Simulator: %d Spieler in %s (nur bei dir, nichts geht an die Gilde). Beenden: /oa raidsim aus",
    ["Raid-Simulator beendet (%d Eintraege entfernt)."] = "Raid-Simulator beendet (%d Einträge entfernt).",
    ["Raid-Simulator laeuft nicht."] = "Raid-Simulator läuft nicht.",
    ["Raid-Sim: du wuerfelst %d"] = "Raid-Sim: du würfelst %d",
    ["Raid-Sim: spielt einen Ready-Check mit dem simulierten Raid durch."] = "Raid-Sim: spielt einen Ready-Check mit dem simulierten Raid durch.",
    ["Was soll die Gildenbank fuer den Raid stellen?"] = "Was soll die Gildenbank für den Raid stellen?",
    ["Feuerschutztraenke"] = "Feuerschutztränke",
    ["Flaeschchen"] = "Fläschchen",
}
for k, v in pairs(DEFIX) do DE[k] = v end

local ENC = {
    ["Raid-Sim"] = "Raid sim",
    ["Raid-Simulator"] = "Raid simulator",
    ["Den Raid-Simulator gibt es nur in der Entwicklerversion."] = "The raid simulator is only available in the developer version.",
    ["Raid-Simulator: %d Spieler in %s (nur bei dir, nichts geht an die Gilde). Beenden: /oa raidsim aus"] = "Raid simulator: %d players in %s (only for you, nothing is sent to the guild). Stop: /oa raidsim aus",
    ["Raid-Simulator beendet (%d Eintraege entfernt)."] = "Raid simulator stopped (%d entries removed).",
    ["Raid-Simulator laeuft nicht."] = "Raid simulator is not running.",
    ["Raid-Simulator aus"] = "Raid simulator off",
    ["Raid-Sim: %s - %s nach %s, %d Tote"] = "Raid sim: %s - %s after %s, %d deaths",
    ["Raid-Sim: Ready-Check gestartet."] = "Raid sim: ready check started.",
    ["Raid-Sim: du wuerfelst %d"] = "Raid sim: you roll %d",
    ["Raid-Sim: spielt einen Ready-Check mit dem simulierten Raid durch."] = "Raid sim: plays a ready check with the simulated raid.",
    ["Raid-Sim: 10 Barrow Deeps"] = "Raid sim: 10 Barrow Deeps",
    ["Raid-Sim: 20 Hyjal"] = "Raid sim: 20 Hyjal",
    ["Raid-Sim: 20 Onyxia"] = "Raid sim: 20 Onyxia",
    ["Raid-Sim: 40 Onyxia"] = "Raid sim: 40 Onyxia",
    ["Ready-Check simulieren"] = "Simulate ready check",
    ["Bosskampf jetzt"] = "Boss fight now",
    ["Beute-Runde"] = "Loot round",
    ["Rechtsklick: Raid-Simulator"] = "Right-click: raid simulator",
    ["Simulierter Raid"] = "Simulated raid",
    ["(Raid-Sim) Einladung an "] = "(Raid sim) Invite to ",
    ["Umhang"] = "Cloak",
    ["Brust"] = "Chest",
    ["Waffe"] = "Weapon",
    ["Stiefel"] = "Boots",
    ["Armschienen"] = "Bracers",
    ["Handschuhe"] = "Gloves",
    -- Demo
    ["Was soll die Gildenbank fuer den Raid stellen?"] = "What should the guild bank provide for the raid?",
    ["Feuerschutztraenke"] = "Fire protection potions",
    ["Flaeschchen"] = "Flasks",
    ["Buff-Essen"] = "Buff food",
    ["Reparaturgeld"] = "Repair money",
    ["Erster Raid: Barrow Deeps oder gleich Onyxia?"] = "First raid: Barrow Deeps or straight to Onyxia?",
    ["Barrow Deeps"] = "Barrow Deeps",
    ["Onyxia"] = "Onyxia",
}
for k, v in pairs(ENC) do EN[k] = v end

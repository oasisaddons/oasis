-- Oasis - Texte fuer Mitspieler, Quest-Partner, Marktpreise (Midas)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DE4 = {
    ["Kuerzliche Mitspieler"] = "Kürzliche Mitspieler",
    ["Noch keine Mitspieler von ausserhalb der Gilde.\nWer mit dir in einer Gruppe war, landet automatisch hier."] = "Noch keine Mitspieler von außerhalb der Gilde.\nWer mit dir in einer Gruppe war, landet automatisch hier.",
    ["Notiz zum ausgewaehlten Mitspieler, z.B. 'super Heiler, netter Typ'"] = "Notiz zum ausgewählten Mitspieler, z. B. „super Heiler, netter Typ“",
    ["Quest-Partner in der Gilde finden und gute Mitspieler von ausserhalb merken"] = "Quest-Partner in der Gilde finden und gute Mitspieler von außerhalb merken",
}
for k, v in pairs(DE4) do DE[k] = v end

local EN4 = {
    ["%d eigene Quests"] = "%d quests in your log",
    ["%dx zusammen"] = "%dx together",
    ["%s hat auch: %s"] = "%s also has: %s",
    ["(Auktionshaus-Addon)"] = "(auction house addon)",
    ["Aus der Liste entfernen"] = "Remove from list",
    ["Enter speichert die Notiz"] = "Enter saves the note",
    ["Gerade hat niemand aus der Gilde dieselben Quests.\nSobald Mitglieder mit Oasis gleiche Quests annehmen, stehen sie hier."] = "Nobody in the guild has the same quests right now.\nAs soon as members with Oasis pick up the same quests, they show up here.",
    ["Gilden-Preis:"] = "Guild price:",
    ["In Gilde einladen"] = "Invite to guild",
    ["Klick: zusammen questen (einladen)"] = "Click: quest together (invite)",
    ["Kuerzliche Mitspieler"] = "Recent players",
    ["Marktwert ~"] = "Market value ~",
    ["Mitspieler"] = "Players",
    ["Neu in WoW"] = "New to WoW",
    ["Noch keine Mitspieler von ausserhalb der Gilde.\nWer mit dir in einer Gruppe war, landet automatisch hier."] = "No players from outside the guild yet.\nAnyone you group with shows up here automatically.",
    ["Notiz zum ausgewaehlten Mitspieler, z.B. 'super Heiler, netter Typ'"] = "Note for the selected player, e.g. \"great healer, nice person\"",
    ["Quest-Partner"] = "Quest partners",
    ["Quest-Partner in der Gilde finden und gute Mitspieler von ausserhalb merken"] = "Find quest partners in the guild and remember good players from outside",
    ["fertig"] = "done",
}
for k, v in pairs(EN4) do EN[k] = v end

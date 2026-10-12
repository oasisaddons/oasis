-- Oasis - Texte: neue Gildenbank
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["Die Gildenbank wurde noch nie gelesen. Sobald jemand mit Oasis den Gildentresor oeffnet, steht hier alles - fuer die ganze Gilde."] = "Die Gildenbank wurde noch nie gelesen. Sobald jemand mit Oasis den Gildentresor öffnet, steht hier alles – für die ganze Gilde.",
    ["Faecher"] = "Fächer",
    ["In allen Faechern suchen ..."] = "In allen Fächern suchen ...",
    ["Rahmenfarbe = Qualitaet"] = "Rahmenfarbe = Qualität",
    ["Rechtsklick: Menue"] = "Rechtsklick: Menü",
    ["Shift-Klick: verlinken  ·  Rechtsklick: Menue"] = "Shift-Klick: verlinken  ·  Rechtsklick: Menü",
    ["in allen Faechern"] = "in allen Fächern",
    ["Gegenstaende"] = "Gegenstände",
}
for k, v in pairs(DEFIX) do DE[k] = v end

local EN11 = {
    ["%d Items hier werden gesucht"] = "%d items here are wanted",
    ["Alles"] = "All",
    ["Darf ich mir %s aus der Gildenbank nehmen?"] = "May I take %s from the guild bank?",
    ["Die Gildenbank wurde noch nie gelesen. Sobald jemand mit Oasis den Gildentresor oeffnet, steht hier alles - fuer die ganze Gilde."] = "The guild bank hasn't been read yet. As soon as someone with Oasis opens the guild vault, everything shows up here – for the whole guild.",
    ["Diese Woche hat noch niemand eingezahlt."] = "Nobody has deposited anything this week.",
    ["Faecher"] = "Tabs",
    ["Gesucht von: "] = "Wanted by: ",
    ["Im Chat verlinken"] = "Link in chat",
    ["Im Gildenchat anfragen"] = "Ask in guild chat",
    ["In allen Faechern suchen ..."] = "Search all tabs ...",
    ["In die Gesucht-Liste"] = "Add to wanted list",
    ["Items"] = "Items",
    ["Klick auf einen Treffer: zum Fach springen"] = "Click a result to jump to its tab",
    ["Letzte Bewegungen"] = "Recent activity",
    ["Nichts gefunden."] = "Nothing found.",
    ["Noch kein Protokoll."] = "No log yet.",
    ["Oasis"] = "Oasis",
    ["Rahmenfarbe = Qualitaet"] = "Border color = quality",
    ["Rechtsklick: Menue"] = "Right-click: menu",
    ["Shift-Klick: verlinken  ·  Rechtsklick: Menue"] = "Shift-click: link  ·  Right-click: menu",
    ["Sorten"] = "kinds",
    ["Stand: "] = "As of: ",
    ["Top-Spender (7 Tage)"] = "Top donors (7 days)",
    ["Treffer"] = "Results",
    ["Was liegt in der Gildenbank, was ist es wert und wer hat was eingezahlt"] = "What's in the guild bank, what it's worth and who deposited what",
    ["Wertvollste Items"] = "Most valuable items",
    ["Wertvollste hier"] = "Most valuable here",
    ["aus der Gildenbank"] = "from the guild bank",
    ["in allen Faechern"] = "in all tabs",
    ["von der Gilde gesucht"] = "wanted by the guild",
    ["Gegenstaende"] = "Items",
    ["Belegt"] = "Used",
    ["Marktwert"] = "Market value",
    ["Preise kommen aus Midas oder aus Oasis' eigener AH-Beobachtung."] = "Prices come from Midas or Oasis' own auction house tracking.",
}
for k, v in pairs(EN11) do EN[k] = v end
EN["Demo-Daten auf den neuen Stand gebracht."] = "Demo data updated to the latest version."

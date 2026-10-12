-- Oasis - Texte: Gesucht-Liste und Item-Vorschlaege
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["%d in der Gilde koennen es bauen"] = "%d in der Gilde können es bauen",
    ["Einkaufsliste der Gilde - wer etwas hat oder bauen kann, bekommt beim Looten und im Tooltip Bescheid"] = "Einkaufsliste der Gilde – wer etwas hat oder bauen kann, bekommt beim Looten und im Tooltip Bescheid",
    ["Niemand in der Gilde hat es gerade - ab auf die Liste!"] = "Niemand in der Gilde hat es gerade – ab auf die Liste!",
    ["Was du pro Stueck zahlen wuerdest (freiwillig)."] = "Was du pro Stück zahlen würdest (freiwillig).",
    ["fuer meine Gesucht-Liste"] = "für meine Gesucht-Liste",
    ["Tippen - Oasis schlaegt Items vor (Taschen, Gildenbank, Rezepte, Dungeons, Auktionshaus)."] = "Tippen – Oasis schlägt Items vor (Taschen, Gildenbank, Rezepte, Dungeons, Auktionshaus).",
}
for k, v in pairs(DEFIX) do DE[k] = v end

local EN12 = {
    [" /Stk"] = " /each",
    ["%d in der Gilde koennen es bauen"] = "%d in the guild can craft it",
    ["Abgehakt!"] = "Done!",
    ["Auftrag geben"] = "Place order",
    ["Bank %d"] = "Bank %d",
    ["Du hast %d"] = "You have %d",
    ["Einkaufsliste der Gilde - wer etwas hat oder bauen kann, bekommt beim Looten und im Tooltip Bescheid"] = "The guild's shopping list – anyone who has or can craft something gets notified on loot and in the tooltip",
    ["Herstellbar"] = "Craftable",
    ["In der Bank"] = "In the bank",
    ["In der Gildenbank: %d"] = "In the guild bank: %d",
    ["Item eintippen oder Shift-Klick ..."] = "Type an item or shift-click ...",
    ["Kann ich bauen"] = "I can craft it",
    ["Niemand in der Gilde hat es gerade - ab auf die Liste!"] = "Nobody in the guild has it right now – put it on the list!",
    ["Notiz ..."] = "Note ...",
    ["Preisangebot"] = "Price offer",
    ["Taschen"] = "bags",
    ["Was du pro Stueck zahlen wuerdest (freiwillig)."] = "What you'd pay per piece (optional).",
    ["baut: "] = "crafts: ",
    ["du kannst es bauen"] = "you can craft it",
    ["fuer meine Gesucht-Liste"] = "for my wanted list",
    ["g/Stk"] = "g/each",
    ["herstellbar"] = "craftable",
    ["zahlt %dg/Stk"] = "pays %dg each",
    ["AH"] = "AH",
    ["Tippen - Oasis schlaegt Items vor (Taschen, Gildenbank, Rezepte, Dungeons, Auktionshaus)."] = "Start typing – Oasis suggests items (bags, guild bank, recipes, dungeons, auction house).",
}
for k, v in pairs(EN12) do EN[k] = v end

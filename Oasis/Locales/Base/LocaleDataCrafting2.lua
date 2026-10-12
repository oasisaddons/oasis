-- Oasis - Texte: Handwerks-Boerse (Neugestaltung)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["Der Auftrag geht an alle Handwerker mit diesem Rezept - wer Zeit hat, nimmt ihn an."] = "Der Auftrag geht an alle Handwerker mit diesem Rezept – wer Zeit hat, nimmt ihn an.",
    ["Du bringst das Material mit - der Handwerker braucht nichts zu besorgen."] = "Du bringst das Material mit – der Handwerker braucht nichts zu besorgen.",
    ["Du stellst es her - der Auftraggeber bekommt Bescheid."] = "Du stellst es her – der Auftraggeber bekommt Bescheid.",
}
for k, v in pairs(DEFIX) do DE[k] = v end

local ENC = {
    ["%d Handwerker"] = "%d crafters",
    ["+%d weitere Materialien"] = "+%d more materials",
    ["Alle offenen ansehen"] = "View all open",
    ["Alle, die es koennen"] = "Everyone who can",
    ["Auftrag"] = "Order",
    ["Auftrag an %s senden"] = "Send order to %s",
    ["Auftrag an alle senden"] = "Send order to everyone",
    ["Auswaehlen und Auftrag vorbereiten"] = "Select and prepare order",
    ["Bank"] = "Bank",
    ["Der Auftrag geht an alle Handwerker mit diesem Rezept - wer Zeit hat, nimmt ihn an."] = "The order goes to every crafter with this recipe - whoever has time takes it.",
    ["Der Auftrag wird fuer alle zurueckgezogen."] = "The order is withdrawn for everyone.",
    ["Der Auftraggeber bekommt Bescheid, dass es fertig ist."] = "The customer is told it's ready.",
    ["Du bringst das Material mit - der Handwerker braucht nichts zu besorgen."] = "You bring the materials - the crafter needs nothing.",
    ["Du stellst es her - der Auftraggeber bekommt Bescheid."] = "You craft it - the customer is notified.",
    ["Erledigten Auftrag aus der Liste nehmen."] = "Remove the finished order from the list.",
    ["Favoriten: %d"] = "Favorites: %d",
    ["Gebraucht: %d"] = "Needed: %d",
    ["Gesendet!"] = "Sent!",
    ["Gesucht: %d"] = "Wanted: %d",
    ["Klick: Auftraege an dich"] = "Click: orders for you",
    ["Klick: Handwerker nach Beruf"] = "Click: crafters by profession",
    ["Klick: Rezept zeigen"] = "Click: show recipe",
    ["Klick: Rezepte zeigen"] = "Click: show recipes",
    ["Klick: alle Rezepte, Filter aufheben"] = "Click: all recipes, clear filters",
    ["Klick: auswaehlen"] = "Click: select",
    ["Klick: nur Rezepte, die du kannst"] = "Click: only recipes you know",
    ["Klick: nur dieser Beruf"] = "Click: only this profession",
    ["Klick: waehlen  ·  Rechtsklick: Menue"] = "Click: choose  ·  Right-click: menu",
    ["Noch niemand sonst kennt das Rezept."] = "Nobody else knows this recipe yet.",
    ["Nur Rezepte, die du selbst kannst"] = "Only recipes you know yourself",
    ["Nur Rezepte, die gerade jemand online herstellen kann"] = "Only recipes someone online can craft right now",
    ["Rechtsklick: Fluestern, Einladen, Profil"] = "Right-click: whisper, invite, profile",
    ["Rezept suchen"] = "Find a recipe",
    ["Rezept zeigen"] = "Show recipe",
    ["Rezepte von %s"] = "Recipes by %s",
    ["Rezepte von %s zeigen"] = "Show recipes by %s",
    ["Steht auf einer Wunschliste der Gilde"] = "On a guild wishlist",
    ["Steht auf einer Wunschliste der Gilde. Klick: nur gesuchte Rezepte"] = "On a guild wishlist. Click: only wanted recipes",
    ["Stornieren"] = "Cancel",
    ["Suche leeren"] = "Clear search",
    ["laut Blizzard-Gildenberufen, ohne Oasis"] = "from Blizzard guild professions, without Oasis",
}
for k, v in pairs(ENC) do EN[k] = v end

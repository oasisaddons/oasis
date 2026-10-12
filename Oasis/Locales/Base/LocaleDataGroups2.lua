-- Oasis - Texte: Gruppen-Seite, Spalte "Eigene Gruppe" (Schritte, Ziel-Karten, Rollen, Optionen)
local ADDON, ns = ...
local DE, EN = ns.LOCALE_DE, ns.LOCALE_EN

local DEFIX = {
    ["Passend fuer mich"] = "Passend für mich",
    ["Grenzwertig fuer dein Level"] = "Grenzwertig für dein Level",
    ["Klick: als Ziel waehlen"] = "Klick: als Ziel wählen",
    ["Klick: mit dieser Rolle starten (stellt auch deine Gruppenrolle um)"] = "Klick: mit dieser Rolle starten (stellt auch deine Gruppenrolle um)",
    ["Waehle oben ein Ziel oder tippe eins ein."] = "Wähle oben ein Ziel oder tippe eins ein.",
    ["Waehle deine Rolle."] = "Wähle deine Rolle.",
    ["Erst eine Rolle waehlen"] = "Erst eine Rolle wählen",
    ["laeuft"] = "läuft",
}
for k, v in pairs(DEFIX) do if DE[k] == nil then DE[k] = v end end

local ENL = {
    ["Ziel"] = "Target",
    ["Rolle"] = "Role",
    ["Los"] = "Go",
    ["Passend fuer mich"] = "Fits me",
    ["Alle"] = "All",
    ["%d-%d von %d"] = "%d-%d of %d",
    ["Nichts in deinem Levelbereich - schalte auf Alle oder tippe ein Ziel ein."] = "Nothing in your level range – switch to All or type a target.",
    ["Eigenes Ziel"] = "Custom target",
    ["Zum Beispiel: Questen im Brachland, Elite-Quest, Ruf farmen ..."] = "For example: questing in the Barrens, elite quest, reputation farming ...",
    ["Wer sich mit passender Rolle meldet, wird sofort in deine Gruppe eingeladen."] = "Anyone who signs up with a fitting role is invited to your group right away.",
    ["Einladungen von Gruppen, bei denen du angefragt hast, nimmst du automatisch an."] = "Invites from groups you asked to join are accepted automatically.",
    ["Noch nicht bereit"] = "Not ready yet",
    ["Waehle oben ein Ziel oder tippe eins ein."] = "Pick a target above or type one in.",
    ["Waehle deine Rolle."] = "Pick your role.",
    ["Erst eine Rolle waehlen"] = "Pick a role first",
    ["Gruppe starten: %s"] = "Start group: %s",
    ["Anfragen"] = "Requests",
    ["laeuft"] = "running",
    ["Wartezeit %d Min"] = "Waiting %d min",
    ["Passt zu deinem Level"] = "Fits your level",
    ["Grenzwertig fuer dein Level"] = "Borderline for your level",
    ["Nicht dein Levelbereich"] = "Not your level range",
    ["Klick: als Ziel waehlen"] = "Click: choose as target",
    ["Klick: mit dieser Rolle starten (stellt auch deine Gruppenrolle um)"] = "Click: start with this role (also sets your group role)",
}
for k, v in pairs(ENL) do if EN[k] == nil then EN[k] = v end end

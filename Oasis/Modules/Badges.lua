-- Oasis: Abzeichen (Badges)
-- Stufen-Abzeichen (Bronze/Silber/Gold) aus eigenen Zaehlern, einmalige Gilden-Titel aus geteilten Daten.
local ADDON, ns = ...
local L = ns.L
local K, C, Store = ns.K, ns.K.C, ns.Store

local Badges = {}
ns.Badges = Badges

-- eigene Symbole (game-icons.net, CC BY 3.0 - Media\\icons\\CREDITS.txt), in Stufenfarbe eingefaerbt
local I = ns.MEDIA .. "icons\\badges\\"

Badges.TIERS = {
    { name = "Bronze", color = { 0.85, 0.55, 0.32 } },
    { name = "Silber", color = { 0.80, 0.83, 0.90 } },
    { name = "Gold", color = { 1.00, 0.80, 0.25 } },
}
Badges.UNIQUE_COLOR = C.accent

-- Kategorien (Reihenfolge der Seite)
Badges.CATS = {
    { key = "zusammen", name = "Zusammen unterwegs" },
    { key = "helfen", name = "Fuereinander da" },
    { key = "stimmung", name = "Gute Stimmung" },
    { key = "unfug", name = "Emotes & Unfug" },
    { key = "welt", name = "Abenteuer & Welt" },
    { key = "handel", name = "Handwerk & Handel" },
    { key = "zeit", name = "Zeit & Treue" },
    { key = "glueck", name = "Glueck, Pech & Wuerfel" },
    { key = "raid", name = "Raid-Momente" },
    { key = "insta", name = "Oasigram" },
    { key = "titel", name = "Gilden-Titel" },
}

-- Stufen-Abzeichen: Zaehler + Schwellen (Bronze/Silber/Gold)
Badges.LIST = {
    -- Zusammen unterwegs
    { cat = "zusammen", id = "pack", name = "Rudeltier", desc = "Minuten mit Gildenmitgliedern in einer Gruppe", stat = "groupMin", tiers = { 60, 600, 3000 } },
    { cat = "zusammen", id = "bosscrew", name = "Boss-Crew", desc = "Bosse mit mindestens zwei Gildenmitgliedern gelegt", stat = "bossCrew", tiers = { 5, 25, 100 } },
    { cat = "zusammen", id = "carry", name = "Babysitter", desc = "Minuten mit Gildenmitgliedern gespielt, die 8+ Level unter dir sind", stat = "carryMin", tiers = { 30, 300, 1500 } },
    { cat = "zusammen", id = "questbuddy", name = "Quest-Kumpel", desc = "Quests zusammen mit Gildenmitgliedern abgegeben", stat = "questsGroup", tiers = { 10, 50, 200 } },
    { cat = "zusammen", id = "dungeonfan", name = "Dungeon-Stammgast", desc = "Dungeons mit mindestens zwei Gildenmitgliedern betreten", stat = "dungeonRuns", tiers = { 5, 25, 100 } },
    { cat = "zusammen", id = "leader", name = "Rudelfuehrer", desc = "Gruppensuchen gestartet - einer muss ja vorangehen", stat = "lfgStarted", tiers = { 3, 15, 50 } },
    { cat = "zusammen", id = "matchmaker", name = "Kuppler", desc = "Deine Gruppensuche wurde voll", stat = "groupsFilled", tiers = { 1, 10, 30 } },
    { cat = "zusammen", id = "adventurer", name = "Immer dabei", desc = "Gruppen der Gilde beigetreten", stat = "joined", tiers = { 3, 15, 50 } },
    { cat = "zusammen", id = "punctual", name = "Schweizer Uhr", desc = "Terminen der Gilde zugesagt", stat = "signups", tiers = { 3, 15, 50 } },
    { cat = "zusammen", id = "organizer", name = "Organisator", desc = "Termine fuer die Gilde erstellt", stat = "eventsCreated", tiers = { 1, 5, 20 } },
    { cat = "zusammen", id = "duelist", name = "Duellant", desc = "Duelle gegen Gildenmitglieder", stat = "duels", tiers = { 5, 25, 100 } },
    { cat = "zusammen", id = "duelwinner", name = "Duellmeister", desc = "Duelle gegen Gildenmitglieder gewonnen", stat = "duelWins", tiers = { 3, 15, 50 } },
    -- Fuereinander da
    { cat = "helfen", id = "angel", name = "Schutzengel", desc = "Gildenmitglieder wiederbelebt", stat = "rez", tiers = { 3, 20, 100 } },
    { cat = "helfen", id = "medic", name = "Sanitaeter", desc = "Gildenmitglieder verbunden", stat = "bandageGuild", tiers = { 5, 25, 100 } },
    { cat = "helfen", id = "buffer", name = "Buff-Onkel", desc = "Zauber auf Gildenmitglieder gewirkt", stat = "castsOnGuild", tiers = { 20, 200, 1000 } },
    { cat = "helfen", id = "standup", name = "Stehaufmaennchen", desc = "Von Gildenmitgliedern wiederbelebt worden", stat = "rezzedByGuild", tiers = { 3, 20, 100 } },
    { cat = "helfen", id = "crafter", name = "Heinzelmaennchen", desc = "Auftraege fuer andere hergestellt - still und heimlich", stat = "crafted", tiers = { 5, 25, 100 } },
    { cat = "helfen", id = "helper", name = "Spendierhosen", desc = "Gesuchte Items an andere abgegeben", stat = "helped", tiers = { 3, 15, 50 } },
    { cat = "helfen", id = "trader", name = "Handelspartner", desc = "Handel mit Gildenmitgliedern abgeschlossen", stat = "trades", tiers = { 5, 25, 100 } },
    { cat = "helfen", id = "postman", name = "Postbote", desc = "Post an Gildenmitglieder geschickt", stat = "mails", tiers = { 3, 20, 100 } },
    { cat = "helfen", id = "generous", name = "Grosszuegig", desc = "Auftraege mit Trinkgeld vergeben", stat = "tips", tiers = { 1, 10, 30 } },
    { cat = "helfen", id = "patron", name = "Maezen", desc = "Gold in die Gildenbank eingezahlt", stat = "bankGold", tiers = { 1, 10, 100 } },
    { cat = "helfen", id = "fire", name = "Pfadfinder", desc = "Lagerfeuer fuer die Gilde angezuendet", stat = "campfires", tiers = { 3, 15, 50 } },
    -- Gute Stimmung
    { cat = "stimmung", id = "welcome", name = "Empfangskomitee", desc = "Neue Mitglieder im Gildenchat begruesst", stat = "welcomed", tiers = { 3, 15, 50 } },
    { cat = "stimmung", id = "cheer", name = "GZ-Maschine", desc = "GZ! GZ! GZ! - anderen gratuliert", stat = "gz", tiers = { 5, 25, 100 } },
    { cat = "stimmung", id = "moin", name = "Moin-Meister", desc = "Die Gilde begruesst (moin, hallo, servus ...)", stat = "greetings", tiers = { 10, 50, 250 } },
    { cat = "stimmung", id = "sandman", name = "Sandmaennchen", desc = "Gute Nacht gewuenscht (gn, n8 ...)", stat = "goodnights", tiers = { 5, 25, 100 } },
    { cat = "stimmung", id = "polite", name = "Hoeflich", desc = "Danke im Gildenchat gesagt", stat = "thanks", tiers = { 10, 50, 250 } },
    { cat = "stimmung", id = "lol", name = "Lachsack", desc = "haha, lol, xD im Gildenchat", stat = "lols", tiers = { 10, 100, 500 } },
    { cat = "stimmung", id = "chat", name = "Plaudertasche", desc = "Nachrichten im Gildenchat - Schweigen ist Silber", stat = "chat", tiers = { 50, 500, 2500 } },
    { cat = "stimmung", id = "showoff", name = "Angeber", desc = "Items im Gildenchat verlinkt", stat = "links", tiers = { 10, 50, 250 } },
    { cat = "stimmung", id = "whisper", name = "Fluesterpost", desc = "Gildenmitglieder angefluestert", stat = "whispers", tiers = { 20, 200, 1000 } },
    { cat = "stimmung", id = "voter", name = "Demokrat", desc = "In Gilden-Umfragen abgestimmt", stat = "votes", tiers = { 3, 15, 50 } },
    { cat = "stimmung", id = "asker", name = "Fragesteller", desc = "Umfragen fuer die Gilde erstellt", stat = "pollsCreated", tiers = { 1, 5, 20 } },
    -- Emotes & Unfug
    { cat = "unfug", id = "hugs", name = "Knuddelbaer", desc = "Gildenmitglieder umarmt, bejubelt oder gedankt (/umarmen, /jubeln, /danke ...)", stat = "hugs", tiers = { 10, 50, 250 } },
    { cat = "unfug", id = "cuddly", name = "Kuscheltier", desc = "Von Gildenmitgliedern umarmt, bejubelt oder angestupst worden", stat = "emotesReceived", tiers = { 10, 50, 250 } },
    { cat = "unfug", id = "party", name = "Partyloewe", desc = "/tanzen mit Gildenmitgliedern in der Gruppe", stat = "dances", tiers = { 5, 25, 100 } },
    { cat = "unfug", id = "jester", name = "Spassvogel", desc = "Mit Gildenmitgliedern gelacht (/lachen, /kichern ...)", stat = "laughs", tiers = { 10, 50, 250 } },
    { cat = "unfug", id = "drama", name = "Drama-Queen", desc = "/weinen, /seufzen, /schmollen - das volle Programm", stat = "drama", tiers = { 10, 50, 200 } },
    { cat = "unfug", id = "slapper", name = "Ohrfeigen-Profi", desc = "Gildenmitglieder geohrfeigt (/ohrfeige)", stat = "slaps", tiers = { 5, 25, 100 } },
    { cat = "unfug", id = "poker", name = "Anstupser", desc = "Gildenmitglieder angestupst (/anstupsen)", stat = "pokes", tiers = { 10, 50, 200 } },
    { cat = "unfug", id = "chicken", name = "Angsthase", desc = "/huhn gemacht - bok bok!", stat = "chickens", tiers = { 10, 50, 200 } },
    { cat = "unfug", id = "roller", name = "Wuerfelfinger", desc = "/wuerfeln benutzt", stat = "rolls", tiers = { 20, 100, 500 } },
    { cat = "unfug", id = "sleepy", name = "Schlafmuetze", desc = "Minuten AFK", stat = "afkMin", tiers = { 60, 600, 3000 } },
    -- Abenteuer & Welt
    { cat = "welt", id = "veteran", name = "Erfahren", desc = "Hoechstes Charakter-Level", stat = "level", tiers = { 20, 40, 60 } },
    { cat = "welt", id = "quester", name = "Questmaschine", desc = "Quests abgegeben", stat = "quests", tiers = { 50, 250, 1000 } },
    { cat = "welt", id = "explorer", name = "Entdecker", desc = "Verschiedene Gebiete besucht", stat = "zones", tiers = { 10, 25, 45 } },
    { cat = "welt", id = "dungeonseen", name = "Dungeon-Sammler", desc = "Verschiedene Dungeons betreten", stat = "dungeonsSeen", tiers = { 5, 15, 30 } },
    { cat = "welt", id = "flyer", name = "Vielflieger", desc = "Flugrouten benutzt", stat = "taxis", tiers = { 10, 50, 200 } },
    { cat = "welt", id = "homesick", name = "Heimweh", desc = "Ruhestein benutzt", stat = "hearth", tiers = { 10, 50, 200 } },
    { cat = "welt", id = "innkeeper", name = "Kneipengaenger", desc = "In Gasthaeusern und Staedten eingekehrt", stat = "inns", tiers = { 20, 100, 500 } },
    { cat = "welt", id = "hunter", name = "Monsterjaeger", desc = "Gegner besiegt (mit Erfahrung)", stat = "kills", tiers = { 500, 5000, 20000 } },
    { cat = "welt", id = "looter", name = "Pluenderer", desc = "Beute aufgesammelt", stat = "loots", tiers = { 100, 1000, 5000 } },
    { cat = "welt", id = "fisher", name = "Petri Heil", desc = "Fische gefangen", stat = "fish", tiers = { 25, 250, 1000 } },
    { cat = "welt", id = "gatherer", name = "Sammelwut", desc = "Kraeuter, Erze und Leder gesammelt", stat = "gathers", tiers = { 50, 500, 2000 } },
    { cat = "welt", id = "rider", name = "Reiter", desc = "Aufs Reittier gestiegen", stat = "mounts", tiers = { 50, 500, 2000 } },
    { cat = "welt", id = "swimmer", name = "Wasserratte", desc = "Minuten geschwommen", stat = "swimMin", tiers = { 30, 300, 1500 } },
    { cat = "welt", id = "jumper", name = "Hopser", desc = "Gesprungen. Einfach so.", stat = "jumps", tiers = { 1000, 10000, 50000 } },
    { cat = "welt", id = "walker", ico = "explorer", name = "Marathon", desc = "Kilometer zu Fuss unterwegs (42 = ein Marathon)", stat = "walkKm", tiers = { 10, 42, 200 } },
    { cat = "welt", id = "stepper", ico = "streak", name = "Schrittzaehler", desc = "Tage mit 10.000 Schritten", stat = "stepGoal", tiers = { 1, 7, 30 } },
    { cat = "welt", id = "glutton", name = "Vielfrass", desc = "Gegessen", stat = "eats", tiers = { 50, 500, 2000 } },
    { cat = "welt", id = "thirsty", name = "Durstig", desc = "Getrunken", stat = "drinks", tiers = { 50, 500, 2000 } },
    { cat = "welt", id = "legacy", name = "Vermaechtnis", desc = "Legacy-Challenges geschafft", stat = "legacy", tiers = { 5, 20, 50 } },
    -- Handwerk & Handel
    { cat = "handel", id = "master", name = "Meister", desc = "Hoechste Berufsstufe", stat = "profMax", tiers = { 150, 225, 300 } },
    { cat = "handel", id = "crafty", name = "Fleissige Haende", desc = "Gegenstaende hergestellt", stat = "crafts", tiers = { 50, 500, 2500 } },
    { cat = "handel", id = "customer", name = "Auftraggeber", desc = "Handwerks-Auftraege erteilt", stat = "ordersPlaced", tiers = { 3, 15, 50 } },
    { cat = "handel", id = "wishlist", name = "Wunschzettel", desc = "Gesuchte Items eingetragen", stat = "wantsPosted", tiers = { 1, 10, 30 } },
    { cat = "handel", id = "auctioneer", name = "Auktionator", desc = "Auktionen eingestellt", stat = "auctionsPosted", tiers = { 10, 100, 500 } },
    { cat = "handel", id = "merchant", name = "Geschaeftsmann", desc = "Auktionen verkauft", stat = "auctionsSold", tiers = { 10, 100, 500 } },
    { cat = "handel", id = "golddigger", name = "Goldgraeber", desc = "Gold aus Beute (in Gold)", stat = "goldLooted", tiers = { 10, 100, 1000 } },
    { cat = "handel", id = "repair", name = "Dauerreparatur", desc = "Gold fuer Reparaturen ausgegeben", stat = "repairGold", tiers = { 1, 10, 50 } },
    -- Zeit & Treue
    { cat = "zeit", id = "loyal", name = "Treue Seele", desc = "Tage in der Oasis online", stat = "daysOnline", tiers = { 7, 30, 100 } },
    { cat = "zeit", id = "streak", name = "Unermuedlich", desc = "Tage am Stueck online (beste Serie)", stat = "bestStreak", tiers = { 3, 7, 30 } },
    { cat = "zeit", id = "marathon", name = "Dauerzocker", desc = "Minuten online", stat = "playMin", tiers = { 600, 6000, 30000 } },
    { cat = "zeit", id = "weekend", name = "Wochenendkrieger", desc = "Wochenendtage online", stat = "weekendDays", tiers = { 4, 15, 50 } },
    { cat = "zeit", id = "owl", name = "Nachteule", desc = "Tage zwischen 1 und 5 Uhr online - schlaf mal!", stat = "nightDays", tiers = { 3, 15, 50 } },
    { cat = "zeit", id = "rooster", name = "Fruehaufsteher", desc = "Tage zwischen 5 und 8 Uhr online", stat = "earlyDays", tiers = { 3, 15, 50 } },
    { cat = "zeit", id = "family", name = "Grosse Familie", desc = "Charaktere mit Oasis", stat = "chars", tiers = { 2, 4, 8 } },
    -- Glueck, Pech & Wuerfel
    { cat = "glueck", id = "lucky", name = "Glueckspilz", desc = "Epische Gegenstaende erbeutet", stat = "epics", tiers = { 1, 5, 20 } },
    { cat = "glueck", id = "dice", name = "Wuerfelhai", desc = "Todeswuerfeln gewonnen", stat = "drWins", tiers = { 1, 10, 50 } },
    { cat = "glueck", id = "unlucky", name = "Pechvogel", desc = "Todeswuerfeln verloren - irgendwer muss ja", stat = "drLosses", tiers = { 5, 25, 100 } },
    { cat = "glueck", id = "gambler", name = "Zocker", desc = "Todeswuerfeln gespielt", stat = "drPlays", tiers = { 10, 50, 200 } },
    { cat = "glueck", id = "highroller", name = "High Roller", desc = "Todeswuerfeln ab 1000 gewonnen", stat = "bigWins", tiers = { 1, 5, 20 } },
    { cat = "glueck", id = "survivor", name = "Stirb langsam", desc = "Level-Ups ohne Tod dazwischen", stat = "cleanLevels", tiers = { 5, 15, 30 } },
    { cat = "glueck", id = "fodder", name = "Kanonenfutter", desc = "In der Gruppe mit Gildenmitgliedern gestorben", stat = "groupDeaths", tiers = { 5, 25, 100 } },
    { cat = "glueck", id = "graveyard", name = "Friedhofs-Abo", desc = "Gestorben. Der Geistheiler kennt dich beim Vornamen.", stat = "deaths", tiers = { 5, 25, 100 } },
}
-- Einmalige Gilden-Titel: gehoeren genau einem Spieler
-- Raid-Momente (Symbole werden von vorhandenen geliehen: ico)
for _, b in ipairs({
    { cat = "raid", id = "firstdown", ico = "fodder", name = "Erster am Boden", desc = "Im Bosskampf als Erster der Gruppe gestorben. Irgendwer muss den Boden testen.", stat = "firstDown", tiers = { 1, 5, 20 } },
    { cat = "raid", id = "wipecause", ico = "drama", name = "Wipe-Verursacher", desc = "Als Erster gefallen - und danach ging der ganze Kampf schief. Zufall? Sicher.", stat = "wipeCause", tiers = { 1, 5, 15 } },
    { cat = "raid", id = "wipevet", ico = "survivor", name = "Wipe-Veteran", desc = "Bosskaempfe mit der Gilde verloren - und trotzdem wieder angetreten", stat = "wipes", tiers = { 3, 15, 50 } },
    { cat = "raid", id = "laststand", ico = "showoff", name = "Letzter Mann stehend", desc = "Im Bosskampf als Letzter der Gruppe gefallen. Heldenhaft. Leider trotzdem tot.", stat = "lastStanding", tiers = { 1, 5, 20 } },
    { cat = "raid", id = "bossfan", ico = "bosscrew", name = "Bossbezwinger", desc = "Bosskaempfe mit der Gilde gewonnen", stat = "bossWins", tiers = { 5, 25, 100 } },
    { cat = "insta", id = "influencer", ico = "showoff", name = "Influencer", desc = "Schnappschuesse auf Oasigram gepostet", stat = "instaPosts", tiers = { 1, 10, 40 } },
    { cat = "insta", id = "heartgiver", ico = "cuddly", name = "Herzchenverteiler", desc = "Posts von anderen geliked", stat = "instaLikes", tiers = { 5, 50, 200 } },
    { cat = "insta", id = "beloved", ico = "heart", name = "Publikumsliebling", desc = "Likes auf deine Posts bekommen", stat = "instaLiked", tiers = { 5, 50, 250 } },
    { cat = "insta", id = "networker", ico = "family", name = "Netzwerker", desc = "Leuten aus der Gilde gefolgt", stat = "instaFollows", tiers = { 3, 10, 25 } },
}) do Badges.LIST[#Badges.LIST + 1] = b end

Badges.UNIQUE = {
    { id = "first10", name = "Erster 10er", desc = "Als Erster der Gilde Level 10" },
    { id = "first20", name = "Erster 20er", desc = "Als Erster der Gilde Level 20" },
    { id = "first30", name = "Erster 30er", desc = "Als Erster der Gilde Level 30" },
    { id = "first40", name = "Erster 40er", desc = "Als Erster der Gilde Level 40" },
    { id = "first50", name = "Erster 50er", desc = "Als Erster der Gilde Level 50" },
    { id = "first60", name = "Erster 60er", desc = "Als Erster der Gilde Level 60" },
    { id = "platzhirsch", name = "Platzhirsch", desc = "Hoechstes Level der Gilde - allein an der Spitze" },
    { id = "dicechamp", name = "Wuerfelkoenig", desc = "Die meisten Todeswuerfeln-Siege der Gilde" },
    { id = "topcrafter", name = "Meisterschmied", desc = "Die meisten erledigten Auftraege der Gilde" },
    { id = "luckychild", name = "Glueckskind", desc = "Die meisten epischen Gegenstaende der Gilde" },
    { id = "chick", name = "Kueken der Oasis", desc = "Das neueste Mitglied der Gilde (letzte 30 Tage)" },
    { id = "reaper", name = "Todesmagnet", desc = "Die meisten Tode der Gilde in den letzten 30 Tagen" },
    { id = "voice", name = "Gildenstimme", desc = "Die meisten Nachrichten im Gildenchat", shared = "chat", min = 100 },
    { id = "heart", name = "Herz der Oasis", desc = "Die meiste Zeit mit Gildenmitgliedern in Gruppen", shared = "groupMin", min = 120 },
    { id = "cuddleking", name = "Kuschelkoenig", desc = "Die meisten Umarmungen und Jubel fuer andere", shared = "hugs", min = 20 },
    { id = "nightking", name = "Nachtschwaermer", desc = "Die meisten Naechte online", shared = "nightDays", min = 3 },
    { id = "saint", name = "Heiliger der Gilde", desc = "Die meisten Wiederbelebungen", shared = "rez", min = 5 },
    { id = "globetrotter", name = "Weltenbummler", desc = "Die meisten besuchten Gebiete", shared = "zones", min = 15 },
    { id = "fishking", name = "Anglerkoenig", desc = "Die meisten gefangenen Fische", shared = "fish", min = 50 },
    { id = "jumpking", name = "Kaenguru", desc = "Die meisten Spruenge der Gilde", shared = "jumps", min = 2000 },
    { id = "goldweek", ico = "golddigger", name = "Goldmacher der Woche", desc = "Beste Handelsbilanz der letzten 7 Tage (freiwillig geteilt, Markt-Seite)" },
    { id = "lootgoblin", ico = "looter", name = "Lootgoblin", desc = "Die meiste Beute der Gilde in den letzten 30 Tagen. Glaenzt es? Meins!" },
    { id = "dicemonth", ico = "roller", name = "Wuerfelkoenig des Monats", desc = "Die meisten Todeswuerfeln-Siege im letzten Monat (Saison)" },
}
-- 0.5.607: viel mehr Abzeichen (witzig, kurios, legendaer) + deutlich hoehere Schwellen fuer reine Zaehler
table.insert(Badges.CATS, #Badges.CATS, { key = "kurios", name = "Kurioses & Missgeschicke" })
table.insert(Badges.CATS, #Badges.CATS, { key = "legende", name = "Fuer Legenden" })
for _, b in ipairs({
    -- Kurioses & Missgeschicke
    { cat = "kurios", id = "ghostrun", ico = "graveyard", name = "Geisterlaeufer", desc = "Als Geist zur eigenen Leiche zurueckgelaufen. Der Weg ist das Ziel.", stat = "ghostRuns", tiers = { 15, 75, 300 } },
    { cat = "kurios", id = "drowned", ico = "swimmer", name = "Seemannsgrab", desc = "Im Wasser gestorben. Luft ist ueberbewertet.", stat = "drowned", tiers = { 1, 5, 25 } },
    { cat = "kurios", id = "messie", ico = "looter", name = "Messie", desc = "Taschen voll - schon wieder. Wegwerfen ist keine Option.", stat = "bagsFull", tiers = { 25, 150, 600 } },
    { cat = "kurios", id = "toofar", ico = "explorer", name = "Zu weit weg", desc = "Ausser Reichweite. Noch ein Schritt. Noch einer.", stat = "outOfRange", tiers = { 100, 750, 3000 } },
    { cat = "kurios", id = "wrongway", ico = "drama", name = "Falsch rum", desc = "Der Gegner stand nicht vor dir. Er stand hinter dir. Die ganze Zeit.", stat = "wrongFacing", tiers = { 50, 400, 2000 } },
    { cat = "kurios", id = "emptytank", ico = "thirsty", name = "Leerer Tank", desc = "Nicht genug Mana, Wut oder Energie. Erst trinken, dann draufhauen.", stat = "noMana", tiers = { 100, 750, 3000 } },
    { cat = "kurios", id = "jackpot", ico = "dice", name = "Volltreffer", desc = "Eine glatte 100 gewuerfelt (/wuerfeln 1-100)", stat = "roll100", tiers = { 1, 5, 20 } },
    { cat = "kurios", id = "snakeeyes", ico = "unlucky", name = "Pechstraehne", desc = "Eine 1 gewuerfelt (/wuerfeln 1-100). Das Universum hasst dich.", stat = "roll1", tiers = { 1, 5, 20 } },
    { cat = "kurios", id = "selftalk", ico = "whisper", name = "Selbstgespraech", desc = "Dir selbst etwas zugefluestert. Wer sonst hoert dir so gut zu?", stat = "selfWhisper", tiers = { 1, 10, 50 } },
    { cat = "kurios", id = "rapidfire", ico = "chat", name = "Dauerfeuer", desc = "Fuenf Gildenchat-Nachrichten in 15 Sekunden. Tippen ist dein Cardio.", stat = "chatBursts", tiers = { 5, 40, 200 } },
    { cat = "kurios", id = "closecall", ico = "survivor", name = "Haarscharf", desc = "Einen Kampf mit weniger als 10 % Leben ueberlebt. Puh.", stat = "closeCalls", tiers = { 5, 50, 250 } },
    { cat = "kurios", id = "lostagain", ico = "explorer", name = "Orientierungslos", desc = "Die Weltkarte geoeffnet. Wo war nochmal Norden?", stat = "mapOpens", tiers = { 150, 1500, 7500 } },
    { cat = "kurios", id = "paparazzi", ico = "influencer", name = "Paparazzi", desc = "Screenshots gemacht. Bitte laecheln!", stat = "screenshots", tiers = { 15, 150, 1000 } },
    -- Alltag in der Welt
    { cat = "welt", id = "banker", ico = "patron", name = "Bankier", desc = "Die Bank besucht. Mal kurz nachzaehlen.", stat = "bankVisits", tiers = { 30, 250, 1200 } },
    { cat = "welt", id = "regular", ico = "merchant", name = "Stammkunde", desc = "Haendler besucht. Man kennt sich.", stat = "merchantVisits", tiers = { 60, 500, 2500 } },
    { cat = "welt", id = "innsleep", ico = "innkeeper", name = "Gasthaus-Schlaefer", desc = "Im Gasthaus ausgeloggt - ausgeruht ist halb gelevelt", stat = "innLogouts", tiers = { 15, 100, 400 } },
    { cat = "welt", id = "lounge", ico = "flyer", name = "Fluglounge", desc = "Minuten auf Flugrouten verbracht. Snacks nicht inklusive.", stat = "taxiMin", tiers = { 90, 900, 4500 } },
    { cat = "handel", id = "dagobert", ico = "golddigger", name = "Dagobert", desc = "Hoechster Goldbestand je Charakter, zusammengezaehlt (in Gold). Baden im Geldspeicher.", stat = "goldMax", tiers = { 250, 2500, 15000 } },
    -- Fuer Legenden: lange Wege, echte Arbeit
    { cat = "legende", id = "turbo", ico = "streak", name = "Turbo-Leveler", desc = "Ein Level in unter 30 Minuten Spielzeit geschafft", stat = "fastLevels", tiers = { 3, 12, 30 } },
    { cat = "legende", id = "dungeonding", ico = "dungeonfan", name = "Dungeon-Ding", desc = "Mitten im Dungeon aufgestiegen", stat = "instanceDings", tiers = { 2, 8, 20 } },
    { cat = "legende", id = "immortal", ico = "angel", name = "Unsterblich", desc = "Spielminuten am Stueck ohne einen einzigen Tod (beste Serie)", stat = "bestAlive", tiers = { 900, 4500, 18000 } },
    { cat = "legende", id = "hundred", ico = "pack", name = "Hundertschaft", desc = "Verschiedene Gildenmitglieder, mit denen du in einer Gruppe warst", stat = "mates", tiers = { 10, 30, 75 } },
    { cat = "legende", id = "nolifer", ico = "marathon", name = "Kein Privatleben", desc = "Stunden online (alle Charaktere). Draussen scheint uebrigens die Sonne.", stat = "playHours", tiers = { 250, 1000, 3000 } },
    { cat = "legende", id = "fearless", ico = "bossfan", name = "Furchtlos", desc = "Bosse mit der Gilde gelegt, ohne dabei zu sterben", stat = "cleanBoss", tiers = { 10, 75, 300 } },
}) do b.fixed = true Badges.LIST[#Badges.LIST + 1] = b end
for _, b in ipairs({
    { id = "ghostking", ico = "graveyard", name = "Geisterkoenig", desc = "Die meisten Geisterlaeufe der Gilde. Der Friedhof hat eine Bank mit deinem Namen.", shared = "ghostRuns", min = 30 },
    { id = "courtphoto", ico = "influencer", name = "Hoffotograf", desc = "Die meisten Screenshots der Gilde", shared = "screenshots", min = 50 },
    { id = "messieking", ico = "looter", name = "Messie-Koenig", desc = "Die meisten vollen Taschen der Gilde", shared = "bagsFull", min = 50 },
}) do Badges.UNIQUE[#Badges.UNIQUE + 1] = b end
-- reine Zaehler deutlich schwerer: Bronze x2, Silber x3, Gold x4 (auf runde Werte). Begrenzte Werte bleiben.
do
    local KEEP = { veteran = true, master = true, explorer = true, dungeonseen = true, family = true, legacy = true }
    local function nice(n)
        if n < 10 then return math.floor(n + 0.5) end
        local step = n < 100 and 5 or (n < 1000 and 25 or (n < 10000 and 250 or 1000))
        return math.floor(n / step + 0.5) * step
    end
    for _, b in ipairs(Badges.LIST) do
        if not b.fixed and not KEEP[b.id] and b.tiers then
            b.tiers = { nice(b.tiers[1] * 2), nice(b.tiers[2] * 3), nice(b.tiers[3] * 4) }
        end
    end
end
for _, b in ipairs(Badges.UNIQUE) do b.cat = "titel" end
for _, b in ipairs(Badges.LIST) do b.icon = I .. (b.ico or b.id) end
for _, b in ipairs(Badges.UNIQUE) do b.icon = I .. (b.ico or b.id) end
-- WoW-Symbole je Abzeichen (rund maskiert, Stufe = Rahmenfarbe); fehlt eins, bleibt das eigene Symbol
local WOW_ICON = {
    pack = "Interface\\Icons\\Ability_Hunter_Pet_Wolf",
    bosscrew = "Interface\\Icons\\Achievement_Boss_EdwinVancleef",
    carry = "Interface\\Icons\\Spell_Holy_SealOfProtection",
    questbuddy = "Interface\\Icons\\INV_Misc_Note_02",
    dungeonfan = "Interface\\Icons\\INV_Misc_Key_10",
    leader = "Interface\\Icons\\Ability_Warrior_BattleShout",
    matchmaker = "Interface\\Icons\\Spell_Holy_PrayerOfSpirit",
    adventurer = "Interface\\Icons\\INV_Misc_Map_01",
    punctual = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    organizer = "Interface\\Icons\\INV_Scroll_03",
    duelist = "Interface\\Icons\\Ability_DualWield",
    duelwinner = "Interface\\Icons\\INV_Sword_27",
    angel = "Interface\\Icons\\Spell_Holy_Resurrection",
    medic = "Interface\\Icons\\Spell_Holy_Heal",
    buffer = "Interface\\Icons\\Spell_Holy_WordFortitude",
    standup = "Interface\\Icons\\Spell_Holy_DivineIntervention",
    crafter = "Interface\\Icons\\Trade_BlackSmithing",
    helper = "Interface\\Icons\\Spell_Holy_HolyBolt",
    trader = "Interface\\Icons\\INV_Misc_Coin_02",
    postman = "Interface\\Icons\\INV_Letter_15",
    generous = "Interface\\Icons\\INV_Misc_Gift_01",
    patron = "Interface\\Icons\\INV_Misc_Bag_10",
    fire = "Interface\\Icons\\Spell_Fire_Fire",
    welcome = "Interface\\Icons\\INV_Misc_Toy_07",
    cheer = "Interface\\Icons\\INV_Misc_Toy_08",
    moin = "Interface\\Icons\\Spell_Holy_MindVision",
    sandman = "Interface\\Icons\\Spell_Nature_Sleep",
    polite = "Interface\\Icons\\INV_Misc_Rune_01",
    lol = "Interface\\Icons\\INV_Misc_Toy_03",
    chat = "Interface\\Icons\\INV_Letter_01",
    showoff = "Interface\\Icons\\INV_Misc_Gem_Diamond_01",
    whisper = "Interface\\Icons\\Spell_Shadow_Charm",
    voter = "Interface\\Icons\\INV_Misc_Note_01",
    asker = "Interface\\Icons\\INV_Misc_QuestionMark",
    hugs = "Interface\\Icons\\Spell_Holy_Renew",
    cuddly = "Interface\\Icons\\INV_ValentinesCard02",
    party = "Interface\\Icons\\INV_Misc_Toy_10",
    jester = "Interface\\Icons\\INV_Misc_Bandage_15",
    drama = "Interface\\Icons\\Spell_Shadow_Possession",
    slapper = "Interface\\Icons\\Ability_Warrior_PunishingBlow",
    poker = "Interface\\Icons\\INV_Misc_Bone_01",
    chicken = "Interface\\Icons\\Spell_Magic_PolymorphChicken",
    roller = "Interface\\Icons\\INV_Misc_Dice_02",
    sleepy = "Interface\\Icons\\Spell_Nature_Sleep",
    veteran = "Interface\\Icons\\INV_Misc_Ribbon_01",
    quester = "Interface\\Icons\\INV_Misc_Book_09",
    explorer = "Interface\\Icons\\INV_Misc_Spyglass_02",
    dungeonseen = "Interface\\Icons\\INV_Misc_Key_14",
    flyer = "Interface\\Icons\\Ability_Mount_Wyvern_01",
    homesick = "Interface\\Icons\\INV_Misc_Rune_01",
    innkeeper = "Interface\\Icons\\INV_Drink_05",
    hunter = "Interface\\Icons\\Ability_Hunter_SniperShot",
    looter = "Interface\\Icons\\INV_Misc_Bag_08",
    fisher = "Interface\\Icons\\Trade_Fishing",
    gatherer = "Interface\\Icons\\Trade_Herbalism",
    rider = "Interface\\Icons\\Ability_Mount_RidingHorse",
    swimmer = "Interface\\Icons\\Spell_Frost_SummonWaterElemental",
    jumper = "Interface\\Icons\\Ability_Rogue_Sprint",
    glutton = "Interface\\Icons\\INV_Misc_Food_15",
    thirsty = "Interface\\Icons\\INV_Drink_07",
    legacy = "Interface\\Icons\\INV_Misc_Book_11",
    master = "Interface\\Icons\\INV_Misc_Book_07",
    crafty = "Interface\\Icons\\Trade_Engineering",
    customer = "Interface\\Icons\\INV_Misc_Coin_01",
    wishlist = "Interface\\Icons\\INV_Misc_Note_03",
    auctioneer = "Interface\\Icons\\INV_Hammer_15",
    merchant = "Interface\\Icons\\INV_Misc_Coin_04",
    golddigger = "Interface\\Icons\\INV_Misc_Coin_17",
    repair = "Interface\\Icons\\Trade_BlackSmithing",
    loyal = "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze",
    streak = "Interface\\Icons\\Spell_Fire_Incinerate",
    marathon = "Interface\\Icons\\Spell_Nature_TimeStop",
    weekend = "Interface\\Icons\\INV_Misc_Food_31",
    owl = "Interface\\Icons\\Ability_EyeOfTheOwl",
    rooster = "Interface\\Icons\\INV_Misc_Food_14",
    family = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
    lucky = "Interface\\Icons\\INV_Misc_Herb_10",
    dice = "Interface\\Icons\\INV_Misc_Dice_01",
    unlucky = "Interface\\Icons\\Spell_Shadow_UnholyStrength",
    gambler = "Interface\\Icons\\INV_Misc_Coin_03",
    highroller = "Interface\\Icons\\INV_Misc_Coin_15",
    survivor = "Interface\\Icons\\Spell_Holy_AshesToAshes",
    fodder = "Interface\\Icons\\Ability_Creature_Cursed_02",
    graveyard = "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01",
    firstdown = "Interface\\Icons\\Spell_Shadow_DeathScream",
    wipecause = "Interface\\Icons\\Spell_Shadow_RaiseDead",
    wipevet = "Interface\\Icons\\INV_Misc_Bone_ElfSkull_01",
    laststand = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    bossfan = "Interface\\Icons\\INV_Misc_Head_Dragon_Black",
    influencer = "Interface\\Icons\\INV_Misc_Horn_01",
    heartgiver = "Interface\\Icons\\INV_ValentinesCandy",
    beloved = "Interface\\Icons\\INV_Jewelry_Necklace_15",
    networker = "Interface\\Icons\\INV_Misc_Orb_02",
    first30 = "Interface\\Icons\\INV_Misc_Trophy_03",
    first60 = "Interface\\Icons\\INV_Misc_Trophy_01",
    platzhirsch = "Interface\\Icons\\Ability_Hunter_Pet_Boar",
    dicechamp = "Interface\\Icons\\INV_Crown_01",
    topcrafter = "Interface\\Icons\\Trade_BlackSmithing",
    luckychild = "Interface\\Icons\\INV_Misc_Herb_10",
    chick = "Interface\\Icons\\INV_Egg_01",
    reaper = "Interface\\Icons\\Spell_Shadow_DeathCoil",
    voice = "Interface\\Icons\\INV_Misc_Horn_02",
    heart = "Interface\\Icons\\INV_Jewelry_Talisman_08",
    cuddleking = "Interface\\Icons\\Spell_Holy_Renew",
    nightking = "Interface\\Icons\\Spell_Shadow_Twilight",
    saint = "Interface\\Icons\\Spell_Holy_HolySmite",
    globetrotter = "Interface\\Icons\\INV_Misc_Map_02",
    fishking = "Interface\\Icons\\INV_Misc_Fish_14",
    jumpking = "Interface\\Icons\\Ability_Druid_Dash",
    goldweek = "Interface\\Icons\\INV_Misc_Coin_17",
    lootgoblin = "Interface\\Icons\\INV_Misc_Bag_11",
    dicemonth = "Interface\\Icons\\INV_Misc_Dice_02",
}
-- abgeschaltet: fehlende Bilddateien bringen diesen Client zum Absturz (ASSERT fileDataID, 04.10.)
for _, b in ipairs(Badges.LIST) do b.wow = nil end
for _, b in ipairs(Badges.UNIQUE) do b.wow = nil end
Badges.byId = {}
for _, b in ipairs(Badges.LIST) do Badges.byId[b.id] = b end
for _, b in ipairs(Badges.UNIQUE) do b.unique = true Badges.byId[b.id] = b end

------------------------------------------------------------------------
-- Zaehler (pro Charakter, Abzeichen zaehlen account-weit)
------------------------------------------------------------------------
function Badges.Add(stat, n)
    if not ns.char then return end
    ns.char.stats = ns.char.stats or {}
    ns.char.stats[stat] = (ns.char.stats[stat] or 0) + (n or 1)
    Badges.Check()
end

local function accountStats(view)
    local s = {}
    local chars = 0
    for _, c in pairs(ns.db.chars) do
        chars = chars + 1
        for k, v in pairs(c.stats or {}) do s[k] = (s[k] or 0) + v end
        s.level = math.max(s.level or 0, c.level or 0)
        s.profMax = math.max(s.profMax or 0, c.profMax or 0)
    end
    s.chars = chars
    s.legacy = ns.Legacy and ns.Legacy.myDoneCount() or 0
    local days = ns.db.badgeDays or {}
    for key, stat in pairs({ online = "daysOnline", night = "nightDays", early = "earlyDays", weekend = "weekendDays" }) do
        local n = 0
        for _ in pairs(days[key] or {}) do n = n + 1 end
        s[stat] = n
    end
    -- laengste Serie aufeinanderfolgender Online-Tage
    local list = {}
    for d in pairs(days.online or {}) do list[#list + 1] = d end
    table.sort(list)
    local best, run, prevT = 0, 0, nil
    for _, d in ipairs(list) do
        local y, m, dd = d:match("(%d+)-(%d+)-(%d+)")
        local t = time({ year = tonumber(y), month = tonumber(m), day = tonumber(dd), hour = 12 })
        if prevT and math.abs(t - prevT - 86400) < 7200 then run = run + 1 else run = 1 end
        prevT = t
        if run > best then best = run end
    end
    s.bestStreak = best
    local S = ns.db.badgeSets or {}
    local nz, nd = 0, 0
    for _ in pairs(S.zones or {}) do nz = nz + 1 end
    for _ in pairs(S.dungeons or {}) do nd = nd + 1 end
    s.zones, s.dungeonsSeen = nz, nd
    s.playHours = math.floor((s.playMin or 0) / 60)
    local nm = 0
    for _ in pairs(S.mates or {}) do nm = nm + 1 end
    s.mates = nm
    local ba = 0
    for _, c in pairs(ns.db.chars) do ba = math.max(ba, c.bestAlive or 0) end
    s.bestAlive = ba
    s.goldLooted = math.floor((s.goldCopper or 0) / 10000)
    s.repairGold = math.floor((s.repairCopper or 0) / 10000)
    s.bankGold = math.floor((s.bankCopper or 0) / 10000)
    -- 0.5.704: Demo-Modus - Beispielwerte NUR zur Anzeige (view = true). Rang-XP, Teilen und Abzeichen-Pruefung
    -- rufen ohne view auf und sehen weiterhin nur die echten Zaehler.
    if view and ns.Demo and ns.Demo.IsActive and ns.Demo.IsActive() and ns.Demo.MineBadgeStats then
        for k, v in pairs(ns.Demo.MineBadgeStats(s)) do if (s[k] or 0) < v then s[k] = v end end
    end
    return s
end
Badges.accountStats = accountStats

local function tierFor(b, v)
    local t = 0
    for i, need in ipairs(b.tiers) do if (v or 0) >= need then t = i end end
    return t
end

-- eigene Stufen-Abzeichen: { [id] = tier }
function Badges.Mine(view)
    local s = accountStats(view)
    local out = {}
    for _, b in ipairs(Badges.LIST) do
        local t = tierFor(b, s[b.stat])
        if t > 0 then out[b.id] = t end
    end
    return out, s
end

function Badges.Encode()
    local mine = Badges.Mine()
    local t = {}
    for id, tier in pairs(mine) do t[#t + 1] = id .. ":" .. tier end
    table.sort(t)
    return table.concat(t, "+")
end
function Badges.Decode(s)
    local out = {}
    for id, tier in (s or ""):gmatch("(%w+):(%d)") do out[id] = tonumber(tier) end
    return out
end

------------------------------------------------------------------------
-- Einmalige Titel aus den geteilten Daten der Gilde
------------------------------------------------------------------------
local holdersCache, holdersAt
function Badges.UniqueHolders()
    -- 0.5.572: je Listenzeile aufgerufen -> 3 s merken
    if holdersCache and GetTime() - holdersAt < 3 then return holdersCache end
    local h = {}
    holdersCache, holdersAt = h, GetTime()
    if ns.Radar and ns.Radar.Race then
        for _, r in ipairs(ns.Radar.Race()) do
            -- nur vergeben, wenn bekannt ist, wer zuerst da war (nicht bei "vor Oasis" erreichten Stufen)
            local e = r.list[1]
            if e and (e.ts or 0) > 0 then h["first" .. r.lvl] = e.name end
        end
    end
    if ns.Deathroll and ns.Deathroll.Ranking then
        local top = ns.Deathroll and ns.Deathroll.Ranking()[1]
        if top and top.w >= 3 then h.dicechamp = top.name end
    end
    local done = {}
    for _, o in ipairs(Store.List("orders", function(o) return o.status == "done" and o.worker end)) do
        local m = ns.Alts and ns.Alts.Main(o.worker) or o.worker
        done[m] = (done[m] or 0) + 1
    end
    local best, bestN = nil, 4
    for m, n in pairs(done) do if n > bestN then best, bestN = m, n end end
    h.topcrafter = best
    -- Kueken: juengster Beitritt der letzten 30 Tage
    local newest, newestT = nil, ns.now() - 30 * 86400
    for _, e in ipairs(Store.List("chronicle", function(e) return e.kind == "guild" and (e.tk or ""):find("^tritt") end)) do
        if (e.ts or 0) > newestT then newest, newestT = e.who, e.ts end
    end
    h.chick = newest and (ns.Alts and ns.Alts.Main(newest) or newest) or nil
    -- Todesmagnet: meiste Tode in 30 Tagen (mind. 3)
    local cut, deaths = ns.now() - 30 * 86400, {}
    for _, d in ipairs(Store.List("deaths", function(d) return (d.ts or 0) > cut end)) do
        local m = ns.Alts and ns.Alts.Main(d.who) or d.who
        deaths[m] = (deaths[m] or 0) + 1
    end
    local rb, rn = nil, 2
    for m, n in pairs(deaths) do if n > rn then rb, rn = m, n end end
    h.reaper = rb
    -- Glueckskind: meiste epische Beute (mind. 2)
    local epics = {}
    for _, x in ipairs(Store.List("loot", function(x) return (x.quality or 0) >= 4 end)) do
        local m = ns.Alts and ns.Alts.Main(x.who) or x.who
        epics[m] = (epics[m] or 0) + 1
    end
    local lb, ln = nil, 1
    for m, n in pairs(epics) do if n > ln then lb, ln = m, n end end
    h.luckychild = lb
    -- Platzhirsch: hoechstes Level, nur wenn allein an der Spitze
    local top, topLvl, tie = nil, 19, false
    for _, m in ipairs(ns.Radar and ns.Radar.roster or {}) do
        local lv = m.level or 0
        if lv > topLvl then top, topLvl, tie = m.name, lv, false elseif lv == topLvl and top then tie = true end
    end
    h.platzhirsch = (top and not tie) and (ns.Alts and ns.Alts.Main(top) or top) or nil
    h.goldweek = ns.Trade and ns.Trade.GoldmakerOfWeek() or nil
    -- Lootgoblin: meiste Beute (ab gruen) in 30 Tagen, mind. 5 Teile
    local cut30, loots = ns.now() - 30 * 86400, {}
    for _, x in ipairs(Store.List("loot", function(x) return (x.ts or x.u or 0) > cut30 and (x.quality or 2) >= 2 end)) do
        if x.who then
            local m = ns.Alts and ns.Alts.Main(x.who) or x.who
            loots[m] = (loots[m] or 0) + 1
        end
    end
    local gb, gn = nil, 4
    for m, n in pairs(loots) do if n > gn then gb, gn = m, n end end
    h.lootgoblin = gb
    -- Deathroll-Saison: Sieger des Vormonats
    h.dicemonth = ns.Deathroll and ns.Deathroll.MonthChampion and ns.Deathroll.MonthChampion(-1) or nil
    -- Titel aus geteilten Zaehlern (Profilfeld "st")
    local mineS = accountStats()
    for _, b in ipairs(Badges.UNIQUE) do
        if b.shared then
            local bestName, bestV = nil, (b.min or 1) - 1
            local meMain = ns.Alts and ns.Alts.MyMain() or ns.me()
            if (mineS[b.shared] or 0) > bestV then bestName, bestV = meMain, mineS[b.shared] end
            for name, pr in pairs(ns.db.members) do
                if not ns.isMe(name) then
                    local v = Badges.DecodeShared(pr.st)[b.shared] or 0
                    if v > bestV then bestName, bestV = (ns.Alts and ns.Alts.Main(name) or name), v end
                end
            end
            h[b.id] = bestName
        end
    end
    return h
end

-- Abzeichen eines beliebigen Mitglieds: { [id] = tier } (einmalige mit tier = 4)
function Badges.Of(name)
    local out
    if ns.isMe(name) or (ns.db.chars and ns.db.chars[name]) then
        out = Badges.Mine(true)
    else
        local p = ns.db.members[name]
        out = Badges.Decode(p and p.bd)
    end
    local main = ns.Alts and ns.Alts.Main(name) or name
    for id, holder in pairs(Badges.UniqueHolders()) do
        if holder == main or holder == name then out[id] = 4 end
    end
    return out
end

function Badges.Color(tier)
    if tier == 4 then return Badges.UNIQUE_COLOR end
    return (Badges.TIERS[tier] or Badges.TIERS[1]).color
end
function Badges.Label(id, tier)
    local b = Badges.byId[id]
    if not b then return id end
    if b.unique then return L[b.name] end
    return L[b.name] .. " (" .. L[Badges.TIERS[tonumber(tier) or 1].name] .. ")"
end

-- Inline-Icons fuer Tooltips/Listen: hoechste zuerst
function Badges.Inline(name, max, size)
    local list = {}
    for id, tier in pairs(Badges.Of(name)) do
        if Badges.byId[id] then list[#list + 1] = { id = id, tier = tier } end
    end
    table.sort(list, function(a, b) if a.tier ~= b.tier then return a.tier > b.tier end return a.id < b.id end)
    local t = {}
    size = size or 14
    for i = 1, math.min(max or 6, #list) do
        local b = Badges.byId[list[i].id]
        local c = Badges.Color(list[i].tier)
        t[#t + 1] = ("|T%s:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t"):format(b.icon, size, size,
            math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
    end
    return table.concat(t, " "), #list
end

-- kompakt fuer Listen: Medaille in der Farbe des besten Abzeichens + Anzahl
function Badges.CountText(name, size)
    local n, best = 0, 0
    for id, tier in pairs(Badges.Of(name)) do
        if Badges.byId[id] and tier > 0 then
            n = n + 1
            if tier > best then best = tier end
        end
    end
    if n == 0 then return "|cff444444-|r" end
    local c = Badges.Color(best)
    return ("|T%sicons\\badges:%d:%d:0:0:64:64:0:64:0:64:%d:%d:%d|t |cffc8c8c8%d|r"):format(ns.MEDIA, size or 12, size or 12,
        math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255), n)
end

------------------------------------------------------------------------
-- Neue Stufe erkannt -> Hinweis, Chronik, Profil aktualisieren
------------------------------------------------------------------------
local checking
-- auf Wunsch: Gold-Abzeichen und Gilden-Titel im Gildenchat feiern (hoechstens alle 2 Minuten)
local lastAnnounce = 0
-- Gilden-Optionen (Gildenleitung): Standard = bisheriges Verhalten
ns.GuildOption({ page = "badges", key = "bdAnnc", default = true, label = "Abzeichen im Gildenchat feiern erlauben",
    desc = "Aus: niemand schreibt bei Gold-Abzeichen und Gilden-Titeln eine Zeile in den Gildenchat, auch wenn es persoenlich eingeschaltet ist" })
ns.GuildOption({ page = "badges", key = "bdGap", default = 2, min = 1, max = 30, step = 1, label = "Abstand der Abzeichen-Zeilen",
    desc = "Hoechstens eine Abzeichen-Zeile pro Person in diesem Zeitraum (gegen Spam im Gildenchat)",
    fmt = function(v) return (ns.L["%d Min"]):format(v) end })
ns.GuildOption({ page = "badges", key = "bdChron", default = true, label = "Abzeichen in der Gildenchronik",
    desc = "Aus: neue Abzeichen und Gilden-Titel werden nicht mehr in die Gildenchronik eingetragen" })
local function chronOk() return ns.Chronicle and ns.db.settings.badgeChronicle ~= false and ns.GuildOpt("bdChron") ~= false end
function Badges.Announce(id, tier)
    local st = ns.db and ns.db.settings
    if not (st and st.badgeAnnounce) or not IsInGuild() then return end
    if ns.GuildOpt("bdAnnc") == false then return end
    if GetTime() - lastAnnounce < (tonumber(ns.GuildOpt("bdGap")) or 2) * 60 then return end
    local b = Badges.byId[id]
    if not b then return end
    lastAnnounce = GetTime()
    local name = (Badges.Label(id, tier) or L[b.name]):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    ns.OfferChat(L["Im Gildenchat zeigen?"], (L["hat ein Abzeichen erhalten: %s"]):format(name), "GUILD")
end
function Badges.Check()
    if checking or not ns.db then return end
    checking = true
    ns.db.badgeSeen = ns.db.badgeSeen or {}
    local seen = ns.db.badgeSeen
    local changed = false
    local mine = Badges.Mine()
    for id, tier in pairs(mine) do
        if (seen[id] or 0) < tier then
            if seen[id] ~= nil or tier > 0 then
                local b = Badges.byId[id]
                if Badges.initialized then
                    ns.Sound.Next("badge")
                    K.Toast(L["Neues Abzeichen"], Badges.Label(id, tier), Badges.Color(tier), function() ns.ShowPage("badges") end)
                    if tier >= 3 then Badges.Announce(id, tier) end
                    if chronOk() then
                        ns.Chronicle.Add("badge", ("badge-%s-%s-%d"):format(ns.short(ns.me()), id, tier), "hat ein Abzeichen erhalten:", { id, tier })
                    end
                end
            end
            seen[id] = tier
            changed = true
        end
    end
    local me = ns.Alts and ns.Alts.MyMain() or ns.me()
    for id, holder in pairs(Badges.UniqueHolders()) do
        local key = "u:" .. id
        if (holder == me or holder == ns.me()) and not seen[key] then
            seen[key] = true
            if Badges.initialized then
                ns.Sound.Next("badge")
                K.Toast(L["Gilden-Titel!"], L[Badges.byId[id].name], Badges.UNIQUE_COLOR, function() ns.ShowPage("badges") end)
                Badges.Announce(id, 4)
                if chronOk() then
                    ns.Chronicle.Add("badge", ("badge-%s-%s"):format(ns.short(ns.me()), id), "hat ein Abzeichen erhalten:", { id, 4 })
                end
            end
        end
    end
    checking = false
    if changed and Badges.initialized and ns.Radar then ns.Radar.SendHello() end
    ns.RefreshPage("badges")
end

------------------------------------------------------------------------
-- Darstellung: rundes Icon mit Ring in Stufenfarbe
------------------------------------------------------------------------
function Badges.Emblem(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f.disc = f:CreateTexture(nil, "BACKGROUND")
    f.disc:SetTexture(ns.MEDIA .. "dot")
    f.disc:SetAllPoints()
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("CENTER")
    f.icon:SetSize(math.floor(size * 0.56), math.floor(size * 0.56))
    f.ring = f:CreateTexture(nil, "OVERLAY")
    f.ring:SetTexture(ns.MEDIA .. "ring")
    f.ring:SetAllPoints()
    function f:Set(b, tier)
        local on = tier and tier > 0
        local c = on and Badges.Color(tier) or C.dim
        -- WoW-Symbol nur, wenn der Client die Datei hat (SetTexture liefert sonst false)
        local useWow = b.wow and self.icon:SetTexture(b.wow) ~= false
        if useWow then
            -- WoW-Symbol, rund, farbig wenn erreicht (sonst grau)
            if self.icon.SetMask and not self.masked then
                pcall(self.icon.SetMask, self.icon, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
                self.masked = true
            end
            self.icon:SetSize(math.floor(size * 0.78), math.floor(size * 0.78))
            self.icon:SetVertexColor(1, 1, 1)
            self.icon:SetDesaturated(not on)
            self.icon:SetAlpha(on and 1 or 0.5)
        else
            self.icon:SetTexture(b.icon)
            self.icon:SetSize(math.floor(size * 0.56), math.floor(size * 0.56))
            self.icon:SetDesaturated(false)
            self.icon:SetVertexColor(c[1], c[2], c[3])
            self.icon:SetAlpha(on and 1 or 0.45)
        end
        self.disc:SetVertexColor(on and c[1] * 0.16 or 0.07, on and c[2] * 0.16 or 0.07, on and c[3] * 0.16 or 0.075)
        local rc = on and c or C.line
        self.ring:SetVertexColor(rc[1], rc[2], rc[3])
        self.ring:SetAlpha(on and 1 or 0.6)
    end
    return f
end

------------------------------------------------------------------------
-- Seite
------------------------------------------------------------------------
local view, showFilter = "mine", "all"
local COLS, TW, TH = 3, 220, 58   -- 0.5.608: waagerechte Kacheln (Abzeichen links, Text rechts)

local function holdersOf(id)
    local out = {}
    local seen = {}
    local function add(name, tier)
        local main = ns.Alts and ns.Alts.Main(name) or name
        if seen[main] and seen[main] >= tier then return end
        seen[main] = tier
    end
    add(ns.me(), Badges.Of(ns.me())[id] or 0)
    for name in pairs(ns.db.members) do
        local t = Badges.Of(name)[id]
        if t then add(name, t) end
    end
    for main, tier in pairs(seen) do if tier > 0 then out[#out + 1] = { name = main, tier = tier } end end
    table.sort(out, function(a, b) if a.tier ~= b.tier then return a.tier > b.tier end return a.name < b.name end)
    return out
end

local function tileTip(tile)
    local b, tier = tile.badge, tile.tier or 0
    if not b then return end
    local lines = { L[b.name], L[b.desc] }
    if not b.unique then
        local s = accountStats(true)
        local v = s[b.stat] or 0
        local t = {}
        for i, need in ipairs(b.tiers) do
            local c = Badges.TIERS[i].color
            t[#t + 1] = ("|cff%02x%02x%02x%s %d|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, L[Badges.TIERS[i].name], need)
        end
        lines[#lines + 1] = " "
        lines[#lines + 1] = table.concat(t, "   ")
        lines[#lines + 1] = L["Dein Stand: "] .. v
    end
    local hold = holdersOf(b.id)
    if #hold > 0 then
        lines[#lines + 1] = " "
        local t = {}
        for i = 1, math.min(10, #hold) do
            local h = hold[i]
            local c = Badges.Color(h.tier)
            t[#t + 1] = ("|cff%02x%02x%02x•|r "):format(c[1] * 255, c[2] * 255, c[3] * 255) .. ns.Radar.Colored(h.name)
        end
        lines[#lines + 1] = L["In der Gilde: "] .. table.concat(t, ", ")
    end
    K.ShowTip(tile, lines)
end

-- 2026: Glas-Optik wie Profil/Sammlungen (Helfer aus ns.Insta, Fallback: alte Flaechen bleiben)
local function glass(f, fill, line, r)
    local IGL = ns.Insta
    if IGL and IGL.Glass then IGL.Glass(f, fill, line, r) end
end
local function round(t, box, r) if K.RoundMask and t then K.RoundMask(t, box or t, r) end end
local NEAR = 0.6   -- ab hier gilt ein Abzeichen als "fast geschafft"
local HERO_Y, HERO_H = -46, 112

-- kleine Glas-Pille als Filterknopf
local function filterPills(parent, items, onChange)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(28)
    f.buttons = {}
    for i, it in ipairs(items) do
        local b = CreateFrame("Button", nil, f)
        b:SetHeight(28)
        b.key = it.key
        glass(b, nil, nil, 9)
        b.label = K.Text(b, 12, C.muted, "CENTER")
        b.label:SetPoint("CENTER", 0, 0)
        b.label:SetText(it.text)
        b.label:SetWordWrap(false)
        local w = (b.label:GetStringWidth() or 0) + 26
        b:SetWidth(math.max(56, math.min(150, w)))
        if i == 1 then b:SetPoint("LEFT", f, "LEFT", 0, 0) else b:SetPoint("LEFT", f.buttons[i - 1], "RIGHT", 6, 0) end
        b:SetScript("OnClick", function() f:Select(it.key, true) end)
        b:SetScript("OnEnter", function(self) if f.value ~= self.key then self.label:SetTextColor(C.text[1], C.text[2], C.text[3]) end end)
        b:SetScript("OnLeave", function(self) if f.value ~= self.key then self.label:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end end)
        f.buttons[i] = b
    end
    function f:Select(key, user)
        self.value = key
        local ac = C.accent
        local total = 0
        for _, b in ipairs(self.buttons) do
            local on = b.key == key
            local c = on and C.text or C.muted
            b.label:SetTextColor(c[1], c[2], c[3])
            glass(b, on and { ac[1], ac[2], ac[3], 0.15 } or nil, on and { ac[1], ac[2], ac[3], 0.45 } or nil)
            total = total + (b:GetWidth() or 0) + 6
        end
        self:SetWidth(math.max(10, total - 6))
        if user and onChange then onChange(key) end
    end
    f:Select(items[1].key)
    return f
end

ns.RegisterPage({
    key = "badges", title = "Abzeichen", order = 7.8,
    sub = "100 Abzeichen fuer alles, was ihr zusammen erlebt - Bronze, Silber, Gold und einmalige Gilden-Titel",
    build = function(p)
        local IGL = ns.Insta
        local TABS = { { key = "mine", text = L["Meine Abzeichen"], icon = "badges" }, { key = "guild", text = L["Gilde"], icon = "groups" } }
        local function onView(k) view = k ns.RefreshPage("badges") end
        if IGL and IGL.ProfileTabs then
            p.seg = IGL.ProfileTabs(p, TABS, onView)
            p.seg:SetWidth(300)
        else
            p.seg = K.Segments(p, TABS, onView)
        end
        p.seg:SetPoint("TOPLEFT", 0, 0)
        p.show = filterPills(p, {
            { key = "all", text = L["Alle"] }, { key = "have", text = L["Erreicht"] },
            { key = "near", text = L["Fast geschafft"] }, { key = "open", text = L["Offen"] },
        }, function(k)
            showFilter = k
            p.scroll:SetVerticalScroll(0)
            ns.RefreshPage("badges")
        end)
        p.show:SetPoint("LEFT", p.seg, "RIGHT", 16, 0)
        p.summary = K.Text(p, 12, C.muted, "RIGHT")
        p.summary:SetPoint("RIGHT", p, "TOPRIGHT", -4, -17)

        ----------------------------------------------------------------
        -- Kopfkarte (Glas): Zahl + runde Leiste | Medaillen-Pillen 2x2 | "Als naechstes"-Karten
        ----------------------------------------------------------------
        local hero = CreateFrame("Frame", nil, p)
        hero:SetPoint("TOPLEFT", 0, HERO_Y)
        hero:SetPoint("TOPRIGHT", 0, HERO_Y)
        hero:SetHeight(HERO_H)
        glass(hero, nil, nil, 14)
        hero.lbl = K.Text(hero, 12, C.muted)
        hero.lbl:SetPoint("TOPLEFT", 18, -16)
        hero.lbl:SetText(L["Deine Abzeichen"])
        hero.big = K.Title(hero, 32, C.text)
        hero.big:SetPoint("TOPLEFT", hero.lbl, "BOTTOMLEFT", 0, -6)
        hero.of = K.Text(hero, 12, C.muted)
        hero.of:SetPoint("BOTTOMLEFT", hero.big, "BOTTOMRIGHT", 6, 5)
        hero.bar = K.Bar(hero, 196, 6)
        hero.bar:SetPoint("BOTTOMLEFT", 18, 18)
        hero.bar.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.9)
        round(hero.bar.fill, hero.bar, 3)
        if hero.bar.bg then round(hero.bar.bg, hero.bar, 3) end
        hero.pct = K.Text(hero, 11, C.dim)
        hero.pct:SetPoint("LEFT", hero.bar, "RIGHT", 8, 0)
        -- Medaillen als Glas-Pillen (Bronze, Silber, Gold, Gilden-Titel)
        hero.tiers = {}
        for i = 1, 4 do
            local tc = i == 4 and Badges.UNIQUE_COLOR or Badges.TIERS[i].color
            local pl = CreateFrame("Frame", nil, hero)
            pl:SetSize(122, 34)
            pl:SetPoint("TOPLEFT", 268 + ((i - 1) % 2) * 130, -16 - math.floor((i - 1) / 2) * 42)
            glass(pl, { tc[1], tc[2], tc[3], 0.07 }, { tc[1], tc[2], tc[3], 0.30 }, 10)
            pl.dot = pl:CreateTexture(nil, "ARTWORK")
            pl.dot:SetTexture(ns.MEDIA .. "ring")
            pl.dot:SetSize(14, 14)
            pl.dot:SetVertexColor(tc[1], tc[2], tc[3], 0.9)
            pl.dot:SetPoint("LEFT", 10, 0)
            pl.num = K.Title(pl, 15, C.text)
            pl.num:SetPoint("LEFT", pl.dot, "RIGHT", 8, 0)
            pl.lbl = K.Text(pl, 11, C.muted)
            pl.lbl:SetPoint("LEFT", pl.num, "RIGHT", 6, 0)
            pl.lbl:SetPoint("RIGHT", pl, "RIGHT", -8, 0)
            pl.lbl:SetWordWrap(false)
            pl.lbl:SetText(i == 4 and L["Gilden-Titel"] or L[Badges.TIERS[i].name])
            hero.tiers[i] = pl.num
        end
        -- "Als naechstes": drei kleine Glaskarten mit Fortschritt
        hero.nextHead = K.Text(hero, 12, C.muted)
        hero.nextHead:SetPoint("TOPLEFT", 548, -14)
        hero.nextHead:SetText(L["Als naechstes"])
        hero.next = {}
        for i = 1, 3 do
            local n = CreateFrame("Frame", nil, hero)
            n:SetHeight(24)
            n:SetPoint("TOPLEFT", 548, -32 - (i - 1) * 26)
            n:SetPoint("RIGHT", hero, "RIGHT", -14, 0)
            glass(n, nil, nil, 8)
            n.t = K.Text(n, 11, C.text)
            n.t:SetPoint("LEFT", 10, 0)
            n.t:SetPoint("RIGHT", n, "RIGHT", -132, 0)
            n.t:SetWordWrap(false)
            n.v = K.Text(n, 10, C.dim, "RIGHT")
            n.v:SetPoint("RIGHT", n, "RIGHT", -78, 0)
            n.v:SetWidth(50)
            n.bar = K.Bar(n, 60, 4)
            n.bar:SetPoint("RIGHT", -10, 0)
            round(n.bar.fill, n.bar, 2)
            n:EnableMouse(true)
            n:SetScript("OnEnter", function(self) if self.badge then tileTip(self) end end)
            n:SetScript("OnLeave", function() GameTooltip:Hide() end)
            hero.next[i] = n
        end
        hero.none = K.Text(hero, 11, C.dim)
        hero.none:SetPoint("TOPLEFT", 548, -36)
        hero.none:SetPoint("RIGHT", hero, "RIGHT", -14, 0)
        hero.none:SetText(L["Sammle Fortschritt, dann erscheinen hier die naechsten Abzeichen."])
        p.hero = hero

        -- scrollbares Raster
        p.scroll = CreateFrame("ScrollFrame", nil, p)
        p.scroll:SetPoint("TOPLEFT", 0, HERO_Y - HERO_H - 14)
        p.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
        p.grid = CreateFrame("Frame", nil, p.scroll)
        p.grid:SetSize(COLS * TW, 10)
        p.scroll:SetScrollChild(p.grid)
        p.scroll:EnableMouseWheel(true)
        p.scroll:SetScript("OnMouseWheel", function(self, d)
            local max = math.max(0, (p.grid:GetHeight() or 0) - (self:GetHeight() or 0))
            self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - d * TH * 2)))
            if p.UpdateBar then p.UpdateBar() end
        end)
        -- Scrollleiste rechts: Spur + Griff (ziehen oder auf die Spur klicken)
        p.sTrack = CreateFrame("Frame", nil, p)
        p.sTrack:SetWidth(6)
        p.sTrack:SetPoint("TOPRIGHT", p.scroll, "TOPRIGHT", 0, 0)
        p.sTrack:SetPoint("BOTTOMRIGHT", p.scroll, "BOTTOMRIGHT", 0, 0)
        p.sTrack.bg = p.sTrack:CreateTexture(nil, "BACKGROUND")
        p.sTrack.bg:SetPoint("TOP", 0, 0) p.sTrack.bg:SetPoint("BOTTOM", 0, 0) p.sTrack.bg:SetWidth(3)
        p.sTrack.bg:SetColorTexture(1, 1, 1, 0.05)
        p.sThumb = p.sTrack:CreateTexture(nil, "ARTWORK")
        p.sThumb:SetWidth(4)
        p.sThumb:SetColorTexture(1, 1, 1, 0.28)
        p.sTrack:EnableMouse(true)
        local function scrollTo(frac)
            local max = math.max(0, (p.grid:GetHeight() or 0) - (p.scroll:GetHeight() or 0))
            p.scroll:SetVerticalScroll(math.max(0, math.min(max, max * frac)))
            p.UpdateBar()
        end
        local function cursorFrac()
            local _, cy = GetCursorPosition()
            local sc = p.sTrack:GetEffectiveScale()
            local top, h = p.sTrack:GetTop(), p.sTrack:GetHeight()
            if not (top and h and h > 0) then return 0 end
            return math.max(0, math.min(1, (top - cy / sc) / h))
        end
        p.sTrack:SetScript("OnMouseDown", function(self) self.drag = true scrollTo(cursorFrac()) end)
        p.sTrack:SetScript("OnMouseUp", function(self) self.drag = nil end)
        p.sTrack:SetScript("OnUpdate", function(self) if self.drag then scrollTo(cursorFrac()) end end)
        p.sTrack:SetScript("OnEnter", function() p.sThumb:SetColorTexture(1, 1, 1, 0.45) end)
        p.sTrack:SetScript("OnLeave", function() p.sThumb:SetColorTexture(1, 1, 1, 0.28) end)
        function p.UpdateBar()
            local vh, gh = p.scroll:GetHeight() or 0, p.grid:GetHeight() or 0
            local show = p.scroll:IsShown() and gh > vh + 2 and vh > 20
            p.sTrack:SetShown(show)
            if not show then return end
            local th = math.max(24, vh * vh / gh)
            local max = gh - vh
            local off = (p.scroll:GetVerticalScroll() or 0) / max
            p.sThumb:ClearAllPoints()
            p.sThumb:SetPoint("TOP", p.sTrack, "TOP", 0, -(vh - th) * off)
            p.sThumb:SetHeight(th)
        end

        -- Kategorie-Koepfe: Name, "1 von 12", kurze runde Leiste, feine Linie
        p.heads, p.tiles = {}, {}
        for _, cat in ipairs(Badges.CATS) do
            local h = CreateFrame("Frame", nil, p.grid)
            h:SetSize(COLS * TW - 8, 30)
            h.text = K.Title(h, 14, C.text)
            h.text:SetPoint("LEFT", 2, 0)
            h.count = K.Text(h, 11, C.muted)
            h.count:SetPoint("LEFT", h.text, "RIGHT", 10, 0)
            h.bar = K.Bar(h, 64, 4)
            h.bar:SetPoint("LEFT", h.count, "RIGHT", 10, 0)
            h.bar.fill:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.8)
            round(h.bar.fill, h.bar, 2)
            h.line = h:CreateTexture(nil, "ARTWORK")
            h.line:SetColorTexture(1, 1, 1, 0.06)
            h.line:SetHeight(1)
            h.line:SetPoint("LEFT", h.bar, "RIGHT", 12, 0)
            h.line:SetPoint("RIGHT", h, "RIGHT", 0, 0)
            h.cat = cat
            p.heads[cat.key] = h
        end
        local all = {}
        for _, b in ipairs(Badges.LIST) do all[#all + 1] = b end
        for _, b in ipairs(Badges.UNIQUE) do all[#all + 1] = b end
        for i, b in ipairs(all) do
            local t = CreateFrame("Frame", nil, p.grid)
            t:SetSize(TW - 8, TH - 8)
            glass(t, nil, nil, 12)
            t.hov = t:CreateTexture(nil, "BORDER", nil, 3)
            t.hov:SetAllPoints()
            t.hov:SetColorTexture(1, 1, 1, 0.035)
            t.hov:Hide()
            round(t.hov, t, 12)
            -- Stufen-Punkte (Bronze/Silber/Gold) oben rechts, klein und ruhig
            t.pips = {}
            for k = 1, 3 do
                local d = t:CreateTexture(nil, "OVERLAY")
                d:SetTexture(ns.MEDIA .. "dot")
                d:SetSize(5, 5)
                d:SetPoint("TOPRIGHT", -10 - (3 - k) * 8, -12)
                t.pips[k] = d
            end
            t.emblem = Badges.Emblem(t, 36)
            t.emblem:SetPoint("LEFT", 9, 0)
            t.name = K.Text(t, 12, C.text, "LEFT")
            t.name:SetPoint("TOPLEFT", 54, -9)
            t.name:SetWidth(TW - 100)
            t.name:SetWordWrap(false)
            t.tierTxt = K.Text(t, 10, C.muted, "LEFT")
            t.tierTxt:SetPoint("TOPLEFT", t.name, "BOTTOMLEFT", 0, -3)
            t.tierTxt:SetWidth(TW - 70)
            t.tierTxt:SetWordWrap(false)
            t.bar = K.Bar(t, TW - 74, 3)
            t.bar:SetPoint("BOTTOMLEFT", 54, 9)
            round(t.bar.fill, t.bar, 2)
            t.badge = b
            t:EnableMouse(true)
            t:SetScript("OnEnter", function(self) self.hov:Show() tileTip(self) end)
            t:SetScript("OnLeave", function(self) self.hov:Hide() GameTooltip:Hide() end)
            t:SetScript("OnMouseWheel", function(_, d) p.scroll:GetScript("OnMouseWheel")(p.scroll, d) end)
            p.tiles[i] = t
        end

        -- Gildenansicht
        -- 0.5.608: Gilde-Ansicht als Verbreitung - Balken = Anteil der Spieler (Mains mit Oasis), geteilt nach
        -- Gold/Silber/Bronze, rechts "x von y", sortiert nach Verbreitung; Namen im Tooltip
        p.list = K.List(p, 40, function(l)
            local r = K.Row(l)
            r.emblem = Badges.Emblem(r, 30)
            r.emblem:SetPoint("LEFT", 6, 0)
            r.cols.name = K.Text(r, 13, C.text)
            r.cols.name:SetPoint("LEFT", 46, 0)
            r.cols.name:SetWidth(170)
            r.cols.name:SetWordWrap(false)
            r.track = r:CreateTexture(nil, "ARTWORK")
            r.track:SetPoint("LEFT", 224, 0)
            r.track:SetPoint("RIGHT", r, "RIGHT", -128, 0)
            r.track:SetHeight(8)
            r.track:SetColorTexture(1, 1, 1, 0.06)
            -- 0.5.609: ein neutraler, leuchtender blauer Balken (keine Stufen-Unterscheidung)
            r.fill = r:CreateTexture(nil, "ARTWORK", nil, 1)
            r.fill:SetHeight(8)
            r.fill:SetPoint("LEFT", r.track, "LEFT", 0, 0)
            local cb = C.blue
            if not K.Gradient(r.fill, "HORIZONTAL", { cb[1], cb[2], cb[3], 0.55 }, { cb[1], cb[2], cb[3], 1 }) then r.fill:SetColorTexture(cb[1], cb[2], cb[3], 0.9) end
            r.glow = r:CreateTexture(nil, "ARTWORK", nil, 2)
            r.glow:SetTexture(ns.MEDIA .. "softglow")
            r.glow:SetBlendMode("ADD")
            r.glow:SetSize(26, 20)
            r.glow:SetPoint("CENTER", r.fill, "RIGHT", 0, 0)
            r.glow:SetVertexColor(cb[1] * 0.7, cb[2] * 0.7, cb[3] * 0.7, 1)
            r.halo = r:CreateTexture(nil, "BORDER")
            r.halo:SetPoint("TOPLEFT", r.fill, "TOPLEFT", -2, 3)
            r.halo:SetPoint("BOTTOMRIGHT", r.fill, "BOTTOMRIGHT", 2, -3)
            r.halo:SetColorTexture(cb[1], cb[2], cb[3], 0.12)
            r.cols.who = K.Text(r, 12, C.muted, "RIGHT")
            r.cols.who:SetPoint("RIGHT", -10, 0)
            r.cols.who:SetWidth(112)
            r:SetScript("OnEnter", function(self)
                local it = self.item
                if not it then return end
                local lines = { L[it.b.name], "|cff888888" .. L[it.b.desc or ""] .. "|r" }
                -- neutral: nur Namen, alphabetisch, ohne Stufe/Klassenfarbe
                local names = {}
                for _, h in ipairs(it.hold) do names[#names + 1] = Ambiguate and Ambiguate(h.name, "short") or h.name end
                table.sort(names)
                for i = 1, math.min(20, #names) do lines[#lines + 1] = "|cffd8d8dc" .. names[i] .. "|r" end
                if #it.hold > 20 then lines[#lines + 1] = "|cff888888+" .. (#it.hold - 20) .. "|r" end
                if #it.hold == 0 then lines[#lines + 1] = "|cff666666" .. L["noch niemand"] .. "|r" end
                K.ShowTip(self, lines)
            end)
            r:SetScript("OnLeave", function() GameTooltip:Hide() end)
            return r
        end, function(r, it)
            r.emblem:Set(it.b, it.top)
            r.cols.name:SetText(L[it.b.name])
            local N = math.max(1, it.total or 1)
            local n = #it.hold
            local W = math.max(10, (r.track:GetWidth() > 10 and r.track:GetWidth()) or 300)
            local w = W * math.min(1, n / N)
            local show = w >= 1
            r.fill:SetWidth(math.max(1, w))
            r.fill:SetShown(show) r.glow:SetShown(show) r.halo:SetShown(show)
            local pct = math.floor(n / N * 100 + 0.5)
            r.cols.who:SetText(n > 0 and ((L["%d von %d"]):format(n, N) .. "  |cffd8d8dc" .. pct .. " %|r") or ("|cff666666" .. L["noch niemand"] .. "|r"))
        end)
        p.list:SetPoint("TOPLEFT", 0, -46)
        p.list:SetPoint("BOTTOMRIGHT")
    end,
    refresh = function(p)
        p.scroll:SetShown(view == "mine")
        p.show:SetShown(view == "mine")
        p.list:SetShown(view == "guild")
        if p.seg.Select and p.seg.value ~= view then p.seg:Select(view) end
        local mine, s = Badges.Mine(true)
        local uniq = Badges.UniqueHolders()
        local me = ns.Alts and ns.Alts.MyMain() or ns.me()
        local have = 0
        local byCat, catHave = {}, {}
        for _, t in ipairs(p.tiles) do
            local b = t.badge
            local tier, progress
            local near = false
            if b.unique then
                tier = (uniq[b.id] == me or uniq[b.id] == ns.me()) and 4 or 0
                t.tierTxt:SetText(tier == 4 and L["Gilden-Titel"] or (uniq[b.id] and (L["gehoert "] .. ns.displayName(uniq[b.id])) or L["noch frei"]))
                t.bar:Hide()
                progress = 0
            else
                tier = mine[b.id] or 0
                local v = s[b.stat] or 0
                local nextNeed = b.tiers[tier + 1]
                t.tierTxt:SetText(tier > 0 and (L[Badges.TIERS[tier].name] .. (nextNeed and ("  ·  " .. v .. " / " .. nextNeed) or "")) or (v .. " / " .. b.tiers[1]))
                local prev = tier > 0 and b.tiers[tier] or 0
                progress = nextNeed and ((v - prev) / (nextNeed - prev)) or 1
                near = nextNeed ~= nil and progress >= NEAR
                t.bar:Set(progress)
                t.bar:Show()
            end
            if tier > 0 then have = have + 1 end
            local tc = tier > 0 and Badges.Color(tier) or nil
            -- Glaskarte: erreicht = Stufenfarbe, fast geschafft = Farbe der naechsten Stufe dezent, offen = neutral
            local nc = (Badges.TIERS[math.min(3, tier + 1)] or Badges.TIERS[3]).color
            if tc then
                glass(t, { tc[1], tc[2], tc[3], 0.06 }, { tc[1], tc[2], tc[3], 0.38 })
            elseif near then
                glass(t, { 1, 1, 1, 0.045 }, { nc[1], nc[2], nc[3], 0.28 })
            else
                glass(t, { 1, 1, 1, 0.025 }, { 1, 1, 1, 0.06 })
            end
            for k, d in ipairs(t.pips) do
                local pc = Badges.TIERS[k].color
                d:SetShown(not b.unique)
                if tier >= k then d:SetVertexColor(pc[1], pc[2], pc[3], 0.9) else d:SetVertexColor(1, 1, 1, 0.10) end
            end
            -- Balken in der Farbe der NAECHSTEN Stufe; offen und weit weg = gedaempft
            if not b.unique then
                t.bar.fill:SetColorTexture(nc[1], nc[2], nc[3], (tier > 0 or near) and 0.9 or 0.5)
            end
            -- Stufentext: erreicht in Stufenfarbe, fast geschafft in Farbe der naechsten Stufe
            local txc = tc or (near and nc) or C.dim
            t.tierTxt:SetTextColor(txc[1], txc[2], txc[3])
            t:SetAlpha((tier > 0 or near) and 1 or 0.82)
            t.prog = progress
            t.tier = tier
            t.emblem:Set(b, tier)
            t.name:SetText(L[b.name])
            t.name:SetTextColor(unpack((tier > 0 or near) and C.text or C.muted))
            local show = showFilter == "all" or (showFilter == "have" and tier > 0) or (showFilter == "open" and tier == 0)
                or (showFilter == "near" and near)
            t.visible = show
            byCat[b.cat] = byCat[b.cat] or {}
            if show then table.insert(byCat[b.cat], t) end
            catHave[b.cat] = catHave[b.cat] or { 0, 0 }
            catHave[b.cat][2] = catHave[b.cat][2] + 1
            if tier > 0 then catHave[b.cat][1] = catHave[b.cat][1] + 1 end
        end
        -- Ueberblick
        p.hero:SetShown(view == "mine")
        p.scroll:ClearAllPoints()
        p.scroll:SetPoint("TOPLEFT", 0, view == "mine" and (HERO_Y - HERO_H - 14) or -46)
        p.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
        do
            local cnt = { 0, 0, 0, 0 }
            local cand = {}
            for _, t in ipairs(p.tiles) do
                if t.tier and t.tier > 0 then cnt[math.min(4, t.tier)] = cnt[math.min(4, t.tier)] + 1 end
                if not t.badge.unique and t.badge.tiers[(t.tier or 0) + 1] and (t.prog or 0) > 0 then cand[#cand + 1] = t end
            end
            table.sort(cand, function(a, b) return (a.prog or 0) > (b.prog or 0) end)
            local h = p.hero
            local frac = #p.tiles > 0 and have / #p.tiles or 0
            h.big:SetText(have)
            h.of:SetText((L["von %d Abzeichen"]):format(#p.tiles))
            h.bar:Set(frac)
            h.pct:SetText(math.floor(frac * 100 + 0.5) .. " %")
            for i = 1, 4 do h.tiers[i]:SetText(cnt[i]) end
            local stats = s or {}
            for i, n in ipairs(h.next) do
                local t = cand[i]
                if t then
                    local nt = math.min(3, (t.tier or 0) + 1)
                    local nc = Badges.TIERS[nt].color
                    n.t:SetText(L[t.badge.name] .. "  " .. K.hex(nc) .. L[Badges.TIERS[nt].name] .. "|r")
                    n.v:SetText((stats[t.badge.stat] or 0) .. " / " .. t.badge.tiers[nt])
                    n.bar:Set(t.prog or 0)
                    n.bar.fill:SetColorTexture(nc[1], nc[2], nc[3], 0.9)
                    n.badge, n.tier = t.badge, t.tier
                    n:Show()
                else
                    n.badge = nil
                    n:Hide()
                end
            end
            h.none:SetShown(#cand == 0)
        end
        -- Spalten nach verfuegbarer Breite
        local W = p.scroll:GetWidth()
        if not W or W < 200 then W = COLS * 107 end
        W = W - 10   -- Platz fuer die Scrollleiste
        COLS = math.max(2, math.floor(W / 210))
        TW = math.floor(W / COLS)
        p.grid:SetWidth(COLS * TW)
        for _, hh in pairs(p.heads) do hh:SetWidth(COLS * TW - 8) end
        for _, t in ipairs(p.tiles) do
            t:SetWidth(TW - 8)
            t.name:SetWidth(TW - 100)
            t.tierTxt:SetWidth(TW - 70)
            t.bar:SetWidth(TW - 74)
        end
        -- Layout: je Kategorie Ueberschrift + Kacheln
        local y = 0
        for _, cat in ipairs(Badges.CATS) do
            local h, list = p.heads[cat.key], byCat[cat.key] or {}
            if #list > 0 then
                h:ClearAllPoints()
                h:SetPoint("TOPLEFT", 0, -y)
                h.text:SetText(L[cat.name])
                local c = catHave[cat.key] or { 0, 0 }
                h.count:SetText((L["%d von %d"]):format(c[1], c[2]))
                h.bar:Set(c[2] > 0 and c[1] / c[2] or 0)
                h:Show()
                y = y + 36
                for i, t in ipairs(list) do
                    t:ClearAllPoints()
                    t:SetPoint("TOPLEFT", ((i - 1) % COLS) * TW, -(y + math.floor((i - 1) / COLS) * TH))
                    t:Show()
                end
                y = y + math.ceil(#list / COLS) * TH + 10
            else
                h:Hide()
            end
        end
        for _, t in ipairs(p.tiles) do if not t.visible then t:Hide() end end
        p.grid:SetHeight(math.max(10, y))
        if p.UpdateBar then C_Timer.After(0, function() pcall(p.UpdateBar) end) end
        p.summary:SetText((L["%d von %d Abzeichen"]):format(have, #p.tiles))
        if view == "guild" then
            local rows = {}
            -- Grundmenge: Spieler (Mains) mit Oasis - nur sie haben Abzeichen-Daten
            local mains = {}
            mains[ns.Alts and ns.Alts.Main(ns.me()) or ns.me()] = true
            for name in pairs(ns.db.members) do mains[ns.Alts and ns.Alts.Main(name) or name] = true end
            local total = 0
            for _ in pairs(mains) do total = total + 1 end
            for _, b in ipairs(Badges.LIST) do
                local hold = holdersOf(b.id)
                rows[#rows + 1] = { b = b, hold = hold, top = hold[1] and hold[1].tier or 0, total = total }
            end
            for _, b in ipairs(Badges.UNIQUE) do
                local hold = uniq[b.id] and { { name = uniq[b.id], tier = 4 } } or {}
                rows[#rows + 1] = { b = b, hold = hold, top = #hold > 0 and 4 or 0, total = total }
            end
            -- am weitesten verbreitet oben, bei Gleichstand hoehere Stufen, dann Name
            table.sort(rows, function(x, y)
                if #x.hold ~= #y.hold then return #x.hold > #y.hold end
                return L[x.b.name] < L[y.b.name]
            end)
            p.list:SetData(rows)
        end
    end,
})
------------------------------------------------------------------------
-- Zaehler fuer die Gemeinschafts-Abzeichen
------------------------------------------------------------------------
local function isGuildName(name)
    name = ns.safe(name)
    if not name or name == "" then return false end
    local full = ns.fullName(name)
    if not full or ns.isMe(full) then return false end
    return ns.Radar and ns.Radar.byName and ns.Radar.byName[full] ~= nil
end
local function isGuildUnit(unit)
    if not unit or not UnitExists(unit) or UnitIsUnit(unit, "player") then return false end
    if UnitIsInMyGuild then
        local ok, v = pcall(UnitIsInMyGuild, unit)
        if ok and ns.safe(v) then return true end
    end
    return isGuildName(GetUnitName and GetUnitName(unit, true) or ns.UnitName(unit))
end
-- Gildenmitglieder in meiner Gruppe (+ das niedrigste Level)
local function guildInGroup()
    local n, lowest = 0, nil
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    if count <= 1 then return 0 end
    local raid = IsInRaid and IsInRaid()
    for i = 1, count do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        if not UnitIsUnit(unit, "player") and isGuildUnit(unit) then
            n = n + 1
            local lv = ns.safe(UnitLevel(unit))
            if lv and lv > 0 and (not lowest or lv < lowest) then lowest = lv end
        end
    end
    return n, lowest
end
Badges.GuildInGroup = guildInGroup

-- gegen Mehrfachzaehlung (z.B. Emote-Spam): hoechstens alle x Sekunden
local lastAdd = {}
local function addThrottled(stat, sec)
    local t = GetTime()
    if lastAdd[stat] and t - lastAdd[stat] < sec then return end
    lastAdd[stat] = t
    Badges.Add(stat, 1)
end

-- jede Minute: Gruppe mit Gilde? Kleinere dabei? Tageszeit?
local function minuteTick()
    if not ns.char then return end
    local n, lowest = guildInGroup()
    if n > 0 then
        Badges.Add("groupMin", 1)
        -- Woche: nur wer wirklich spielt (nicht AFK, in den letzten 5 Min. gekaempft/XP/Quest)
        if not ns.safe(UnitIsAFK("player")) and Badges.lastActive and GetTime() - Badges.lastActive < 300 then
            if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("groupMin") end
        end
        local me = ns.safe(UnitLevel("player")) or 0
        if lowest and me - lowest >= 8 then Badges.Add("carryMin", 1) end
    end
    ns.db.badgeDays = ns.db.badgeDays or {}
    local D = ns.db.badgeDays
    local day, hour = date("%Y-%m-%d"), tonumber(date("%H"))
    D.online = D.online or {}
    if not D.online[day] then D.online[day] = true Badges.Check() end
    if hour >= 1 and hour < 5 then
        D.night = D.night or {}
        if not D.night[day] then D.night[day] = true Badges.Check() end
    elseif hour >= 5 and hour < 8 then
        D.early = D.early or {}
        if not D.early[day] then D.early[day] = true Badges.Check() end
    end
end

-- Boss mit mind. zwei Gildenmitgliedern
ns.On("ENCOUNTER_END", function(_, _, _, _, success)
    if ns.safe(success) == 1 and guildInGroup() >= 2 then
        Badges.Add("bossCrew", 1)
        -- Woche: Dungeon-Boss mit mind. 2 weiteren Gildenmitgliedern (einmal je Instanz)
        local inInst, kind = IsInInstance()
        if inInst and (kind == "party" or kind == "raid") then
            if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("dungeonRuns", ns.safe(GetInstanceInfo()) or "?") end
        end
    end
end)

-- Raid-Momente: wer faellt im Bosskampf zuerst / zuletzt, und ging der Kampf danach schief?
local fight
ns.On("ENCOUNTER_START", function() fight = { t = GetTime() } end)
local function othersDeadAlive()
    local dead, alive = 0, 0
    local count = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    local raid = IsInRaid and IsInRaid()
    for i = 1, count do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            if ns.safe(UnitIsDeadOrGhost(unit)) then dead = dead + 1 else alive = alive + 1 end
        end
    end
    return dead, alive
end
ns.On("PLAYER_DEAD", function()
    if not fight or fight.died or guildInGroup() < 1 then return end
    fight.died = true
    local dead, alive = othersDeadAlive()
    if dead == 0 and alive > 0 then
        fight.first = true
        Badges.Add("firstDown", 1)
    elseif alive == 0 and dead > 0 then
        Badges.Add("lastStanding", 1)
    end
end)
ns.On("ENCOUNTER_END", function(_, _, _, _, success)
    local f = fight
    fight = nil
    if not f or guildInGroup() < 1 then return end
    if ns.safe(success) == 1 then
        Badges.Add("bossWins", 1)
    else
        Badges.Add("wipes", 1)
        if f.first then Badges.Add("wipeCause", 1) end
    end
end)

-- Gildenchat: Plaudern und Begruessen
local greeted = {}
ns.On("CHAT_MSG_GUILD", function(msg, sender)
    sender, msg = ns.safe(sender), ns.safe(msg)
    if not sender or not msg or not ns.isMe(ns.fullName(sender)) then return end
    addThrottled("chat", 3)
    -- Woche: hoechstens eine Nachricht pro Minute, mind. 4 Zeichen
    if #msg >= 4 and (not Badges.lastChatCredit or GetTime() - Badges.lastChatCredit >= 60) then
        Badges.lastChatCredit = GetTime()
        if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("chat") end
    end
    local low = msg:lower()
    if low:find("willkommen") or low:find("welcome") or low:find("^wb") or low:find("%swb") then
        -- wer ist in den letzten 15 Minuten beigetreten?
        for _, e in ipairs(Store.List("chronicle", function(e)
            return e.kind == "guild" and (e.tk or ""):find("^tritt") and ns.now() - (e.ts or 0) < 900
        end)) do
            if not greeted[e.who] and not ns.isMe(e.who) then
                greeted[e.who] = true
                Badges.Add("welcomed", 1)
            end
        end
    end
end)

-- Wiederbeleben
local REZ = {
    [2006] = true, [2010] = true, [10880] = true, [10881] = true, [20770] = true,
    [7328] = true, [10322] = true, [10324] = true, [20772] = true, [20773] = true,
    [2008] = true, [20609] = true, [20610] = true, [20776] = true, [20777] = true,
    [20484] = true, [20739] = true, [20742] = true, [20747] = true, [20748] = true,
}
local REZ_WORDS = { "wiederbeleb", "auferstehung", "geist der ahnen", "erl\195\182sung", "wiedergeburt",
    "resurrect", "ancestral spirit", "redemption", "rebirth", "revive" }
local function isRez(spellID)
    spellID = ns.safe(spellID)
    if not spellID then return false end
    if REZ[spellID] then return true end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID) or (GetSpellInfo and GetSpellInfo(spellID))
    name = ns.safe(name)
    if not name then return false end
    name = name:lower()
    for _, w in ipairs(REZ_WORDS) do if name:find(w, 1, true) then return true end end
    return false
end
local rezTarget = {}
ns.On("UNIT_SPELLCAST_SENT", function(unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    castGUID = ns.safe(castGUID)
    if castGUID and isRez(spellID) then rezTarget[castGUID] = ns.safe(target) end
end)
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID)
    if unit ~= "player" then return end
    castGUID = ns.safe(castGUID)
    local t = castGUID and rezTarget[castGUID]
    if t then
        rezTarget[castGUID] = nil
        if isGuildName(t) then Badges.Add("rez", 1) if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("rez", t) end end
    end
end)

-- Handel
local tradeWith
ns.On("TRADE_SHOW", function() tradeWith = ns.safe(ns.UnitName("NPC")) end)
ns.On("UI_INFO_MESSAGE", function(_, msg)
    if tradeWith and ns.safe(msg) and msg == ERR_TRADE_COMPLETE then
        if isGuildName(tradeWith) then Badges.Add("trades", 1) if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("trades", tradeWith) end end
        tradeWith = nil
    end
end)

-- Post
local mailTo
if hooksecurefunc and SendMail then
    hooksecurefunc("SendMail", function(recipient) mailTo = recipient end)
elseif hooksecurefunc and C_Mail and C_Mail.SendMail then
    hooksecurefunc(C_Mail, "SendMail", function(recipient) mailTo = recipient end)
end
ns.On("MAIL_SEND_SUCCESS", function()
    if mailTo and isGuildName(mailTo) then Badges.Add("mails", 1) end
    mailTo = nil
end)

-- Emotes: nett zu Gildenmitgliedern, Tanzen mit der Gilde
local NICE = {
    HUG = true, KISS = true, CHEER = true, THANK = true, WAVE = true, BOW = true, APPLAUD = true, HIGHFIVE = true,
    LOVE = true, PAT = true, CUDDLE = true, GREET = true, HAIL = true, SALUTE = true, WELCOME = true,
    CONGRATULATE = true, TICKLE = true, COMFORT = true, PRAISE = true, SMILE = true, WINK = true, BRAVO = true,
}
if hooksecurefunc and DoEmote then
    hooksecurefunc("DoEmote", function(token, unit)
        token = type(token) == "string" and token:upper() or ""
        if NICE[token] then
            local target = unit or "target"
            if isGuildUnit(target) then
                addThrottled("hugs", 5)
                if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("hugs", ns.safe(ns.UnitName(target))) end
            end
        elseif token == "DANCE" then
            if guildInGroup() >= 1 or isGuildUnit("target") then addThrottled("dances", 20) end
        end
    end)
end

ns.Listen("LOGIN", function()
    ns.After(30, minuteTick)
    ns.Every(60, minuteTick)
end)

------------------------------------------------------------------------
-- Weitere Zaehler (Welt, Handel, Chat, Emotes, Zeit)
------------------------------------------------------------------------
-- leise hochzaehlen (haeufige Ereignisse wie Spruenge), geprueft wird im 90-s-Takt
local function addQuiet(stat, n)
    if not ns.char then return end
    ns.char.stats = ns.char.stats or {}
    ns.char.stats[stat] = (ns.char.stats[stat] or 0) + (n or 1)
end
Badges.AddQuiet = addQuiet
local function sets()
    ns.db.badgeSets = ns.db.badgeSets or {}
    local S = ns.db.badgeSets
    S.zones, S.dungeons = S.zones or {}, S.dungeons or {}
    return S
end
-- Blizzard-Textmuster ("%s rolls %d (%d-%d)") in Lua-Suchmuster umwandeln
local function pattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    -- 1) Platzhalter (%s, %d, %1$s ...) durch Steuerzeichen ersetzen
    local p = fmt:gsub("%%%d%$s", "\1"):gsub("%%%d%$d", "\2"):gsub("%%s", "\1"):gsub("%%d", "\2")
    -- 2) uebrige Sonderzeichen maskieren, 3) Platzhalter zu Fangmustern
    p = p:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")
    p = p:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. p .. "$"
end

-- Quests
ns.On("QUEST_TURNED_IN", function()
    Badges.Add("quests", 1)
    if guildInGroup() > 0 then
        Badges.Add("questsGroup", 1)
        -- Woche: ein Gildenmitglied muss in der Naehe sein
        local raid = IsInRaid and IsInRaid()
        for i = 1, (GetNumGroupMembers() or 0) do
            local u = raid and ("raid" .. i) or ("party" .. i)
            if UnitExists(u) and not UnitIsUnit(u, "player") and isGuildUnit(u) and ns.safe(UnitInRange(u)) then
                if ns.Rewards and ns.Rewards.Credit then ns.Rewards.Credit("questsGroup") end
                break
            end
        end
    end
    Badges.lastActive = GetTime()
end)

-- Gebiete + Dungeons
local lastRun = {}
local function zoneCheck()
    local S = sets()
    local zone = ns.safe(GetRealZoneText())
    if zone and zone ~= "" and not S.zones[zone] then S.zones[zone] = true Badges.Check() end
    local inInst, kind = IsInInstance()
    if inInst and (kind == "party" or kind == "raid") then
        local name = ns.safe(GetInstanceInfo())
        if name and name ~= "" then
            if not S.dungeons[name] then S.dungeons[name] = true Badges.Check() end
            if guildInGroup() >= 2 and (not lastRun[name] or GetTime() - lastRun[name] > 7200) then
                lastRun[name] = GetTime()
                Badges.Add("dungeonRuns", 1)
            end
        end
    end
end
ns.On("ZONE_CHANGED_NEW_AREA", function() ns.After(2, zoneCheck) end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.After(4, zoneCheck) end)

-- Flugrouten
ns.On("PLAYER_CONTROL_LOST", function()
    ns.After(1.5, function() if UnitOnTaxi and UnitOnTaxi("player") then Badges.Add("taxis", 1) end end)
end)

-- Zauber: Ruhestein, Sammeln, Essen/Trinken
local HEARTH = { [8690] = true }
local GATHER = { [2366] = true, [2368] = true, [3570] = true, [11993] = true, [2575] = true, [2576] = true,
    [3564] = true, [10248] = true, [8613] = true, [8617] = true, [8618] = true, [10768] = true }
local GATHER_WORDS = { "kr\195\164utersammeln", "bergbau", "k\195\188rschnerei", "herb gathering", "mining", "skinning" }
local function spellName(id)
    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or (GetSpellInfo and GetSpellInfo(id))
    return ns.safe(n)
end
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" then return end
    spellID = ns.safe(spellID)
    if not spellID then return end
    if HEARTH[spellID] then Badges.Add("hearth", 1) return end
    local name = (spellName(spellID) or ""):lower()
    if GATHER[spellID] then addQuiet("gathers", 1) return end
    for _, w in ipairs(GATHER_WORDS) do if name == w then addQuiet("gathers", 1) return end end
    if name == "essen" or name == "food" then addQuiet("eats", 1)
    elseif name == "trinken" or name == "drink" then addQuiet("drinks", 1)
    elseif name == "erfrischung" or name == "refreshment" then addQuiet("eats", 1) addQuiet("drinks", 1) end
end)

-- Zauber auf Gildenmitglieder: Verbaende und Buffs
local BANDAGE = { [746] = true, [1159] = true, [3267] = true, [3268] = true, [7926] = true, [7927] = true,
    [10838] = true, [10839] = true, [18608] = true, [18610] = true }
local sentTo = {}
ns.On("UNIT_SPELLCAST_SENT", function(unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    castGUID, target, spellID = ns.safe(castGUID), ns.safe(target), ns.safe(spellID)
    if castGUID and target and target ~= "" then sentTo[castGUID] = { target = target, spell = spellID } end
end)
ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, castGUID)
    if unit ~= "player" then return end
    castGUID = ns.safe(castGUID)
    local s = castGUID and sentTo[castGUID]
    if not s then return end
    sentTo[castGUID] = nil
    if not isGuildName(s.target) or isRez(s.spell) then return end
    local name = (spellName(s.spell or 0) or ""):lower()
    if BANDAGE[s.spell] or name:find("verband", 1, true) or name:find("bandage", 1, true) or name:find("erste hilfe", 1, true) or name:find("first aid", 1, true) then
        Badges.Add("bandageGuild", 1)
    else
        addThrottled("castsOnGuild", 3)
    end
end)

-- Wiederbelebt worden (von Gildenmitgliedern)
local rezzedBy, rezzedAt
ns.On("RESURRECT_REQUEST", function(inviter)
    inviter = ns.safe(inviter)
    if inviter and isGuildName(inviter) then rezzedBy, rezzedAt = inviter, GetTime() end
end)
ns.On("PLAYER_ALIVE", function()
    if rezzedBy and GetTime() - (rezzedAt or 0) < 120 then Badges.Add("rezzedByGuild", 1) end
    rezzedBy = nil
end)
ns.On("PLAYER_UNGHOST", function()
    if rezzedBy and GetTime() - (rezzedAt or 0) < 120 then Badges.Add("rezzedByGuild", 1) end
    rezzedBy = nil
end)

-- Tod: in der Gruppe mit der Gilde / Level-Ups ohne Tod
ns.On("PLAYER_DEAD", function()
    if guildInGroup() > 0 then Badges.Add("groupDeaths", 1) end
    if ns.char then ns.char.diedThisLevel = true end
end)
ns.On("PLAYER_LEVEL_UP", function()
    if not ns.char then return end
    if not ns.char.diedThisLevel then Badges.Add("cleanLevels", 1) end
    ns.char.diedThisLevel = false
end)

-- Beute, Gold, Angeln, Herstellen
local moneyAtLoot
ns.On("LOOT_OPENED", function()
    addQuiet("loots", 1)
    moneyAtLoot = GetMoney and GetMoney()
    if IsFishingLoot and IsFishingLoot() then Badges.Add("fish", 1) end
end)
ns.On("LOOT_CLOSED", function()
    if moneyAtLoot and GetMoney then
        local d = GetMoney() - moneyAtLoot
        if d > 0 then addQuiet("goldCopper", d) end
    end
    moneyAtLoot = nil
end)
-- Muster erst bei Bedarf bauen (Blizzard-Texte sind dann sicher geladen)
local patCache = {}
local function pat(globalName)
    if patCache[globalName] == nil then patCache[globalName] = pattern(_G[globalName]) or false end
    return patCache[globalName] or nil
end
ns.On("CHAT_MSG_LOOT", function(msg)
    msg = ns.safe(msg)
    if not msg then return end
    local c1, c2 = pat("LOOT_ITEM_CREATED_SELF"), pat("LOOT_ITEM_CREATED_SELF_MULTIPLE")
    if (c1 and msg:find(c1)) or (c2 and msg:find(c2)) then addQuiet("crafts", 1) end
end)
-- Kills: zentral erkannt in Life.lua (Erfahrung bzw. Tod des eigenen Ziels), 0.5.616
ns.Listen("KILL", function() addQuiet("kills", 1) end)

-- Reparieren, Gildenbank-Einzahlung
if hooksecurefunc then
    if RepairAllItems then
        hooksecurefunc("RepairAllItems", function(guildBank)
            if guildBank then return end
            local cost = GetRepairAllCost and GetRepairAllCost()
            if cost and cost > 0 then addQuiet("repairCopper", cost) end
        end)
    end
    if DepositGuildBankMoney then
        hooksecurefunc("DepositGuildBankMoney", function(copper)
            if copper and copper > 0 then addQuiet("bankCopper", copper) Badges.Check() end
        end)
    end
    if JumpOrAscendStart then
        hooksecurefunc("JumpOrAscendStart", function() addQuiet("jumps", 1) end)
    end
end

-- Systemmeldungen: Duelle, /wuerfeln, Auktionen
ns.On("CHAT_MSG_SYSTEM", function(msg)
    msg = ns.safe(msg)
    if not msg then return end
    for _, gname in ipairs({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" }) do
        local dp = pat(gname)
        local w, l
        if dp then w, l = msg:match(dp) end
        if w then
            local meW, meL = ns.isMe(ns.fullName(w)), ns.isMe(ns.fullName(l))
            if (meW and isGuildName(l)) or (meL and isGuildName(w)) then
                Badges.Add("duels", 1)
                if meW then Badges.Add("duelWins", 1) end
            end
            return
        end
    end
    local rp, sp = pat("RANDOM_ROLL_RESULT"), pat("ERR_AUCTION_SOLD_S")
    local who = rp and msg:match(rp)
    if who and ns.isMe(ns.fullName(who)) then addQuiet("rolls", 1) return end
    if ERR_AUCTION_STARTED and msg == ERR_AUCTION_STARTED then Badges.Add("auctionsPosted", 1) return end
    if sp and msg:find(sp) then Badges.Add("auctionsSold", 1) end
end)

-- Fluestern an Gildenmitglieder
ns.On("CHAT_MSG_WHISPER_INFORM", function(_, target)
    if isGuildName(target) then addThrottled("whispers", 5) end
end)

-- Emotes, die Gildenmitglieder an mich richten
ns.On("CHAT_MSG_TEXT_EMOTE", function(text, sender)
    text, sender = ns.safe(text), ns.safe(sender)
    if not text or not sender or not isGuildName(sender) then return end
    local low = text:lower()
    if low:find(" euch") or low:find(" dich") or low:find(" you") then addThrottled("emotesReceived", 3) end
end)

-- Gildenchat: was ich schreibe
local function has(low, list)
    for _, w in ipairs(list) do if low:find(w) then return true end end
    return false
end
ns.On("CHAT_MSG_GUILD", function(msg, sender)
    sender, msg = ns.safe(sender), ns.safe(msg)
    if not sender or not msg or not ns.isMe(ns.fullName(sender)) then return end
    local low = " " .. msg:lower() .. " "
    if msg:find("|Hitem:", 1, true) then addThrottled("links", 3) end
    if has(low, { "haha", " lol", "xd", ":d", "rofl", "hihi" }) then addThrottled("lols", 5) end
    if has(low, { " gn ", " gn8", " n8 ", "gute nacht", "good night", "nacht zusammen" }) then addThrottled("goodnights", 600) end
    if has(low, { " moin", " hallo", " servus", " hi ", " hey ", "guten morgen", "guten abend", "n'abend", " huhu" }) then addThrottled("greetings", 600) end
    if has(low, { "danke", " thx", " ty ", "dankesch", "thank" }) then addThrottled("thanks", 30) end
end)

-- Reittier, Gasthaus
ns.On("PLAYER_MOUNT_DISPLAY_CHANGED", function()
    if IsMounted and IsMounted() then addThrottled("mounts", 10) end
end)
ns.On("PLAYER_UPDATE_RESTING", function()
    if IsResting and IsResting() then addThrottled("inns", 120) end
end)

-- Eigene Oasis-Aktionen: Umfragen, Termine, Gesucht, Auftraege, Trinkgeld, volle Gruppe
ns.Listen("STORE", function(coll, rec, old)
    if not rec or rec.del or rec.demo or tostring(rec.id):find("demo-", 1, true) then return end
    local mine = ns.isMe(rec.by or rec.who or rec.from or "")
    if not old and mine then
        if coll == "polls" then Badges.Add("pollsCreated", 1)
        elseif coll == "events" then Badges.Add("eventsCreated", 1)
        elseif coll == "wants" then Badges.Add("wantsPosted", 1)
        elseif coll == "orders" and ns.isMe(rec.from) then
            Badges.Add("ordersPlaced", 1)
            if rec.tip then Badges.Add("tips", 1) end
        end
    end
    if coll == "lfg" and old and old.open and not rec.open and ns.isMe(rec.who) and (rec.count or 0) >= (rec.size or 5) then
        Badges.Add("groupsFilled", 1)
    end
end)

-- Minuten-Takt ergaenzen: Spielzeit, AFK, Schwimmen, Wochenende
local function minuteExtra()
    if not ns.char then return end
    addQuiet("playMin", 1)
    if UnitIsAFK and ns.safe(UnitIsAFK("player")) then addQuiet("afkMin", 1) end
    if IsSwimming and ns.safe(IsSwimming()) then addQuiet("swimMin", 1) end
    local wd = tonumber(date("%w"))
    if wd == 0 or wd == 6 then
        ns.db.badgeDays = ns.db.badgeDays or {}
        local D = ns.db.badgeDays
        D.weekend = D.weekend or {}
        local day = date("%Y-%m-%d")
        if not D.weekend[day] then D.weekend[day] = true Badges.Check() end
    end
end
ns.Listen("LOGIN", function()
    ns.After(35, minuteExtra)
    ns.Every(60, minuteExtra)
end)

------------------------------------------------------------------------
-- 0.5.607: Zaehler fuer die neuen Abzeichen (nur eigene Ereignisse, gedrosselt, nichts wird gesendet)
------------------------------------------------------------------------
-- Geisterlauf, ertrunken, Serie ohne Tod
ns.On("PLAYER_UNGHOST", function() addQuiet("ghostRuns", 1) end)
ns.On("PLAYER_DEAD", function()
    if IsSwimming and ns.safe(IsSwimming()) then Badges.Add("drowned", 1) end
    if ns.char then ns.char.aliveMin = 0 end
end)
-- Fehlermeldungen: Taschen voll, ausser Reichweite, falsch herum, keine Ressource
do
    local MAP
    local function build()
        MAP = {}
        local function put(globalName, stat) local t = _G[globalName] if type(t) == "string" and t ~= "" then MAP[t] = stat end end
        for _, g in ipairs({ "ERR_INV_FULL", "ERR_BAG_FULL", "INVENTORY_FULL" }) do put(g, "bagsFull") end
        for _, g in ipairs({ "ERR_OUT_OF_RANGE", "SPELL_FAILED_OUT_OF_RANGE", "ERR_TOO_FAR_TO_INTERACT" }) do put(g, "outOfRange") end
        for _, g in ipairs({ "ERR_BADATTACKFACING", "SPELL_FAILED_UNIT_NOT_INFRONT", "SPELL_FAILED_NOT_INFRONT" }) do put(g, "wrongFacing") end
        for _, g in ipairs({ "ERR_OUT_OF_MANA", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_ENERGY", "SPELL_FAILED_NO_POWER" }) do put(g, "noMana") end
    end
    local GAP = { bagsFull = 10, outOfRange = 4, wrongFacing = 4, noMana = 4 }
    ns.On("UI_ERROR_MESSAGE", function(_, msg)
        msg = ns.safe(msg)
        if type(msg) ~= "string" then return end
        if not MAP then build() end
        local stat = MAP[msg]
        if stat then addThrottled(stat, GAP[stat] or 5) end
    end)
end
-- sich selbst anfluestern
ns.On("CHAT_MSG_WHISPER", function(_, sender)
    sender = ns.safe(sender)
    if sender and ns.isMe(ns.fullName(sender)) then addThrottled("selfWhisper", 10) end
end)
-- Dauerfeuer: 5 eigene Gildennachrichten in 15 Sekunden
do
    local times = {}
    ns.On("CHAT_MSG_GUILD", function(_, sender)
        sender = ns.safe(sender)
        if not (sender and ns.isMe(ns.fullName(sender))) then return end
        local now = GetTime()
        times[#times + 1] = now
        while times[1] and now - times[1] > 15 do table.remove(times, 1) end
        if #times >= 5 then times = {} Badges.Add("chatBursts", 1) end
    end)
end
-- Haarscharf: Kampf mit unter 10 % Leben ueberstanden
ns.On("PLAYER_REGEN_ENABLED", function()
    local h, m = UnitHealth and UnitHealth("player"), UnitHealthMax and UnitHealthMax("player")
    if issecretvalue and (issecretvalue(h) or issecretvalue(m)) then return end
    h, m = tonumber(h), tonumber(m)
    if h and m and m > 0 and h > 0 and h / m < 0.10 and not (UnitIsDeadOrGhost and ns.safe(UnitIsDeadOrGhost("player"))) then
        Badges.Add("closeCalls", 1)
    end
end)
-- Screenshots, Bank, Haendler
ns.On("SCREENSHOT_SUCCEEDED", function() addThrottled("screenshots", 1) end)
ns.On("BANKFRAME_OPENED", function() addThrottled("bankVisits", 20) end)
ns.On("MERCHANT_SHOW", function() addThrottled("merchantVisits", 20) end)
-- Weltkarte geoeffnet (nur angehaengt, nichts an Blizzards Karte veraendert)
ns.Listen("LOGIN", function()
    if WorldMapFrame and WorldMapFrame.HookScript and not Badges.mapHooked then
        Badges.mapHooked = true
        WorldMapFrame:HookScript("OnShow", function() addThrottled("mapOpens", 3) end)
    end
end)
-- im Gasthaus ausgeloggt
ns.On("PLAYER_LOGOUT", function()
    if IsResting and ns.safe(IsResting()) and ns.char then
        ns.char.stats = ns.char.stats or {}
        ns.char.stats.innLogouts = (ns.char.stats.innLogouts or 0) + 1
    end
end)
-- hoechster Goldbestand je Charakter (in Gold)
ns.On("PLAYER_MONEY", function()
    if not (ns.char and GetMoney) then return end
    local g = math.floor((GetMoney() or 0) / 10000)
    ns.char.stats = ns.char.stats or {}
    if g > (ns.char.stats.goldMax or 0) then ns.char.stats.goldMax = g end
end)
-- Level: schnell (unter 30 Spielminuten) und im Dungeon
ns.On("PLAYER_LEVEL_UP", function()
    if not ns.char then return end
    ns.char.stats = ns.char.stats or {}
    local pm = ns.char.stats.playMin or 0
    if ns.char.lvlAtPlay and pm - ns.char.lvlAtPlay < 30 then Badges.Add("fastLevels", 1) end
    ns.char.lvlAtPlay = pm
    if IsInInstance and select(1, IsInInstance()) then Badges.Add("instanceDings", 1) end
end)
-- Furchtlos: Boss mit Gildenmitgliedern gelegt, ohne im Kampf zu sterben
do
    local diedInFight = false
    ns.On("ENCOUNTER_START", function() diedInFight = false end)
    ns.On("PLAYER_DEAD", function() diedInFight = true end)
    ns.On("ENCOUNTER_END", function(_, _, _, _, success)
        if success == 1 and not diedInFight and guildInGroup() >= 1 then Badges.Add("cleanBoss", 1) end
    end)
end
-- jede Minute: Flugzeit, Serie ohne Tod, Gruppen-Kameraden aus der Gilde
local function minuteNew()
    if not ns.char then return end
    if UnitOnTaxi and ns.safe(UnitOnTaxi("player")) then addQuiet("taxiMin", 1) end
    if not (UnitIsAFK and ns.safe(UnitIsAFK("player"))) and not (UnitIsDeadOrGhost and ns.safe(UnitIsDeadOrGhost("player"))) then
        ns.char.aliveMin = (ns.char.aliveMin or 0) + 1
        if ns.char.aliveMin > (ns.char.bestAlive or 0) then ns.char.bestAlive = ns.char.aliveMin end
    end
    if IsInGroup and IsInGroup() then
        ns.db.badgeSets = ns.db.badgeSets or {}
        local S = ns.db.badgeSets
        S.mates = S.mates or {}
        local raid = IsInRaid and IsInRaid()
        local n = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, n do
            local unit = raid and ("raid" .. i) or ("party" .. i)
            if UnitExists(unit) and not UnitIsUnit(unit, "player") and isGuildUnit(unit) then
                local nm = GetUnitName and ns.safe(GetUnitName(unit, true))
                if nm and not S.mates[nm] then S.mates[nm] = true end
            end
        end
    end
end
ns.Listen("LOGIN", function() ns.Every(60, function() pcall(minuteNew) end) end)

------------------------------------------------------------------------
-- Geteilte Zaehler (fuer die Gilden-Titel "Gildenstimme", "Kaenguru" ...)
------------------------------------------------------------------------
function Badges.SharedStats()
    local s = accountStats()
    local t = {}
    for _, b in ipairs(Badges.UNIQUE) do
        if b.shared and (s[b.shared] or 0) > 0 then t[#t + 1] = b.shared .. "=" .. math.floor(s[b.shared]) end
    end
    return table.concat(t, ",")
end
function Badges.DecodeShared(str)
    local out = {}
    for k, v in (str or ""):gmatch("(%w+)=(%d+)") do out[k] = tonumber(v) end
    return out
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
local function snapshot()
    -- Level und beste Berufsstufe dieses Charakters merken
    ns.char.level = ns.safe(UnitLevel("player")) or ns.char.level
    local best = 0
    if ns.Radar then
        for _, pr in ipairs(ns.Radar.myProfessions()) do best = math.max(best, pr.rank or 0) end
    end
    ns.char.profMax = math.max(ns.char.profMax or 0, best)
end
ns.Listen("LOGIN", function()
    ns.After(20, function()
        snapshot()
        -- beim ersten Mal still nachziehen (keine Hinweis-Flut fuer Altes)
        Badges.initialized = false
        Badges.Check()
        Badges.initialized = true
    end)
    ns.Every(90, function() snapshot() Badges.Check() end)
end)
ns.Listen("LEVEL_UP", function() snapshot() Badges.Check() end)
ns.On("SKILL_LINES_CHANGED", function() ns.After(2, function() snapshot() Badges.Check() end) end)
ns.Listen("PROFILE", function() ns.RefreshPage("badges") end)

-- Aktivitaet fuer die Wochenwertung (Gruppen-Minuten)
ns.On("PLAYER_REGEN_DISABLED", function() Badges.lastActive = GetTime() end)
ns.On("PLAYER_XP_UPDATE", function() Badges.lastActive = GetTime() end)

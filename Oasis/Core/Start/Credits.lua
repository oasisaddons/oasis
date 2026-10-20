-- Oasis - Credits: Lizenz und Herkunft der fremden Bestandteile. Steht seit 0.5.928 unten im Reiter
-- Einstellungen > Profil & Daten > Status (vorher eigener Reiter - die Reiterzeile wurde zu voll).
-- Kurzfassung von CREDITS.txt (dort und in LICENSE / LICENSE-MIT.txt stehen die vollen Texte). Bei neuen fremden
-- Inhalten BEIDE Stellen pflegen.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

-- { head = Ueberschrift } oder { Name, Beschreibung }; Eigennamen bleiben unuebersetzt
local ROWS = {
    { head = "Oasis" },
    { "Lizenz", "GNU General Public License Version 2 (GPL-2.0). Oasis darf weitergegeben und veraendert werden, solange diese Lizenz erhalten bleibt." },
    { "Eigene Arbeit", "Rang-Wappen, Profilrahmen, Stufen-Abzeichen, Wappen, Ziffern, Deathroll-Grafiken, Logos, Effekte und Designs stammen vom Oasis-Autor. Die Dashboard-Banner hat der Autor mit KI erstellt." },

    { head = "Grafik" },
    { "game-icons.net", "Symbole und Abzeichen-Symbole von Lorc und Delapouite - CC BY 3.0" },
    { "Twemoji", "Emojis, Copyright Twitter/X und Mitwirkende - CC BY 4.0, fuer Oasis verkleinert" },
    { "flag-icons", "Flaggen von Panayiotis Lipiridis - MIT-Lizenz" },
    { "ambientCG", "Hintergrund-Texturen der Designs - CC0 1.0" },
    { "Midas", "Banner auf der Uebersicht: Midas, das Auktionshaus-Addon von Rebo aus der Gilde OASIS" },

    { head = "Klang und Schrift" },
    { "Kenney", "Klick-Toene aus \"Interface Sounds\" (kenney.nl) - CC0 1.0" },
    { "Google Fonts", "Alle Schriften unter der SIL Open Font License 1.1" },

    { head = "Daten" },
    { "AtlasLootClassic / Forever Atlas", "Boss-Positionen im Dungeon-Atlas und Drop-Chancen der Dungeon-Bosse - GPL-2.0. Autoren: Lag, Daviesh und weitere" },
    { "SimpleDungeonMap", "Teile der Boss-Positionen, von Babilounet - MIT-Lizenz" },
    { "foreverchanges.pro, wowforevertalents.com", "Quellen fuer Dungeons, Bosse, Beute und Quests" },

    { head = "Blizzard" },
    { "World of Warcraft", "World of Warcraft und zugehoerige Namen, Wappen und Grafiken sind Marken von Blizzard Entertainment. Oasis ist ein Fan-Projekt und steht in keiner Verbindung zu Blizzard." },
}
ns.CreditRows = ROWS

local NAME_W = 230

-- f = Reiter-Flaeche, x0/y0 = linke obere Ecke des Blocks, width = Breite. Die Ueberschrift bekommt wie alle
-- Abschnitte der Einstellungen automatisch eine Karte um sich und ihren Inhalt (Settings.lua autoCards).
local Credits = {}
ns.Credits = Credits
function Credits.Build(f, x0, y0, width)
    local H = ns.SettingsHelpers
    local W = math.max(300, (width or (f:GetWidth() or 740)) - 28)
    local X = (x0 or 0) + 14
    if H and H.section then H.section(f, L["Credits"], X, (y0 or 0) - 12, W) end
    local prev, indent   -- indent: prev ist eine Beschreibung (steht um NAME_W eingerueckt)
    local function below(o, gap)
        if prev then
            o:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", indent and -NAME_W or 0, -gap)
        else
            o:SetPoint("TOPLEFT", f, "TOPLEFT", X, (y0 or 0) - 46)
        end
    end
    for _, r in ipairs(ROWS) do
        if r.head then
            local h = K.Header(f, L[r.head])
            h:SetWidth(W)
            below(h, 26)
            prev, indent = h, false
        else
            local name = K.Text(f, 13, C.text)
            name:SetWidth(NAME_W - 12)
            name:SetWordWrap(true)
            name:SetJustifyV("TOP")
            name:SetText(L[r[1]])
            below(name, 12)
            local desc = K.Text(f, 12, C.dim)
            desc:SetPoint("TOPLEFT", name, "TOPLEFT", NAME_W, 0)
            desc:SetWidth(W - NAME_W)
            desc:SetWordWrap(true)
            desc:SetJustifyV("TOP")
            desc:SetText(L[r[2]])
            prev, indent = desc, true
        end
    end
    local foot = K.Text(f, 11, C.dim)
    foot:SetWidth(W)
    foot:SetWordWrap(true)
    foot:SetJustifyV("TOP")
    foot:SetText(L["Die vollstaendigen Lizenztexte liegen im Oasis-Ordner: CREDITS.txt, LICENSE und LICENSE-MIT.txt."])
    below(foot, 30)
end


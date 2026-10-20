-- Oasis - Credits: license and origin of third-party components. Since 0.5.928 at the bottom of the tab
-- Settings > Profile & Data > Status (previously its own tab - the tab row got too full).
-- Short version of CREDITS.txt (the full texts are there and in LICENSE / LICENSE-MIT.txt). For new third-party
-- content, maintain BOTH places.
local ADDON, ns = ...
local L = ns.L
local K, C = ns.K, ns.K.C

-- { head = heading } or { name, description }; proper names stay untranslated
local ROWS = {
    { head = "Oasis" },
    { "License", "GNU General Public License version 2 (GPL-2.0). Oasis may be shared and modified as long as this license is kept." },
    { "Own work", "Rank crests, profile frames, level badges, emblems, digits, Deathroll graphics, logos, effects and themes were made by the Oasis author. The dashboard banners were created by the author with AI." },

    { head = "Graphics" },
    { "game-icons.net", "Icons and badge icons by Lorc and Delapouite – CC BY 3.0" },
    { "Twemoji", "Emojis, copyright Twitter/X and contributors – CC BY 4.0, resized for Oasis" },
    { "flag-icons", "Flags by Panayiotis Lipiridis – MIT license" },
    { "ambientCG", "Background textures of the themes – CC0 1.0" },
    { "Midas", "Banner on the overview: Midas, the auction house add-on by Rebo of the guild OASIS" },

    { head = "Sound and fonts" },
    { "Kenney", "Click sounds from “Interface Sounds” (kenney.nl) – CC0 1.0" },
    { "Google Fonts", "All fonts under the SIL Open Font License 1.1" },

    { head = "Data" },
    { "AtlasLootClassic / Forever Atlas", "Boss positions in the dungeon atlas and drop chances of dungeon bosses – GPL-2.0. Authors: Lag, Daviesh and others" },
    { "SimpleDungeonMap", "Parts of the boss positions, by Babilounet – MIT license" },
    { "foreverchanges.pro, wowforevertalents.com", "Sources for dungeons, bosses, loot and quests" },

    { head = "Blizzard" },
    { "World of Warcraft", "World of Warcraft and related names, crests and artwork are trademarks of Blizzard Entertainment. Oasis is a fan project and is not affiliated with Blizzard." },
}
ns.CreditRows = ROWS

local NAME_W = 230

-- f = tab area, x0/y0 = top left corner of the block, width = width. Like all settings sections, the heading
-- automatically gets a card around itself and its content (Settings.lua autoCards).
local Credits = {}
ns.Credits = Credits
function Credits.Build(f, x0, y0, width)
    local H = ns.SettingsHelpers
    local W = math.max(300, (width or (f:GetWidth() or 740)) - 28)
    local X = (x0 or 0) + 14
    if H and H.section then H.section(f, L["Credits"], X, (y0 or 0) - 12, W) end
    local prev, indent   -- indent: prev is a description (indented by NAME_W)
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
    foot:SetText(L["The full license texts are in the Oasis folder: CREDITS.txt, LICENSE and LICENSE-MIT.txt."])
    below(foot, 30)
end


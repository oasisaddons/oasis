# Oasis - Guild Hub for WoW Forever

Oasis is a guild addon for **WoW Forever** (Classic+). It brings your guild together in one window: member list and
online status, guild finder for groups, polls, events, crafting orders and wants/offers, a guild chronicle, ranks and
badges, a dungeon atlas, Deathroll duels and more. Everything is optional and can be switched off in the settings.

- Oasis never sends chat messages on its own; it only offers messages for you to send with one click.
- Open Oasis with the minimap button or `/oasis` (short: `/oa`).
- Guild data is shared only with guild members. Sharing your position, deaths and similar is configurable.
- Languages: German, English, French, Spanish, Italian, Portuguese, Russian, Polish, Korean, Japanese, Chinese (Simplified and Traditional). Translations are machine-made; corrections are welcome.

## What is inside

- **Guild**: member list with roles, professions and alts, guild chat with emojis, chronicle, polls, guild goals, guild bank overview.
- **Playing together**: group finder with fixed slots, quest partners, guild map, rare and gathering spots.
- **Map and minimap**: guild positions, gathering route, rare sightings with time, guild markers and notes, dungeon entrances, danger zones, a layer helper. Everything can be switched on or off and sized to taste.
- **Raid**: events with sign-up, raid planner, ready check with buffs and enchants, boss tactics, loot master, soft reserve, lockouts.
- **Trade**: crafting exchange with orders, wish list, market page (uses the optional add-on Midas).
- **Fun**: ranks and badges, Deathroll arena (stakes are off by default and can only be enabled by guild leadership), graveyard.
- **Guild leadership**: announcements, permissions per rank, promotion suggestions, history, inactive members.
- **Your own content**: a guild can add its own sounds and emojis with two small companion folders. They are not part of this download (so updates never overwrite them); the template is on the project's source page.

## Commands

- `/oasis` or `/oa` - open or close the window
- `/oa mini` - collapse to the slim bar
- `/oa sync` - sync guild data now
- `/oa rundgang` - show the first-start tour again
- `/oa weiterleiten` - switch the whisper offer for alts on or off
- `/oa bug` - report a problem (guild version)

## License

Oasis is free software under the **GNU General Public License v2** (see `LICENSE`). The dungeon atlas data is derived from Forever Atlas / AtlasLootClassic (GPL-2.0).

## Credits and licenses

Full list: `CREDITS.txt` in the addon folder.

- **Icons** (`Media/icons`): [game-icons.net](https://game-icons.net) by Lorc and Delapouite, licensed
  [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
- **Emojis**: [Twemoji](https://github.com/jdecked/twemoji), Copyright Twitter/X and contributors, licensed
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
- **Flags**: [flag-icons](https://github.com/lipis/flag-icons) by Panayiotis Lipiridis, MIT license.
- **Fonts**: Google Fonts, SIL Open Font License 1.1 (details in `Media/fonts/LICENSE-FONTS.txt`).
- **Textures**: ambientCG, CC0 1.0.
- **Dungeon maps / boss positions**: based on Forever Atlas / AtlasLootClassic (GPL-2.0) and SimpleDungeonMap by Babilounet (MIT),
  see `Media/CREDITS_MAPS.txt`.
- Rank crests, profile frames, level badges and logos: original work by the Oasis author.

World of Warcraft and related names/graphics are trademarks of Blizzard Entertainment.


## Install

Download the latest `Oasis-Public-<version>.zip` from the Releases page and unpack it into `Interface/AddOns`.

## Your own sounds and emojis

The same release has a second file, `Oasis-Tools-<version>.zip`. It contains the templates `Oasis_Sounds` and `Oasis_Emojis` with their import scripts and instructions (plus the export tools). Unpack it into `Interface/AddOns`, drop your files in, run the import and share the two folders with your guild. They are not part of the Oasis package, so add-on updates never touch them.

# Oasis - changelog for CurseForge uploads

Add a new section at the top for every file that is uploaded. Describe what changed since the previous uploaded file.

## 0.6.161

- New "What's new" window: title with version, one row per change with icon, title and short text.
- Start window: centred header, calmer background with vignette, round badges of equal size on every tile, the "keep everything" card pulses gently with a shimmer along its edge, a short sound when you click next to the window.
- Main window: frame with a fine accent line like the start window; finer dot grid on both sides.
- Appearance > Own colours: separate colours for the background left and right, sliders "Glow left" / "Glow right" and a "Glow breathes" switch. Picking a design resets all own colours.
- "Sidebar left" colour no longer changes the right side.
- "X is online" notice uses the new notice design.
- Gathering nodes on the minimap are see-through (ring only), so the game's own node icon stays visible, and they sit below frame and compass.
- Animated emojis (emoji mode 4): position respects the chat line's text scale; /oa emojiversatz <factor> to fine-tune; /oa emojitest shows more values and opens the output in a copy box.

## 0.6.139

- Guild members on the world map and minimap now glide smoothly between updates instead of jumping; while moving, positions are sent every 2.5 s.
- Player book: "Add to player book" in the right-click menu (chat names, party, raid, target, focus, friends) and /oa buch for your target - creates the entry and puts the cursor into the note.
- Appearance > Own colours: fourth colour button "Background" (right-click resets).
- Start window: wider, rounded corners, nothing cut off any more; "Don't ask again" can be switched off again.
- Notifications at the top with a cleaner timer bar.

## 0.6.117

- Settings search also finds related words (sound, privacy, size ...), ignores umlauts, searches tab and area names and lists matches in the name first.
- A short grey line under each switch tells what it does (quick start, tooltips, map, privacy and all areas).
- Map settings on one page in two columns, sorted by world map, gathering map, icons and sending.
- Tooltips, Map and Privacy have a "Reset this page" button (asks once before resetting).
- New "What's new" window once per new version with up to 5 points and a button to the settings (/oa neu, can be turned off).
- Guild chat: select text with the mouse and copy it with Ctrl+C.

## 0.6.112

- Settings reorganised by topic instead of by module: Start, Appearance, Notifications & sound, Tooltips & map, Areas, Gameplay helpers, Profile, Advanced.
- New "Quick start" page: the most important switches at a glance, plus tiles that lead to every topic.
- New page "Tooltips": all extra tooltip lines (wanted by, crafters, guild bank, materials, reservations, player ratings) in one place.
- New page "Map": all world map and minimap switches in one place.
- No more duplicate settings: notification switches only under Notifications, sharing switches only under Privacy, chat sounds and online display only under Sound. Areas link to these pages.
- Technical pages (status, modules, performance) moved to "Advanced".
- Appearance > Details: cleaner layout without cut-off titles; window size and transparency directly below.
- Chat: select text right in the chat window by dragging with the mouse - letter by letter, also across wrapped lines. Ctrl+C copies, right-click shows more (insert into chat line, open as text box, clear). Scrolling with the mouse wheel while dragging extends or shrinks the selection.
- Chat: Alt + click opens the chat as a text box for selecting; the copy button at the top right of the chat opens it too (right-click: search window).
- Game chat (level, class icon and coloured names in Blizzard's chat) is now on by default; its history after /reload is off by default.
- Game chat settings now also contain the chat switches from Comfort (arrow keys, no fading, input above the chat) and the selection switches.
- "Keep chat after /reload" no longer carries old history blocks along and saves only new lines.
- Sound settings: the button "Own sounds and emojis" no longer overlaps the click volume.

## 0.5.994

- Chat: clicking a player name in a line with an animated emoji works again (whisper, right-click menu). The line under the mouse pauses its animation.
- Game chat: now also works when another addon restyles chat lines (shortened channel names, coloured timestamps); before, nothing changed in that case.
- Chat: animated emojis now also move in whisper tabs, and the emoji and sound buttons appear at the input of whisper tabs.
- Dungeons, quests: every quest now says "Missing", "Active" or "Done" in colour; missing quests come first, finished ones last, and a line above the list counts each group.
- Dungeons, quests: the map in the quest details is larger - it starts right below the text and uses the free space at the bottom.
- Dungeons, quests: each quest row has a soft colour gradient for its state (pink = missing, yellow = active, green = done).
- Dungeons, quests: new button "Dungeon map" in the quest details opens the dungeon map with the boss locations.
- New module "Game chat" for Blizzard's chat windows (Settings > Gameplay helpers > Game chat, off by default): first names only, level and class/race icon before the name, icons on item and spell links, shortened channel names, quiet text, timestamps, item tooltip on hover.
- Game chat: filters for public chat - blocked words, Cyrillic text, Chinese characters, repeated messages, and muting a player in one channel (/oa chatmute channel; name).
- Game chat: search and copy the lines of a chat tab (/oa chatsuche) and keep the chat history between sessions.
- Game chat: keyword alerts with notice, sound and a list of matches (/oa chatalarm).
- Game chat: hide the chat menu, channel, social and scroll buttons.
- Dungeons: the dungeon map with boss locations is shown again on the Forever client (the map image now comes from the game map of the dungeon).
- Collections: a character no longer appears twice in the ranking when it was recorded under two spellings (first name only, or a different realm suffix); the newest record counts.

## 0.5.986

- Sample data (/oa demo) is now in English for every language except German: events, guild chat, notes, boss tactics, dungeon and item names.
- Without a guild: with the sample data loaded, the guild pages are shown too, and the start page for players without a guild has a button "See an example".
- Labels now follow the language chosen in Oasis even if it differs from the game client (role names, loot choices, order status, chronicle types, whisper filters).
- Groups: the switches "Voice chat" and "Auto-accept" no longer overlap.
- Crafting: materials whose name the client has not loaded yet are requested instead of being shown as a number.
- Map: danger zones (red tint on the world map) are off by default; they can be switched on in the settings.
- Translations: 15 texts that were still shown in English are now translated in French, Spanish, Italian, Portuguese, Russian, Chinese, Korean, Japanese and Polish (sample data, own sounds and emojis, map markers).
- Chinese: fixed an error when showing the number of recipes of a crafter.

## 0.5.981

- Item comparison: the panel no longer covers the window the item is in (bags, bank, vendor) if there is room elsewhere.
- Sounds are twice as loud by default (the volume slider in the sound settings still goes from 0 to 200 %).
- Item comparison: Blizzard's own comparison tooltip no longer flickers behind the Oasis panel.
- Guild chat: messages written from Discord are marked with an icon and "Discord" next to the name.
- Guild chat: your own messages no longer count as unread.
- Own guild sounds and emojis can require an Oasis rank: put "@20" at the end of a file or folder name before importing (applies only while guild leadership has the rank lock switched on).
- Map: danger zones (red shimmer) are only drawn on zone maps, no longer on continent maps.
- Map bar: small slide switches, everything in one row (it tightens up on narrow maps); heatmap, position sharing and minimap dots are in the settings only.
- Chat: the emoji and sound buttons in the input line have a larger click area.
- Minimap: Oasis icons no longer cover your own arrow in the centre, and they sit below the minimap frame and compass.
- Emoji picker: one group "Emojis"; the "Mine" group is gone.
- Emoji picker: the standard emojis are back, as the first tab under "Stickers".
- Top bar: the "N new" counter can be clicked and opens the page with news (or a list if there are several).
- More sample data: guild log, former members, applicants, ban list, raid attendance, bank value history, map markers and profession cooldowns; the logo shows a long sample guild name while sample data is on.
- Every notification can now be hidden right on the notification (eye icon), including one-off ones like "Campfire reported". "All on" in the settings brings them back.
- Sample data for everyone: Settings > Status > "Show sample data" (or `/oa demo`) fills Oasis with example members, events and more so you can try and set things up. It stays on your PC, is never sent to your guild, and one click removes it again.
- The download now contains only the folder `Oasis` (no companion folders, no scripts or programs).
- Sound settings: new entry "Your own sounds and emojis" explains how a guild adds its own (template on the Oasis Discord) and shows what is loaded.
- Map bar below the world map redesigned: quiet text switches in three groups with tooltips, buttons in the same row.
- Member list: badges, add-on dot, menu and invite button no longer overlap on the right.
- Guild leadership can block individual members from sending sound effects.
- Highest crit: crits in groups and dungeons are estimated (a hit right after your own attack, checked against the damage meter) and marked as estimated.
- Talent viewer: trees of other classes are laid out correctly; tooltips fall back to name and rank.

## 0.5.944

- Map bar below the world map now uses two rows so all buttons fit; the upgrade search shows a loading indicator.
- Item comparison: a weapon or armor type your character has not learned yet counts as not usable.
- Member list: wider name column and more space between badges, menu and invite button.
- Oasis no longer opens the world map while you are in combat.
- Automatic combat logging is off by default.
- Translations proofread in all languages.

## 0.5.937

- Map: a settings button below the world map opens all map options. Size and opacity of gathering and guild icons
  can be adjusted, icons are round with a colored ring, and they follow smoothly on the minimap.
- Gathering: optional route that connects the visible nodes of a zone into a loop (line on the world map, arrow with
  distance on the minimap), nodes fade with age, just-harvested nodes turn gray for five minutes, filter by individual
  herb or ore, new node types for fishing spots and locked chests.
- Rare enemies: time since the last sighting next to the skull, sightings also on the minimap.
- Group searches appear at the dungeon entrance on the world map; a click opens the group finder.
- Guild markers and notes on the map (meeting point, caution, note) with an expiry time, or notes just for yourself.
- Optional: trails of guild members, danger zones from recent deaths, dungeon entrances with level range, quest givers
  of dungeon quests, coordinates and an arrow to your waypoint on the minimap, visited vendors, repair, mailboxes and
  flight points.
- Layer helper: shows guild members in your zone by layer and lets you ask for a group invite with one click. The other
  player always confirms the invite; nothing is sent or accepted automatically.
- Guild data such as markers and gathering spots is only shared inside your own guild.

## 0.5.926 - first public release

- Guild hub in one window: dashboard, member list with roles, professions and alts, guild chat with emojis,
  chronicle, polls, guild goals and a guild bank overview.
- Playing together: group finder with fixed slots, quest partners, guild map, rare and gathering spots.
- Raids: events with sign-up, raid planner, ready check with buffs and enchants, boss tactics, loot master,
  soft reserve and lockouts.
- Trade: crafting exchange with orders, wish list and a market page (uses the optional add-on Midas).
- Guild leadership: announcements, permissions per rank, promotion suggestions, history and inactive members.
- Twelve languages: English, German, French, Spanish, Italian, Portuguese, Russian, Polish, Korean, Japanese,
  Simplified and Traditional Chinese.
- Themes, fonts and a personal logo style.
- Optional data export as JSON for your own guild website or Discord bot (off by default).
- Oasis never sends chat messages on its own; it only offers messages for you to send with one click.

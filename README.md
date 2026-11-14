# Rubber Dinghy Rapid Level Guide

A level 10–60 leveling route for **WoW Forever** (Alliance). It tells you where to go next and in
what order, and keeps track of your progress as you play.

## What you get
- **Route tracker.** Replaces Blizzard's objective tracker in the same spot, in Forever's own style.
  - Each zone is a list of numbered stops: who to pick quests up from, where to hand them in, and
    where the mobs are.
  - Stops are ordered nearest-first from where you're standing.
  - It shows live quest progress ("0/10 Thick Yeti Hide").
  - Your other quests stay listed under "Other Quests".
- **Quest item buttons.** Beside the tracker, like Questie's: click to use the item a quest needs.
- **World map.** Numbered stops joined by a route line, with Blizzard's blue objective areas for the
  quests you're on. Click a stop in the tracker to open the map on it.
- **Minimap pins** for the next stops, and an **arrow** pointing at the next stop with the distance.
  It never places map markers.
- **Quest icons like Questie** on the world map: quest givers (!), hand-ins (?), every spawn of the
  mobs your quests need, and patrol paths of NPCs that walk. Shift-click an icon to hide that quest.
- **Rare and named mob alerts.** A rare, rare elite or named quest target nearby gets a raid warning,
  a sound and a skull. A Target button (or your key binding) targets it in one press. WoW doesn't let
  addons target by themselves. Turn on enemy nameplates (V) to spot them from further away.
- **Automatic progress.** It reads your progress from the game and picks the step for your level
  (the zone you're in wins when your level fits more than one). It moves on when you've done a zone
  or levelled past it.
- **Route efficiency.** Hover the tracker's step header to see this step's XP per minute of travel
  against the route average, whether you're on the planned level, and your own XP per hour.
- **Dungeon Journal.** Every 10-60 dungeon on one page of cards (levels, "4/5 quests", a tick when
  they're all done), with search, filters and Hide Dungeons. Each dungeon has:
  - **Quests**: live status, where each one starts, its objective, where to hand it in, the chain
    before it ("step 2 of 4"), XP at your level, and whether it can be shared.
  - **Bosses**: from the game's own Encounter Journal when it has the dungeon, plus the quest items
    each boss drops.
  - **Runs**: your Run Log.
  Open it from the settings window, Shift + click on the minimap button, a Journal button in the
  Dungeons window, or "Open in the Dungeon Journal" on a dungeon step.
- **Run Log.** Every dungeon run is recorded on its own: time, mob XP, kills, bosses, deaths, money
  and time outside. While you're inside, the tracker shows "This run 23:10 - 8,450 XP - bosses 3/5".
  Character Logs in the journal lists every run. The route planner uses your runs to calibrate
  dungeon XP and time.
- **Automation, like Leatrix Plus:** accept and hand in quests, skip gossip, accept summons and
  resurrections, release in battlegrounds, sell junk, repair, faster loot. Each one is a tick box in
  settings. Hold Shift to do it yourself. A job Leatrix Plus still has on is left to Leatrix.

**The route is planned on XP against travel** from Questie's database. A search picks the order of
zone visits that reaches 60 with the least travel between quests: 43 zone visits from Teldrassil at
10 to Silithus at 59, about 4.1 million XP for 14.5 hours of pure travel, and no grinding. Dungeons
are optional: tick one in settings and a side route collects its quests first. Dungeon steps open
our own Dungeon Journal, which shows where each quest starts.

**Alliance only for now.** A Horde route is planned. On Horde characters the addon stays switched
off and changes nothing.

## Install
- **WowUp:** *Get Addons → Install from URL*, then paste this repository's GitHub address. WowUp
  installs updates whenever a new version is released.
- **CurseForge app:** search for *Rubber Dinghy Rapid Level Guide* once the project is live.
- **By hand:** download the zip from the Releases page and unzip it into
  `World of Warcraft\_forever_\Interface\AddOns\`.

Questie is recommended alongside it, since its map icons show every individual mob.

## Settings
Type `/rdr` or left-click the minimap button to open the settings window. It's also listed under
Game Menu > Options > AddOns.

## Commands
- **Changing step:** `/rdr next`, `/rdr prev`, or `/rdr auto` to go back to the automatic step.
- **Showing and hiding:**
  - `/rdr map` turns the map route and minimap pins on and off.
  - `/rdr arrow` turns the arrow on and off.
  - `/rdr tracker` shows or hides the route tracker.
  - `/rdr blizzard` gives Blizzard's objective tracker back.
- **Moving things:** `/rdr unlock` highlights the tracker and the arrow so you can drag them. Then
  `/rdr lock`, or click Lock. Shift + drag on the tracker header works at any time. `/rdr reset`
  puts both back.
- **Minimap button:** `/rdr minimap` shows or hides it.
- **Skipping:** right-click a stop in the tracker to skip it (or one quest at it). `/rdr skip`
  skips stop 1, and `/rdr unskip` brings skipped quests back. Settings can also skip all dungeon
  quests.
- **Dungeons:** `/rdr dungeons` chooses which dungeons are in your route. `/rdr prep sunken` (or
  "Get ready" on a dungeon step) routes every chain and pick-up for that dungeon; `/rdr prep off` ends it. `/rdr dj` opens the Dungeon
  Journal on the current dungeon step.
- **Rare alerts:** `/rdr rares` turns them on or off, and `/rdr raretest` shows a sample. Bind a key
  to the Target button under Key Bindings > Rubber Dinghy.
- **Problems:** `/rdr debug` shows any errors.

`/dinghy` works too.

## Credits and licence
- **Quest data** (quest givers, hand-ins, mob locations, prerequisites) is generated from
  [QuestieDB](https://github.com/Questie/QuestieDB), used under GPLv3. Thanks to the Questie team
  and contributors. This addon is not part of or endorsed by Questie.
- **Map maths and minimap pins:** [HereBeDragons](https://github.com/Nevcairiel/HereBeDragons) by
  Nevcairiel. The **LibStub** and **CallbackHandler** libraries are also used.
- **Dungeon Journal data** (`Data_Dungeons.lua`, built by `tools/gen_dungeons.py`):
  - **From QuestieDB:** dungeon areas, instance IDs, entrances, every quest and its chain, objective
    text, shareable flags and quest XP.
  - **Classic dungeons' level ranges and bosses:** [Wowhead Classic](https://www.wowhead.com/classic).
  - **WoW Forever's new dungeons:** Blizzard's dungeon announcement, as reported by
    [Icy Veins](https://www.icy-veins.com/wow-forever/) and
    [PC Games](https://www.pcgames.de/World-of-Warcraft-Spiel-42971/Tipps/WoW-Forever-Dungeons-Uebersicht-zum-Start-1553853/),
    plus [Warcraft Tavern's Forever dungeon guides](https://www.warcrafttavern.com/forever/guides/dungeons/)
    for entrances, bosses and quest lists.
  - **In game:** the journal reads boss descriptions, portraits and art from the game's own
    Encounter Journal, and level ranges from the group finder.
  - It's our own work. Nothing is taken from the DungeonJournal addon.
- **Licence:** GNU GPL v3 or later (see `LICENSE.md`).

## Rebuilding the route data
`Data.lua` is generated, so don't edit it by hand. With Questie installed in the Forever client, and a
Python that has the `lupa` package for the planner:

```
powershell -File tools/build_route.ps1 -LupaPython <path to python with lupa>
```

This decodes QuestieDB, builds the zone data, makes a first plan (`tools/plan_route.py`), searches
for the fastest order of zones and dungeons (`tools/optimize.py`, `-Minutes` to search longer,
`-Force "Sunken Temple"` for dungeons that must be in it) and writes `Data.lua`. The time model's
numbers (kill time, flights, boats, dungeon runs) are in `tools/routelib.py`. Dungeon run times and
kill XP come from your Run Log (and runs the old DungeonJournal addon logged, as history).
Dungeons come from `Data_Dungeons.lua`. Rebuild it with
`python -I tools/gen_dungeons.py "<WoW>/_forever_" Data_Dungeons.lua` when QuestieDB updates. Zone notes are in `STEPS` in
`tools/gen_route.py`.

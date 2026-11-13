# Rubber Dinghy Rapid Level Guide

A level 40–60 leveling route for **WoW Forever** (Alliance). It tells you where to go next and in
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
- **Rare and named mob alerts.** A rare, rare elite or named quest target nearby gets a raid warning,
  a sound and a skull. A Target button (or your key binding) targets it in one press. WoW doesn't let
  addons target by themselves. Turn on enemy nameplates (V) to spot them from further away.
- **Automatic progress.** It reads your progress from the game, finds the right zone for your level,
  and moves on when you've done a zone.

**The route is planned for the fastest time to 60** from Questie's database and the DungeonJournal
addon. Every quest's objectives, follow-up chains, travel time, dungeon runs (with a good group)
and grinding are timed. A search then picks the order of zones and dungeons that reaches 60 in
the fewest hours played: about 44 in simulation, including Zul'Farrak, Maraudon and Sunken Temple.
Dungeon steps link to the Dungeon Journal for where each quest starts.

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
- **Dungeon levels, quest lists and entrance points** used for planning come from the DungeonJournal
  addon by Exehn, read from the local install at build time. Only the dungeon names and entrance
  points end up in the route. The addon opens the journal (`/dj`) when it's installed, and bundles
  none of its code.
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
kill XP come from the DungeonJournal addon's Run Log when it has one. Zone notes are in `STEPS` in
`tools/gen_route.py`.

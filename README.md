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
- **Automatic progress.** It reads your progress from the game, finds the right zone for your level,
  and moves on when you've done a zone.

The route: Riverglades, Arathi Highlands, Badlands, Stranglethorn Vale, Shen'dralas, Feralas, Tanaris,
The Hinterlands, Blasted Lands, Searing Gorge, Burning Steppes, Un'Goro Crater, Felwood, Azshara,
Western and Eastern Plaguelands, Silithus, Winterspring and Mount Hyjal.

**Alliance only for now.** A Horde route is planned. On Horde characters the addon stays switched
off and changes nothing.

## Install
- **WowUp:** *Get Addons → Install from URL*, then paste this repository's GitHub address. WowUp
  installs updates whenever a new version is released.
- **CurseForge app:** search for *Rubber Dinghy Rapid Level Guide* once the project is live.
- **By hand:** download the zip from the Releases page and unzip it into
  `World of Warcraft\_forever_\Interface\AddOns\`.

Questie is recommended alongside it, since its map icons show every individual mob.

## Commands
- **Changing step:** `/rdr next`, `/rdr prev`, or `/rdr auto` to go back to the automatic step.
- **Showing and hiding:**
  - `/rdr map` turns the map route and minimap pins on and off.
  - `/rdr arrow` turns the arrow on and off.
  - `/rdr tracker` shows or hides the route tracker.
  - `/rdr blizzard` gives Blizzard's objective tracker back.
- **Moving things:** Shift + drag the tracker header at any time. `/rdr unlock` lets you drag the
  tracker header and the arrow. `/rdr reset` puts them back.
- **Problems:** `/rdr debug` shows any errors.

`/dinghy` works too.

## Credits and licence
- **Quest data** (quest givers, hand-ins, mob locations, prerequisites) is generated from
  [QuestieDB](https://github.com/Questie/QuestieDB), used under GPLv3. Thanks to the Questie team
  and contributors. This addon is not part of or endorsed by Questie.
- **Map maths and minimap pins:** [HereBeDragons](https://github.com/Nevcairiel/HereBeDragons) by
  Nevcairiel. The **LibStub** and **CallbackHandler** libraries are also used.
- **Licence:** GNU GPL v3 or later (see `LICENSE.md`).

## Rebuilding the route data
`Data.lua` is generated, so don't edit it by hand. With Questie installed in the Forever client:

```
python -I tools/decode.py "C:\Program Files (x86)\World of Warcraft\_forever_" tools/data.json
python -I tools/gen_route.py tools "C:\Program Files (x86)\World of Warcraft\_forever_" Data.lua
```

The zone order and level ranges are in `STEPS` at the top of `tools/gen_route.py`.

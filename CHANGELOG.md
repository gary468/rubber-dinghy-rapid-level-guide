# Changelog

## v1.0.10
- **Skipping a dungeon asks first** ("Skip Sunken Temple?") when you click "click to skip it" on a
  dungeon step.
- **Choose dungeons** is wider, so long names no longer run into the next column.

## v1.0.9
- **Settings window in two columns**, about half as tall, so it fits on screen.
- **Choose dungeons** opens beside the settings window (or on the left of the screen), not on top of
  your UI. Drag it and it opens there next time.

## v1.0.8
- **Choose your dungeons and the route updates.** Every 40-60 dungeon is in the route at the level
  where it costs least time.
  - The planner's picks (Zul'Farrak, Maraudon, Sunken Temple) start ticked. The rest are optional,
    and each shows how much time it adds to your time to 60.
  - Tick or untick them in **Choose dungeons** (settings, or `/rdr dungeons`), or click "Doing X -
    click to skip it" on a dungeon step. Unticked dungeons and their quests drop out of the route
    at once.
- **Dungeon steps list every quest for the dungeon, like the Dungeon Journal:**
  - done, hand in, progress (e.g. 0/1), where to get it, what it still needs (e.g. "needs: The
    Ancient Egg"), or the level it opens at;
  - the journal's own pick-up text, required chains and notes (in tooltips) are used when the
    DungeonJournal addon is loaded.
## v1.0.7
- **Heading to a dungeon:** while you carry a dungeon's quests, that dungeon's step stays current
  (with their progress), wherever you are on the way, e.g. flying into Blasted Lands for the Temple
  of Atal'Hakkar. Before, the zone you passed through or an older zone took over.
- **Flying into a zone** the route visits around your level makes it the current step, even before
  you've picked anything up there.

## v1.0.6
- **The route is now planned for the fastest time to 60**, in hours played, with travel counted
  only as the time it takes.
  - The time model covers everything: each quest's objectives (kills, loot, objects), kill XP while
    questing, riding between quest spots, flights and boats, and dungeon runs. Grinding is used
    where nothing beats it.
  - A search tries thousands of zone and dungeon orders and keeps whatever saves time.
  - Result in simulation: about 44 hours played from 40 to 60, against about 47 for v1.0.5 on the
    same clock.
- **Quest chains and follow-ups:**
  - A quest is worth its own XP plus the chain it opens. Cheap breadcrumbs into good chains are
    done, and dead ends that grinding beats are skipped.
  - Quests handed out in one zone but done in another are picked up on the way. They show as
    **"Get for later"** stops.
- **Dungeons are part of the route** (assuming a good group): Zul'Farrak, Maraudon and Sunken
  Temple.
  - Dungeon times and kill XP are calibrated from the DungeonJournal addon's Run Log. Your logged
    runs count as below average.
  - A dungeon step shows the entrance, every quest for that dungeon (the ones you hold or can get),
    and an **"Open in the Dungeon Journal"** link (also `/rdr dj`).
  - Inside the instance, the route switches to that dungeon's step.
  - Dungeon quests are picked up in the zones you pass through beforehand.
  - "Skip dungeon quests" in settings drops the dungeon steps.
- **Grind steps** where nothing beats killing mobs (one short one at 59 in this plan).

## v1.0.5
- **A faster route, planned from Questie's database.**
  - Every Alliance quest at 40–60 was scored by XP against travel. The route is the fastest order
    of zone visits: 48 visits, and you come back to a zone when its next quests open up.
  - In simulation it reaches 60 on quests alone, with no grinding. That's about 8 hours of travel
    against about 18 for the old route, which left 28% of the XP to grinding.
  - Return visits are labelled, e.g. "Tanaris (return visit)".
- A visit stays current for one level past its planned range, so a little extra XP doesn't skip it.
- **Rare and named mob alerts.**
  - When a rare, a rare elite or a named quest target ("... slain: 0/1") shows up, you get a raid
    warning, a sound and a skull on the mob.
  - A **Target** button also appears: click it, or bind a key under Key Bindings > Rubber Dinghy. WoW
    doesn't let addons target a mob on their own, so it takes that one press.
  - Spotted on enemy nameplates (turn them on with V), mouseover and your target. Minimap rare
    markers are used too where the client has them.
  - Settings: on/off, skull, sound and a test alert. Also `/rdr rares` and `/rdr raretest`. Shift +
    drag moves the button.
- **Note when updating:** quit and restart WoW (not just `/reload`).

## v1.0.4
- **Click a numbered stop on the world map** to show its kill area and highlight it, like clicking a
  Blizzard quest marker. Click it again to turn the highlight off. It works even with quest areas
  switched off.
- **Thinner quest-area outline.**

## v1.0.3
- **Every quest covered:** all 1,570 Alliance quests at 40–60 in Questie's database are in.
  - 1,164 are part of the route.
  - The rest (item-started, no known giver, dungeon quests elsewhere) are routed as soon as you
    accept them.
- **New steps and zones:**
  - Zephras Isle (Forever's reworked Swamp of Sorrows) and Desolace (with Ratchet's Barrens quests).
  - Hillsbrad and Alterac are now part of Arathi, Thousand Needles part of Tanaris, and Moonglade
    part of Felwood.
- **Quests from capitals** (lead-ins, breadcrumbs) join the step they send you to, as
  "pick up in Ironforge" stops.
- **Skipping:**
  - Right-click a stop in the tracker to skip it, or one quest at it. The route re-plans at once.
  - `/rdr skip` skips stop 1, and `/rdr unskip` (or "Un-skip all" in settings) brings them back.
  - New option: skip dungeon quests.
- **Quest areas:** much subtler. Only the stop you're heading to, with a lighter fill and a thin edge.
- **New icon:** a rubber duck.
- **Note when updating:** quit and restart WoW (not just `/reload`) the first time, so it picks up
  the new image files.

## v1.0.2
- **Stays in your zone:** the zone you're standing in stays the current step while you have its
  quests in your log, even after a level-up. Before, handing in quests could jump you to the next zone.
- **Follow-up quests:** quests from a zone's NPCs, at any level up to 60, belong to that zone's step.
  This includes repeatable quests (e.g. Zorbin's), which show once you've accepted them.
- **Hand-ins first:** finished quests in your zone come right after what you're doing, before new
  quests.
- **Map:** Blizzard's own quest markers are hidden while the route is on, so the numbered stops are
  your quest markers. Quest areas are drawn in the route's gold, for the next 2 stops only (or every
  stop, or off).
- **Settings window:** `/rdr` or the minimap button. It has the step, tracker, map, arrow and minimap
  options, tracker and arrow size, quest-area strength, move mode and reset. It's also listed in Game
  Menu > Options > AddOns.
- **Minimap button:** left-click opens settings, right-click shows or hides the tracker, and the
  tooltip shows your step.
- **Move mode:** `/rdr unlock` highlights the tracker and the arrow so you can drag them (the arrow
  shows even with no target). Click Lock or type `/rdr lock` when done.
- **Tooltips:** hover a quest giver, hand-in NPC or a mob your quests need to see its stop number and
  your progress.

## v1.0.1
- **Fix:** the tracker no longer starts half off the left edge of the screen. It now opens where
  Blizzard's tracker actually sits.
- **Moving the tracker:** Shift + drag its header at any time (or `/rdr unlock`, then drag). Hover the
  header for a reminder. `/rdr reset` puts it back.
- **Route order:** it finishes what you've started first. The quest you're making progress on comes
  first, then quests whose mobs are around you, then other started quests, then new ones. Distance
  to a mob area is measured to its nearest spawn.

## v1.0.0
First public version.
- **Route:** a 40–60 Alliance route across 19 zones, built from QuestieDB.
- **Stops:** each zone becomes a list of stops ordered nearest-first, with quest givers, hand-ins and
  mob areas.
- **Route tracker:** replaces Blizzard's objective tracker, styled like Forever's. It shows live
  quest progress and lists your other quests separately.
- **Quest item buttons** beside the tracker.
- **World map:** a route line, numbered stops and Blizzard's quest objective areas.
- **Minimap pins** for the next stops, and an arrow to the next stop with the distance.

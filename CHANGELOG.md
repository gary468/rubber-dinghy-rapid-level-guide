# Changelog

## v1.0.17 - fixes from a full review
- **Fixes:**
  - The tracker failed to start after a /reload while it was unlocked for moving.
  - No more freezes while riding on a get-ready route: it re-plans when you change zone or your quests
    change, not every time you move.
  - A get-ready route no longer says "ready" when it simply can't reach anything yet. It stays and
    shows why ("Not yet: ... opens at level 52"), and ends only when you hold everything you can get.
  - Get-ready respects your quest log: when it's full, it says so instead of getting stuck on "Get: X".
  - Get-ready no longer sends you to a lead-in quest meant for another race or class.
  - The world map shows a get-ready route's stops in whichever zone you open, not just one.
  - Dire Maul, Stratholme and Scarlet Monastery: the step for the wing you're actually doing.
  - After a get-ready route finishes, the route really takes you to the dungeon.
  - A step no longer holds you with nothing to do when you're a level or two short.
  - Rare alerts are off inside dungeons (no re-skulling bosses over the tank's marks).
  - The step buttons (< A >) now leave a get-ready route.
  - Hiding the route tracker brings Blizzard's tracker back.
  - The old "skip dungeon quests" setting is cleared (dungeons are opt-in now).
  - No more error on looting for Horde characters.
- **UI:**
  - The Dungeons window opens beside the settings window, not over it.
  - The step text in settings no longer runs into the buttons.
  - The tracker is never taller than the screen.
  - Tooltips and the skip menu follow the route when it changes.
  - Reset positions also resets the rare Target button.
  - Quest item buttons move to the tracker's right when it's docked at the left edge.
## v1.0.16
- **The route is planned on XP against location only**: every quest that isn't grey, in the order that
  needs the least riding, flying and sailing. Quest and kill times aren't used. In theory: 568 quests,
  27 zone visits, about 8 hours of pure travel from 40 to 60, and no grinding.
- **No dungeons unless you choose them.** Every dungeon is optional (Dungeons window). When you choose
  one, a **side route** comes first: it picks up every quest for that dungeon (max XP from the run).
  It ends by itself when you have them all, and the route then takes you to the dungeon.
- Tracker: a quest's progress shows once, at its first stop (no more "0/10" twice). No "(dungeon)" tag
  on get-ready routes.
## v1.0.15
- **Learns quest counts and flight times as you play** (settings > Route, on by default). It notes
  each quest's real objective counts (Questie's data has none, so the planner guessed) and how long
  flights take. The next route rebuild uses them. Only facts about the game, never your pace: the
  route stays planned for efficient play. Stored on your PC only.

## v1.0.14
- **Re-routes from where you are.** As you move (a few % of the map, or into another zone), the route
  re-plans from your spot.
- **Flights:** when you take a flight, the route plans from where it lands (e.g. flying to Ratchet: the
  get-ready route starts on Kalimdor at once).
- **Fix:** the get-ready route misjudged distances inside your own zone and sent you to other zones
  (e.g. Azshara) first.

## v1.0.13
- **No commands needed:** the Dungeons window (settings > "Dungeons & get ready...", or the
  minimap button > settings) has a **Get ready** button next to every dungeon. Click it for the
  get-ready route, and click again ("Stop") to go back to the leveling route.

## v1.0.12
- **Get ready: skipping works.** Right-click > Skip on a chain quest (e.g. Muigin and Larion) takes it and the
  rest of its chain out of the get-ready route. The dungeon quest behind it shows under "Not yet: you
  skipped ...". Un-skip brings it back.

## v1.0.11
- **Get ready for a dungeon.** Click "Get ready for Sunken Temple" on a dungeon step, or type
  `/rdr prep sunken`. The route becomes the quickest way, from where you are, to walk every quest
  chain and pick up every quest that dungeon has for you (class quests too).
  - Chains are followed from start to finish, across zones and continents.
  - Many orderings are tried and the one with the least travel wins. A flight costs more the further
    it goes, and a boat costs the most.
  - It re-plans as you go and shows what it can't reach yet ("opens at level 52"). When everything
    is picked up, it points you to the entrance. "Back to the route" ends it.
- **Map:** only the route's own quests swap Blizzard's quest markers for numbered stops. Every other
  quest keeps its Blizzard marker and area, and so does the quest you've selected in your quest
  log, even if it's on the route.
- **Other Quests:** click one in the tracker to open the map on it (where it's done or handed in).
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

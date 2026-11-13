# Changelog

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

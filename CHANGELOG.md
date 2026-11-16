# Changelog

## v1.0.42
- **Fixed: after updating, the route could jump to a dungeon** (Dire Maul: East at level 56). The
  route remembered your place by step number, and the new route has different numbers. It now
  remembers the step itself, and never lands on a dungeon you haven't added.

## v1.0.41
- **Updated for Questie's latest Forever data** (21 new quests, 81 changed) and re-planned: about
  87 hours from level 14 to 60, with fewer zone visits.
- **Mount Hyjal is one visit.** Questie had Ketharas in Moonglade; he's in Hyjal (73, 82), so
  there's no more trip to Moonglade and back.
- **Tighter walking order inside every zone** (Hyjal's path is now shorter than going nearest-first).
- Into The Maw of Madness no longer makes a step named after the Kalimdor continent map.

## v1.0.40
- **Stop order fixes.** Named mobs and other single-spot objectives keep their quest's planned
  place (v1.0.39 could push them behind a later hand-in). Stops the plan has for a later visit to
  the zone - a hand-in, an objective you're carrying - now slot in where they add the least travel
  instead of trailing at the end. No more Chillwind, back to Andorhal, back to Mulgris.

## v1.0.39
- **Quests with several single-spot objectives** (All Along the Watchtowers' towers) get one stop
  per spot, nearest first, and each drops off as you do it, even when the quest log words it
  differently from the object ("Tower Two marked" for Andorhal Tower Two).

## v1.0.38
- **Quests that aren't on the route** are still routed in their zone, marked "(not on the route)",
  and picking one up (by hand or by the auto-accept) says so in chat. New setting: "Only accept
  quests on the route" (off by default).
- **Escorts are never auto-accepted**, so handing in the quest before one can't start it for your
  whole group by accident. Accept it yourself when everyone's ready.

## v1.0.37
Restart the game after updating (there's a new file).
- **One straight route.** The route keeps your place and only moves forward: when a step is done
  or skipped, when you've out-levelled it, or when you've already gone ahead to the next zone.
  Leftover quests in earlier zones, or standing in an old zone on another continent, no longer pull
  it back. Skip ahead with > and press A to carry on from there.
- **Behind the route? Catch-up options.** When you're below a step's planned level, the tracker
  offers the best way back on track from anywhere: quests at your level, grinding camps, and
  dungeons that fit (click a dungeon to add it to your route).
- **Challenge of the Desert Wolf** (Tanaris) is a shaman quest and no longer shows for other
  classes.

## v1.0.36
- **The route now starts at level 1, in your race's own starting zone.**
  - Humans: Elwynn Forest and Stormwind, level 1 to about 15.
  - Night elves: Teldrassil and Darnassus, level 1 to about 14.
  - Dwarves and gnomes: Dun Morogh's quests in level order, with who gives each. Forever's quest
    data has no map positions there yet; the addon now learns them as you talk to quest givers, so
    Dun Morogh gets a full route later.
  - Then everyone joins the shared route at about level 14 (re-planned: about 89 hours to 60). Other
    races' starting zones never show up.
- **Fixed the "blocked from an action only available to the Blizzard UI" pop-up.** The dungeon run
  log no longer uses the combat log (Forever forbids it), and the map no longer hides or refreshes
  Blizzard's own map pins.

## v1.0.35
- **Fixed "Tooltip failed ... UnitGUID ... Secret values" errors in chat.** Forever sometimes hands
  addons a hidden unit; the tooltip and the rare-mob check now skip it instead of erroring.

## v1.0.34
- **More of Forever's own quests have a place on the map.** Where the quest data had nothing, the
  route now uses ForeverChanges' objectives, descriptions and quest maps: Slithering Looters goes to
  Lady Sesspira in the Ruins of Eldarath, Reclaiming Ravencrest to the Spitelash on Azshara's
  southern tip.
- **Right-clicking a "Hunt" or "Look for" hint asks first**, with the same skip menu as a stop.
- **A step you picked with < or > goes back to automatic** once it's finished and the route has
  moved past it.

## v1.0.33
- **No more getting stuck on a finished zone.** When everything at your level is done, the route
  moves on to the next zone and tells you to "Grind to level N" until its quests open.
- **"Hunt" and "Look for" hints:** click to see the spot on the world map; right-click to skip the
  quest.
- **Quests our data has no objectives for** (Reclaiming Ravencrest) are listed with their objectives
  instead of sending you to the hand-in early.
- **Azshara:** Berdun Cliffbrew's Winter Frontier Fishery (fishing) and Deadliest Catch (not in the
  game) are off the route.

## v1.0.32
- **Planned for Forever's 40-quest log** (not Classic's 20). About 90 hours played to 60.
- **A quest whose objectives are far apart gets a stop for each place**, slotted in where the route
  passes. Expedition Salvation's Crate of Foodstuffs at the eastern camp is now its own stop.
- **Tracker objective lines fit on one line.** No "drops from", and nothing extra when the item already
  names its mob (Un'Goro Gorilla Pelt). The full text is in the line's tooltip.
- **Riverglades:** Proof of Profit's Cubic Draconia is in Gelinda Coppergleam's cave (30,69). Not My
  Circus (10 Briny Seafood Stew, cooked only) is off the route and not auto-accepted.

## v1.0.31
- **Kill areas drop the objectives you've finished.** A quest with two kinds of mob (Beware of
  Pterrordax) used to keep pointing at both; once one count is done, the stop's name, arrow, gold
  dots and minimap area show only the mobs you still need.
- **Stop pins land on a real spawn**, never the empty middle of an area whose mobs live in two
  separate places.

## v1.0.30
Restart the game after updating (there's a new file).
- **The route stops changing as you move.** Each step's stops follow one planned order; where you
  stand never re-sorts them. Only a finished stop drops off.
- **Finish the zone you're in.** In the zone of a step that's due for your level (up to 2 levels
  past it) with quests left, the route finishes it; anywhere else it follows your level.
- **Real minimum levels** for Forever's own quests (read from ForeverChanges), so the route no longer
  sends you to quests you can't take yet. Re-planned on them: about 90 hours played to 60.
- **Hand-ins:**
  - every finished quest handed in in the step's zone is a stop, planned or not, and it's handed in
    when the route passes that NPC, not first;
  - passing through another zone with a hand-in for a finished quest shows "Hand in here".
- **Quests that start from an item** (A Mangled Journal, Message in a Bottle):
  - in a zone where you can get one, the tracker says so: "Hunt" a named mob, "Look for" something on
    the ground, or "Watch for" a random drop;
  - mob tooltips say "Can drop ... - starts ...";
  - once the item is in your bags: "Starts a quest: ... - right-click it in your bags".
- **Pick-ups lying all over the zone** (Crystals of Power) are "As you go" instead of a stop in the
  far corner; they become a stop once they're all that's left.
- **Map:**
  - the current stop's kill area is bright and its nearby mobs are gold dots; other stops' areas are
    faint, and other quests' dots small and faint;
  - stop 1 points at the part of its kill area nearest you;
  - Blizzard's quest areas no longer show on the minimap.
- **Quest targets:** a quest that names its target (Gor'tesh's head) goes to that mob, not others
  that happen to drop the item.
- **Auto-accept** leaves out Chasing A-Me 01 part 2 (it needs a Mithril Casing nothing in Un'Goro
  drops) and says why in chat.
- **Rare pop-up:** hides once clicked; no raid-warning text.

## v1.0.29
- **The Dungeon Journal is no longer part of this addon.** v1.0.28 included it by mistake. The
  leveling route still knows every dungeon, its quests and your runs (the tracker shows a run's time,
  XP and bosses), and links to a journal only when one is installed.
- **Tracker, cleaner:**
  - a faint dark backdrop with a thin gold edge, and a plain header band;
  - one line per stop (short name on the left, coordinates or zone on the right);
  - only unfinished objectives are shown;
  - the zone note and counts are in the header's tooltip;
  - nothing wraps.
- **Map and minimap:** quest-mob spawn dots are grey with a dark edge, so they no longer look like a
  party member.
## v1.0.28
- **A new route, planned action by action on real time.** Every pick-up, objective and hand-in is
  placed in order using Forever's real geography (zone positions and flight masters read from the
  game), flights, boats and the tram, kill and collect times, quest chains, levels and the 20-quest
  log. Pick-ups and hand-ins are fitted in where you pass anyway (46 pick-ups and 48 hand-ins on the
  way), and quests slower than grinding are left out. On the same clock the route reaches 60 in about
  87 hours played against 120 for the old route as the addon played it (28% faster), with the same
  number of quests. Zones are kept together (53 zone visits).
- **One set route by level.** The step follows your level alone - never where you stand or what's
  left in your log - and stops within a step follow the planned order instead of re-sorting as you
  move. Grinding or a dungeon run that levels you past steps moves the route ahead.
- Steps that grind a level or two to unlock their quests say so in their note.
- Rare alerts: no automatic skull (Forever forbids addons from setting raid markers), just the
  pop-up you click to target.
- **Our own Dungeon Journal and Run Log**, replacing the DungeonJournal addon: every dungeon's
  quests, bosses (portraits and a 3D model), runs and logs, in the game's own art and styling. The
  route's dungeon steps link to it, and the route planner uses its data.
- **Maps:**
  - the route shows on every map, including continent and world views;
  - the minimap shows the route line, numbered stops, kill areas and nearby quest icons, with
    Blizzard's own minimap quest markers hidden;
  - hovering a mob area or spawn dot shows the quest and your progress, and "!" and "?" icons are
    outlined.
- **Tooltips:** mobs, quest givers and hand-in NPCs show the quest and your progress, matched by NPC
  ID because Forever hides unit names. Objectives say what drops each item.
- **Forever data:** spawn points from Wowhead for Forever-only quest objects (Fledgling Rescue, Treaty
  Obligations and others). Quests still without a location show their own objective text, and
  learning records where they progress. Swamp of Sorrows visits are no longer labelled Zephras Isle.
  Removed innkeeper breadcrumbs are dropped, and Sisters In Duty waits for Eyes of the Sentinels.
- **Tracker:** keeps its top-right corner in place as the list grows.
## v1.0.27
- **Automation, like Leatrix Plus**, so you can switch Leatrix's off. Settings > Automation has a tick
  box for each job, all on by default:
  - accept and hand in quests, and pick them from a quest giver's list (a choice of rewards is left
    to you; never a quest you skipped or one that costs gold or reagents);
  - skip gossip: vendors, flight masters, trainers, bankers and stable masters open straight away,
    any other NPC with Alt held;
  - accept summons (after 10 seconds) and resurrections, release in battlegrounds;
  - sell junk (and say what it fetched), repair (guild funds first), faster auto loot.
  - Hold Shift at an NPC or vendor to do it yourself.
  - A job Leatrix Plus still has on is left to Leatrix, and the settings show "(Leatrix Plus is doing
    it)". Turn it off there (/ltp > Automation) and /reload.
  - Each quest in a giver's list is picked at most once per visit, so a quest the game won't give you
    can't bounce the window back and forth.
- **The step follows your level first, where you are second.** Every step your level fits is a
  candidate, and the nearest wins: the zone you're in, then your continent. Levelling past a zone
  (more than 2 levels over) moves you on even with its quests still in your log.
- **How efficient is the route?** Hover the tracker's step header to see:
  - this step's XP for its travel time, and how that compares with the route average;
  - whether you're on the planned level, or ahead or behind;
  - the whole route's totals;
  - your own XP per hour.
  The settings window shows the same in one line under the step.
- Tracker: the step header is one line ("Westfall (16-19)  4/76"), there's more space between stops,
  and dungeon steps no longer repeat "(dungeon)" on every line.
## v1.0.26
- **The route now runs 10-60:** Teldrassil and Zephras Isle, then Westfall, Loch Modan, Duskwood,
  Redridge, Darkshore, Ashenvale and Wetlands into the 30s and on to 60. In theory that's 1,020
  quests in 43 zone visits, about 14.5 hours of pure travel, and no grinding. Every dungeon from 10
  to 60 is optional (Deadmines, Wailing Caverns, Shadowfang Keep and the rest), each with its Get
  ready button and Dungeon Journal link.
- **Quest icons like Questie** on the world map, for everything that isn't a route stop:
  - "!" for quest givers (faded when the quest is low level for you), "?" for hand-ins;
  - a dot at every spawn of the mobs your quests need;
  - dashed patrol paths for NPCs and quest mobs that walk (gold for the route's own).
  - Hover for the quest and what to do; shift-click to hide a quest's icons. Settings > Map has the
    switch and "Show hidden quests again".
- **Rare alerts fixed for Forever:** mobs are recognised by the NPC ID in their GUID (QuestieDB's 363
  rares and 186 named quest targets), so they work even when the client hides a mob's name and type
  from addons - the same way RareScanner does it. Forever's rare markers (vignettes) are read too.
- **Dungeon step, clearer:** each quest once, in the order you'd do it ("Hand in at the Altar of
  Hakkar: ..." last), "Get ready first" only while there's something left to pick up, "Skip this
  dungeon", and the quests you're not doing folded into "+ 3 not this run" (click to see why).
- **Get-ready route:** it ends once you hold every quest you can get. Hand-ins and drops inside the run,
  and chains you skipped, no longer hold it open. "Not yet" folds into "+ N not yet". It also stops
  when the dungeon is unticked.
## v1.0.25
- **The route now starts at level 30** (30-60). The 30s go Stormwind > Duskwood > Wetlands > Desolace >
  Ashenvale > Zephras Isle > Stranglethorn Vale > Desolace, then into the 40s as before. In theory that's
  764 quests in 35 zone visits, about 11 hours of pure travel, and no grinding.
- The 30-40 dungeons are optional in the Dungeons window too: Blackfathom Deeps, the Stockade,
  Gnomeregan, Razorfen Kraul and Downs, Scarlet Monastery's wings, the Drowned City, City of Dalaran
  and Excavation Site: Wetlands. Each has its Dungeon Journal link.
## v1.0.24
- **Map colours mean one thing each:** gold = the route (numbered stops, line, areas). Green = a quest you
  selected in your quest log that isn't on the route (its area and Blizzard's marker). Grey dots =
  other quests in your log. Blizzard's own green areas are no longer drawn for route quests.

## v1.0.23
- **Route vs other quests, clearly apart:**
  - Only the route's own quests (or the get-ready quests on a dungeon side route) are numbered stops.
    Quests you pick up that aren't in the plan never join the route.
  - On the map, other quests in your log are small grey dots: no number, no line, no area. Hover for
    "Not on the route"; click to see Blizzard's marker for it. Settings > Map can turn them off.
  - The tracker says "Other Quests - not on the route".
## v1.0.22
- **Map:** Blizzard's markers for quests that aren't on your route are hidden again. Only the quest you
  select in your quest log (or click under Other Quests) keeps its Blizzard marker and area.

## v1.0.21
- **Removed auto accept / hand-in.** It could leave you stuck in place when talking to NPCs. Use
  Leatrix Plus or Questie for quest automation.

## v1.0.20
- **Quest XP on Blizzard's own XP bar:** a light blue stretch shows the XP waiting in finished quests.
  Hover the bar for the numbers, XP per hour and time to level. The tracker's XP bar is now optional
  (off by default, settings > Tracker).

## v1.0.19
- **Fix: freezes on a get-ready route.** Each re-plan (on every hand-in, pick-up or quest item looted)
  made over 120,000 quest-log lookups, freezing the game for seconds. That's why handing in and moving
  stopped working. Now it's under 100 lookups, with a hard 30 ms limit that keeps the best route found
  so far.

## v1.0.18
- **Accepts and hands in route quests automatically** (settings > Route, on by default).
  - Only quests on your route (or your get-ready side route), never ones you skipped. Hands in quests
    the guide knows, and leaves a choice of rewards to you.
  - Picks the right quest from a quest giver's chat menu or list. Hold **Shift** at the NPC to do it
    yourself.
  - Stays off (and says so once) if Questie or Leatrix Plus already accept quests for you.
- **XP bar in the tracker** (settings > Tracker): your XP, a lighter part for the XP waiting in finished
  quests ("+18% to hand in"), XP per hour over the last 30 minutes and time to your next level - or
  "hand-ins level you up!" when they will.
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

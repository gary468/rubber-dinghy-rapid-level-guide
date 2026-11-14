-- Rubber Dinghy - core: quest status, route building, events and slash commands.
-- Progress, race and class are read live from the game. Each step's quests become numbered stops
-- (quest givers, hand-ins, mob areas) ordered nearest-first from where you stand. The tracker
-- (Tracker.lua), map overlay (Map.lua) and arrow (Arrow.lua) all draw from ns.route.
local ADDON, ns = ...

ns.MERGE = 1.5            -- stops closer than this (map %) are merged into one
ns.inits, ns.listeners = {}, {}

local band = bit and bit.band or function(a, b)
  local r, p = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return r
end

---------------------------------------------------------------------------
-- Safe calls: a UI module failing must never break the others. First error per module is printed.
---------------------------------------------------------------------------
ns.errors = {}
function ns.Print(msg) print("|cff66ccffRubber Dinghy|r " .. msg) end
function ns.Safe(name, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    if not ns.errors[name] then ns.Print(name .. " failed: " .. tostring(err) .. " (/rdr debug)") end
    ns.errors[name] = tostring(err)
  end
  return ok
end

---------------------------------------------------------------------------
-- Game API wrappers (same fallbacks Questie uses on this client)
---------------------------------------------------------------------------
local function IsDone(id)
  if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
    return C_QuestLog.IsQuestFlaggedCompleted(id) and true or false
  elseif IsQuestFlaggedCompleted then
    return IsQuestFlaggedCompleted(id) and true or false
  end
  return false
end

local function LogIndex(id)
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
    return C_QuestLog.GetLogIndexForQuestID(id) or 0
  elseif GetQuestLogIndexByID then
    return GetQuestLogIndexByID(id) or 0
  end
  return 0
end
ns.LogIndex = LogIndex

local function IsReady(id, index)
  if C_QuestLog and C_QuestLog.IsComplete then
    return C_QuestLog.IsComplete(id) and true or false
  end
  if GetQuestLogTitle and index and index > 0 then
    local isComplete = select(6, GetQuestLogTitle(index))
    return isComplete == 1 or isComplete == true
  end
  return false
end

--- Objective lines for a quest in the log: { {text=, done=} }.
function ns.Objectives(id)
  local out = {}
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
      if o.text and o.text ~= "" then out[#out + 1] = { text = o.text, done = o.finished and true or false } end
    end
    return out
  end
  local index = LogIndex(id)
  if index > 0 and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    for j = 1, GetNumQuestLeaderBoards(index) or 0 do
      local text, _, finished = GetQuestLogLeaderBoard(j, index)
      if text and text ~= "" then out[#out + 1] = { text = text, done = finished and true or false } end
    end
  end
  return out
end

--- Every quest in the log: { {id=, title=, level=} }.
function ns.QuestLog()
  local out = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, (C_QuestLog.GetNumQuestLogEntries()) or 0 do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID and info.questID > 0 then
        out[#out + 1] = { id = info.questID, title = info.title, level = info.level }
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, (GetNumQuestLogEntries()) or 0 do
      local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
      if not isHeader and questID and questID > 0 then
        out[#out + 1] = { id = questID, title = title, level = level }
      end
    end
  end
  return out
end

--- How far into a quest you are: fulfilled, required (summed over its objectives).
function ns.Progress(id)
  local have, need = 0, 0
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    for _, o in ipairs(C_QuestLog.GetQuestObjectives(id) or {}) do
      if o.numRequired and o.numRequired > 0 then
        have, need = have + math.min(o.numFulfilled or 0, o.numRequired), need + o.numRequired
      elseif o.text then
        local a, b = o.text:match("(%d+)%s*/%s*(%d+)")
        if a then have, need = have + tonumber(a), need + tonumber(b)
        else need = need + 1; if o.finished then have = have + 1 end end
      end
    end
    return have, need
  end
  for _, o in ipairs(ns.Objectives(id)) do
    local a, b = o.text:match("(%d+)%s*/%s*(%d+)")
    if a then have, need = have + tonumber(a), need + tonumber(b)
    else need = need + 1; if o.done then have = have + 1 end end
  end
  return have, need
end

local mapNames = {}
function ns.MapName(uiMap)
  if not uiMap or uiMap == 0 then return nil end
  if mapNames[uiMap] == nil then
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(uiMap)
    mapNames[uiMap] = info and info.name or false
  end
  return mapNames[uiMap] or nil
end

function ns.PlayerPos()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local m = C_Map.GetBestMapForUnit("player")
  if not m then return nil end
  local p = C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local x, y = p:GetXY()
  if not x or (x == 0 and y == 0) then return nil end
  return m, x * 100, y * 100
end

--- Where to route from: where your flight is going while you're on one, else where you are.
--- Returns map, x, y (0-100), onTaxi.
function ns.HerePos()
  if ns.taxiDest and UnitOnTaxi and UnitOnTaxi("player") then
    return ns.taxiDest.map, ns.taxiDest.x, ns.taxiDest.y, true
  end
  local m, x, y = ns.PlayerPos()
  return m, x, y, false
end

-- Taking a flight: remember where it lands, so the route plans from there straight away.
local function OnTakeTaxi(slot)
  local taxiMap = GetTaxiMapID and GetTaxiMapID()
  if not (taxiMap and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
  local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, taxiMap)
  if not ok or type(nodes) ~= "table" then return end
  for _, node in ipairs(nodes) do
    if node.slotIndex == slot and node.position then
      local cx, cy = node.position.x, node.position.y
      if not cx and node.position.GetXY then cx, cy = node.position:GetXY() end
      local info = cx and C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(taxiMap, cx, cy)
      local zone = info and info.mapID
      local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
      if zone and HBD and HBD.TranslateZoneCoordinates then
        local zx, zy = HBD:TranslateZoneCoordinates(cx, cy, taxiMap, zone)
        if zx then
          ns.taxiDest = { map = zone, x = zx * 100, y = zy * 100, name = node.name }
          ns.Print(("flying to %s: the route now plans from there."):format(node.name or ns.MapName(zone) or "?"))
          ns.Queue()
        end
      end
      return
    end
  end
end

local raceBit, classBit
local function ReadPlayerBits()
  local _, _, raceID = UnitRace("player")
  local _, _, classID = UnitClass("player")
  raceBit = raceID and 2 ^ (raceID - 1) or nil
  classBit = classID and 2 ^ (classID - 1) or nil
end

-- Texture/font helpers: use Forever's own art when the client has it, else a plain fallback.
function ns.HasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end
function ns.SetAtlasOr(tex, atlases, fallback, ...)
  for _, a in ipairs(atlases) do
    if ns.HasAtlas(a) and tex.SetAtlas then tex:SetAtlas(a); return a end
  end
  if fallback then tex:SetTexture(fallback); if ... then tex:SetVertexColor(...) end end
  return nil
end
function ns.Font(names)
  for _, n in ipairs(names) do if _G[n] then return n end end
  return "GameFontNormal"
end

---------------------------------------------------------------------------
-- Quest status
---------------------------------------------------------------------------
-- READY = in log and complete, LOG = in log, OPEN = can pick up now, SOON = one or two levels short,
-- LOCKED = an earlier quest is missing, DONE, LATER = too far above you, NA = not for your race/class.
-- SKIP = you chose to skip it (or it's a dungeon quest and dungeon quests are skipped).
local READY, LOG, OPEN, SOON, LOCKED, DONE, LATER, NA, SKIP = 1, 2, 3, 4, 5, 6, 7, 8, 9
ns.S = { READY = READY, LOG = LOG, OPEN = OPEN, SOON = SOON, LOCKED = LOCKED, DONE = DONE, LATER = LATER, NA = NA, SKIP = SKIP }
ns.IsDone, ns.LogIndex, ns.IsReady = IsDone, LogIndex, IsReady

-- Quests that are never suggested but are routed once they're in your log.
ns.trackSet = {}
for _, id in ipairs(ns.track or {}) do ns.trackSet[id] = true end

-- Which route dungeon each dungeon quest belongs to, and whether you've chosen to skip it.
-- The planner's dungeons are on by default; every other 10-60 dungeon is in the data as an optional
-- step at its best point in the route, off until you tick it.
ns.questDungeon, ns.dungeonDefault = {}, {}
for _, step in ipairs(ns.steps or {}) do
  if step.dungeon then
    ns.dungeonDefault[step.dungeon] = not step.optional
    for _, id in ipairs(step.quests) do ns.questDungeon[id] = step.dungeon end
  end
end
function ns.DungeonOn(name)
  local db = ns.db
  if not db or not name then return true end
  if db.skipDungeons then return false end
  local pick = db.dungeons and db.dungeons[name]
  if pick ~= nil then return pick end
  return ns.dungeonDefault[name] ~= false
end
function ns.DungeonOff(name) return not ns.DungeonOn(name) end
function ns.SetDungeon(name, on)
  ns.db.dungeons = ns.db.dungeons or {}
  ns.db.dungeons[name] = on and true or false
  if on and ns.db.skipDungeons then ns.db.skipDungeons = nil end
  ns.Print(name .. (on and " is in your route now." or " is out of your route: its quests and its step drop out."))
  -- Choosing a dungeon: first a side route to pick up every quest for it (max XP from the run).
  if on and ns.StartPrep and ns.db.prep ~= name then ns.StartPrep(name); return end
  if not on and ns.db.prep == name and ns.StopPrep then ns.StopPrep(); return end
  ns.db.step = nil
  ns.Recompute()
  if ns.Options and ns.Options.Refresh then ns.Safe("Options", ns.Options.Refresh) end
  if ns.Options and ns.Options.RefreshDungeons then ns.Safe("Options", ns.Options.RefreshDungeons) end
end

--- The dungeon journal addon's entry for a quest (pickup text, note, required chain), if it's loaded.
function ns.JournalQuest(id, dungeon)
  local fdj = _G.ForeverDungeonJournal_NS
  if not fdj or not fdj.DB then return nil end
  local out = {}
  local d = dungeon and fdj.DB[dungeon]
  if d and type(d.quests) == "table" then
    for _, q in ipairs(d.quests) do
      if q.id == id then out.pickup, out.note, out.objective = q.pickup, q.note, q.objective; break end
    end
  end
  out.chain = fdj.QUEST_PREREQ_CHAINS and fdj.QUEST_PREREQ_CHAINS[id]
  out.map = fdj.QUEST_START_MAPS and fdj.QUEST_START_MAPS[id]
  return out
end

local function ForMe(q)
  if q.ra and raceBit and band(q.ra, raceBit) == 0 then return false end
  if q.cl and classBit and band(q.cl, classBit) == 0 then return false end
  return true
end

ns.ForMe = function(q) return ForMe(q) end   -- race/class only (cheap)

local function PrereqsMet(q)
  if q.pg then
    for _, p in ipairs(q.pg) do
      if p > 0 and not IsDone(p) then return false end
    end
  end
  if q.ps then
    local any = false
    for _, p in ipairs(q.ps) do
      if IsDone(p) then any = true; break end
    end
    if not any then return false end
  end
  if q.ex then
    for _, p in ipairs(q.ex) do
      if IsDone(p) or LogIndex(p) > 0 then return false end
    end
  end
  return true
end

local function Status(id, level)
  local q = ns.quests[id]
  if not q or not ForMe(q) then return NA end
  local index = LogIndex(id)
  -- Skipped: drops out of the route even if it's in your log (it stays under Other Quests).
  local skip = ns.db and ns.db.skip
  if skip and skip[id] then return SKIP end
  if q.d and index == 0 and ns.db and (ns.db.skipDungeons or (ns.questDungeon[id] and ns.DungeonOff(ns.questDungeon[id]))) then
    return SKIP
  end
  -- Repeatable quests: only part of the route while they're in your log.
  if q.rep then
    if index > 0 then return IsReady(id, index) and READY or LOG end
    return NA
  end
  if IsDone(id) then return DONE end
  if index > 0 then return IsReady(id, index) and READY or LOG end
  if not PrereqsMet(q) then return LOCKED end
  if level < (q.r or 0) then
    return (q.r - level <= 2) and SOON or LATER
  end
  if q.l > level + 4 then return LATER end
  return OPEN
end

ns.Status = function(id, level) return Status(id, level) end

local function ScanStep(step, level)
  local rows, counts = {}, { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  for _, id in ipairs(step.quests) do
    local s = Status(id, level)
    counts[s] = counts[s] + 1
    if s <= SOON then rows[#rows + 1] = { id = id, s = s, q = ns.quests[id] } end
  end
  -- Dungeon quests to pick up here for a later run: only their giver is a stop here. Once accepted
  -- they belong to the dungeon's step, so they never hold you in this zone.
  for _, id in ipairs(step.pick or {}) do
    local s = Status(id, level)
    if s == OPEN or s == SOON then
      counts[s] = counts[s] + 1
      rows[#rows + 1] = { id = id, s = s, q = ns.quests[id], pick = true }
    end
  end
  return rows, counts
end

--- The dungeon you're inside, as the route names it (the journal addon maps the game's instance
--- names, e.g. "The Temple of Atal'Hakkar" -> "Sunken Temple"), or nil.
-- Instance map IDs that name exactly one route dungeon (Classic IDs). Multi-wing places (Dire Maul,
-- Stratholme, Scarlet Monastery) share an ID or a name, so they're matched by wing below.
local INSTANCE_DUNGEON = {
  [70] = "Uldaman", [209] = "Zul'Farrak", [349] = "Maraudon", [109] = "Sunken Temple",
  [230] = "Blackrock Depths", [229] = "Lower Blackrock Spire", [289] = "Scholomance",
}
local INSTANCE_NAME = { ["The Temple of Atal'Hakkar"] = "Sunken Temple", ["Temple of Atal'Hakkar"] = "Sunken Temple" }
function ns.CurrentDungeon()
  if not GetInstanceInfo then return nil end
  local name, kind, _, _, _, _, _, id = GetInstanceInfo()
  if kind ~= "party" or not name then return nil end
  if id and INSTANCE_DUNGEON[id] then return INSTANCE_DUNGEON[id] end
  if INSTANCE_NAME[name] then return INSTANCE_NAME[name] end
  local fdj = _G.ForeverDungeonJournal_NS
  if fdj and fdj.DungeonFromInstanceName then
    local ok, mapped = pcall(fdj.DungeonFromInstanceName, name)
    if ok and mapped then return mapped end
  end
  return name
end

-- The step for the dungeon you're in. An exact name wins; for a multi-wing place ("Dire Maul" ->
-- "Dire Maul: East/West/North") the wing you chose and carry quests for, else the first chosen wing.
local function DungeonStepFor(dn, level)
  local exact, wings = nil, {}
  for i, step in ipairs(ns.steps) do
    if step.dungeon == dn then exact = i end
    if step.dungeon and step.dungeon:find(dn .. ":", 1, true) == 1 then wings[#wings + 1] = i end
  end
  if exact then return exact end
  local first
  for _, i in ipairs(wings) do
    local step = ns.steps[i]
    if ns.DungeonOn(step.dungeon) then
      local _, c = ScanStep(step, level)
      if c[READY] + c[LOG] > 0 then return i end
      first = first or i
    end
  end
  return first or wings[1]
end

-- Continent of a map (cached): how "near" two steps are when your level fits both.
local contCache = {}
function ns.Continent(m)
  if not m then return nil end
  local c = contCache[m]
  if c == nil then
    c = false
    local id, guard = m, 0
    while id and id > 0 and guard < 8 and C_Map and C_Map.GetMapInfo do
      local info = C_Map.GetMapInfo(id)
      if not info then break end
      if info.mapType == 2 then c = id; break end   -- Enum.UIMapType.Continent
      id = info.parentMapID; guard = guard + 1
    end
    contCache[m] = c
  end
  return c or nil
end

-- Current step - your LEVEL first, where you are second:
--   1. inside a dungeon: its step;
--   2. just finished getting ready for a dungeon: that dungeon, while you carry its quests;
--   3. every step your level fits (its range, one level either side; up to 2 levels past it while
--      you have its quests on the go; 5 for a chosen dungeon) is a candidate. Of those: a dungeon
--      run that's done with hand-ins left; the zone you're in while you have its quests on the go;
--      a chosen dungeon whose quests you carry; the zone you're in; then your continent (quests on
--      the go first); then the route's own order;
--   4. nothing fits (you're behind or ahead of the plan): the first step with work left you haven't
--      out-levelled; if you're a little under-levelled for everything ahead, the next to open.
-- Levelling up therefore moves you on even while you stand in a zone with quests left, and the
-- zone you're in only wins among steps your level fits.
local STAY_LEVELS = 2
local DUNGEON_STAY = 5   -- a chosen dungeon's quests (and hand-ins after the run) hold longer
local function AutoStep(level)
  local dn = ns.CurrentDungeon()
  if dn then
    local i = DungeonStepFor(dn, level)
    if i then return i end
  end
  local go = ns.db and ns.db.goDungeon
  if go then
    for i, step in ipairs(ns.steps) do
      if step.dungeon == go then
        local _, c = ScanStep(step, level)
        if c[READY] + c[LOG] > 0 and ns.DungeonOn(go) then return i end
      end
    end
    ns.db.goDungeon = nil   -- done (or dropped): back to the normal route
  end
  local pm = ns.HerePos()
  local pc = pm and ns.Continent(pm)
  local best, bestScore, grind
  for i, step in ipairs(ns.steps) do
    -- cheap level filter first: only the handful of steps around your level get scanned
    if level >= step.from - 1 and level <= step.to + (step.dungeon and DUNGEON_STAY or STAY_LEVELS)
      and not (step.dungeon and ns.DungeonOff(step.dungeon)) then
      if step.grind then
        if not grind and level >= step.from and level < step.to then grind = i end
      else
        local _, c = ScanStep(step, level)
        local going = c[READY] + c[LOG] > 0
        -- a chosen dungeon is a candidate while you carry its quests (picking them up is the zones' job)
        local fits = going or (not step.dungeon and c[OPEN] > 0 and level <= step.to + 1)
        if fits then
          local here = pm and step.map == pm
          local score
          if step.dungeon and c[READY] > 0 and c[LOG] == 0 then
            score = 7   -- run done, only hand-ins left: finish it before anything else
          elseif here and going then score = 6
          elseif step.dungeon then score = 5          -- carrying its quests: the run comes first
          elseif here then score = 4
          else
            local near = pc and ns.Continent(step.map) == pc
            score = (near and 2 or 0) + (going and 1 or 0)
          end
          if not best or score > bestScore then best, bestScore = i, score end
        end
      end
    end
  end
  if best then return best end
  if grind then return grind end
  local soon
  for i, step in ipairs(ns.steps) do
    if step.grind and level >= step.from and level < step.to then return i end
    if step.dungeon and ns.DungeonOff(step.dungeon) then
      -- not a chosen dungeon: never the automatic step
    elseif level <= step.to + STAY_LEVELS then
      local _, c = ScanStep(step, level)
      if c[READY] + c[LOG] > 0 then return i end
      if level <= step.to + 1 and c[OPEN] > 0 then return i end
      -- quests only a level or two away don't hold a step on their own (no stops to show)...
      if not soon and level <= step.to + 1 and c[SOON] > 0 then soon = i end
    end
  end
  -- ...unless there's nothing open anywhere ahead: then the step that opens next
  return soon or #ns.steps
end

-- How efficient the route is, from the plan the search settled on (tools/plan.json): XP per minute
-- of travel. Zone visits: travel time between stops (quest time isn't modelled - XP vs distance).
-- Dungeons: the run itself. Optional dungeons are left out of the totals.
local routeStats
function ns.RouteStats()
  if routeStats then return routeStats end
  local xp, secs, n, lo, hi = 0, 0, 0, 99, 0
  for _, s in ipairs(ns.steps) do
    if not s.optional and s.xp then
      xp, secs, n = xp + s.xp, secs + (s.secs or 0), n + 1
      lo, hi = math.min(lo, s.from), math.max(hi, s.to)
    end
  end
  routeStats = { xp = xp, secs = secs, n = n, from = lo, to = hi, perMin = secs > 0 and xp / secs * 60 or 0 }
  return routeStats
end

local function Short(n)
  if n >= 1000000 then return ("%.1fM"):format(n / 1000000) end
  if n >= 10000 then return ("%dk"):format(math.floor(n / 1000 + 0.5)) end
  if n >= 1000 then return ("%.1fk"):format(n / 1000) end
  return tostring(math.floor(n + 0.5))
end
local function Mins(s)
  if s >= 3600 then return ("%dh %02dm"):format(math.floor(s / 3600), math.floor(s % 3600 / 60)) end
  return ("%d min"):format(math.max(1, math.floor(s / 60 + 0.5)))
end

--- One line for the settings window: "This step 2.4k XP/min (110% of average) - on plan".
function ns.EfficiencyShort(step, level)
  local rs, parts = ns.RouteStats(), {}
  if step and step.xp and step.secs and step.secs > 0 and rs.perMin > 0 then
    local per = step.xp / step.secs * 60
    local ratio = per / rs.perMin
    local col = ratio >= 1 and "33ff33" or ratio >= 0.6 and "ffd100" or "ff6040"
    parts[#parts + 1] = ("This step |cff%s%s XP/min|r (%d%% of the route average)"):format(col, Short(per), math.floor(ratio * 100 + 0.5))
  end
  if step and level then
    local d = level < step.from and (level - step.from) or level > step.to and (level - step.to) or 0
    parts[#parts + 1] = d == 0 and "|cff33ff33on plan|r" or d > 0 and ("|cff8fd6ff%d ahead of plan|r"):format(d)
      or ("|cffff6040%d behind plan|r"):format(-d)
  end
  return table.concat(parts, "  -  ")
end

--- Lines for the step's tooltip: how good this visit is, whether you're on the planned level, the
--- whole route, and your own pace.
function ns.EfficiencyText(step, level)
  local rs, out = ns.RouteStats(), {}
  if step and step.xp and step.secs and step.secs > 0 then
    local per = step.xp / step.secs * 60
    local ratio = rs.perMin > 0 and per / rs.perMin or 1
    local col = ratio >= 1 and "33ff33" or ratio >= 0.6 and "ffd100" or "ff6040"
    local what = step.dungeon and "a run of about " or "about "
    out[#out + 1] = ("|cffffd100This step:|r ~%s XP for %s%s %s"):format(Short(step.xp), what, Mins(step.secs),
      step.dungeon and "" or "of travel")
    out[#out + 1] = ("  |cff%s%s XP per minute|r - %d%% of the route average (%s)"):format(col, Short(per),
      math.floor(ratio * 100 + 0.5), Short(rs.perMin))
  end
  if step and level then
    local d = level < step.from and (level - step.from) or level > step.to and (level - step.to) or 0
    local where = d == 0 and "|cff33ff33on plan|r" or d > 0 and ("|cff8fd6ff%d level%s ahead|r"):format(d, d == 1 and "" or "s")
      or ("|cffff6040%d level%s behind|r"):format(-d, d == -1 and "" or "s")
    out[#out + 1] = ("|cffffd100Planned level here:|r %s. You're %d: %s"):format(
      step.from == step.to and step.from or (step.from .. "-" .. step.to), level, where)
  end
  if rs.n > 0 then
    out[#out + 1] = ("|cffffd100Whole route %d-%d:|r %d steps, ~%s XP for %s of travel"):format(
      rs.from, rs.to, rs.n, Short(rs.xp), Mins(rs.secs))
  end
  local rate = ns.XP and ns.XP.Rate and ns.XP.Rate()
  if rate then out[#out + 1] = ("|cffffd100Your pace:|r %s XP per hour played"):format(Short(rate)) end
  return table.concat(out, "\n")
end
---------------------------------------------------------------------------
-- Routing: rows -> stops -> nearest-first order
---------------------------------------------------------------------------
-- A stop is a place: {map, x, y, r?, name, area, actions = {{kind, row}}, away}
local curStep
local function Target(r)
  local q = r.q
  -- On a dungeon step, a hand-in at an altar/idol inside (Questie puts it at the entrance) is part of
  -- the run: shown at the entrance as "hand in inside".
  if r.s == READY and q.d and curStep and curStep.ent then
    local t, e = q.t, curStep.ent
    if not t or not t[3] or (t[2] == e[2] and math.abs(t[3] - e[3]) < 6 and math.abs(t[4] - e[4]) < 6) then
      return e, "dungeonturn"
    end
  end
  if r.s == READY then return q.t, "turn" end
  -- Dungeon step: quests you're doing are done inside, so the stop is the dungeon's entrance.
  if r.s == LOG and q.d and curStep and curStep.ent then return curStep.ent, "dungeon" end
  if r.s == LOG then
    if q.o then return q.o, "do" end
    -- No mobs/objects to find (talk-to and delivery quests): head for the hand-in NPC.
    if q.t and not q.ob then return q.t, "go" end
    -- Has objectives but the database has no location for them: listed without a stop.
    return nil, "do"
  end
  if r.s == OPEN then return q.g, "get" end
  return nil, "soon"
end

local function BuildStops(rows, stepMap, current)
  local stops, loose = {}, {}
  for _, r in ipairs(rows) do
    local loc, kind = Target(r)
    if loc and loc[3] and loc[4] and loc[3] >= 0 and loc[2] and loc[2] > 0 then
      local found
      for _, s in ipairs(stops) do
        if s.map == loc[2] and math.abs(s.x - loc[3]) < ns.MERGE and math.abs(s.y - loc[4]) < ns.MERGE
          and (s.area == (kind == "do")) then
          found = s; break
        end
      end
      if not found then
        -- cx/cy/r = the mob area's centre and size (for the map circle); pts = where its spawns
        -- actually are (flat x,y list). x/y later move to the spawn nearest the route.
        found = { map = loc[2], x = loc[3], y = loc[4], cx = loc[3], cy = loc[4], r = loc[5], name = loc[1],
                  area = (kind == "do"), actions = {}, away = (loc[2] ~= stepMap), pts = nil }
        if loc[6] then found.pts = {}; for k = 1, #loc[6] do found.pts[k] = loc[6][k] end end
        stops[#stops + 1] = found
      else
        if kind == "do" and loc[1] and not found.name:find(loc[1], 1, true) then
          found.name = found.name .. ", " .. loc[1]
        end
        if loc[6] then
          found.pts = found.pts or {}
          for k = 1, #loc[6] do found.pts[#found.pts + 1] = loc[6][k] end
        end
      end
      found.actions[#found.actions + 1] = { kind = kind, row = r }
    else
      loose[#loose + 1] = { kind = kind, row = r }
    end
  end

  -- Within a stop: hand-ins inside a dungeon come after the quests you do in there.
  for _, s in ipairs(stops) do
    if #s.actions > 1 then
      local rank = function(a) return a.kind == "dungeonturn" and 2 or 1 end
      for i = 2, #s.actions do        -- stable insertion sort (keeps the original order otherwise)
        local a, j = s.actions[i], i - 1
        while j >= 1 and rank(s.actions[j]) > rank(a) do s.actions[j + 1] = s.actions[j]; j = j - 1 end
        s.actions[j + 1] = a
      end
    end
  end
  -- Start from the player if they're in this zone, else from the busiest stop (the hub).
  local here, away = {}, {}
  for _, s in ipairs(stops) do
    if s.away then away[#away + 1] = s else here[#here + 1] = s end
  end
  local pm, px, py = ns.HerePos()
  local cx, cy
  if pm == stepMap then
    cx, cy = px, py
  else
    local hub
    for _, s in ipairs(here) do
      if not hub or #s.actions > #hub.actions then hub = s end
    end
    if hub then cx, cy = hub.x, hub.y end
  end
  -- Distance to a stop: to its nearest spawn for mob areas, else to the NPC. Returns the point too.
  local function Dist(s, x, y)
    local bx, by = s.cx or s.x, s.cy or s.y
    if not x then return 0, bx, by end
    local bd = (bx - x) ^ 2 + (by - y) ^ 2
    if s.pts then
      for k = 1, #s.pts - 1, 2 do
        local u, v = s.pts[k], s.pts[k + 1]
        local d = (u - x) ^ 2 + (v - y) ^ 2
        if d < bd then bd, bx, by = d, u, v end
      end
    end
    return bd, bx, by
  end

  -- Finish what you've started before anything new; distance only decides within a tier.
  --   tier 0: the quest you're making progress on right now (its count went up last)
  --   tier 1: a quest whose mobs are around you (within ~5% of one of its spawns)
  --   tier 2: finished quests to hand in here - they give XP and often unlock follow-ups
  --   tier 3: other quests you've already started (some progress, not done)
  --   tier 4: everything else (pick-ups, untouched quests), nearest first
  for _, s in ipairs(here) do
    s.tier = 4
    for _, a in ipairs(s.actions) do
      if a.kind ~= "get" and a.row.started and s.tier > 3 then s.tier = 3 end
      if a.kind == "turn" and s.tier > 2 then s.tier = 2 end
      if a.kind ~= "get" and current and a.row.id == current then s.tier = 0 end
    end
    if s.area and pm == stepMap and s.tier > 1 and not s.done then
      local d = Dist(s, px, py)
      if d <= 25 then s.tier = 1 end
    end
  end
  local ordered = {}
  while #here > 0 do
    local bi, bt, bd, bx, by = 1, math.huge, math.huge, nil, nil
    for i, s in ipairs(here) do
      local d, px2, py2 = Dist(s, cx, cy)
      if s.area and s.tier == 4 then d = d + 4 end -- same distance: pick-ups before mob areas
      if s.tier < bt or (s.tier == bt and d < bd) then bi, bt, bd, bx, by = i, s.tier, d, px2, py2 end
    end
    local s = table.remove(here, bi)
    if s.area and bx then s.x, s.y = bx, by end -- pin, arrow and line go to the nearest part
    ordered[#ordered + 1] = s
    cx, cy = s.x, s.y
  end
  table.sort(away, function(a, b) return a.map < b.map end)
  for _, s in ipairs(away) do ordered[#ordered + 1] = s end
  for i, s in ipairs(ordered) do s.index = i end
  return ordered, loose, (pm == stepMap) and { px, py } or nil
end

---------------------------------------------------------------------------
-- Text shared by the tracker, map tooltips and arrow
---------------------------------------------------------------------------
ns.C = { TURN = "|cff33ff33", DO = "|cffffd100", GET = "|cffffffff", SOON = "|cff999999", DIM = "|cff999999" }

function ns.ActionText(a)
  local q = a.row.q
  -- "(dungeon)" marks dungeon quests on the leveling route; on a get-ready route they all are
  -- "(dungeon)" marks dungeon quests on a zone step; on a dungeon step or get-ready route they all are
  local nm = q.n .. ((q.d and not a.row.prep and not (curStep and curStep.dungeon)) and " (dungeon)" or "")
  local C = ns.C
  if a.kind == "turn" then return C.TURN .. "Hand in: " .. nm .. "|r" end
  if a.kind == "get" and a.row.pick then return C.GET .. "Get for later: " .. nm .. "|r" end
  if a.kind == "get" then return C.GET .. "Get: " .. nm .. "|r" end
  if a.kind == "do" then return C.DO .. nm .. "|r" end
  if a.kind == "dungeon" then return C.DO .. q.n .. "|r" end
  if a.kind == "dungeonturn" then
    return C.TURN .. "Hand in" .. ((q.t and q.t[1]) and (" at the " .. q.t[1]) or " inside") .. ": " .. q.n .. "|r"
  end
  if a.kind == "go" then return C.DO .. "Finish: " .. nm .. "|r" end
  return C.SOON .. nm .. " (level " .. (q.r or "?") .. ")|r"
end

function ns.StopTitle(s)
  if s.area then return "Kill/loot: " .. (s.name or "?") end
  return s.name or "?"
end

--- Open the dungeon journal addon (DungeonJournal, /dj) on a dungeon, if it's installed.
function ns.OpenJournal(step)
  step = step or (ns.route and ns.route.step)
  local dj = step and step.dj
  local open = SlashCmdList and SlashCmdList.FOREVERDUNGEONJOURNAL
  if open then
    open(dj or "")
    return true
  end
  ns.Print("install the DungeonJournal addon to see where every dungeon quest starts (/dj).")
  return false
end

function ns.StopTooltip(owner, s, anchor)
  GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
  GameTooltip:AddLine(s.index .. ". " .. ns.StopTitle(s))
  GameTooltip:AddLine(("%s %.1f, %.1f"):format(ns.MapName(s.map) or "?", s.x, s.y), 0.8, 0.8, 0.8)
  for _, a in ipairs(s.actions) do
    GameTooltip:AddLine(ns.ActionText(a) .. " |cff999999[" .. a.row.q.l .. "]|r", 1, 1, 1)
  end
  -- other quests at the same spot (their map icon would sit under this stop's number)
  if s.alsoHere and #s.alsoHere > 0 then
    GameTooltip:AddLine("Also here, not on the route:", 0.6, 0.6, 0.6)
    for _, e in ipairs(s.alsoHere) do
      local q = ns.quests[e.id]
      if q then
        GameTooltip:AddLine(("%s %s |cff999999[%s]|r"):format(e.kind == "turnin" and "Hand in:" or "Pick up:", q.n, q.l or "?"), 0.8, 0.8, 0.8)
      end
    end
  end
  GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Route state
---------------------------------------------------------------------------
ns.route = { stops = {}, loose = {}, counts = { 0, 0, 0, 0, 0, 0, 0, 0 } }

function ns.Recompute()
  local db = ns.db
  if not db or ns.disabled then return end   -- not logged in yet, or a Horde character
  local level = UnitLevel("player") or 1
  -- "Get ready for <dungeon>": the side route replaces the step until it's done or you leave it.
  if db.prep and not ns.DungeonOn(db.prep) then db.prep = nil end   -- that dungeon is no longer chosen
  if db.prep and ns.Prep then
    local ok, r = pcall(ns.Prep.Route, db.prep, level)
    if ok and r and r.allReady then
      -- every quest you can get for it is in your log: done - on to the dungeon
      ns.Print(("ready for %s: you have every quest you can get for it. The route now takes you there."):format(db.prep))
      db.goDungeon, db.prep, db.step = db.prep, nil, nil
      ok, r = true, nil
      if ns.Options and ns.Options.RefreshDungeons then ns.Safe("Options", ns.Options.RefreshDungeons) end
    elseif not ok or not r then
      -- broken or unknown dungeon (e.g. renamed in an update): leave the side route
      ns.errors.Prep = ok and ("no dungeon called " .. tostring(db.prep)) or tostring(r)
      db.prep = nil
      ok, r = true, nil
    end
    if ok and r then
      ns.route = r
      for name, fn in pairs(ns.listeners) do ns.Safe(name, fn, ns.route) end
      return
    end
  end
  local idx = db.step or AutoStep(level)
  if idx < 1 then idx = 1 elseif idx > #ns.steps then idx = #ns.steps end
  local step = ns.steps[idx]
  local rows, counts = ScanStep(step, level)
  -- Only the step's own quests are the route. Anything else in your log (picked up along the way,
  -- not part of the plan) stays under Other Quests and shows as a grey dot on the map - it never
  -- becomes a numbered stop.
  local logList = ns.QuestLog()
  -- Which quests are started, and which one you're working on right now (its count just went up).
  -- The "current" quest is remembered across reloads and stays first until it's done.
  ns.lastProg = ns.lastProg or {}
  for _, r in ipairs(rows) do
    if r.s == LOG then
      local have, need = ns.Progress(r.id)
      r.started = have > 0 and have < need
      local before = ns.lastProg[r.id]
      if before and have > before then db.currentQuest = r.id end
      ns.lastProg[r.id] = have
    end
  end
  if db.currentQuest then
    local still = false
    for _, r in ipairs(rows) do if r.id == db.currentQuest and r.s == LOG then still = true end end
    if not still then db.currentQuest = nil end -- finished, handed in or dropped
  end
  curStep = step
  local stops, loose, start = BuildStops(rows, step.map, db.currentQuest)
  -- Quests in the log that this step's route doesn't cover (other zones etc.): the tracker still
  -- shows them, since it replaces Blizzard's.
  local inRoute = {}
  for _, r in ipairs(rows) do inRoute[r.id] = true end
  local other = {}
  for _, e in ipairs(logList) do
    if not inRoute[e.id] then other[#other + 1] = e end
  end
  local pm = ns.PlayerPos()
  ns.route = { level = level, idx = idx, step = step, counts = counts, stops = stops, loose = loose,
               start = start, other = other, manual = db.step ~= nil, inZone = (pm == step.map) }
  for name, fn in pairs(ns.listeners) do ns.Safe(name, fn, ns.route) end
end

local pending = false
function ns.Queue()
  if pending then return end
  pending = true
  C_Timer.After(0.3, function() pending = false; ns.Recompute() end)
end

function ns.Step(delta)
  ns.db.prep = nil    -- changing step leaves a get-ready side route
  local cur = ns.db.step or AutoStep(UnitLevel("player") or 1)
  local n = cur + delta
  if n < 1 then n = 1 elseif n > #ns.steps then n = #ns.steps end
  ns.db.step = n
  ns.Recompute()
end

function ns.Auto()
  ns.db.step, ns.db.prep = nil, nil
  ns.Recompute()
end

--- Skipping: skipped quests drop out of the route (and AutoStep) at once; the route re-plans.
function ns.Skip(ids, label)
  ns.db.skip = ns.db.skip or {}
  local n = 0
  for _, id in ipairs(ids) do
    if not ns.db.skip[id] then ns.db.skip[id] = true; n = n + 1 end
  end
  ns.Print(("skipped %s. The route has re-planned. (/rdr unskip brings skipped quests back)"):format(
    label or (n .. (n == 1 and " quest" or " quests"))))
  ns.Recompute()
end
function ns.SkipCount()
  local n = 0
  for _ in pairs(ns.db.skip or {}) do n = n + 1 end
  return n
end
function ns.UnskipAll()
  local n = ns.SkipCount()
  ns.db.skip = nil
  ns.Print(("%d skipped %s back in the route."):format(n, n == 1 and "quest is" or "quests are"))
  ns.Recompute()
end
--- The quests a stop is for (everything except plain pick-ups still counts; pick-ups are skippable too).
function ns.StopQuestIDs(s)
  local ids = {}
  for _, a in ipairs(s.actions) do ids[#ids + 1] = a.row.id end
  return ids
end

--- Move mode: the tracker and the arrow get a highlighted "drag to move" overlay; the arrow shows even
--- with nothing to point at. /rdr unlock (or the settings window) turns it on, /rdr lock turns it off.
function ns.SetMoveMode(on)
  ns.db.unlocked = on and true or nil
  if ns.Tracker and ns.Tracker.SetMoveMode then ns.Safe("Tracker", ns.Tracker.SetMoveMode, on) end
  if ns.Arrow and ns.Arrow.SetUnlocked then ns.Safe("Arrow", ns.Arrow.SetUnlocked, on) end
  if ns.Options and ns.Options.Refresh then ns.Safe("Options", ns.Options.Refresh) end
  ns.Print(on and "Move mode: drag the tracker and the arrow where you want them, then /rdr lock (or the Lock button)."
    or "Positions locked.")
end

---------------------------------------------------------------------------
-- Events + slash command
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("QUEST_REMOVED")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" then
    -- Version 1 is an Alliance route. On Horde characters do nothing at all (Blizzard's tracker stays).
    if UnitFactionGroup and UnitFactionGroup("player") == "Horde" then
      ns.disabled = true
      ns.Print("the route is Alliance-only for now - a Horde route is planned. Nothing changes on this character.")
      return
    end
    RubberDinghyDB = RubberDinghyDB or {}
    ns.db = RubberDinghyDB
    -- Older versions: "skip dungeon quests" / "skip all dungeons". Dungeons are opt-in now, so the
    -- old switch just goes (it would otherwise turn dungeons back on when one is ticked).
    if ns.db.skipDungeons and not ns.db.dungeonsV2 then ns.db.skipDungeons, ns.db.dungeons = nil, {} end
    ns.db.dungeonsV2 = true
    ReadPlayerBits()
    if hooksecurefunc and TakeTaxiNode then hooksecurefunc("TakeTaxiNode", function(slot) ns.Safe("Taxi", OnTakeTaxi, slot) end) end
    for name, fn in pairs(ns.inits) do ns.Safe(name, fn) end
    ns.Queue()
    return
  end
  if not ns.db then return end
  if event == "PLAYER_LEVEL_UP" then
    local newLevel = tonumber(arg1)
    if newLevel and newLevel % 2 == 0 then ns.Print(("Level %d - new spells to train."):format(newLevel)) end
  end
  if event == "QUEST_TURNED_IN" then
    C_Timer.After(1.5, ns.Queue) -- the completed flag can lag the event
  end
  if event == "PLAYER_CONTROL_GAINED" and not (UnitOnTaxi and UnitOnTaxi("player")) then
    ns.taxiDest = nil   -- landed
  end
  ns.Queue()
end)
pcall(ev.RegisterEvent, ev, "PLAYER_CONTROL_GAINED")

-- Re-route as you move: when you've gone a few % of the map, or into another zone, re-plan.
local lastM, lastX, lastY, tick = nil, nil, nil, 0
local mover = CreateFrame("Frame")
mover:SetScript("OnUpdate", function(_, dt)
  tick = tick + dt
  if tick < 2 then return end
  tick = 0
  if not ns.db or ns.disabled then return end
  local m, x, y = ns.HerePos()
  if not m then return end
  if m ~= lastM or not lastX or ((x - lastX) ^ 2 + (y - lastY) ^ 2) > 9 then   -- moved 3% of the map
    lastM, lastX, lastY = m, x, y
    ns.Queue()
  end
end)

ns.commands = {}
SLASH_RUBBERDINGHY1 = "/rdr"
SLASH_RUBBERDINGHY2 = "/dinghy"
SlashCmdList.RUBBERDINGHY = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if ns.disabled then ns.Print("Alliance-only for now - a Horde route is planned."); return end
  if not ns.db then return end
  local cmd = ns.commands[msg]
  if cmd then cmd(); return end
  if msg == "" and ns.Options then ns.Options.Toggle()
  elseif msg == "next" then ns.Step(1)
  elseif msg == "prev" then ns.Step(-1)
  elseif msg == "skip" then
    local s = ns.route.stops and ns.route.stops[1]
    if s then ns.Skip(ns.StopQuestIDs(s), "stop 1 (" .. ns.StopTitle(s) .. ")") else ns.Print("nothing to skip.") end
  elseif msg == "unskip" then ns.UnskipAll()
  elseif msg == "auto" or msg == "route" then ns.Auto()
  elseif msg == "dj" or msg == "journal" or msg == "dungeon" then ns.OpenJournal()
  elseif msg:match("^prep") or msg:match("^ready") then
    if ns.Prep then ns.Prep.Command(msg:match("^%a+%s*(.*)$")) end
  elseif msg == "debug" then
    local any = false
    for name, err in pairs(ns.errors) do ns.Print(name .. ": " .. err); any = true end
    if not any then ns.Print("no errors recorded") end
    if ns.commands.mapdebug then ns.commands.mapdebug() end
  else
    ns.Print("/rdr - settings window | /rdr unlock - move the tracker and arrow, /rdr lock when done | "
      .. "/rdr reset - default places and sizes | /rdr next, prev, auto - change step | "
      .. "/rdr skip - skip stop 1 (or right-click a stop) | /rdr unskip - bring skipped quests back | "
      .. "/rdr map, arrow, tracker, minimap - show/hide | /rdr blizzard - Blizzard's tracker back | "
      .. "/rdr rares - rare alerts on/off, /rdr raretest - sample alert | /rdr debug")
  end
end

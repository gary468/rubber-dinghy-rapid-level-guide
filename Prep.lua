-- Rubber Dinghy - "Get ready for <dungeon>": the most efficient route to walk every quest chain and
-- pick up every quest a dungeon has for you, from where you are now.
--
-- For each of the dungeon's quests you can take (class quests too), the chain behind it is walked
-- back through Questie's prerequisites (and the DungeonJournal's chains). The whole job is then
-- simulated as one route of tasks - pick up, do, hand in - where doing a task opens the next quest
-- of its chain. Many orderings are tried (nearest next task, favouring zones where several tasks
-- wait, with small variations) and the one with the least travel wins: a flight costs about 60 map-%
-- of riding, a boat about 160. It's re-planned when your quests change; once every quest is picked
-- up, it sends you to the entrance.
local ADDON, ns = ...
local P = {}
ns.Prep = P

local HOP_SAME, HOP_OTHER, NO_COORDS, NO_LOC = 60, 160, 40, 250  -- map-% units
local MAX_TASKS = 80
local STRATEGIES = { 1, 2, 0, 4 }        -- how strongly to favour zones with several tasks waiting (best first)
local SEEDS = 4                          -- variations per strategy
local BUDGET_MS = 30                     -- planning stops after this and keeps the best so far (never freezes)

---------------------------------------------------------------------------
-- Continents (for travel cost), from the game's own map tree
---------------------------------------------------------------------------
local contCache = {}
local function Continent(m)
  if not m or m == 0 then return nil end
  if contCache[m] ~= nil then return contCache[m] or nil end
  local id, guard = m, 0
  while id and id > 0 and guard < 10 do
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    if not info then break end
    if info.mapType == 2 then contCache[m] = id; return id end   -- Enum.UIMapType.Continent
    id, guard = info.parentMapID, guard + 1
  end
  contCache[m] = false
  return nil
end

-- Where a zone sits on its continent's map (centre, 0-1), for flight distances.
local centreCache = {}
local function Centre(m, cont)
  local key = m .. ":" .. cont
  if centreCache[key] ~= nil then return centreCache[key] or nil end
  local c = false
  if C_Map and C_Map.GetMapRectOnMap then
    local ok, minX, maxX, minY, maxY = pcall(C_Map.GetMapRectOnMap, m, cont)
    if ok and minX and maxX then c = { (minX + maxX) / 2, (minY + maxY) / 2 } end
  end
  centreCache[key] = c
  return c or nil
end

-- A flight within a continent costs more the further apart the zones are; a boat costs the most.
local function Hop(a, b)
  if a == b then return 0 end
  local ca, cb = Continent(a), Continent(b)
  if not (ca and ca == cb) then return HOP_OTHER end
  local pa, pb = Centre(a, ca), Centre(b, ca)
  if pa and pb then
    local d = ((pa[1] - pb[1]) ^ 2 + (pa[2] - pb[2]) ^ 2) ^ 0.5   -- 0 .. ~1 across the continent
    return 30 + 110 * d
  end
  return HOP_SAME
end

local function Cost(from, loc)
  if not loc or not loc[2] or loc[2] == 0 then return NO_LOC end
  local m, x, y = loc[2], loc[3], loc[4]
  if from.map == m then
    if not x or not from.x then return NO_COORDS end
    return ((x - from.x) ^ 2 + (y - from.y) ^ 2) ^ 0.5
  end
  return Hop(from.map, m)
end

---------------------------------------------------------------------------
-- The dungeon's quests and the chains behind them
---------------------------------------------------------------------------
local function DungeonStep(name)
  for i, st in ipairs(ns.steps) do if st.dungeon == name then return st, i end end
end

-- Prerequisites of a quest: ours (all of pg, any one of ps), else the journal's required chain.
-- The data never changes, so each quest's list is worked out once.
local prereqCache = {}
local function PrereqsRaw(id)
  local q = ns.quests[id]
  local all, any = {}, {}
  if q then
    for _, p in ipairs(q.pg or {}) do if p > 0 then all[#all + 1] = p end end
    for _, p in ipairs(q.ps or {}) do if p > 0 then any[#any + 1] = p end end
  end
  if #all == 0 and #any == 0 then
    -- not in the route's data: our Dungeon Journal's (Data_Dungeons.lua)
    local dq = ns.dungeonQuests and ns.dungeonQuests[id]
    local ch = ns.dungeonChain and ns.dungeonChain[id]
    for _, p in ipairs((dq and dq.pg) or (ch and ch[4]) or {}) do if p > 0 then all[#all + 1] = p end end
    for _, p in ipairs((dq and dq.ps) or {}) do if p > 0 then any[#any + 1] = p end end
  end
  return all, any
end
local function Prereqs(id)
  local c = prereqCache[id]
  if not c then c = { PrereqsRaw(id) }; prereqCache[id] = c end
  return c[1], c[2]
end

-- Real quest state: "done", "ready" (objectives done), "log", or nil. While planning, each quest is
-- asked about once (realMemo), not thousands of times.
local realMemo
local function RealState(id)
  if realMemo then
    local v = realMemo[id]
    if v ~= nil then return v or nil end
  end
  local r
  if ns.IsDone(id) then r = "done"
  else
    local idx = ns.LogIndex(id)
    if idx > 0 then r = ns.IsReady(id, idx) and "ready" or "log" end
  end
  if realMemo then realMemo[id] = r or false end
  return r
end

-- One simulated run. weight: favour zones with several tasks waiting; rnd: tie-break noise (or nil).
-- logN/logMax: quests in your log now and how many it holds - pick-ups wait for room.
local function Run(targets, level, start, weight, rnd, logN, logMax)
  local state, why, touched = {}, {}, {}
  local function St(id)
    touched[id] = true
    if state[id] then return state[id] end
    return RealState(id)
  end
  local function Met(id)
    local all, any = Prereqs(id)
    for _, p in ipairs(all) do if St(p) ~= "done" then return false end end
    if #any > 0 then
      for _, p in ipairs(any) do if St(p) == "done" then return true end end
      return false
    end
    return true
  end
  local skip = (ns.db and ns.db.skip) or {}
  local function Frontier(id, depth, seen)
    if depth > 12 or seen[id] then return nil end
    seen[id] = true
    local q = ns.quests[id]
    -- You skipped it (right-click > Skip): its chain stops here.
    if skip[id] then why[id] = "skipped"; return nil end
    -- Not for your race or class (e.g. one of several alternative lead-ins): not this way.
    if q and not ns.ForMe(q) then why[id] = "isn't for your race or class"; return nil end
    local s = St(id)
    if s == "done" or s == "held" then return nil end
    -- A dungeon quest you hold is the point of getting ready: the rest (objectives, hand-ins at an
    -- altar inside, or back at the giver after the run) is part of the run, not the prep.
    if depth == 0 and q and q.d and (s == "ready" or s == "log") then return nil end
    if s == "ready" then return q and { id = id, kind = "turn", loc = q.t } end
    if s == "log" then
      if not q then why[id] = "isn't in the quest data"; return nil end
      if q.o then return { id = id, kind = "do", loc = q.o } end
      if q.t then return { id = id, kind = "go", loc = q.t } end
      return { id = id, kind = "do", loc = nil }
    end
    if Met(id) then
      if not q then why[id] = "isn't in the quest data"; return nil end
      if (q.r or 0) > level then why[id] = "opens at level " .. q.r; return nil end
      -- started by an item that drops inside (e.g. The Essence of Eranikus): you get it in the run
      if depth == 0 and q.d and not (q.g and q.g[3]) then why[id] = "starts from a drop inside the dungeon"; return nil end
      return { id = id, kind = "get", loc = q.g }
    end
    local all, any = Prereqs(id)
    local blocked
    for _, p in ipairs(all) do
      if St(p) ~= "done" then
        local f = Frontier(p, depth + 1, seen)
        if f then return f end
        blocked = blocked or p
      end
    end
    for _, p in ipairs(any) do
      local f = Frontier(p, depth + 1, seen)
      if f then return f end
      blocked = blocked or p
    end
    if blocked and why[blocked] then
      local pn = ns.quests[blocked] and ns.quests[blocked].n or ("quest " .. blocked)
      local w = why[blocked]
      if w == "skipped" then w = "you skipped " .. pn
      elseif not w:find("^you skipped") then w = pn .. " " .. w end
      why[id] = why[id] or w
    end
    why[id] = why[id] or "needs an earlier quest you can't do yet"
    return nil
  end

  local pos = { map = start.map, x = start.x, y = start.y }
  local tasks, total, logFull = {}, 0, false
  for _ = 1, MAX_TASKS do
    -- what can be done next, one task per chain
    local cands, seenTask, perMap = {}, {}, {}
    for _, t in ipairs(targets) do
      local f = Frontier(t, 0, {})
      if f and not seenTask[f.id .. f.kind] then
        seenTask[f.id .. f.kind] = true
        cands[#cands + 1] = f
        local m = f.loc and f.loc[2] or 0
        perMap[m] = (perMap[m] or 0) + 1
      end
    end
    if #cands == 0 then break end
    -- a full quest log: only hand-ins and objectives until there's room for the next pick-up
    if logN >= logMax then
      local room = {}
      for _, f in ipairs(cands) do if f.kind ~= "get" then room[#room + 1] = f end end
      if #room == 0 then logFull = true; break end
      cands = room
    end
    local best, bestScore, bestCost
    for _, f in ipairs(cands) do
      local c = Cost(pos, f.loc)
      local m = f.loc and f.loc[2] or 0
      local score = c
      if m ~= pos.map and m ~= 0 then score = c / (1 + weight * ((perMap[m] or 1) - 1)) end
      if rnd then score = score * (1 + 0.3 * rnd()) end
      if not best or score < bestScore then best, bestScore, bestCost = f, score, c end
    end
    tasks[#tasks + 1] = best
    total = total + bestCost
    local q = ns.quests[best.id]
    if best.kind == "get" then
      state[best.id] = (q and q.d) and "held" or ((q and not q.ob) and "ready" or "log")
      logN = logN + 1
    elseif best.kind == "do" or best.kind == "go" then
      state[best.id] = "ready"
    elseif best.kind == "turn" then
      state[best.id] = "done"
      logN = logN - 1
    end
    if best.loc and best.loc[2] and best.loc[2] ~= 0 then pos = { map = best.loc[2], x = best.loc[3], y = best.loc[4] } end
  end
  return tasks, total, state, why, touched, logFull
end

-- Small deterministic random numbers (same plan for the same situation).
local function Rng(seed)
  local s = seed
  return function()
    s = (s * 1103515245 + 12345) % 2147483648
    return s / 2147483648
  end
end

--- Plan the route: { tasks = {{id, kind, loc}}, stalled = {{id, why}}, ready = {ids}, step, touched }.
function P.Plan(name, level)
  local st = DungeonStep(name)
  if not st then return nil end
  local S = ns.S
  local targets = {}
  for _, id in ipairs(st.quests) do
    local s = ns.Status(id, level)
    if s ~= S.NA and s ~= S.SKIP and s ~= S.DONE and ns.quests[id] then targets[#targets + 1] = id end
  end
  -- from where you are, or where your flight lands (PlayerPos is already in map %)
  local pm, px, py = ns.HerePos()
  local start = { map = pm, x = px, y = py }
  local logN = #ns.QuestLog()
  local logMax = (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept()) or 20
  local best
  realMemo = {}
  local clock = debugprofilestop
  local t0 = clock and clock()
  for si, w in ipairs(STRATEGIES) do
    if best and t0 and clock() - t0 > BUDGET_MS then break end
    for seed = 0, SEEDS - 1 do
      if best and t0 and clock() - t0 > BUDGET_MS then break end
      local rnd = seed > 0 and Rng(si * 1000 + seed) or nil
      local tasks, total, state, why, touched, logFull = Run(targets, level, start, w, rnd, logN, logMax)
      if not best or #tasks > #best.tasks or (#tasks == #best.tasks and total < best.total) then
        best = { tasks = tasks, total = total, state = state, why = why, touched = touched, logFull = logFull }
      end
    end
  end
  realMemo = nil
  local ready, stalled = {}, {}
  for _, t in ipairs(targets) do
    if ns.LogIndex(t) > 0 then ready[#ready + 1] = t
    elseif not best.state[t] then stalled[#stalled + 1] = { id = t, why = best.why[t] or "needs an earlier quest you can't do yet" } end
  end
  return { tasks = best.tasks, total = best.total, stalled = stalled, ready = ready, step = st, touched = best.touched,
           logFull = best.logFull, logN = logN, logMax = logMax }
end

-- Re-plan only when something it depends on changed (quest states, level, zone).
local cache
local function Signature(name, level, touched)
  -- the zone you're in (or flying to): a new zone re-plans; moving around inside one doesn't
  -- (that would re-plan every few seconds while riding)
  local m = ns.HerePos()
  local parts = { name, level, m or 0, #ns.QuestLog() }
  -- skipping or un-skipping a quest re-plans
  local sk = {}
  for id in pairs((ns.db and ns.db.skip) or {}) do sk[#sk + 1] = id end
  table.sort(sk)
  parts[#parts + 1] = "skip:" .. table.concat(sk, "/")
  local ids = {}
  for id in pairs(touched or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do parts[#parts + 1] = id .. "=" .. (RealState(id) or "-") end
  return table.concat(parts, ",")
end

---------------------------------------------------------------------------
-- Turn the plan into a route the tracker, map, minimap and arrow already understand
---------------------------------------------------------------------------
function P.Route(name, level)
  local plan
  if cache and cache.name == name and cache.sig == Signature(name, level, cache.plan.touched) then
    plan = cache.plan
  else
    plan = P.Plan(name, level)
    if not plan then return nil end
    cache = { name = name, plan = plan, sig = Signature(name, level, plan.touched) }
  end
  local st = plan.step
  local pm = ns.PlayerPos()
  local stops, loose = {}, {}
  local last
  for _, t in ipairs(plan.tasks) do
    local q = ns.quests[t.id]
    local loc = t.loc
    local row = { id = t.id, q = q, s = (t.kind == "get") and ns.S.OPEN or (t.kind == "turn" and ns.S.READY or ns.S.LOG), prep = true }
    local action = { kind = t.kind, row = row }
    if loc and loc[2] and loc[3] and loc[4] and loc[3] >= 0 then
      if last and last.map == loc[2] and math.abs(last.x - loc[3]) < ns.MERGE and math.abs(last.y - loc[4]) < ns.MERGE
        and last.area == (t.kind == "do") then
        last.actions[#last.actions + 1] = action
      else
        last = { map = loc[2], x = loc[3], y = loc[4], cx = loc[3], cy = loc[4], r = loc[5], name = loc[1],
                 area = (t.kind == "do"), actions = { action }, away = (loc[2] ~= pm) }
        if loc[6] then last.pts = {}; for k = 1, #loc[6] do last.pts[k] = loc[6][k] end end
        stops[#stops + 1] = last
      end
    else
      loose[#loose + 1] = action
    end
  end
  for i, s in ipairs(stops) do s.index = i end
  -- Ready = nothing left to do AND nothing out of reach AND no full log holding pick-ups back.
  -- (Nothing doable but quests out of reach is "not yet", not "ready".)
  -- Nothing left you can do before the run, and you hold at least one of its quests. Chains you
  -- skipped or that open later don't keep it open (they're listed under "Not yet").
  local allReady = (#plan.tasks == 0) and (#plan.ready > 0) and not plan.logFull
  local counts = { 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  -- The rest of your log stays listed under Other Quests.
  local inRoute, other = {}, {}
  for _, t in ipairs(plan.tasks) do inRoute[t.id] = true end
  for _, e in ipairs(ns.QuestLog()) do if not inRoute[e.id] then other[#other + 1] = e end end
  local zones, lastMap = 0, nil
  for _, s in ipairs(stops) do if s.map ~= lastMap then zones = zones + 1; lastMap = s.map end end
  local note
  if plan.logFull then
    note = ("Your quest log is full (%d/%d): hand in or drop a quest to pick up the rest."):format(plan.logN, plan.logMax)
    if #plan.tasks > 0 then note = ("%d steps first. "):format(#plan.tasks) .. note end
  elseif #plan.tasks > 0 then
    note = ("%d steps across %d zone visits to pick up every %s quest you can, in the quickest order found. %d already in your log.")
      :format(#plan.tasks, zones, name, #plan.ready)
  else
    note = ("Nothing more to pick up for %s yet - see \"Not yet\" below. You can still run it with what you have."):format(name)
  end
  local pstep = {
    name = "Get ready: " .. name, from = st.from, to = st.to, map = (stops[1] and stops[1].map) or st.map,
    quests = st.quests, dungeon = name, dj = st.dj, ent = st.ent, prep = true, note = note,
  }
  return { level = level, idx = select(2, DungeonStep(name)) or 1, step = pstep, counts = counts, stops = stops,
           loose = loose, stalled = plan.stalled, other = other, manual = false, inZone = (pm == pstep.map), prep = name,
           allReady = allReady }
end
function ns.StartPrep(name)
  name = name or (ns.route and ns.route.step and ns.route.step.dungeon)
  if not name then ns.Print("pick a dungeon: /rdr prep Sunken Temple (or click \"Get ready\" on a dungeon step)."); return end
  if not DungeonStep(name) then ns.Print("no dungeon called " .. name .. " in the route."); return end
  ns.db.prep = name           -- set first: SetDungeon below then won't start it again
  cache = nil
  if not ns.DungeonOn(name) then ns.SetDungeon(name, true) end
  ns.Print("side route: picking up every " .. name .. " quest first (max XP from the run). It ends by itself when you have them all - or click \"Back to the route\".")
  ns.Recompute()
  if ns.Options and ns.Options.RefreshDungeons then ns.Safe("Options", ns.Options.RefreshDungeons) end
end

function ns.StopPrep()
  ns.db.prep = nil
  cache = nil
  ns.Print("back to the leveling route.")
  ns.Recompute()
  if ns.Options and ns.Options.RefreshDungeons then ns.Safe("Options", ns.Options.RefreshDungeons) end
end

--- /rdr prep [dungeon | off]: matches the start of a dungeon's name ("sunken", "st", "brd" ...).
function P.Command(arg)
  arg = (arg or ""):lower()
  if arg == "off" or arg == "stop" then ns.StopPrep(); return end
  if arg == "" then ns.StartPrep(); return end
  for _, st in ipairs(ns.steps) do
    if st.dungeon and (st.dungeon:lower():find(arg, 1, true) == 1 or (st.dj and st.dj == arg)) then
      ns.StartPrep(st.dungeon); return
    end
  end
  ns.Print("no dungeon matching \"" .. arg .. "\". Try /rdr prep sunken, or /rdr dungeons for the list.")
end

-- Rubber Dinghy - learn facts about the game as you play (never your pace):
--   * each quest's real objective counts ("0/10 ..."), which Questie's database doesn't have;
--   * flights: from which zone to which, and how long they take;
--   * where a quest's objectives are, for quests no database has a location for (Forever-only mobs
--     and objects): each time such a quest's progress goes up, the spot you're standing on.
-- tools/learn.py feeds these into the route planner, so it plans with real counts and real flight
-- times. Your own speed is deliberately not recorded: the planner keeps an efficient player's pace,
-- so the route is the fastest one, not a copy of how you happened to play. Stored in this addon's
-- saved variables on your PC only. Settings > "Learn quest counts and flight times" switches it off.
local ADDON, ns = ...
local L = {}
ns.Learn = L

local MAX_FLIGHTS = 400

local function DB()
  local db = ns.db
  if not db or db.noLearn then return nil end
  db.learn = db.learn or { v = 1, obj = {}, fl = {} }
  db.learn.obj = db.learn.obj or {}
  db.learn.fl = db.learn.fl or {}
  return db.learn
end

---------------------------------------------------------------------------
-- Real objective counts
---------------------------------------------------------------------------
local TYPE = { monster = "m", item = "i", object = "o", event = "e", reputation = "r", log = "l", player = "p" }
local function RecordObjectives(id)
  local d = DB(); if not d or d.obj[id] then return end
  if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return end
  local objs = C_QuestLog.GetQuestObjectives(id)
  if not objs then return end
  -- No objectives may just mean the data hasn't loaded yet: only believe "talk/deliver" (empty)
  -- after seeing it empty on a later scan too.
  if #objs == 0 then
    d.empty = d.empty or {}
    d.empty[id] = (d.empty[id] or 0) + 1
    if d.empty[id] < 3 then return end
  end
  local parts = {}
  for _, o in ipairs(objs) do
    local need = o.numRequired
    if not need and o.text then need = tonumber(o.text:match("%d+%s*/%s*(%d+)")) end
    parts[#parts + 1] = (TYPE[o.type or ""] or "x") .. (need or 1)
  end
  d.obj[id] = table.concat(parts, ",")   -- e.g. "m10,i8" = kill 10, collect 8; "" = talk/deliver
end

---------------------------------------------------------------------------
-- Where objectives are, for quests with no location in the data (no "o" field): the spot you're on
-- each time the quest's progress goes up. tools/learn.py turns them into the quest's map area.
---------------------------------------------------------------------------
local MAX_SPOTS, NEAR = 25, 1.5   -- per quest; spots closer than this (map %) count as one
local lastProg = {}
local function RecordSpot(id)
  local q = ns.quests and ns.quests[id]
  if not q or q.o or not q.ob then return end   -- has a location already, or nothing to do out there
  local have = ns.Progress(id)
  local before = lastProg[id]
  lastProg[id] = have
  if not before or have <= before then return end   -- first sight, or no progress
  local d = DB(); if not d then return end
  local m, x, y = ns.PlayerPos()
  if not m then return end
  d.spots = d.spots or {}
  local list = d.spots[id] or ""
  local n = 0
  for pm, px, py in list:gmatch("(%d+):([%d.]+),([%d.]+)") do
    n = n + 1
    if tonumber(pm) == m and math.abs(tonumber(px) - x) < NEAR and math.abs(tonumber(py) - y) < NEAR then return end
  end
  if n >= MAX_SPOTS then return end
  d.spots[id] = list .. (list ~= "" and ";" or "") .. ("%d:%.1f,%.1f"):format(m, x, y)
end

local function ScanLog()
  if not DB() then return end
  for _, e in ipairs(ns.QuestLog()) do
    RecordObjectives(e.id)
    RecordSpot(e.id)
  end
end

---------------------------------------------------------------------------
-- Flight times (real game time; a flight takes as long as it takes, whoever's on it)
---------------------------------------------------------------------------
local flight
local function CheckTaxi()
  local on = UnitOnTaxi and UnitOnTaxi("player")
  if on and not flight then
    flight = { f = ns.PlayerPos(), s = GetTime(), to = ns.taxiDest and ns.taxiDest.map }
  elseif not on and flight then
    local d = DB()
    local secs = GetTime() - flight.s
    if d and secs > 5 then
      d.fl[#d.fl + 1] = { f = flight.f, t = ns.PlayerPos() or flight.to, s = math.floor(secs + 0.5) }
      while #d.fl > MAX_FLIGHTS do table.remove(d.fl, 1) end
    end
    flight = nil
  end
end

local f = CreateFrame("Frame")
local tick, pending = 0, false
f:SetScript("OnUpdate", function(_, dt)
  tick = tick + dt
  if tick > 1 then tick = 0; if DB() then CheckTaxi() end end
end)
f:SetScript("OnEvent", function()
  if pending or not DB() then return end
  pending = true
  C_Timer.After(1, function() pending = false; ns.Safe("Learn", ScanLog) end)
end)

ns.inits.Learn = function()
  pcall(f.RegisterEvent, f, "QUEST_ACCEPTED")
  pcall(f.RegisterEvent, f, "QUEST_LOG_UPDATE")
  ns.Safe("Learn", ScanLog)
end

--- "Learned: 40 quests' objective counts, 3 flights." for the settings window.
function L.Summary()
  local d = ns.db and ns.db.learn
  local counts = 0
  for _ in pairs((d and d.obj) or {}) do counts = counts + 1 end
  local spots = 0
  for _ in pairs((d and d.spots) or {}) do spots = spots + 1 end
  return ("Learned so far: %d quests' objective counts, %d flight times, %d quest locations."):format(
    counts, #((d and d.fl) or {}), spots)
end

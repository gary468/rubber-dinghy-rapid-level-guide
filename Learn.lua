-- Rubber Dinghy - learn facts about the game as you play (never your pace):
--   * each quest's real objective counts ("0/10 ..."), which Questie's database doesn't have;
--   * flights: from which zone to which, and how long they take.
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

local function ScanLog()
  if not DB() then return end
  for _, e in ipairs(ns.QuestLog()) do RecordObjectives(e.id) end
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
  return ("Learned so far: %d quests' objective counts, %d flight times."):format(counts, #((d and d.fl) or {}))
end

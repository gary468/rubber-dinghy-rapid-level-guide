-- Rubber Dinghy - Run Log: every dungeon run, recorded on its own.
-- A run is one copy of a dungeon: stepping out (or a corpse run) and coming back carries on the same
-- run; a reset dungeon (new copy) starts a new one. Each run keeps: dungeon, start and last-seen time,
-- mob XP and kills (with first/last kill time), quest XP, money looted, deaths, your level, bosses
-- killed, and time spent outside. The route planner reads these to calibrate dungeon XP and time.
--
-- Cost: outside dungeons only two zone events are watched. Inside, the combat log adds one
-- CombatLogGetCurrentEventInfo per event, and only deaths are looked at.
local ADDON, ns = ...
local RL = {}
ns.RunLog = RL

local MAX_RUNS = 200
local SAME_RUN_GAP = 45 * 60   -- back inside the same instance within 45 min (and no reset): same run
local HOSTILE = 0x00000040     -- COMBATLOG_OBJECT_REACTION_HOSTILE
local CleuInfo = CombatLogGetCurrentEventInfo
local band = bit and bit.band or function(a, b)   -- the game has bit; this is only for test clients
  local r, m = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + m end
    a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2
  end
  return r
end

local f = CreateFrame("Frame")
local cur                     -- the run going on (inside, or stepped out of)
local inside = false
local lastXP, lastMax, lastMoney
local seenDead = {}           -- GUIDs already counted (UNIT_DIED can repeat)
local bossByNpc, bossByName = {}, {}   -- for the dungeon you're in

local function Now() return time() end

--- The journal's entry for a route dungeon name or a place ("Dire Maul" -> its first wing).
function RL.Dungeon(name)
  if not name then return nil end
  for _, d in ipairs(ns.dungeonDB or {}) do
    if d.name == name then return d end
  end
  for _, d in ipairs(ns.dungeonDB or {}) do
    if d.place == name then return d end
  end
  return nil
end

-- Which dungeon you're in, from the game's instance ID (our data), else the route's own lookup.
local function Here()
  if not GetInstanceInfo then return nil end
  local name, kind, _, _, _, _, _, instID = GetInstanceInfo()
  if kind ~= "party" then return nil end
  local place
  for _, d in ipairs(ns.dungeonDB or {}) do
    if d.inst and d.inst == instID then place = d.place or d.name; break end
    if d.name == name or d.place == name then place = d.place or d.name; break end
    if d.ej then for _, n in ipairs(d.ej) do if n == name then place = d.place or d.name end end end
    if place then break end
  end
  if not place and ns.CurrentDungeon then place = ns.CurrentDungeon() end
  return place or name, instID
end

-- Bosses of a place (all its wings), by NPC ID and by name: boss -> wing name.
local function LoadBosses(place)
  wipe(bossByNpc); wipe(bossByName)
  for _, d in ipairs(ns.dungeonDB or {}) do
    if d.name == place or d.place == place then
      for _, b in ipairs(d.bosses or {}) do
        if b[2] and b[2] > 0 then bossByNpc[b[2]] = { b[1], d.name } end
        bossByName[b[1]] = d.name
      end
    end
  end
end

local function Runs()
  ns.db.runs = ns.db.runs or {}
  return ns.db.runs
end

local function NewRun(place, instID)
  local runs = Runs()
  local d = RL.Dungeon(place)
  local run = { d = (d and not d.wing) and d.name or place, place = place, inst = instID, t0 = Now(),
                t1 = Now(), kills = 0, xp = 0, qxp = 0, money = 0, deaths = 0, out = 0,
                lv0 = UnitLevel("player"), lv1 = UnitLevel("player"), bosses = {} }
  runs[#runs + 1] = run
  while #runs > MAX_RUNS do table.remove(runs, 1) end
  wipe(seenDead)
  return run
end

local function Watch(on)
  if on then
    f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    f:RegisterEvent("PLAYER_XP_UPDATE")
    f:RegisterEvent("PLAYER_MONEY")
    f:RegisterEvent("QUEST_TURNED_IN")
    f:RegisterEvent("ENCOUNTER_END")
    f:RegisterEvent("PLAYER_DEAD")
  else
    f:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    f:UnregisterEvent("PLAYER_XP_UPDATE")
    f:UnregisterEvent("PLAYER_MONEY")
    f:UnregisterEvent("QUEST_TURNED_IN")
    f:UnregisterEvent("ENCOUNTER_END")
    f:UnregisterEvent("PLAYER_DEAD")
  end
end

local function Snapshot()
  lastXP, lastMax = UnitXP("player"), UnitXPMax("player")
  lastMoney = GetMoney and GetMoney() or 0
end

-- Entering or leaving the world / a zone: start, resume or pause a run.
local function CheckZone()
  local place, instID = Here()
  local now = Now()
  if place then
    if cur and cur.place == place and not cur.left then
      -- still inside (a zone change within the instance)
    elseif cur and cur.place == place and cur.left and now - cur.left <= SAME_RUN_GAP then
      cur.out = (cur.out or 0) + (now - cur.left)   -- back from outside: same run (unless reset, see kills)
      cur.left = nil
    else
      cur = NewRun(place, instID)
    end
    if not inside then inside = true; LoadBosses(place); Snapshot(); Watch(true) end
  elseif inside then
    inside = false
    Watch(false)
    if cur then cur.left = now; cur.t1 = now end
  end
end

local function Complete(run)
  local d = RL.Dungeon(run.d)
  if not d or run.done then return end
  for _, b in ipairs(d.bosses or {}) do
    if b[2] and b[2] > 0 and not run.bosses[b[1]] then return end
  end
  run.done = Now()
end

local function BossDown(name, wing)
  if not cur or not name or cur.bosses[name] then return end
  cur.bosses[name] = Now() - cur.t0
  if wing and cur.d ~= wing then cur.d = wing end   -- a wing's boss tells which wing this run is
  Complete(cur)
  if ns.Tracker and ns.Tracker.Refresh then ns.Safe("Tracker", ns.Tracker.Refresh) end
  if ns.Journal and ns.Journal.RefreshIfShown then ns.Safe("Journal", ns.Journal.RefreshIfShown) end
end

local function OnDeath(guid, flags)
  if seenDead[guid] or not guid then return end
  local kind, _, _, _, zuid, npc = strsplit("-", guid)
  if kind ~= "Creature" or band(flags or 0, HOSTILE) == 0 then return end
  seenDead[guid] = true
  -- a different copy of the dungeon (it was reset): a new run
  if cur.zuid and zuid and cur.zuid ~= zuid and cur.kills > 0 then
    local place = cur.place
    cur = NewRun(place, cur.inst)
    seenDead[guid] = true
  end
  cur.zuid = cur.zuid or zuid
  local now = Now()
  cur.kills = cur.kills + 1
  cur.k0 = cur.k0 or now
  cur.k1 = now
  cur.t1 = now
  local b = bossByNpc[tonumber(npc)]
  if b then BossDown(b[1], b[2]) end
end

f:SetScript("OnEvent", function(_, event, ...)
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    if not cur then return end
    local _, sub, _, _, _, _, _, dstGUID, _, dstFlags = CleuInfo()
    if sub == "UNIT_DIED" or sub == "PARTY_KILL" then OnDeath(dstGUID, dstFlags) end
  elseif event == "PLAYER_XP_UPDATE" then
    if not cur then return end
    local xp, max = UnitXP("player"), UnitXPMax("player")
    local gained = (xp >= (lastXP or xp)) and (xp - (lastXP or xp)) or ((lastMax or 0) - (lastXP or 0) + xp)
    if gained > 0 then cur.xp = cur.xp + gained end
    lastXP, lastMax = xp, max
    cur.lv1 = UnitLevel("player")
  elseif event == "PLAYER_MONEY" then
    if not cur then return end
    local m = GetMoney()
    if lastMoney and m > lastMoney then cur.money = cur.money + (m - lastMoney) end
    lastMoney = m
  elseif event == "QUEST_TURNED_IN" then
    if not cur then return end
    local _, xp, money = ...
    cur.qxp = cur.qxp + (tonumber(xp) or 0)
    cur.qmoney = (cur.qmoney or 0) + (tonumber(money) or 0)
  elseif event == "ENCOUNTER_END" then
    local _, name, _, _, success = ...
    if success == 1 and name then BossDown(name, bossByName[name]) end
  elseif event == "PLAYER_DEAD" then
    if cur then cur.deaths = cur.deaths + 1 end
  else
    CheckZone()
  end
end)
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")

ns.inits.RunLog = function()
  -- carry on a run you logged out inside of
  local runs = Runs()
  local last = runs[#runs]
  if last and not last.done and Now() - (last.t1 or 0) <= SAME_RUN_GAP then cur = last end
  CheckZone()
end

---------------------------------------------------------------------------
-- Reading the log
---------------------------------------------------------------------------
--- Mob XP of a run: XP gained inside minus quest XP handed in during it.
function RL.MobXP(run) return math.max(0, (run.xp or 0) - (run.qxp or 0)) end
--- Run time: first kill to last kill (the old journal's "first trash to last boss"), else in/out.
function RL.Secs(run)
  if run.k0 and run.k1 and run.k1 > run.k0 then return run.k1 - run.k0 end
  return math.max(0, (run.t1 or run.t0) - run.t0 - (run.out or 0))
end
function RL.Gold(run) return math.max(0, (run.money or 0) - (run.qmoney or 0)) end
function RL.Current() return inside and cur or nil end
function RL.All() return Runs() end
function RL.For(name)
  local out = {}
  for i = #Runs(), 1, -1 do
    local r = Runs()[i]
    if r.d == name or r.place == name then out[#out + 1] = r end
  end
  return out
end
function RL.Delete(run)
  local runs = Runs()
  for i = #runs, 1, -1 do if runs[i] == run then table.remove(runs, i) end end
  if cur == run then cur = nil end
end
function RL.BossCount(run)
  local d = RL.Dungeon(run.d)
  local n, of = 0, 0
  for _, b in ipairs(d and d.bosses or {}) do
    of = of + 1
    if run.bosses[b[1]] then n = n + 1 end
  end
  return n, of
end

function RL.Clock(secs)
  secs = math.floor(secs or 0)
  if secs >= 3600 then return ("%d:%02d:%02d"):format(secs / 3600, (secs % 3600) / 60, secs % 60) end
  return ("%d:%02d"):format(secs / 60, secs % 60)
end

local function Thousands(n)
  local s = tostring(math.floor(n or 0))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end
RL.Thousands = Thousands

--- One line for the tracker while you're in a run: "This run 23:10 - 8,450 XP - bosses 3/5".
function RL.Line()
  local run = RL.Current()
  if not run then return nil end
  local secs = run.k0 and (Now() - run.k0) or 0
  local n, of = RL.BossCount(run)
  local atCap = UnitLevel("player") >= (GetMaxPlayerLevel and GetMaxPlayerLevel() or 60)
  local gain = atCap and (GetCoinTextureString and GetCoinTextureString(RL.Gold(run)) or (RL.Gold(run) .. "c"))
    or (Thousands(RL.MobXP(run)) .. " XP")
  return ("This run %s - %s - bosses %d/%d%s"):format(RL.Clock(secs), gain, n, of, run.done and " - cleared" or "")
end

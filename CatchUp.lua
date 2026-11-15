-- Rubber Dinghy - catching up when you're behind the route's planned level (Gary 15 Nov: "my mate is
-- behind the guide a bit, is it possible to offer alternatives, either quests, grinding or dungeons").
-- Three kinds of option, nearest / best first:
--   * quests you can take at your level that the current step doesn't use;
--   * grinding camps in the zone you're in (ns.grindCamps: dense spots of normal mobs at your level);
--   * dungeons whose level range fits you.
local ADDON, ns = ...
local C = {}
ns.CatchUp = C

local cache, cacheKey, cacheT = nil, nil, 0

local function Dist2(m1, x1, y1, m2, x2, y2)
  if m1 ~= m2 or not (x1 and x2) then return 1e9 end
  return (x1 - x2) ^ 2 + (y1 - y2) ^ 2
end

--- How many levels you're behind this step's planned start (0 = on plan or ahead).
function C.Behind(step, level)
  if not step or step.dungeon or step.prep or not step.from then return 0 end
  return math.max(0, step.from - level)
end

--- { quests = {{id, q, zone}}, camps = {{name, lo, hi, x, y, n, map}}, dungeons = {{name, lo, hi}} }
function C.Options(step, level)
  local pm, px, py = ns.PlayerPos()
  local key = level .. ":" .. tostring(step and step.name) .. ":" .. tostring(pm)
  if cache and key == cacheKey and GetTime() - cacheT < 10 then return cache end
  local out = { quests = {}, camps = {}, dungeons = {} }
  -- quests at your level that the step doesn't already route
  local onStep = {}
  for _, id in ipairs((step and step.quests) or {}) do onStep[id] = true end
  local S = ns.S
  local qs = {}
  for id, q in pairs(ns.quests or {}) do
    if not onStep[id] and not q.d and not q.rep and q.g and q.g[2] and q.g[3]
      and q.l and q.l >= level - 1 and q.l <= level + 2 and ns.Status(id, level) == S.OPEN then
      qs[#qs + 1] = { id = id, q = q, d = Dist2(pm, px, py, q.g[2], q.g[3], q.g[4]) }
    end
  end
  table.sort(qs, function(a, b) if a.d ~= b.d then return a.d < b.d end return (a.q.l or 0) > (b.q.l or 0) end)
  for i = 1, math.min(3, #qs) do
    qs[i].zone = ns.MapName(qs[i].q.g[2]) or "?"
    out.quests[i] = qs[i]
  end
  -- grinding camps where you are (else in the step's zone), mobs at your level or a bit above
  local m = (pm and ns.grindCamps and ns.grindCamps[pm]) and pm or (step and step.map)
  local camps = {}
  for _, c in ipairs((ns.grindCamps and ns.grindCamps[m]) or {}) do
    local lo, hi = c[2], c[3]
    if lo <= level + 2 and hi >= level - 1 then
      local mid = (lo + hi) / 2
      camps[#camps + 1] = { name = c[1], lo = lo, hi = hi, x = c[4], y = c[5], n = c[6], map = m,
                            score = c[6] - 12 * math.abs(mid - (level + 1)) }
    end
  end
  table.sort(camps, function(a, b) return a.score > b.score end)
  for i = 1, math.min(2, #camps) do out.camps[i] = camps[i] end
  -- dungeons that fit your level (Alliance ones)
  for _, d in ipairs(ns.dungeonDB or {}) do
    if not d.horde and d.lo and d.hi and d.lo <= level and level <= d.hi - 2 then
      out.dungeons[#out.dungeons + 1] = { name = d.place or d.name, wing = d.wing, full = d.name, lo = d.lo, hi = d.hi }
    end
  end
  cache, cacheKey, cacheT = out, key, GetTime()
  return out
end

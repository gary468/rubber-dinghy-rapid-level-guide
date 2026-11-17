-- Rubber Dinghy - walking distance round mountains, for zones with a terrain grid (TerrainData.lua).
--
-- The route measures stops in straight lines. In Mount Hyjal that's badly wrong: the Shrine of Aviana
-- plateau and the Tainted Foothills look a few steps apart, but a cliff lies between them (Gary 17 Nov:
-- "the mountains block the quests", "no quick way to get there without slow fall"). The grid marks the
-- valley floor from the zone map; distances follow it round ridges. Valleys the grid doesn't join
-- (their passes are too narrow for 1% cells) cost the straight line plus a large fixed amount, so the
-- route finishes the valley you're in before moving to the next.
local ADDON, ns = ...
local T = {}
ns.Terrain = T

local CROSS = 30          -- extra cost (map %) to move between valleys the grid doesn't join
local SNAP = 4            -- a point this many cells from the valley floor snaps to it
local MAX_CACHE = 48      -- shortest-path tables kept (one per start cell)
local grids = {}

local function Build(map)
  local raw = ns.terrainData and ns.terrainData[map]
  if not raw then return nil end
  local n = raw.n
  local walk, comp = {}, {}
  for j = 1, n do
    local row = raw.rows[j] or ""
    for i = 1, n do
      if row:sub(i, i) == "1" then walk[(j - 1) * n + i] = true end
    end
  end
  -- valleys: 8-connected parts of the floor
  local id = 0
  for idx in pairs(walk) do
    if not comp[idx] then
      id = id + 1
      comp[idx] = id
      local stack = { idx }
      while #stack > 0 do
        local c = table.remove(stack)
        local ci, cj = (c - 1) % n + 1, math.floor((c - 1) / n) + 1
        for dj = -1, 1 do
          for di = -1, 1 do
            local i2, j2 = ci + di, cj + dj
            if i2 >= 1 and i2 <= n and j2 >= 1 and j2 <= n then
              local k = (j2 - 1) * n + i2
              if walk[k] and not comp[k] then comp[k] = id; stack[#stack + 1] = k end
            end
          end
        end
      end
    end
  end
  return { n = n, walk = walk, comp = comp, cache = {}, cached = 0 }
end

local function Grid(map)
  if grids[map] == nil then grids[map] = Build(map) or false end
  return grids[map] or nil
end

--- The floor cell for a point in map % (0-100), or nil when it's nowhere near the floor.
local function Snap(g, x, y)
  local n = g.n
  local ci = math.min(n, math.max(1, math.floor(x / 100 * n) + 1))
  local cj = math.min(n, math.max(1, math.floor(y / 100 * n) + 1))
  for r = 0, SNAP do
    local best, bd
    for j = cj - r, cj + r do
      for i = ci - r, ci + r do
        if i >= 1 and i <= n and j >= 1 and j <= n then
          local k = (j - 1) * n + i
          if g.walk[k] then
            local d = (i - ci) ^ 2 + (j - cj) ^ 2
            if not bd or d < bd then best, bd = k, d end
          end
        end
      end
    end
    if best then return best end
  end
end

-- Shortest paths over the floor from one cell (Dijkstra, binary heap), in cells.
local SQ2 = math.sqrt(2)
local function Paths(g, src)
  local hit = g.cache[src]
  if hit then return hit end
  if g.cached >= MAX_CACHE then g.cache, g.cached = {}, 0 end
  local n, walk = g.n, g.walk
  local dist = { [src] = 0 }
  local heap, hd = { src }, { 0 }
  local function push(k, d)
    local p = #heap + 1
    heap[p], hd[p] = k, d
    while p > 1 do
      local q = math.floor(p / 2)
      if hd[q] <= hd[p] then break end
      heap[p], heap[q], hd[p], hd[q] = heap[q], heap[p], hd[q], hd[p]
      p = q
    end
  end
  local function pop()
    local k, d = heap[1], hd[1]
    local last = #heap
    heap[1], hd[1] = heap[last], hd[last]
    heap[last], hd[last] = nil, nil
    local p, m = 1, #heap
    while true do
      local l, r, s = p * 2, p * 2 + 1, p
      if l <= m and hd[l] < hd[s] then s = l end
      if r <= m and hd[r] < hd[s] then s = r end
      if s == p then break end
      heap[p], heap[s], hd[p], hd[s] = heap[s], heap[p], hd[s], hd[p]
      p = s
    end
    return k, d
  end
  while #heap > 0 do
    local c, d = pop()
    if d <= dist[c] then
      local ci, cj = (c - 1) % n + 1, math.floor((c - 1) / n) + 1
      for dj = -1, 1 do
        for di = -1, 1 do
          if di ~= 0 or dj ~= 0 then
            local i2, j2 = ci + di, cj + dj
            if i2 >= 1 and i2 <= n and j2 >= 1 and j2 <= n then
              local k = (j2 - 1) * n + i2
              if walk[k] then
                local nd = d + ((di ~= 0 and dj ~= 0) and SQ2 or 1)
                if not dist[k] or nd < dist[k] then dist[k] = nd; push(k, nd) end
              end
            end
          end
        end
      end
    end
  end
  g.cache[src] = dist
  g.cached = g.cached + 1
  return dist
end

--- Whether this map has a terrain grid.
function T.Has(map) return Grid(map) ~= nil end

--- A distance function for the map (map %, like the straight line it replaces), or nil when the
--- map has no grid. Never shorter than the straight line.
function T.Dist(map)
  local g = Grid(map)
  if not g then return nil end
  local scale = 100 / g.n
  return function(x1, y1, x2, y2)
    local straight = math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
    local a, b = Snap(g, x1, y1), Snap(g, x2, y2)
    if not a or not b then return straight end
    if g.comp[a] ~= g.comp[b] then return straight + CROSS end
    local d = Paths(g, a)[b]
    if not d then return straight + CROSS end
    return math.max(straight, d * scale)
  end
end

--- Same valley (true), different valleys (false), or unknown (nil: no grid, or off the floor).
function T.SameValley(map, x1, y1, x2, y2)
  local g = Grid(map)
  if not g then return nil end
  local a, b = Snap(g, x1, y1), Snap(g, x2, y2)
  if not a or not b then return nil end
  return g.comp[a] == g.comp[b]
end

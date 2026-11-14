-- Rubber Dinghy - the game's own geography, saved once per client build for the route planner
-- (tools/geo.py): where every zone sits in the world (so travel between zones is real distance, not a
-- guess), and every flight master on each continent. Opening a flight map adds the nodes it shows
-- (with their positions and whether you know them). Facts about the game only; stays on your PC.
local ADDON, ns = ...
local G = {}
ns.Geo = G

local VERSION = 1
local CONTINENTS = { 1414, 1415 }   -- Kalimdor, Eastern Kingdoms

local function Rect(m)
  if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local ok1, c1, p1 = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(0, 0))
  local ok2, c2, p2 = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(1, 1))
  if not (ok1 and ok2 and p1 and p2) then return nil end
  local x1, y1 = p1:GetXY()
  local x2, y2 = p2:GetXY()
  return { c = c1, x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
end

local function Node(n, onMap)
  local x, y
  if n.position then
    x, y = n.position.x, n.position.y
    if not x and n.position.GetXY then x, y = n.position:GetXY() end
  end
  return { id = n.nodeID, n = n.name, m = onMap, x = x, y = y, f = n.faction, s = n.state }
end

local function AddNodes(geo, list, onMap)
  geo.taxi = geo.taxi or {}
  for _, n in ipairs(list or {}) do
    if n.name and n.position then
      local key = (n.nodeID or n.name) .. "@" .. onMap
      geo.taxi[key] = Node(n, onMap)
    end
  end
end

function G.Collect(force)
  local db = ns.db
  if not db or not C_Map then return end
  local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
  if not force and db.geo and db.geo.v == VERSION and db.geo.build == build then return end
  local geo = { v = VERSION, build = build, maps = {}, taxi = {} }
  for _, cont in ipairs(CONTINENTS) do
    local r = Rect(cont)
    if r then
      local info = C_Map.GetMapInfo(cont)
      r.n, r.t, r.p = info and info.name, info and info.mapType, info and info.parentMapID
      geo.maps[cont] = r
    end
    local ok, kids = pcall(C_Map.GetMapChildrenInfo, cont, nil, true)
    for _, info in ipairs(ok and kids or {}) do
      local rr = Rect(info.mapID)
      if rr then
        rr.n, rr.t, rr.p = info.name, info.mapType, info.parentMapID
        geo.maps[info.mapID] = rr
      end
    end
    if C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
      local ok2, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, cont)
      if ok2 then AddNodes(geo, nodes, cont) end
    end
  end
  -- keep nodes learned from flight maps you opened earlier
  if db.geo and db.geo.taxi then
    for k, v in pairs(db.geo.taxi) do if not geo.taxi[k] then geo.taxi[k] = v end end
  end
  db.geo = geo
end

-- A flight map is open: every node it shows, with whether you know it.
local function OnTaxiMap()
  local db = ns.db
  if not db or not db.geo then return end
  local m = GetTaxiMapID and GetTaxiMapID()
  if not (m and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes) then return end
  local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, m)
  if ok then AddNodes(db.geo, nodes, m) end
  -- the node you're standing at, for the flight-time record (Learn.lua)
  for _, n in ipairs(ok and nodes or {}) do
    if n.state == (Enum and Enum.FlightPathState and Enum.FlightPathState.Current or 0) then ns.taxiFromNode = n.name end
  end
end

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event)
  if event == "TAXIMAP_OPENED" then ns.Safe("Geo", OnTaxiMap) end
end)

ns.inits.Geo = function()
  pcall(f.RegisterEvent, f, "TAXIMAP_OPENED")
  -- a moment after login, so the map data is ready; a few hundred cheap calls, once per build
  C_Timer.After(5, function() ns.Safe("Geo", G.Collect) end)
end

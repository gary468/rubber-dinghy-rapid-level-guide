-- Rubber Dinghy - world map overlay (route lines, mob-area circles, numbered pins) and minimap pins.
-- Pins use Forever's quest-number circle (UI-QuestPoi-QuestNumber), the same art Blizzard's quest
-- map and ForeverDungeonJournal use. Minimap pins go through HereBeDragons, like Questie's.
local ADDON, ns = ...
local Map = {}
ns.Map = Map

local HBDP = LibStub and LibStub("HereBeDragons-Pins-2.0", true)

-- Questie draws its patrol lines at frame level 2015 on this client (map tiles sit below that).
local OVERLAY_LEVEL, PIN_LEVEL = 2016, 2030
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local POI_RING = { "UI-QuestPoi-QuestNumber" }
local POI_LIT = { "ui-questpoi-questnumber-supertracked", "UI-QuestPoi-QuestNumber-Pressed" }
local POI_GLOW = { "UI-QuestPoi-InnerGlow" }

-- Number colours on the pins: hand-in green, pick-up white, mob area gold.
local function KindColor(s)
  if s.area then return 1, 0.82, 0 end
  for _, a in ipairs(s.actions) do if a.kind == "turn" then return 0.2, 1, 0.2 end end
  return 1, 1, 1
end
Map.KindColor = KindColor

local overlay, mapPins, mapLines, mapAreas = nil, {}, {}, {}
local hlStop -- the stop clicked in the tracker, highlighted until the map closes
local route = ns.route

local function Canvas()
  local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
  if not canvas then return nil end
  if not overlay then
    overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
  end
  overlay:SetFrameLevel(OVERLAY_LEVEL)
  return overlay
end

local function CanvasScale()
  local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
  local s = sc and sc.GetCanvasScale and sc:GetCanvasScale()
  return (s and s > 0) and s or 1
end

-- Blizzard's own quest-objective areas (the blue "blobs" the map shows when you hover a quest), drawn
-- for every in-progress quest on the route. Same QuestPOIFrame, textures and alphas as Blizzard's
-- QuestBlobPinTemplate (NaowhForever's QuestAreaTint confirms these on Forever). Quests the game has
-- no area data for keep our orange circle instead.
local BLOB_FILL, BLOB_EDGE = "Interface\\WorldMap\\UI-QuestBlob-Inside", "Interface\\WorldMap\\UI-QuestBlob-Outside"
local blobFrame, blobOK
local function Blob()
  if blobOK == false then return nil end
  local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
  if not canvas then return nil end
  if not blobFrame then
    local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, canvas)
    if not ok or not f or not f.DrawBlob then blobOK = false; return nil end
    f:SetAllPoints(canvas)
    pcall(function()
      f:SetFillTexture(BLOB_FILL)
      f:SetBorderTexture(BLOB_EDGE)
      f:SetFillAlpha(128)
      f:SetBorderAlpha(192)
      f:SetBorderScalar(1.0)
    end)
    blobFrame, blobOK = f, true
  end
  blobFrame:SetFrameLevel(OVERLAY_LEVEL - 1) -- under our lines and pins, above the map tiles
  return blobFrame
end

local function QuestsWithAreas(mapID)
  local set = {}
  if C_QuestLog and C_QuestLog.GetQuestsOnMap then
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, mapID)
    if ok and list then
      for _, info in ipairs(list) do if info.questID then set[info.questID] = true end end
    end
  end
  return set
end

local function HideMap()
  for _, p in ipairs(mapPins) do p:Hide() end
  for _, l in ipairs(mapLines) do l:Hide() end
  for _, a in ipairs(mapAreas) do a:Hide() end
  if blobFrame then pcall(blobFrame.DrawNone, blobFrame) end
end

--- A numbered POI-style pin. Used on the world map and (smaller) on the minimap.
local function NewPin(parent, size)
  local p = CreateFrame("Button", nil, parent)
  p:SetSize(size, size)
  p.glow = p:CreateTexture(nil, "BACKGROUND", nil, -2)
  p.glow:SetPoint("CENTER")
  p.glow:SetSize(size * 1.9, size * 1.9)
  if not ns.SetAtlasOr(p.glow, POI_GLOW, CIRCLE) then p.glow:SetVertexColor(1, 1, 1, 0.8) end
  p.glow:Hide()
  p.ring = p:CreateTexture(nil, "BACKGROUND")
  p.ring:SetAllPoints()
  p.hasRing = ns.SetAtlasOr(p.ring, POI_RING, CIRCLE, 0.1, 0.1, 0.1, 0.95) ~= nil
  p.num = p:CreateFontString(nil, "OVERLAY", size >= 20 and "GameFontNormal" or "GameFontNormalSmall")
  p.num:SetPoint("CENTER", 0, 0)
  pcall(function()
    local ag = p.glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1); a:SetToAlpha(0.2); a:SetDuration(0.6)
    p.pulse = ag
  end)
  p:SetScript("OnEnter", function(self) if self.stop then ns.StopTooltip(self, self.stop, "ANCHOR_RIGHT") end end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return p
end

local function StylePin(p, s, lit)
  p.stop = s
  p.num:SetText(s.index)
  p.num:SetTextColor(KindColor(s))
  if lit then
    ns.SetAtlasOr(p.ring, POI_LIT, CIRCLE, 0.9, 0.7, 0.1, 1)
    p.glow:Show()
    if p.pulse then p.pulse:Play() end
  else
    if not ns.SetAtlasOr(p.ring, POI_RING, CIRCLE, 0.1, 0.1, 0.1, 0.95) then end
    p.glow:Hide()
    if p.pulse then p.pulse:Stop() end
  end
end

local function GetLine(i, canvas)
  local l = mapLines[i]
  if not l then
    if canvas.CreateLine then
      l = canvas:CreateLine(nil, "OVERLAY"); l.isLine = true
    else
      l = canvas:CreateTexture(nil, "OVERLAY"); l:SetTexture("Interface\\BUTTONS\\WHITE8X8")
    end
    mapLines[i] = l
  end
  return l
end

local function PlaceLine(l, canvas, x1, y1, x2, y2, thick, alpha)
  if l.isLine then
    l:SetThickness(thick)
    l:SetColorTexture(1, 0.82, 0, alpha)
    l:SetStartPoint("TOPLEFT", canvas, x1, y1)
    l:SetEndPoint("TOPLEFT", canvas, x2, y2)
  elseif DrawLine then
    DrawLine(l, canvas, x1, y1, x2, y2, thick, 1, "TOPLEFT")
    l:SetVertexColor(1, 0.82, 0, alpha)
  else
    return
  end
  l:Show()
end

local function GetArea(i, canvas)
  local a = mapAreas[i]
  if not a then
    a = canvas:CreateTexture(nil, "OVERLAY")
    a:SetTexture(CIRCLE)
    mapAreas[i] = a
  end
  return a
end

local function PlacePin(n, s, canvas, P, scale)
  local p = mapPins[n]
  if not p then p = NewPin(canvas, 24); mapPins[n] = p end
  local lit = (s == hlStop)
  StylePin(p, s, lit)
  -- Scaled against the zoom so it keeps one size on screen; anchor offsets are in its own units.
  p:SetScale((lit and 1.25 or 1) / scale)
  p:ClearAllPoints()
  local cx, cy = P(s.x, s.y)
  local k = scale / (lit and 1.25 or 1)
  p:SetPoint("CENTER", canvas, "TOPLEFT", cx * k, cy * k)
  p:SetFrameLevel(PIN_LEVEL + (lit and 5 or 0))
  p:Show()
end

local function Draw()
  HideMap()
  if not ns.db or ns.db.noMap then return end
  local canvas = Canvas()
  if not canvas or not WorldMapFrame:IsShown() then return end
  local cur = WorldMapFrame:GetMapID()
  local step = route.step
  local onStep = step and cur == step.map
  local hlHere = hlStop and hlStop.away and hlStop.map == cur
  if not onStep and not hlHere then return end
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  if not w or w == 0 then return end
  local scale = CanvasScale()
  local thick = 4 / scale
  local function P(x, y) return x / 100 * w, -y / 100 * h end

  local pinN = 0
  if hlHere then pinN = 1; PlacePin(pinN, hlStop, canvas, P, scale) end
  if not onStep then return end

  local li, ai, first = 0, 0, true
  local prevX, prevY
  if route.start then prevX, prevY = route.start[1], route.start[2] end
  local hasArea = QuestsWithAreas(cur)
  local bf = Blob()
  if bf then
    if bf.SetMapID then pcall(bf.SetMapID, bf, cur) end
    bf:Show()
  end
  for _, s in ipairs(route.stops) do
    if not s.away then
      if prevX then
        li = li + 1
        local x1, y1 = P(prevX, prevY)
        local x2, y2 = P(s.x, s.y)
        PlaceLine(GetLine(li, canvas), canvas, x1, y1, x2, y2, thick, first and 0.95 or 0.65)
      end
      first = false
      prevX, prevY = s.x, s.y
      local blobbed = false
      if s.area and bf then
        for _, a in ipairs(s.actions) do
          if a.kind == "do" and hasArea[a.row.id] then
            if pcall(bf.DrawBlob, bf, a.row.id, true) then blobbed = true end
          end
        end
      end
      if s.area and s.r and not blobbed then
        ai = ai + 1
        local a = GetArea(ai, canvas)
        a:SetSize(s.r * 2 / 100 * w, s.r * 2 / 100 * h)
        a:ClearAllPoints()
        local cx, cy = P(s.cx or s.x, s.cy or s.y) -- the whole area, not just the nearest spawn
        a:SetPoint("CENTER", canvas, "TOPLEFT", cx, cy)
        a:SetVertexColor(1, 0.45, 0, 0.3)
        a:Show()
      end
      pinN = pinN + 1
      PlacePin(pinN, s, canvas, P, scale)
    end
  end
end

local function SafeDraw() ns.Safe("Map", Draw) end

-- Like Questie: while the map is open, redraw when the zone, canvas size or zoom changes.
local dirty = true
local drawnMap, drawnW, drawnH, drawnScale
local function StartDriver()
  local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
  if not canvas then return end
  local driver = CreateFrame("Frame", nil, canvas)
  driver:SetScript("OnUpdate", function()
    local m = WorldMapFrame:GetMapID()
    local w, h = canvas:GetWidth(), canvas:GetHeight()
    local s = CanvasScale()
    if dirty or m ~= drawnMap or w ~= drawnW or h ~= drawnH
      or (drawnScale and math.abs(s / drawnScale - 1) > 0.1) then
      dirty, drawnMap, drawnW, drawnH, drawnScale = false, m, w, h, s
      SafeDraw()
    end
  end)
  driver:SetScript("OnHide", function() hlStop = nil; dirty = true end)
end

---------------------------------------------------------------------------
-- Minimap pins (HereBeDragons): the next stops, with stop 1 riding the minimap edge when far away.
---------------------------------------------------------------------------
local miniPins = {}
local MINI_MAX = 8
local function UpdateMinimap()
  if not HBDP then return end
  HBDP:RemoveAllMinimapIcons(Map)
  if ns.db.noMap then return end
  local n = 0
  for _, s in ipairs(route.stops) do
    if n >= MINI_MAX then break end
    n = n + 1
    local p = miniPins[n]
    if not p then p = NewPin(Minimap, 16); miniPins[n] = p end
    StylePin(p, s, false)
    HBDP:AddMinimapIconMap(Map, p, s.map, s.x / 100, s.y / 100, false, n == 1)
  end
end

---------------------------------------------------------------------------
-- Public: tracker click -> open the map on the stop's zone and highlight it. No waypoint is set.
---------------------------------------------------------------------------
function ns.ShowOnMap(s)
  if not s or not WorldMapFrame then return end
  if not WorldMapFrame:IsShown() then
    if InCombatLockdown and InCombatLockdown() then ns.Print("can't open the map in combat."); return end
    if OpenWorldMap then pcall(OpenWorldMap, s.map) elseif ToggleWorldMap then pcall(ToggleWorldMap) end
  end
  if WorldMapFrame.SetMapID and WorldMapFrame:GetMapID() ~= s.map then
    pcall(WorldMapFrame.SetMapID, WorldMapFrame, s.map)
  end
  hlStop = s
  dirty = true
end

ns.listeners.Map = function(r)
  route = r
  hlStop = nil
  dirty = true
  UpdateMinimap()
end

ns.inits.Map = StartDriver

ns.commands.map = function()
  ns.db.noMap = not ns.db.noMap
  ns.Print("map route " .. (ns.db.noMap and "off" or "on"))
  dirty = true
  ns.Safe("Minimap", UpdateMinimap)
end

ns.commands.mapdebug = function()
  local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
  local shownPins = 0
  for _, p in ipairs(mapPins) do if p:IsShown() then shownPins = shownPins + 1 end end
  ns.Print(("map open=%s mapID=%s stepMap=%s canvas=%s scale=%.2f pins=%d stops=%d HBD-Pins=%s quest areas=%s off=%s"):format(
    tostring(WorldMapFrame and WorldMapFrame:IsShown()), tostring(WorldMapFrame and WorldMapFrame:GetMapID()),
    tostring(route.step and route.step.map), tostring(canvas ~= nil), CanvasScale(), shownPins,
    #route.stops, tostring(HBDP ~= nil), tostring(blobOK), tostring(ns.db.noMap)))
end

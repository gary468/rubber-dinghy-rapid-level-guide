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
-- Quest areas in the route's own gold (our 16x16 fill/edge textures, the same format NaowhForever's
-- Quest Area Tint uses), drawn only for the next stops so the map reads as one route.
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"
local AREA_FILL, AREA_EDGE = MEDIA .. "area_fill", MEDIA .. "area_edge"
local blobFrame, blobOK
local function Blob()
  if blobOK == false then return nil end
  local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
  if not canvas then return nil end
  if not blobFrame then
    local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, canvas)
    if not ok or not f or not f.DrawBlob then blobOK = false; return nil end
    f:SetAllPoints(canvas)
    blobFrame, blobOK = f, true
  end
  -- Subtle on purpose: a light fill and a thin, soft edge.
  local alpha = math.floor((ns.db.areaAlpha or 0.2) * 255 + 0.5)
  pcall(function()
    blobFrame:SetFillTexture(AREA_FILL)
    blobFrame:SetBorderTexture(AREA_EDGE)
    blobFrame:SetFillAlpha(alpha)
    blobFrame:SetBorderAlpha(math.min(255, alpha * 2))
    blobFrame:SetBorderScalar(0.2) -- a thin rim, not Blizzard's thick glow
  end)
  blobFrame:SetFrameLevel(OVERLAY_LEVEL - 1) -- under our lines and pins, above the map tiles
  return blobFrame
end

-- The area of a quest you picked that ISN'T on the route: green (Blizzard's own quest-area look), so
-- gold always means "route" and green "your pick, not on the route".
local chosenBlob
local function ChosenBlob()
  if blobOK == false then return nil end
  local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
  if not canvas then return nil end
  if not chosenBlob then
    local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, canvas)
    if not ok or not f or not f.DrawBlob then return nil end
    f:SetAllPoints(canvas)
    pcall(function()
      f:SetFillTexture("Interface\\WorldMap\\UI-QuestBlob-Inside")
      f:SetBorderTexture("Interface\\WorldMap\\UI-QuestBlob-Outside")
      f:SetFillAlpha(110); f:SetBorderAlpha(200); f:SetBorderScalar(0.5)
    end)
    chosenBlob = f
  end
  chosenBlob:SetFrameLevel(OVERLAY_LEVEL - 2)
  return chosenBlob
end

-- Blizzard's own quest markers (the gold "..." / "?" circles and their blue areas) are hidden while
-- the route is on, so our numbered stops are the quest markers. Pin templates are found at runtime
-- (any map pin pool named like Quest...Pin / ...QuestBlob..., never quest offers or other addons'
-- pins); /rdr mapdebug lists what was found.
local suppressed = false
local function BlizzQuestTemplates()
  local list = {}
  local pools = WorldMapFrame and WorldMapFrame.pinPools
  if type(pools) == "table" then
    for name in pairs(pools) do
      if type(name) == "string" and (name:find("^Quest") or name:find("QuestBlob") or name:find("QuestPin"))
        and not name:find("Offer") and not name:find("HereBeDragons") then
        list[#list + 1] = name
      end
    end
  end
  return list
end
Map.BlizzQuestTemplates = BlizzQuestTemplates

-- Only the route's own quests swap Blizzard's markers for our numbered stops. Every other quest in
-- your log keeps its Blizzard marker and area, and so does the quest you've picked in the quest log
-- (or clicked under Other Quests), route or not.
local routeSet = {}
function Map.ChosenQuest()
  local id = (C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()) or 0
  if (not id or id == 0) and GetQuestLogSelection and GetQuestLogTitle then
    local idx = GetQuestLogSelection()
    if idx and idx > 0 then id = select(8, GetQuestLogTitle(idx)) end
  end
  if (not id or id == 0) and ns.mapFocusQuest then id = ns.mapFocusQuest end   -- clicked under Other Quests
  return id or 0
end

local function SuppressBlizzard()
  if not (WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate) then return end
  local on = ns.db and not ns.db.noMap and not ns.db.keepBlizzMap
  if on then
    local chosen = Map.ChosenQuest()
    for _, name in ipairs(BlizzQuestTemplates()) do
      for pin in WorldMapFrame:EnumeratePinsByTemplate(name) do
        local qid = pin.questID or pin.questId
        local hide
        -- only the quest you picked in the quest log keeps Blizzard's marker; the route's own
        -- quests have our numbered stops, and other quests stay out of the way
        -- Blizzard's areas are always hidden (route areas are ours, in gold; a chosen off-route quest
        -- gets ours in green). Its marker stays only for a quest you picked that isn't on the route.
        if qid then hide = (qid ~= chosen) or routeSet[qid]
        else hide = true end
        if hide and pin:IsShown() then pin:Hide() end
      end
    end
    suppressed = true
  elseif suppressed then
    suppressed = false
    if WorldMapFrame.RefreshAllDataProviders then pcall(WorldMapFrame.RefreshAllDataProviders, WorldMapFrame) end
  end
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

local otherPins = {}
local HideIcons   -- set below, with the quest icon layer
local function HideMap()
  for _, p in ipairs(otherPins) do p:Hide() end
  if HideIcons then HideIcons() end
  for _, p in ipairs(mapPins) do p:Hide() end
  for _, l in ipairs(mapLines) do l:Hide() end
  for _, a in ipairs(mapAreas) do a:Hide() end
  if blobFrame then pcall(blobFrame.DrawNone, blobFrame) end
  if chosenBlob then pcall(chosenBlob.DrawNone, chosenBlob) end
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
  p:SetScript("OnEnter", function(self)
    if not self.stop then return end
    ns.StopTooltip(self, self.stop, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.stop.area and "Click: show its kill area" or "Click: highlight this stop", 0.4, 0.8, 1)
    GameTooltip:Show()
  end)
  -- Like clicking a Blizzard quest marker: highlight this stop and show its kill area.
  p:SetScript("OnClick", function(self)
    if not self.stop then return end
    if parent == Minimap then ns.ShowOnMap(self.stop) else Map.Highlight(self.stop) end
  end)
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

-- Questie-style quest icons for everything that isn't a route stop (the route keeps its numbered gold
-- stops, line and areas on top):
--   "!"  quest givers with a quest you can pick up (faded when it's low level for you)
--   "?"  where to hand in a quest you've finished
--   dots every spawn of the mobs/objects a quest in your log needs
--   dashed patrol paths for quest givers, hand-in NPCs and quest mobs that walk
-- Hover: the quest and what to do there. Shift-click: hide that quest's icons (settings brings them
-- back). Click a quest-log icon: show Blizzard's marker and area for it.
local ICON_AVAIL = "Interface\\GossipFrame\\AvailableQuestIcon"
local ICON_TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon"
local iconPool, pathLines = {}, {}
local byGiverMap

local function GiverIndex()
  if byGiverMap then return byGiverMap end
  byGiverMap = {}
  for id, q in pairs(ns.quests or {}) do
    local g = q.g
    if g and g[2] and g[3] then
      byGiverMap[g[2]] = byGiverMap[g[2]] or {}
      table.insert(byGiverMap[g[2]], id)
    end
  end
  return byGiverMap
end

local function HideQuest(id)
  ns.db.hiddenQuests = ns.db.hiddenQuests or {}
  ns.db.hiddenQuests[id] = true
  local q = ns.quests[id]
  ns.Print(("hid %s's map icons. Settings > Map > \"Show hidden quests again\" brings them back."):format(q and q.n or "that quest"))
  if Map.MarkDirty then Map.MarkDirty() end
end

local function Icon(i, canvas)
  local p = iconPool[i]
  if p then return p end
  p = CreateFrame("Button", nil, canvas)
  p.tex = p:CreateTexture(nil, "ARTWORK")
  p.tex:SetAllPoints()
  p.edge = p:CreateTexture(nil, "BACKGROUND")
  p.edge:SetPoint("CENTER")
  p.edge:SetTexture(CIRCLE)
  p.edge:SetVertexColor(0, 0, 0, 0.85)
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p:SetScript("OnEnter", function(self)
    local q = self.qid and ns.quests[self.qid]
    if not q then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("%s |cff999999[%s]|r"):format(q.n, q.l or "?"), 1, 0.82, 0)
    if self.kind == "avail" then GameTooltip:AddLine("Pick up from " .. (q.g and q.g[1] or "?"), 1, 1, 1)
    elseif self.kind == "turnin" then GameTooltip:AddLine("Finished: hand in to " .. (q.t and q.t[1] or "?"), 0.2, 1, 0.2)
    else GameTooltip:AddLine((q.o and q.o[1]) or "Objective", 1, 1, 1) end
    GameTooltip:AddLine(self.onRoute and "On your route" or "Not on the route", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Shift-click: hide this quest's icons", 0.4, 0.8, 1)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p:SetScript("OnClick", function(self)
    if not self.qid then return end
    if IsShiftKeyDown and IsShiftKeyDown() then HideQuest(self.qid); return end
    if self.kind ~= "avail" and ns.ShowQuestOnMap then ns.ShowQuestOnMap(self.qid) end
  end)
  iconPool[i] = p
  return p
end

local function PathLine(i, canvas)
  local l = pathLines[i]
  if not l then
    if not canvas.CreateLine then return nil end
    l = canvas:CreateLine(nil, "OVERLAY")
    pathLines[i] = l
  end
  return l
end

HideIcons = function()
  for _, p in ipairs(iconPool) do p:Hide() end
  for _, l in ipairs(pathLines) do l:Hide() end
end

local function DrawOthers(canvas, cur)
  HideIcons()
  if ns.db.noOtherPins then return end
  local w, h = canvas:GetWidth(), canvas:GetHeight()
  if not w or w == 0 then return end
  local scale = CanvasScale()
  local level = UnitLevel("player") or 1
  local hidden = ns.db.hiddenQuests or {}
  local skip = ns.db.skip or {}
  local n, li, pathsDone = 0, 0, {}
  local function Place(qid, kind, x, y, size, r, g, b, a, onRoute)
    n = n + 1
    local p = Icon(n, canvas)
    p.qid, p.kind, p.onRoute = qid, kind, onRoute
    p:SetSize(size, size)
    p.edge:SetSize(size + 3, size + 3)
    if kind == "spawn" then
      p.tex:SetTexture(CIRCLE); p.tex:SetVertexColor(r, g, b, a); p.edge:Show()
    else
      p.tex:SetTexture(kind == "avail" and ICON_AVAIL or ICON_TURNIN)
      p.tex:SetVertexColor(1, 1, 1, a)
      if p.tex.SetDesaturated then p.tex:SetDesaturated(r == 0) end
      p.edge:Hide()
    end
    p:SetScale(1 / scale)
    p:ClearAllPoints()
    p:SetPoint("CENTER", canvas, "TOPLEFT", x / 100 * w * scale, -y / 100 * h * scale)
    p:SetFrameLevel(PIN_LEVEL - (kind == "spawn" and 8 or 4))
    p:Show()
  end
  local function Path(npcId, gold)
    if not npcId or pathsDone[npcId] or not ns.paths then return end
    pathsDone[npcId] = true
    local pth = ns.paths[npcId]
    if not pth or pth[1] ~= cur then return end
    local c = pth[2]
    for k = 1, #c - 3, 2 do
      li = li + 1
      local l = PathLine(li, canvas)
      if not l then return end
      l:SetThickness(2 / scale)
      if gold then l:SetColorTexture(1, 0.82, 0, 0.55) else l:SetColorTexture(1, 1, 1, 0.45) end
      l:SetStartPoint("TOPLEFT", canvas, c[k] / 100 * w, -c[k + 1] / 100 * h)
      l:SetEndPoint("TOPLEFT", canvas, c[k + 2] / 100 * w, -c[k + 3] / 100 * h)
      l:Show()
    end
  end

  -- quests in your log that aren't route stops: hand-in "?" or their mobs' spawns
  local inLog = {}
  for _, e in ipairs(ns.QuestLog()) do
    inLog[e.id] = true
    local q = ns.quests[e.id]
    if q and not routeSet[e.id] and not hidden[e.id] and not skip[e.id] then
      if ns.IsReady(e.id) then
        if q.t and q.t[2] == cur and q.t[3] then Place(e.id, "turnin", q.t[3], q.t[4], 18, 1, 1, 1, 1, false) end
        if q.tp then Path(q.tp, false) end
      elseif q.o and q.o[2] == cur then
        local pts = q.o[6]
        if pts and #pts >= 2 then
          for k = 1, #pts - 1, 2 do Place(e.id, "spawn", pts[k], pts[k + 1], 8, 1, 1, 1, 0.9, false) end
        elseif q.o[3] then Place(e.id, "spawn", q.o[3], q.o[4], 10, 1, 1, 1, 0.9, false) end
        for _, nid in ipairs(q.op or {}) do Path(nid, false) end
      end
    end
  end
  -- quests you can pick up here: "!" at the giver (faded when it's well below your level)
  for _, id in ipairs(GiverIndex()[cur] or {}) do
    if not inLog[id] and not routeSet[id] and not hidden[id] and not skip[id] then
      local q = ns.quests[id]
      if ns.Status(id, level) == ns.S.OPEN then
        local low = (q.l or 0) < level - 5
        Place(id, "avail", q.g[3], q.g[4], 18, low and 0 or 1, 1, 1, low and 0.6 or 1, false)
        if q.gp then Path(q.gp, false) end
      end
    end
  end
  -- patrol paths for the route's own NPCs and mobs, in gold
  for _, s in ipairs((route and route.stops) or {}) do
    if s.map == cur then
      for _, a in ipairs(s.actions or {}) do
        local q = a.row.q
        if q then
          if a.kind == "get" and q.gp then Path(q.gp, true)
          elseif a.kind == "turn" and q.tp then Path(q.tp, true)
          elseif q.op then for _, nid in ipairs(q.op) do Path(nid, true) end end
        end
      end
    end
  end
end
local function Draw()
  HideMap()
  if not ns.db or ns.db.noMap then return end
  local canvas = Canvas()
  if not canvas or not WorldMapFrame:IsShown() then return end
  local cur = WorldMapFrame:GetMapID()
  ns.Safe("MapOthers", DrawOthers, canvas, cur)
  -- the quest you picked in the quest log, if it's not on the route: its area in green
  local chosen = Map.ChosenQuest()
  if chosen and chosen ~= 0 and not routeSet[chosen] and QuestsWithAreas(cur)[chosen] then
    local cb = ChosenBlob()
    if cb then
      if cb.SetMapID then pcall(cb.SetMapID, cb, cur) end
      cb:Show()
      pcall(cb.DrawBlob, cb, chosen, true)
    end
  end
  -- Draw whichever of the route's stops are on the map you're looking at (a get-ready route spans
  -- several zones; its stops in another zone show when you open that zone).
  local onStep = false
  for _, s in ipairs(route.stops or {}) do if s.map == cur then onStep = true; break end end
  local hlHere = hlStop and hlStop.map == cur and not onStep
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
  local pmNow, pxNow, pyNow = ns.PlayerPos()
  if pmNow == cur and pxNow then prevX, prevY = pxNow, pyNow end   -- the line starts at you
  local hasArea = QuestsWithAreas(cur)
  local mode = ns.db.areaMode or "next"
  local areasLeft = (mode == "all") and 99 or (mode == "off" and 0) or 1
  local bf = areasLeft > 0 and Blob() or nil
  if bf then
    if bf.SetMapID then pcall(bf.SetMapID, bf, cur) end
    bf:Show()
  end
  for _, s in ipairs(route.stops) do
    if s.map == cur then
      if prevX then
        li = li + 1
        local x1, y1 = P(prevX, prevY)
        local x2, y2 = P(s.x, s.y)
        PlaceLine(GetLine(li, canvas), canvas, x1, y1, x2, y2, thick, first and 0.95 or 0.65)
      end
      first = false
      prevX, prevY = s.x, s.y
      -- The next stop's area, plus the area of a stop you clicked (even if areas are off).
      if s.area and (areasLeft > 0 or s == hlStop) then
        if s ~= hlStop then areasLeft = areasLeft - 1 end
        bf = bf or Blob()
        if bf and bf.SetMapID then pcall(bf.SetMapID, bf, cur) end
        if bf then bf:Show() end
        local blobbed = false
        if bf then
          for _, a in ipairs(s.actions) do
            if a.kind == "do" and hasArea[a.row.id] then
              if pcall(bf.DrawBlob, bf, a.row.id, true) then blobbed = true end
            end
          end
        end
        if s.r and not blobbed then
          ai = ai + 1
          local a = GetArea(ai, canvas)
          a:SetSize(s.r * 2 / 100 * w, s.r * 2 / 100 * h)
          a:ClearAllPoints()
          local cx, cy = P(s.cx or s.x, s.cy or s.y) -- the whole area, not just the nearest spawn
          a:SetPoint("CENTER", canvas, "TOPLEFT", cx, cy)
          a:SetVertexColor(1, 0.78, 0.16, (ns.db.areaAlpha or 0.2) * 0.9)
          a:Show()
        end
      end
      pinN = pinN + 1
      PlacePin(pinN, s, canvas, P, scale)
    end
  end
end

local function SafeDraw() ns.Safe("Map", Draw) end

-- Like Questie: while the map is open, redraw when the zone, canvas size or zoom changes.
local dirty = true
function Map.MarkDirty() dirty = true end
local drawnMap, drawnW, drawnH, drawnScale
local function StartDriver()
  local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
  if not canvas then return end
  local driver = CreateFrame("Frame", nil, canvas)
  local sinceSuppress = 0
  driver:SetScript("OnUpdate", function(_, elapsed)
    -- Blizzard re-acquires its quest pins on its own schedule; keep them hidden.
    sinceSuppress = sinceSuppress + (elapsed or 0)
    if sinceSuppress > 0.2 then sinceSuppress = 0; ns.Safe("MapSuppress", SuppressBlizzard) end
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
  if ns.db.noMap or ns.db.noMiniPins then return end
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
--- Highlight a stop on the open map (pin click) and show its kill area.
function Map.Highlight(s)
  hlStop = (hlStop ~= s) and s or nil -- clicking it again turns the highlight off
  dirty = true
end

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
  routeSet = {}
  for _, s in ipairs(r.stops or {}) do
    for _, a in ipairs(s.actions or {}) do routeSet[a.row.id] = true end
  end
  -- Keep a highlight across route updates (the stops are rebuilt): same place, same name.
  if hlStop then
    local keep
    for _, s in ipairs(r.stops) do
      if s.map == hlStop.map and s.name == hlStop.name then keep = s; break end
    end
    hlStop = keep
  end
  dirty = true
  UpdateMinimap()
end

--- Open the world map on a quest from your log (on the route or not): select it, so Blizzard draws
--- its marker and area, and show the map where it's handed in (when finished) or done.
function ns.ShowQuestOnMap(id)
  if not id or not WorldMapFrame then return end
  if InCombatLockdown and InCombatLockdown() then ns.Print("can't open the map in combat."); return end
  ns.mapFocusQuest = id
  if C_QuestLog and C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, id) end
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then pcall(C_SuperTrack.SetSuperTrackedQuestID, id) end
  local q = ns.quests and ns.quests[id]
  local loc = q and ((ns.IsReady and ns.IsReady(id) and q.t) or q.o or q.t or q.g)
  local m = loc and loc[2]
  if (not m or m == 0) and GetQuestUiMapID then
    local ok, mm = pcall(GetQuestUiMapID, id); if ok then m = mm end
  end
  if not WorldMapFrame:IsShown() then
    if OpenWorldMap then pcall(OpenWorldMap, m) elseif ToggleWorldMap then pcall(ToggleWorldMap) end
  end
  if m and m > 0 and WorldMapFrame.SetMapID then pcall(WorldMapFrame.SetMapID, WorldMapFrame, m) end
  if WorldMapFrame.RefreshAllDataProviders then pcall(WorldMapFrame.RefreshAllDataProviders, WorldMapFrame) end
  dirty = true
end

ns.inits.Map = StartDriver

--- Re-apply map settings (called by the settings window and /rdr map).
function Map.Refresh()
  dirty = true
  ns.Safe("Minimap", UpdateMinimap)
  ns.Safe("MapSuppress", SuppressBlizzard)
end

ns.commands.map = function()
  ns.db.noMap = not ns.db.noMap
  ns.Print("map route " .. (ns.db.noMap and "off - Blizzard's quest markers are back" or "on"))
  Map.Refresh()
end

ns.commands.mapdebug = function()
  local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
  local shownPins = 0
  for _, p in ipairs(mapPins) do if p:IsShown() then shownPins = shownPins + 1 end end
  ns.Print(("map open=%s mapID=%s stepMap=%s canvas=%s scale=%.2f pins=%d stops=%d HBD-Pins=%s quest areas=%s off=%s"):format(
    tostring(WorldMapFrame and WorldMapFrame:IsShown()), tostring(WorldMapFrame and WorldMapFrame:GetMapID()),
    tostring(route.step and route.step.map), tostring(canvas ~= nil), CanvasScale(), shownPins,
    #route.stops, tostring(HBDP ~= nil), tostring(blobOK), tostring(ns.db.noMap)))
  local t = BlizzQuestTemplates()
  ns.Print("Blizzard quest pin types hidden while the route is on: " .. (#t > 0 and table.concat(t, ", ") or "none found"))
end

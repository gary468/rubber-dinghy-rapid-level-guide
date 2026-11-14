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
local BuildHoverAreas   -- defined with the hover code below Draw
-- The game always has some quest "selected" (often just the first in your log), so a selection only
-- counts once it changes from the one you logged in with - i.e. you clicked a quest.
local selBaseline, selPicked
function Map.ChosenQuest()
  if ns.mapFocusQuest then return ns.mapFocusQuest end   -- clicked under Other Quests
  local id = (C_QuestLog and C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()) or 0
  if (not id or id == 0) and GetQuestLogSelection and GetQuestLogTitle then
    local idx = GetQuestLogSelection()
    if idx and idx > 0 then id = select(8, GetQuestLogTitle(idx)) end
  end
  id = id or 0
  if selBaseline == nil then selBaseline = id end
  if id ~= selBaseline then selPicked = id; selBaseline = -1 end
  return (selPicked == id) and id or 0
end

local function SuppressBlizzard()
  if not (WorldMapFrame and WorldMapFrame.EnumeratePinsByTemplate) then return end
  local on = ns.db and not ns.db.noMap and not ns.db.keepBlizzMap
  if on then
    for _, name in ipairs(BlizzQuestTemplates()) do
      for pin in WorldMapFrame:EnumeratePinsByTemplate(name) do
        -- All of Blizzard's quest markers and areas go: route quests have our numbered stops, other
        -- quests our own "!", "?" and spawn icons, and the quest you pick in the log its area in
        -- green. (The game always has some quest "selected", so keeping that one's marker left a
        -- stray Blizzard "?" on the map.)
        if pin:IsShown() then pin:Hide() end
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

local OUTLINE = { { -1.5, 0 }, { 1.5, 0 }, { 0, -1.5 }, { 0, 1.5 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
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
  -- Outline for "!" and "?": eight black copies of the icon just around it, so it reads on any map.
  p.outline = {}
  for k, o in ipairs(OUTLINE) do
    local t = p:CreateTexture(nil, "BORDER")
    t:SetPoint("TOPLEFT", o[1], o[2]); t:SetPoint("BOTTOMRIGHT", o[1], o[2])
    t:SetVertexColor(0, 0, 0, 1)
    p.outline[k] = t
  end
  p:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  p:SetScript("OnEnter", function(self)
    local q = self.qid and ns.quests[self.qid]
    if not q then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("%s |cff999999[%s]|r"):format(q.n, q.l or "?"), 1, 0.82, 0)
    if self.kind == "avail" then GameTooltip:AddLine("Pick up from " .. (q.g and q.g[1] or "?"), 1, 1, 1)
    elseif self.kind == "turnin" then GameTooltip:AddLine("Finished: hand in to " .. (q.t and q.t[1] or "?"), 0.2, 1, 0.2)
    else
      GameTooltip:AddLine((q.o and q.o[1]) or "Objective", 1, 1, 1)
      for _, o in ipairs(ns.Objectives(self.qid)) do
        if o.done then GameTooltip:AddLine("  " .. o.text, 0.4, 1, 0.4) else GameTooltip:AddLine("  " .. ns.ObjText(o), 1, 1, 1) end
      end
    end
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
  -- Route stops on this map: a "!" or "?" that would sit under a numbered stop isn't drawn (it
  -- would hide the number); the stop's tooltip lists it under "Also here" instead.
  local stopsHere = {}
  for _, st in ipairs((route and route.stops) or {}) do
    st.alsoHere = nil
    if st.map == cur and st.x and st.y then stopsHere[#stopsHere + 1] = st end
  end
  local NEAR = 2.2   -- map % (a stop marker is about this wide at normal zoom)
  local function UnderStop(qid, kind, x, y)
    for _, st in ipairs(stopsHere) do
      if math.abs(st.x - x) < NEAR and math.abs(st.y - y) < NEAR then
        st.alsoHere = st.alsoHere or {}
        st.alsoHere[#st.alsoHere + 1] = { id = qid, kind = kind }
        return true
      end
    end
    return false
  end
  local function Place(qid, kind, x, y, size, r, g, b, a, onRoute)
    if kind ~= "spawn" and UnderStop(qid, kind, x, y) then return end
    n = n + 1
    local p = Icon(n, canvas)
    p.qid, p.kind, p.onRoute = qid, kind, onRoute
    p:SetSize(size, size)
    p.edge:SetSize(size + 3, size + 3)
    if kind == "spawn" then
      p.tex:SetTexture(CIRCLE); p.tex:SetVertexColor(r, g, b, a); p.edge:Show()
      for _, t in ipairs(p.outline) do t:Hide() end
    else
      local tex = kind == "avail" and ICON_AVAIL or ICON_TURNIN
      p.tex:SetTexture(tex)
      p.tex:SetVertexColor(1, 1, 1, a)
      if p.tex.SetDesaturated then p.tex:SetDesaturated(r == 0) end
      p.edge:Hide()
      for _, t in ipairs(p.outline) do
        t:SetTexture(tex); t:SetVertexColor(0, 0, 0, a); t:Show()
      end
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
        if q.t and q.t[2] == cur and q.t[3] then Place(e.id, "turnin", q.t[3], q.t[4], 20, 1, 1, 1, 1, false) end
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
        Place(id, "avail", q.g[3], q.g[4], 20, low and 0 or 1, 1, 1, low and 0.6 or 1, false)
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
  ns.Safe("MapHover", BuildHoverAreas, cur)
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

---------------------------------------------------------------------------
-- Hovering a mob area (ours, Blizzard's or another addon's tint): which quest it's for and your
-- progress. Areas come from the quest data (spawn points and area centre), rebuilt when the map
-- redraws; hovering only tests those points, so it costs nothing per frame but a few sums.
---------------------------------------------------------------------------
local hoverAreas, hoverKey, hoverAt = {}, nil, 0
local HOVER_PT = 3.0     -- map % around a spawn point
BuildHoverAreas = function(cur)
  hoverAreas = {}
  for _, e in ipairs(ns.QuestLog()) do
    local q = ns.quests[e.id]
    if q and q.o and q.o[2] == cur and not ns.IsReady(e.id) then
      hoverAreas[#hoverAreas + 1] = { id = e.id, x = q.o[3], y = q.o[4], r = q.o[5], pts = q.o[6], title = e.title }
    end
  end
end

local function HoverOff()
  if hoverKey then
    hoverKey = nil
    if GameTooltip:GetOwner() == WorldMapFrame.ScrollContainer then GameTooltip:Hide() end
  end
end

local function MouseFocus()
  if GetMouseFoci then local f = GetMouseFoci(); return f and f[1] end
  if GetMouseFocus then return GetMouseFocus() end
end

local function AreaHover()
  local sc = WorldMapFrame and WorldMapFrame.ScrollContainer
  if ns.db.noMap or #hoverAreas == 0 or not (sc and sc.GetNormalizedCursorPosition and sc:IsMouseOver()) then return HoverOff() end
  -- over one of our pins/icons (they have their own tooltip) or any button: leave it to them
  local focus = MouseFocus()
  if focus and focus ~= sc and focus.GetObjectType and focus:GetObjectType() == "Button" then return HoverOff() end
  local cx, cy = sc:GetNormalizedCursorPosition()
  if not cx then return HoverOff() end
  cx, cy = cx * 100, cy * 100
  local hits, key = {}, ""
  for _, a in ipairs(hoverAreas) do
    local hit = false
    if a.x and a.y then
      local rr = math.max(a.r or 0, 2)
      hit = (cx - a.x) ^ 2 + (cy - a.y) ^ 2 <= rr * rr
    end
    if not hit and a.pts then
      for k = 1, #a.pts - 1, 2 do
        if math.abs(a.pts[k] - cx) < HOVER_PT and math.abs(a.pts[k + 1] - cy) < HOVER_PT then hit = true; break end
      end
    end
    if hit then hits[#hits + 1] = a; key = key .. a.id .. "," end
  end
  if #hits == 0 then return HoverOff() end
  -- same quests as last time: refresh the progress once a second, not every frame
  local now = GetTime()
  if key == hoverKey and now - hoverAt < 1 then return end
  hoverKey, hoverAt = key, now
  GameTooltip:SetOwner(sc, "ANCHOR_CURSOR")
  for i, a in ipairs(hits) do
    if i > 4 then GameTooltip:AddLine(("+ %d more"):format(#hits - 4), 0.6, 0.6, 0.6); break end
    local q = ns.quests[a.id]
    GameTooltip:AddLine(("%s |cff999999[%s]|r"):format(q.n or a.title or "?", q.l or "?"), 1, 0.82, 0)
    GameTooltip:AddLine(routeSet[a.id] and "On your route" or "Not on the route", 0.6, 0.6, 0.6)
    local objs = ns.Objectives(a.id)
    if #objs == 0 and q.o[1] then GameTooltip:AddLine(q.o[1], 1, 1, 1) end
    for _, o in ipairs(objs) do
      if o.done then GameTooltip:AddLine("  " .. o.text, 0.4, 1, 0.4) else GameTooltip:AddLine("  " .. ns.ObjText(o), 1, 1, 1) end
    end
  end
  GameTooltip:Show()
end

-- Like Questie: while the map is open, redraw when the zone, canvas size or zoom changes.
local dirty = true
function Map.MarkDirty() dirty = true end
local drawnMap, drawnW, drawnH, drawnScale
local function StartDriver()
  local canvas = WorldMapFrame and WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
  if not canvas then return end
  local driver = CreateFrame("Frame", nil, canvas)
  local sinceSuppress, sinceHover = 0, 0
  driver:SetScript("OnUpdate", function(_, elapsed)
    sinceHover = sinceHover + (elapsed or 0)
    if sinceHover > 0.1 then sinceHover = 0; ns.Safe("MapHover", AreaHover) end
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
  driver:SetScript("OnHide", function() hlStop = nil; dirty = true; HoverOff() end)
end

---------------------------------------------------------------------------
-- Minimap pins (HereBeDragons): the next stops, with stop 1 riding the minimap edge when far away.
---------------------------------------------------------------------------
local miniPins, miniIcons = {}, {}
local MINI_MAX = 8          -- numbered stops
local MINI_ICONS = 60       -- "!", "?" and mob dots, nearest first
local MINI_RANGE = 12       -- map % around you worth putting on the minimap

-- Blizzard's own minimap quest markers (the gold edge arrow for a tracked quest and its shaded
-- areas) are hidden while the route is on, like on the world map. They come back after a /reload
-- once "Show the route on the map and minimap" is off.
local BLANK = MEDIA .. "blank"
local miniSuppressed = false
local function SuppressMinimap()
  if not Minimap or ns.db.noMap or ns.db.keepBlizzMap then return end
  pcall(function()
    if Minimap.SetPOIArrowTexture then Minimap:SetPOIArrowTexture(BLANK) end
    if Minimap.SetQuestBlobInsideAlpha then Minimap:SetQuestBlobInsideAlpha(0) end
    if Minimap.SetQuestBlobOutsideAlpha then Minimap:SetQuestBlobOutsideAlpha(0) end
    if Minimap.SetQuestBlobRingAlpha then Minimap:SetQuestBlobRingAlpha(0) end
  end)
  miniSuppressed = true
end

local function MiniIcon(i)
  local p = miniIcons[i]
  if p then return p end
  p = CreateFrame("Button", nil, Minimap)
  p.tex = p:CreateTexture(nil, "ARTWORK"); p.tex:SetAllPoints()
  p.outline = {}
  for k, o in ipairs(OUTLINE) do
    local t = p:CreateTexture(nil, "BORDER")
    t:SetPoint("TOPLEFT", o[1], o[2]); t:SetPoint("BOTTOMRIGHT", o[1], o[2])
    p.outline[k] = t
  end
  p:SetScript("OnEnter", function(self)
    local q = self.qid and ns.quests[self.qid]
    if not q then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(("%s |cff999999[%s]|r"):format(q.n, q.l or "?"), 1, 0.82, 0)
    if self.kind == "avail" then GameTooltip:AddLine("Pick up from " .. (q.g and q.g[1] or "?"), 1, 1, 1)
    elseif self.kind == "turnin" then GameTooltip:AddLine("Finished: hand in to " .. (q.t and q.t[1] or "?"), 0.2, 1, 0.2)
    else
      GameTooltip:AddLine((q.o and q.o[1]) or "Objective", 1, 1, 1)
      for _, o in ipairs(ns.Objectives(self.qid)) do
        if o.done then GameTooltip:AddLine("  " .. o.text, 0.4, 1, 0.4) else GameTooltip:AddLine("  " .. ns.ObjText(o), 1, 1, 1) end
      end
    end
    GameTooltip:AddLine("Not on the route", 0.6, 0.6, 0.6)
    GameTooltip:Show()
  end)
  p:SetScript("OnLeave", function() GameTooltip:Hide() end)
  miniIcons[i] = p
  return p
end

local miniStops, MiniStops, MiniHide = {}   -- minimap route line/areas (defined below)
local function UpdateMinimap()
  if not HBDP then return end
  HBDP:RemoveAllMinimapIcons(Map)
  if ns.db.noMap or ns.db.noMiniPins then miniStops = {}; MiniHide(); return end
  SuppressMinimap()
  MiniStops()
  -- the route's next stops, numbered (stop 1 rides the edge when it's off the minimap)
  local n = 0
  local stopAt = {}
  for _, s in ipairs(route.stops) do
    if n >= MINI_MAX then break end
    n = n + 1
    local p = miniPins[n]
    if not p then p = NewPin(Minimap, 20); miniPins[n] = p end
    p:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    StylePin(p, s, false)
    HBDP:AddMinimapIconMap(Map, p, s.map, s.x / 100, s.y / 100, false, n == 1)
    stopAt[#stopAt + 1] = s
  end
  -- other quests near you, like the world map's icons: "!" to pick up, "?" to hand in, mob dots
  if ns.db.noOtherPins then return end
  local pm = ns.HerePos and ns.HerePos()
  if not pm then return end
  local px, py
  if C_Map and C_Map.GetPlayerMapPosition then
    local pos = C_Map.GetPlayerMapPosition(pm, "player")
    if pos then px, py = pos:GetXY(); px, py = px * 100, py * 100 end
  end
  if not px then return end
  local level = UnitLevel("player") or 1
  local hidden, skip = ns.db.hiddenQuests or {}, ns.db.skip or {}
  local cand = {}
  local function Add(qid, kind, x, y)
    if not x or not y then return end
    local d = (x - px) ^ 2 + (y - py) ^ 2
    if d > MINI_RANGE * MINI_RANGE then return end
    if kind ~= "spawn" then
      for _, s in ipairs(stopAt) do   -- never under a numbered stop
        if s.map == pm and math.abs(s.x - x) < 1 and math.abs(s.y - y) < 1 then return end
      end
    end
    cand[#cand + 1] = { qid = qid, kind = kind, x = x, y = y, d = d }
  end
  local inLog = {}
  for _, e in ipairs(ns.QuestLog()) do
    inLog[e.id] = true
    local q = ns.quests[e.id]
    if q and not routeSet[e.id] and not hidden[e.id] and not skip[e.id] then
      if ns.IsReady(e.id) then
        if q.t and q.t[2] == pm then Add(e.id, "turnin", q.t[3], q.t[4]) end
      elseif q.o and q.o[2] == pm then
        local pts = q.o[6]
        if pts and #pts >= 2 then for k = 1, #pts - 1, 2 do Add(e.id, "spawn", pts[k], pts[k + 1]) end
        else Add(e.id, "spawn", q.o[3], q.o[4]) end
      end
    end
  end
  for _, id in ipairs(GiverIndex()[pm] or {}) do
    if not inLog[id] and not routeSet[id] and not hidden[id] and not skip[id] and ns.Status(id, level) == ns.S.OPEN then
      local q = ns.quests[id]
      Add(id, "avail", q.g[3], q.g[4])
    end
  end
  table.sort(cand, function(a, b)
    if (a.kind == "spawn") ~= (b.kind == "spawn") then return b.kind == "spawn" end   -- ! and ? first
    return a.d < b.d
  end)
  for i = 1, math.min(#cand, MINI_ICONS) do
    local c = cand[i]
    local p = MiniIcon(i)
    p.qid, p.kind = c.qid, c.kind
    p:SetFrameLevel(Minimap:GetFrameLevel() + (c.kind == "spawn" and 4 or 6))
    if c.kind == "spawn" then
      p:SetSize(7, 7)
      p.tex:SetTexture(CIRCLE); p.tex:SetVertexColor(1, 1, 1, 0.9)
      for k, t in ipairs(p.outline) do
        t:SetTexture(CIRCLE); t:SetVertexColor(0, 0, 0, 0.85)
        if k > 4 then t:Hide() else t:Show() end
      end
    else
      local tex = c.kind == "avail" and ICON_AVAIL or ICON_TURNIN
      local low = c.kind == "avail" and (ns.quests[c.qid].l or 0) < level - 5
      p:SetSize(14, 14)
      p.tex:SetTexture(tex); p.tex:SetVertexColor(1, 1, 1, low and 0.6 or 1)
      if p.tex.SetDesaturated then p.tex:SetDesaturated(low) end
      for _, t in ipairs(p.outline) do t:SetTexture(tex); t:SetVertexColor(0, 0, 0, low and 0.6 or 1); t:Show() end
    end
    HBDP:AddMinimapIconMap(Map, p, pm, c.x / 100, c.y / 100, false, false)
  end
end
Map.UpdateMinimap = UpdateMinimap

---------------------------------------------------------------------------
-- Minimap route line and kill areas, like the world map: a gold line from you through the next
-- stops, and the gold areas of the stops (per "Quest areas" in settings). Same maths HereBeDragons
-- uses for minimap pins (world yards -> minimap pixels), clipped to the minimap.
---------------------------------------------------------------------------
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local MINI_SIZE = {
  indoor = { [0] = 300, 240, 180, 120, 80, 50 },
  outdoor = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 },
}
local miniBox, miniMask, miniLines, miniAreas = nil, nil, {}, {}
-- miniStops: { wx, wy, inst, ryd (area radius in yards) or nil }

local function MiniRadius()
  if C_Minimap and C_Minimap.GetViewRadius then return C_Minimap.GetViewRadius() end
  local zoom = Minimap:GetZoom() or 0
  local indoors = (GetCVar and tonumber(GetCVar("minimapZoom")) == zoom) and "outdoor" or "indoor"
  return (MINI_SIZE[indoors][zoom] or 466) / 2
end

local function MiniBox()
  if miniBox then return miniBox end
  miniBox = CreateFrame("Frame", nil, Minimap)
  miniBox:SetAllPoints(Minimap)
  if miniBox.SetClipsChildren then miniBox:SetClipsChildren(true) end
  local shape = GetMinimapShape and GetMinimapShape()
  if (not shape or shape == "ROUND") and miniBox.CreateMaskTexture then
    miniMask = miniBox:CreateMaskTexture()
    if miniMask then
      miniMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      miniMask:SetAllPoints(miniBox)
    end
  end
  return miniBox
end

local function Masked(t)
  if miniMask and t.AddMaskTexture then pcall(t.AddMaskTexture, t, miniMask) end
  return t
end

MiniHide = function()
  for _, l in ipairs(miniLines) do l:Hide() end
  for _, a in ipairs(miniAreas) do a:Hide() end
end

-- Where the next stops are in world yards, worked out once per route update.
MiniStops = function()
  miniStops = {}
  if not HBD then return end
  local mode = ns.db.areaMode or "next"
  local areasLeft = (mode == "all") and 99 or (mode == "off" and 0) or 1
  local withArea = {}
  for i, s in ipairs(route.stops or {}) do
    if i > MINI_MAX then break end
    local wx, wy, inst = HBD:GetWorldCoordinatesFromZone(s.x / 100, s.y / 100, s.map)
    if wx then
      local st = { wx = wx, wy = wy, inst = inst, map = s.map }
      -- the same areas as the world map: Blizzard's shapes where the game has them, else a circle
      -- around the whole area (its centre, not the nearest spawn)
      if s.area and areasLeft > 0 then
        areasLeft = areasLeft - 1
        withArea[s.map] = withArea[s.map] or QuestsWithAreas(s.map)
        for _, a in ipairs(s.actions) do
          if a.kind == "do" and withArea[s.map][a.row.id] then
            st.blobs = st.blobs or {}
            st.blobs[#st.blobs + 1] = a.row.id
          end
        end
        if not st.blobs and s.r then
          local w, h
          if HBD.GetZoneSize then w, h = HBD:GetZoneSize(s.map) end
          local cwx, cwy = HBD:GetWorldCoordinatesFromZone((s.cx or s.x) / 100, (s.cy or s.y) / 100, s.map)
          if w and w > 0 and cwx then st.ryd, st.cwx, st.cwy = s.r / 100 * (w + (h or w)) / 2, cwx, cwy end
        end
      end
      miniStops[#miniStops + 1] = st
    end
  end
end

-- Blizzard's quest-area shapes on the minimap: a QuestPOIFrame the size of the whole zone, placed
-- so the zone lines up with the minimap (the world map uses the same frame type over its canvas).
local miniBlob, miniBlobOK, miniBlobKey, miniBlobW
local function MiniBlob(box)
  if miniBlobOK == false then return nil end
  if not miniBlob then
    local ok, f = pcall(CreateFrame, "QuestPOIFrame", nil, box)
    if not ok or not f or not f.DrawBlob then miniBlobOK = false; return nil end
    miniBlob, miniBlobOK = f, true
  end
  local alpha = math.floor(math.min(0.6, (ns.db.areaAlpha or 0.2) * 1.2) * 255 + 0.5)
  pcall(function()
    miniBlob:SetFillTexture(AREA_FILL)
    miniBlob:SetBorderTexture(AREA_EDGE)
    miniBlob:SetFillAlpha(alpha)
    miniBlob:SetBorderAlpha(math.min(255, alpha * 2))
    miniBlob:SetBorderScalar(0.2)
  end)
  return miniBlob
end

local function MiniDraw()
  MiniHide()
  if not HBD or #miniStops == 0 or ns.db.noMap or ns.db.noMiniPins then
    if miniBlob then miniBlob:Hide(); miniBlobKey = nil end
    return
  end
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  if not px then return end
  local box = MiniBox()
  box:SetFrameLevel(Minimap:GetFrameLevel() + 2)
  local R = MiniRadius()
  local hw, hh = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
  if not R or R <= 0 or hw <= 0 then return end
  local sinf, cosf
  if GetCVar and GetCVar("rotateMinimap") == "1" then
    local f = GetPlayerFacing and GetPlayerFacing()
    if not f then return end
    sinf, cosf = math.sin(f), math.cos(f)
  end
  local function XY(wx, wy)
    local dx, dy = px - wx, py - wy
    if sinf then dx, dy = dx * cosf - dy * sinf, dx * sinf + dy * cosf end
    return dx / R * hw, -dy / R * hh
  end
  local alphaArea = (ns.db.areaAlpha or 0.2) * 1.2
  -- Blizzard's area shapes for the stops in the zone you're in (not with a rotating minimap:
  -- frames can't rotate, so those keep circles)
  local pm = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local blobIds = {}
  if pm and not sinf then
    for _, st in ipairs(miniStops) do
      if st.map == pm and st.blobs then for _, id in ipairs(st.blobs) do blobIds[#blobIds + 1] = id end end
    end
  end
  local fb = #blobIds > 0 and MiniBlob(box) or nil
  if fb then
    local ox, oy = HBD:GetWorldCoordinatesFromZone(0, 0, pm)
    local ex, ey = HBD:GetWorldCoordinatesFromZone(1, 1, pm)
    if ox and ex then
      local x0, y0 = XY(ox, oy)
      local x1, y1 = XY(ex, ey)
      local w, h = math.abs(x1 - x0), math.abs(y1 - y0)
      fb:ClearAllPoints()
      fb:SetPoint("TOPLEFT", box, "CENTER", math.min(x0, x1), math.max(y0, y1))
      fb:SetSize(w, h)
      fb:SetFrameLevel(box:GetFrameLevel())
      local key = pm .. ":" .. table.concat(blobIds, ",")
      if key ~= miniBlobKey or not miniBlobW or math.abs(w - miniBlobW) > 1 then
        miniBlobKey, miniBlobW = key, w
        if fb.SetMapID then pcall(fb.SetMapID, fb, pm) end
        pcall(fb.DrawNone, fb)
        for _, id in ipairs(blobIds) do pcall(fb.DrawBlob, fb, id, true) end
      end
      fb:Show()
    else
      fb:Hide()
    end
  elseif miniBlob then
    miniBlob:Hide(); miniBlobKey = nil
  end
  local nl, na = 0, 0
  local lx, ly = 0, 0   -- the line starts at you (the minimap centre)
  for _, st in ipairs(miniStops) do
    if st.inst ~= pinst then break end
    local x, y = XY(st.wx, st.wy)
    if box.CreateLine then
      nl = nl + 1
      local l = miniLines[nl]
      if not l then l = Masked(box:CreateLine(nil, "ARTWORK")); miniLines[nl] = l end
      l:SetThickness(2)
      l:SetColorTexture(1, 0.82, 0, 0.75)
      l:SetStartPoint("CENTER", box, lx, ly)
      l:SetEndPoint("CENTER", box, x, y)
      l:Show()
    end
    if st.blobs and sinf and not st.ryd then
      -- rotating minimap: no shapes, so a small circle at the stop instead
      st.ryd, st.cwx, st.cwy = 40, st.wx, st.wy
    end
    if st.ryd then
      na = na + 1
      local a = miniAreas[na]
      if not a then
        a = Masked(box:CreateTexture(nil, "BORDER"))
        a:SetTexture(CIRCLE)
        miniAreas[na] = a
      end
      local rp = st.ryd / R * hw
      local axp, ayp = XY(st.cwx or st.wx, st.cwy or st.wy)
      a:SetSize(rp * 2, rp * 2)
      a:ClearAllPoints()
      a:SetPoint("CENTER", box, "CENTER", axp, ayp)
      a:SetVertexColor(1, 0.78, 0.16, math.min(0.6, alphaArea))
      a:Show()
    end
    lx, ly = x, y
  end
end
Map.MiniDraw = MiniDraw

do
  local f = CreateFrame("Frame")
  local t = 0
  f:SetScript("OnUpdate", function(_, e)
    t = t + (e or 0)
    if t < 0.05 then return end
    t = 0
    if ns.db and not ns.disabled then ns.Safe("MinimapRoute", MiniDraw) end
  end)
end

-- Questie draws its own minimap icons; with both on, the minimap shows two sets. Say so once.
ns.inits.MapQuestieNote = function()
  C_Timer.After(8, function()
    local qp = rawget(_G, "Questie") and Questie.db and Questie.db.profile
    if qp and qp.enableMiniMapIcons and not ns.db.toldQuestieMini and not ns.db.noMiniPins then
      ns.db.toldQuestieMini = true
      ns.Print("the minimap now shows your route and nearby quests. Questie's minimap icons are on too: "
        .. "to see only the route's, turn them off in Questie's settings > Icons > Minimap icons.")
    end
  end)
end

-- Nearby icons change as you move: refresh them every few seconds (cheap: no route work).
do
  local mm = CreateFrame("Frame")
  local t = 0
  mm:SetScript("OnUpdate", function(_, e)
    t = t + (e or 0)
    if t < 3 then return end
    t = 0
    if ns.db and not ns.disabled and not ns.db.noMap and not ns.db.noMiniPins and not ns.db.noOtherPins then
      ns.Safe("Minimap", UpdateMinimap)
    end
  end)
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

-- Rubber Dinghy - on-screen arrow to the next stop, in Forever's navigation-arrow art.
-- Direction and distance come from HereBeDragons world coordinates (the way TomTom does it), so no
-- map marker or Blizzard waypoint is ever set.
local ADDON, ns = ...
local Arrow = {}
ns.Arrow = Arrow

local HBD = LibStub and LibStub("HereBeDragons-2.0", true)
local ARROW_ATLAS = { "Navigation-Tracked-Arrow" }   -- points up at rotation 0
local ARROW_FALLBACK = "Interface\\Minimap\\MinimapArrow"
local HERE_YARDS = 12

local frame, arrow, title, dist
local target, targetRadius
local elapsed = 0

local function Default()
  frame:ClearAllPoints()
  local p = ns.db.arrowPos
  if p then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
  else frame:SetPoint("TOP", UIParent, "TOP", 0, -140) end
end

--- Yards from the centre of a mob area to its edge, so "arrived" means "inside the circle".
local function RadiusYards(s)
  if not (HBD and s.area and s.r) then return nil end
  local d = HBD:GetZoneDistance(s.map, s.x / 100, s.y / 100, s.map, (s.x + s.r) / 100, s.y / 100)
  return d
end

local function Update()
  if not target or ns.db.noArrow or not HBD then frame:Hide(); return end
  local px, py, pinst = HBD:GetPlayerWorldPosition()
  local tx, ty, tinst = HBD:GetWorldCoordinatesFromZone(target.x / 100, target.y / 100, target.map)
  if not px or not tx or pinst ~= tinst then frame:Hide(); return end
  local angle, yards = HBD:GetWorldVector(pinst, px, py, tx, ty)
  if not angle then frame:Hide(); return end
  frame:Show()
  local hereAt = math.max(HERE_YARDS, (targetRadius or 0) * 0.8)
  local facing = GetPlayerFacing and GetPlayerFacing()
  if yards <= hereAt then
    arrow:SetRotation(0)
    arrow:SetVertexColor(0.2, 1, 0.2)
    dist:SetText("|cff33ff33You're here|r")
  else
    if facing then
      arrow:SetRotation(angle - facing)
      arrow:Show()
    else
      arrow:Hide() -- no facing inside instances
    end
    arrow:SetVertexColor(1, 1, 1)
    dist:SetText(("%d yd"):format(math.floor(yards + 0.5)))
  end
end

local function Init()
  frame = CreateFrame("Frame", "RubberDinghyArrow", UIParent)
  frame:SetSize(160, 70)
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() if ns.db.unlocked then frame:StartMoving() end end)
  frame:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local p, _, rp, x, y = frame:GetPoint(1)
    ns.db.arrowPos = { p, rp, x, y }
  end)
  Default()

  arrow = frame:CreateTexture(nil, "ARTWORK")
  arrow:SetPoint("TOP", 0, 0)
  if ns.SetAtlasOr(arrow, ARROW_ATLAS, ARROW_FALLBACK) then arrow:SetSize(44, 36) else arrow:SetSize(40, 40) end

  title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
  dist = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dist:SetPoint("TOP", title, "BOTTOM", 0, -1)

  frame:SetScript("OnUpdate", function(_, e)
    elapsed = elapsed + e
    if elapsed < 0.05 then return end
    elapsed = 0
    ns.Safe("Arrow", Update)
  end)
  frame:Hide()
  Arrow.SetUnlocked(ns.db.unlocked)
  -- The OnUpdate only runs while shown, so a hidden arrow is woken by route changes (listener below)
  -- and by this slow ticker while a target exists.
  C_Timer.NewTicker(1, function() if target and not frame:IsShown() then ns.Safe("Arrow", Update) end end)
end

function Arrow.SetUnlocked(on)
  if frame then frame:EnableMouse(on and true or false) end
end

function Arrow.Reset()
  if frame then Default() end
end

ns.inits.Arrow = Init

ns.listeners.Arrow = function(r)
  -- The next stop in this zone; stops elsewhere (hand-ins on another continent) don't get the arrow.
  target = nil
  for _, s in ipairs(r.stops) do
    if not s.away then target = s; break end
  end
  if not target and r.stops[1] then target = r.stops[1] end
  targetRadius = target and RadiusYards(target) or nil
  if frame then
    if target then title:SetText(target.index .. ". " .. ns.StopTitle(target)) end
    Update()
  end
end

ns.commands.arrow = function()
  ns.db.noArrow = not ns.db.noArrow
  ns.Print("arrow " .. (ns.db.noArrow and "off" or "on"))
  if frame then ns.Safe("Arrow", Update) end
end

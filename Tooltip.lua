-- Rubber Dinghy - route info in unit tooltips. Hover a quest giver, hand-in NPC or a mob your quests
-- need, and the tooltip says which stop it is and what to do (with your progress).
local ADDON, ns = ...

local function Matches(s, name)
  if s.name == name then return true end
  if s.area and s.name then
    for part in s.name:gmatch("[^,]+") do
      if part:match("^%s*(.-)%s*$") == name then return true end
    end
  end
  return false
end

local function AddRouteLines(tt)
  if not (ns.db and ns.route and ns.route.stops) or ns.db.noTooltips then return end
  local _, unit = tt:GetUnit()
  local name = unit and UnitName(unit)
  if not name then return end
  local added = false
  for _, s in ipairs(ns.route.stops) do
    if Matches(s, name) then
      if not added then
        tt:AddLine("|cff66ccffRubber Dinghy|r - stop " .. s.index, 1, 1, 1)
        added = true
      end
      for _, a in ipairs(s.actions) do
        local text = ns.ActionText(a)
        if a.kind == "do" then
          local objs = ns.Objectives(a.row.id)
          if objs[1] then text = text .. " |cffffffff" .. objs[1].text .. "|r" end
        end
        tt:AddLine("  " .. text)
      end
    end
  end
  if added then tt:Show() end
end

ns.inits.Tooltip = function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
      if tt == GameTooltip then ns.Safe("Tooltip", AddRouteLines, tt) end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt) ns.Safe("Tooltip", AddRouteLines, tt) end)
  end
end

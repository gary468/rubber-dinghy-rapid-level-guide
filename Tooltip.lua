-- Rubber Dinghy - quest info in unit tooltips, like Questie's. Hover a mob your quests need and the
-- tooltip shows each quest with your progress; hover a quest giver or hand-in NPC and it shows what
-- to pick up or hand in. Route quests say which stop they are.
--
-- Matched by the NPC ID in the unit's GUID: Forever hides unit names from addons (secret values),
-- so matching by name silently finds nothing. Names are only a fallback when they're readable.
local ADDON, ns = ...

local function Secret(v) return issecretvalue and issecretvalue(v) end

local function NpcId(unit)
  local guid = UnitGUID and UnitGUID(unit)
  if not guid or Secret(guid) or (canaccessvalue and not canaccessvalue(guid)) then return nil end
  local kind, _, _, _, _, id = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return tonumber(id)
end

-- "npc:q,q;npc:q" -> { [npc] = {q, q} }, parsed the first time a tooltip needs it
local maps = {}
local function Map(key)
  local m = maps[key]
  if m then return m end
  m = {}
  for npc, qs in tostring(ns[key] or ""):gmatch("(%d+):([%d,]+)") do
    local list = {}
    for q in qs:gmatch("%d+") do list[#list + 1] = tonumber(q) end
    m[tonumber(npc)] = list
  end
  maps[key] = m
  return m
end

-- Route stop number for a quest, if it's on the route.
local function StopOf(id)
  for _, s in ipairs((ns.route and ns.route.stops) or {}) do
    for _, a in ipairs(s.actions or {}) do
      if a.row.id == id then return s.index end
    end
  end
end

local GOLD, GREY = "|cffffd100", "|cff999999"
local function Title(id)
  local q = ns.quests[id]
  local stop = StopOf(id)
  return GOLD .. (q and q.n or ("Quest " .. id)) .. "|r" .. (stop and (GREY .. "  (route stop " .. stop .. ")|r") or "")
end

local function InLog(id) return (ns.LogIndex(id) or 0) > 0 end

local function AddLines(tt)
  if not (ns.db and ns.quests) or ns.db.noTooltips or ns.disabled then return end
  local _, unit = tt:GetUnit()
  if not unit then return end
  local npc = NpcId(unit)
  local added, seen = false, {}
  local function Line(text, r, g, b)
    tt:AddLine(text, r or 1, g or 1, b or 1)
    added = true
  end
  if npc then
    local skip = ns.db.skip or {}
    -- a mob your quests need: each quest and your progress on it
    for _, id in ipairs(Map("tipMobs")[npc] or {}) do
      if InLog(id) and not ns.IsReady(id) and not seen[id] then
        seen[id] = true
        Line(Title(id))
        for _, o in ipairs(ns.Objectives(id)) do
          if o.done then Line("  " .. o.text, 0.4, 1, 0.4) else Line("  " .. ns.ObjText(o), 1, 1, 1) end
        end
      end
    end
    -- a hand-in NPC: finished quests to hand in here
    for _, id in ipairs(Map("tipEnds")[npc] or {}) do
      if InLog(id) and ns.IsReady(id) and not seen[id] then
        seen[id] = true
        Line("|cff33ff33?|r Hand in: " .. Title(id))
      end
    end
    -- a quest giver: quests you can pick up now
    local level = UnitLevel("player") or 1
    for _, id in ipairs(Map("tipStarts")[npc] or {}) do
      if not seen[id] and not skip[id] and ns.Status(id, level) == ns.S.OPEN then
        seen[id] = true
        local q = ns.quests[id]
        Line(GOLD .. "!|r Pick up: " .. Title(id) .. GREY .. " [" .. (q and q.l or "?") .. "]|r")
      end
    end
  end
  -- fallback when the name is readable (an object or a client that shows names): route stops by name
  if not added then
    local name = UnitName(unit)
    if name and not Secret(name) then
      for _, s in ipairs((ns.route and ns.route.stops) or {}) do
        local match = s.name == name
        if not match and s.area and s.name then
          for part in s.name:gmatch("[^,]+") do if part:match("^%s*(.-)%s*$") == name then match = true end end
        end
        if match then
          Line(GREY .. "Route stop " .. s.index .. "|r")
          for _, a in ipairs(s.actions) do
            local text = ns.ActionText(a)
            if a.kind == "do" then
              local objs = ns.Objectives(a.row.id)
              if objs[1] then text = text .. " |cffffffff" .. objs[1].text .. "|r" end
            end
            Line("  " .. text)
          end
        end
      end
    end
  end
  if added then tt:Show() end
end

ns.inits.Tooltip = function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
      if tt == GameTooltip then ns.Safe("Tooltip", AddLines, tt) end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tt) ns.Safe("Tooltip", AddLines, tt) end)
  end
end

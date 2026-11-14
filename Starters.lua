-- Rubber Dinghy - items in your bags that start a quest ("This Item Begins a Quest": A Mangled
-- Journal, Message in a Bottle...). They're looted from mobs or picked up from objects, so no quest
-- giver ever shows them. Whenever your bags change, any such item for a quest you haven't done and
-- don't have is listed at the top of the tracker, with one chat note when it first turns up.
-- Opening it (right-click in your bags) shows the quest; "Accept and hand in quests" accepts it.
local ADDON, ns = ...
local S = {}
ns.Starters = S

local list = {}          -- { {bag, slot, itemID, item, questID, quest} }
local told = {}          -- questID -> true (chat note once per session)

local function QuestInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemQuestInfo then
    local ok, info = pcall(C_Container.GetContainerItemQuestInfo, bag, slot)
    if ok and type(info) == "table" then return info.questID, info.isActive end
  end
  if GetContainerItemQuestInfo then
    local ok, _, questID, isActive = pcall(GetContainerItemQuestInfo, bag, slot)
    if ok then return questID, isActive end
  end
end

local function Done(id)
  return (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(id)) or false
end

local function QuestName(id)
  local q = ns.quests and ns.quests[id]
  if q and q.n then return q.n end
  if C_QuestLog and C_QuestLog.GetTitleForQuestID then
    local ok, t = pcall(C_QuestLog.GetTitleForQuestID, id)
    if ok and t then return t end
  end
  return "a quest"
end

function S.Scan()
  local out = {}
  if not (C_Container and C_Container.GetContainerNumSlots) then list = out; return out end
  for bag = 0, 4 do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      local questID, isActive = QuestInfo(bag, slot)
      if questID and questID > 0 and not isActive and not Done(questID) and ns.LogIndex(questID) == 0
        and not (ns.db and ns.db.skip and ns.db.skip[questID]) then
        local info = C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)
        local name = info and (info.itemName or (info.hyperlink and info.hyperlink:match("%[(.-)%]"))) or "an item"
        out[#out + 1] = { bag = bag, slot = slot, itemID = info and info.itemID, item = name,
                          questID = questID, quest = QuestName(questID) }
        if not told[questID] then
          told[questID] = true
          ns.Print(("%s starts a quest: %s. Right-click it in your bags."):format(name, QuestName(questID)))
        end
      end
    end
  end
  list = out
  return out
end

--- Items in your bags that start a quest you can take.
function S.List() return list end

local KIND_ORDER = { mob = 1, obj = 2, drop = 3 }
--- Quests started by an item you could get in this step's zone, before you have it (Gary 14 Nov:
--- "it should warn you about these or suggest you farm to get them"). From q.si =
--- {itemId, itemName, kind, source, uiMap, x, y}: "mob" = a named mob to hunt, "obj" = something on
--- the ground, "drop" = a random drop from the zone's mobs. Only quests near your level that you
--- haven't done, don't have, and aren't carrying the item for.
function S.Watch(step, level)
  local out = {}
  if not (step and step.map and ns.quests) or step.dungeon or step.prep then return out end
  local have = {}
  for _, it in ipairs(list) do have[it.questID] = true end
  local S_ = ns.S
  for id, q in pairs(ns.quests) do
    local si = q.si
    if si and si[5] == step.map and not have[id] and q.l and q.l <= step.to + 3 and q.l >= step.from - 4 then
      local st = ns.Status(id, level)
      if st == S_.OPEN or st == S_.SOON then
        out[#out + 1] = { id = id, q = q, itemId = si[1], item = si[2], kind = si[3], src = si[4], x = si[6], y = si[7] }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.kind ~= b.kind then return (KIND_ORDER[a.kind] or 9) < (KIND_ORDER[b.kind] or 9) end
    return a.id < b.id
  end)
  return out
end

--- One tracker line and its tooltip for a Watch() entry.
function S.WatchText(w)
  local q = w.q
  local tail = (" - starts %s"):format(q.n)
  local text, tip
  if w.kind == "mob" then
    text = ("|cffffd100Hunt:|r %s (%.0f,%.0f)%s"):format(w.src, w.x, w.y, tail)
    tip = ("%s drops %s, which starts %s (level %d). A named mob: worth the detour if it's near your route.")
      :format(w.src, w.item, q.n, q.l)
  elseif w.kind == "obj" then
    text = ("|cffffd100Look for:|r %s (%.0f,%.0f)%s"):format(w.src, w.x, w.y, tail)
    tip = ("Pick up %s from %s on the ground. It starts %s (level %d).")
      :format(w.item, w.src, q.n, q.l)
  else
    text = ("|cffffd100Watch for:|r %s%s"):format(w.item, tail)
    tip = ("%s can drop from %s here. It starts %s (level %d). No drop rate is known, so don't farm just "
      .. "for it - loot what you kill and right-click it in your bags when it drops."):format(w.item, w.src, q.n, q.l)
  end
  return text, tip
end

local f = CreateFrame("Frame")
local pending = false
f:SetScript("OnEvent", function()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    if not ns.db or ns.disabled then return end
    local before = #list
    ns.Safe("Starters", S.Scan)
    if #list ~= before then ns.Queue() end
  end)
end)

ns.inits.Starters = function()
  for _, e in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
    pcall(f.RegisterEvent, f, e)
  end
  ns.Safe("Starters", S.Scan)
end
